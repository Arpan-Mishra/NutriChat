import logging
from typing import Optional

import httpx
from sqlalchemy import or_, func
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import FoodItem

logger = logging.getLogger(__name__)
settings = get_settings()

HTTPX_TIMEOUT = 10.0


async def search_food(db: Session, query: str, limit: int = 20) -> list[dict]:
    """Layered food search: local DB → USDA → Open Food Facts → Edamam.
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

    return results[:limit]


async def search_by_barcode(db: Session, barcode: str) -> Optional[dict]:
    """Search by barcode: local DB first, then Open Food Facts."""
    # Check local
    item = db.query(FoodItem).filter(FoodItem.barcode == barcode).first()
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
    # Use ILIKE for case-insensitive pattern matching
    pattern = f"%{query}%"
    items = (
        db.query(FoodItem)
        .filter(FoodItem.name.ilike(pattern))
        .order_by(
            # Prioritize exact matches, then verified, then by name length (shorter = more relevant)
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

    # Check if already cached
    existing = db.query(FoodItem).filter(
        FoodItem.external_id == fdc_id, FoodItem.source == "usda"
    ).first()
    if existing:
        return existing

    # Extract nutrients
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
        serving_description=food.get("servingSize", "100g") if food.get("servingSize") else "100g",
        verified=True,
    )
    db.add(item)
    try:
        db.commit()
        db.refresh(item)
    except Exception:
        db.rollback()
        # Might be a race condition; try to find existing
        existing = db.query(FoodItem).filter(
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

    # Check if already cached by barcode
    if barcode:
        existing = db.query(FoodItem).filter(FoodItem.barcode == barcode).first()
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
    except Exception:
        db.rollback()
        if barcode:
            existing = db.query(FoodItem).filter(FoodItem.barcode == barcode).first()
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

    existing = db.query(FoodItem).filter(
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
    except Exception:
        db.rollback()
        existing = db.query(FoodItem).filter(
            FoodItem.external_id == food_id, FoodItem.source == "edamam"
        ).first()
        return existing
    return item


# --- Helpers ---

def _food_item_to_result(item: FoodItem) -> dict:
    """Convert a FoodItem model to a search result dict."""
    return {
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
    }
