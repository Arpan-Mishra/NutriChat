import logging
from typing import Optional

import httpx
from sqlalchemy import or_, func
from sqlalchemy.orm import Session, joinedload

from app.config import get_settings
from app.models import FoodItem, FoodServing

logger = logging.getLogger(__name__)
settings = get_settings()

HTTPX_TIMEOUT = 10.0


async def search_food(db: Session, query: str, limit: int = 20) -> list[dict]:
    """Layered food search: local DB → USDA → Open Food Facts → Edamam → FatSecret.
    Results from external APIs are cached into food_items table."""
    if not query or not query.strip():
        return []

    query = query.strip()

    # Layer 1: Local database
    results = _search_local(db, query, limit)
    if len(results) >= limit:
        return results[:limit]

    remaining = limit - len(results)
    seen_ids = {r["food_id"] for r in results}

    # Layer 2: USDA FoodData Central
    if settings.usda_api_key:
        usda_results = await _search_usda(db, query, remaining)
        for r in usda_results:
            if r["food_id"] not in seen_ids:
                results.append(r)
                seen_ids.add(r["food_id"])

    remaining = limit - len(results)
    if remaining <= 0:
        return results[:limit]

    # Layer 3: Open Food Facts
    off_results = await _search_open_food_facts(db, query, remaining)
    for r in off_results:
        if r["food_id"] not in seen_ids:
            results.append(r)
            seen_ids.add(r["food_id"])

    remaining = limit - len(results)
    if remaining <= 0:
        return results[:limit]

    # Layer 4: Edamam
    if settings.edamam_app_id and settings.edamam_app_key:
        edamam_results = await _search_edamam(db, query, remaining)
        for r in edamam_results:
            if r["food_id"] not in seen_ids:
                results.append(r)
                seen_ids.add(r["food_id"])

    remaining = limit - len(results)
    if remaining <= 0:
        return results[:limit]

    # Layer 5: FatSecret
    if settings.fatsecret_consumer_key and settings.fatsecret_consumer_secret:
        fs_results = await _search_fatsecret(db, query, remaining)
        for r in fs_results:
            if r["food_id"] not in seen_ids:
                results.append(r)
                seen_ids.add(r["food_id"])

    return results[:limit]


async def suggest_food(db: Session, query: str, limit: int = 10) -> list[dict]:
    """Lightweight typeahead — local DB only, no external API calls."""
    if not query or not query.strip():
        return []
    return _search_local(db, query.strip(), limit)


async def search_by_barcode(db: Session, barcode: str) -> Optional[dict]:
    """Search by barcode: local DB first, then Open Food Facts."""
    # Check local
    item = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
        FoodItem.barcode == barcode
    ).first()
    if item:
        return _food_item_to_result(item)

    # Try Open Food Facts
    try:
        async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
            resp = await client.get(f"https://world.openfoodfacts.org/api/v2/product/{barcode}")
            if resp.status_code == 200:
                data = resp.json()
                if data.get("status") == 1:
                    product = data["product"]
                    item = _cache_off_product(db, product)
                    if item:
                        return _food_item_to_result(item)
    except Exception as e:
        logger.warning(f"Open Food Facts barcode lookup failed: {e}")

    return None


# --- Local DB search ---

def _search_local(db: Session, query: str, limit: int) -> list[dict]:
    """Full-text search on food_items.name."""
    pattern = f"%{query}%"
    items = (
        db.query(FoodItem)
        .options(joinedload(FoodItem.servings))
        .filter(FoodItem.name.ilike(pattern))
        .order_by(
            FoodItem.verified.desc(),
            func.length(FoodItem.name),
        )
        .limit(limit)
        .all()
    )
    return [_food_item_to_result(item) for item in items]


# --- USDA FoodData Central ---

async def _search_usda(db: Session, query: str, limit: int) -> list[dict]:
    """Search USDA FoodData Central API and cache results."""
    try:
        async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
            resp = await client.get(
                "https://api.nal.usda.gov/fdc/v1/foods/search",
                params={
                    "api_key": settings.usda_api_key,
                    "query": query,
                    "pageSize": min(limit, 10),
                    "dataType": ["Foundation", "SR Legacy", "Branded"],
                },
            )
            if resp.status_code != 200:
                logger.warning(f"USDA API returned {resp.status_code}")
                return []

            data = resp.json()
            results = []
            for food in data.get("foods", [])[:limit]:
                item = _cache_usda_food(db, food)
                if item:
                    results.append(_food_item_to_result(item))
            return results
    except Exception as e:
        logger.warning(f"USDA search failed: {e}")
        return []


def _cache_usda_food(db: Session, food: dict) -> Optional[FoodItem]:
    """Cache a USDA food item into the local database."""
    fdc_id = str(food.get("fdcId", ""))
    if not fdc_id:
        return None

    existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
        FoodItem.external_id == fdc_id, FoodItem.source == "usda"
    ).first()
    if existing:
        return existing

    nutrients = {}
    for nutrient in food.get("foodNutrients", []):
        name = nutrient.get("nutrientName", "").lower()
        value = nutrient.get("value", 0)
        if "energy" in name and "kcal" in nutrient.get("unitName", "").lower():
            nutrients["calories"] = value
        elif "protein" in name:
            nutrients["protein"] = value
        elif "total lipid" in name or ("fat" in name and "total" in name):
            nutrients["fat"] = value
        elif "carbohydrate" in name:
            nutrients["carbs"] = value
        elif "fiber" in name:
            nutrients["fiber"] = value
        elif "sodium" in name:
            nutrients["sodium"] = value

    if "calories" not in nutrients:
        return None

    raw_serving_size = food.get("servingSize")
    raw_unit = food.get("servingSizeUnit", "g") or "g"
    # servingSizeUnit is a unit string like "g", "ml", "MLT" — NOT a number
    # servingSize is the numeric amount
    try:
        serving_g = float(raw_serving_size) if raw_serving_size else 100.0
    except (ValueError, TypeError):
        serving_g = 100.0
    serving_desc = f"{int(serving_g)}{raw_unit}" if raw_serving_size else "100g"

    item = FoodItem(
        external_id=fdc_id,
        source="usda",
        name=food.get("description", "Unknown"),
        brand=food.get("brandName") or food.get("brandOwner"),
        calories_per_100g=nutrients.get("calories", 0),
        protein_per_100g=nutrients.get("protein", 0),
        fat_per_100g=nutrients.get("fat", 0),
        carbs_per_100g=nutrients.get("carbs", 0),
        fiber_per_100g=nutrients.get("fiber", 0),
        sodium_per_100g=nutrients.get("sodium", 0),
        serving_size_g=100,
        serving_description=serving_desc,
        verified=True,
    )
    db.add(item)
    try:
        db.commit()
        db.refresh(item)
        _create_default_serving(db, item)
    except Exception:
        db.rollback()
        existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
            FoodItem.external_id == fdc_id, FoodItem.source == "usda"
        ).first()
        return existing
    return item


# --- Open Food Facts ---

async def _search_open_food_facts(db: Session, query: str, limit: int) -> list[dict]:
    """Search Open Food Facts API and cache results."""
    try:
        async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
            resp = await client.get(
                "https://world.openfoodfacts.org/cgi/search.pl",
                params={
                    "search_terms": query,
                    "search_simple": 1,
                    "action": "process",
                    "json": 1,
                    "page_size": min(limit, 10),
                    "fields": "code,product_name,brands,nutriments,serving_size",
                },
            )
            if resp.status_code != 200:
                logger.warning(f"Open Food Facts API returned {resp.status_code}")
                return []

            data = resp.json()
            results = []
            for product in data.get("products", [])[:limit]:
                item = _cache_off_product(db, product)
                if item:
                    results.append(_food_item_to_result(item))
            return results
    except Exception as e:
        logger.warning(f"Open Food Facts search failed: {e}")
        return []


def _cache_off_product(db: Session, product: dict) -> Optional[FoodItem]:
    """Cache an Open Food Facts product into the local database."""
    barcode = product.get("code", "")
    name = product.get("product_name", "")
    if not name:
        return None

    nutriments = product.get("nutriments", {})
    calories = nutriments.get("energy-kcal_100g", 0)
    if not calories:
        return None

    if barcode:
        existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
            FoodItem.barcode == barcode
        ).first()
        if existing:
            return existing

    item = FoodItem(
        external_id=barcode or None,
        source="off",
        name=name,
        brand=product.get("brands"),
        barcode=barcode or None,
        calories_per_100g=calories,
        protein_per_100g=nutriments.get("proteins_100g", 0),
        fat_per_100g=nutriments.get("fat_100g", 0),
        carbs_per_100g=nutriments.get("carbohydrates_100g", 0),
        fiber_per_100g=nutriments.get("fiber_100g", 0),
        sodium_per_100g=nutriments.get("sodium_100g", 0) * 1000 if nutriments.get("sodium_100g") else 0,
        serving_size_g=100,
        serving_description=product.get("serving_size", "100g") or "100g",
        verified=False,
    )
    db.add(item)
    try:
        db.commit()
        db.refresh(item)
        _create_default_serving(db, item)
    except Exception:
        db.rollback()
        if barcode:
            existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
                FoodItem.barcode == barcode
            ).first()
            return existing
        return None
    return item


# --- Edamam ---

async def _search_edamam(db: Session, query: str, limit: int) -> list[dict]:
    """Search Edamam Food Database API and cache results."""
    try:
        async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
            resp = await client.get(
                "https://api.edamam.com/api/food-database/v2/parser",
                params={
                    "app_id": settings.edamam_app_id,
                    "app_key": settings.edamam_app_key,
                    "ingr": query,
                },
            )
            if resp.status_code != 200:
                logger.warning(f"Edamam API returned {resp.status_code}")
                return []

            data = resp.json()
            results = []
            for hint in data.get("hints", [])[:limit]:
                food = hint.get("food", {})
                item = _cache_edamam_food(db, food)
                if item:
                    results.append(_food_item_to_result(item))
            return results
    except Exception as e:
        logger.warning(f"Edamam search failed: {e}")
        return []


def _cache_edamam_food(db: Session, food: dict) -> Optional[FoodItem]:
    """Cache an Edamam food item into the local database."""
    food_id = food.get("foodId", "")
    if not food_id:
        return None

    existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
        FoodItem.external_id == food_id, FoodItem.source == "edamam"
    ).first()
    if existing:
        return existing

    nutrients = food.get("nutrients", {})
    calories = nutrients.get("ENERC_KCAL", 0)
    if not calories:
        return None

    item = FoodItem(
        external_id=food_id,
        source="edamam",
        name=food.get("label", "Unknown"),
        brand=food.get("brand"),
        calories_per_100g=calories,
        protein_per_100g=nutrients.get("PROCNT", 0),
        fat_per_100g=nutrients.get("FAT", 0),
        carbs_per_100g=nutrients.get("CHOCDF", 0),
        fiber_per_100g=nutrients.get("FIBTG", 0),
        sodium_per_100g=nutrients.get("NA", 0),
        serving_size_g=100,
        serving_description="100g",
        verified=False,
    )
    db.add(item)
    try:
        db.commit()
        db.refresh(item)
        _create_default_serving(db, item)
    except Exception:
        db.rollback()
        existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
            FoodItem.external_id == food_id, FoodItem.source == "edamam"
        ).first()
        return existing
    return item


# --- FatSecret ---

async def _search_fatsecret(db: Session, query: str, limit: int) -> list[dict]:
    """Search FatSecret API and cache results with multiple servings."""
    from app.integrations.fatsecret import search_foods, get_food_servings

    foods = await search_foods(query, max_results=min(limit, 10))
    results = []

    for food in foods[:limit]:
        fs_food_id = food.get("food_id", "")
        if not fs_food_id:
            continue

        # Check if already cached
        existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
            FoodItem.external_id == str(fs_food_id), FoodItem.source == "fatsecret"
        ).first()
        if existing:
            results.append(_food_item_to_result(existing))
            continue

        # Fetch detailed servings
        servings = await get_food_servings(str(fs_food_id))
        if not servings:
            continue

        item = _cache_fatsecret_food(db, food, servings)
        if item:
            results.append(_food_item_to_result(item))

    return results


def _cache_fatsecret_food(
    db: Session, food: dict, servings: list[dict]
) -> Optional[FoodItem]:
    """Cache a FatSecret food item with multiple servings."""
    fs_food_id = str(food.get("food_id", ""))
    food_name = food.get("food_name", "Unknown")
    brand = food.get("brand_name")

    # Find the "per 100g" serving or use the first serving to normalize
    default_serving = None
    for s in servings:
        desc = s.get("serving_description", "").lower()
        if "100g" in desc or "100 g" in desc:
            default_serving = s
            break
    if not default_serving:
        default_serving = servings[0]

    # Extract per-100g values
    cal = float(default_serving.get("calories", 0))
    protein = float(default_serving.get("protein", 0))
    fat = float(default_serving.get("fat", 0))
    carbs = float(default_serving.get("carbohydrate", 0))
    fiber = float(default_serving.get("fiber", 0))
    sodium = float(default_serving.get("sodium", 0))
    metric_amount = float(default_serving.get("metric_serving_amount", 100))
    metric_unit = default_serving.get("metric_serving_unit", "g")

    # Normalize to per-100g if the default serving isn't 100g
    if metric_amount and metric_amount != 100 and metric_unit == "g":
        factor = 100.0 / metric_amount
        cal *= factor
        protein *= factor
        fat *= factor
        carbs *= factor
        fiber *= factor
        sodium *= factor

    if cal <= 0:
        return None

    item = FoodItem(
        external_id=fs_food_id,
        source="fatsecret",
        name=food_name,
        brand=brand,
        calories_per_100g=round(cal, 1),
        protein_per_100g=round(protein, 1),
        fat_per_100g=round(fat, 1),
        carbs_per_100g=round(carbs, 1),
        fiber_per_100g=round(fiber, 1),
        sodium_per_100g=round(sodium, 1),
        serving_size_g=metric_amount if metric_unit == "g" else 100,
        serving_description=default_serving.get("serving_description", "100g"),
        verified=False,
    )
    db.add(item)
    try:
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()
        existing = db.query(FoodItem).options(joinedload(FoodItem.servings)).filter(
            FoodItem.external_id == fs_food_id, FoodItem.source == "fatsecret"
        ).first()
        return existing

    # Store all available servings
    for i, s in enumerate(servings):
        m_amount = float(s.get("metric_serving_amount", 0)) if s.get("metric_serving_amount") else None
        m_unit = s.get("metric_serving_unit")
        serving_g = m_amount if m_amount and m_unit == "g" else 100.0

        serving = FoodServing(
            food_item_id=item.id,
            serving_description=s.get("serving_description", "1 serving"),
            serving_size_g=serving_g,
            metric_serving_amount=m_amount,
            metric_serving_unit=m_unit,
            is_default=(i == 0),
        )
        db.add(serving)

    try:
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()

    return item


# --- Helpers ---

def _create_default_serving(db: Session, item: FoodItem) -> None:
    """Create a default FoodServing entry for a cached food item."""
    serving = FoodServing(
        food_item_id=item.id,
        serving_description=item.serving_description or "100g",
        serving_size_g=item.serving_size_g or 100,
        metric_serving_amount=item.serving_size_g or 100,
        metric_serving_unit="g",
        is_default=True,
    )
    db.add(serving)
    try:
        db.commit()
    except Exception:
        db.rollback()


def _food_item_to_result(item: FoodItem) -> dict:
    """Convert a FoodItem model to a search result dict, including servings."""
    result = {
        "food_id": item.id,
        "food_name": item.name,
        "brand": item.brand,
        "source": item.source,
        "calories_per_100g": item.calories_per_100g,
        "protein_per_100g": item.protein_per_100g,
        "fat_per_100g": item.fat_per_100g,
        "carbs_per_100g": item.carbs_per_100g,
        "serving_size_g": item.serving_size_g,
        "serving_description": item.serving_description,
        "servings": [],
    }

    if hasattr(item, "servings") and item.servings:
        result["servings"] = [
            {
                "id": s.id,
                "serving_description": s.serving_description,
                "serving_size_g": s.serving_size_g,
                "metric_serving_amount": s.metric_serving_amount,
                "metric_serving_unit": s.metric_serving_unit,
                "is_default": s.is_default,
            }
            for s in item.servings
        ]

    return result
