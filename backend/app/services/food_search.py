import asyncio
import logging
import time
from typing import Optional

import httpx
from sqlalchemy import or_, func
from sqlalchemy.orm import Session, joinedload

from app.config import get_settings
from app.models import FoodItem, FoodServing

logger = logging.getLogger(__name__)
settings = get_settings()

HTTPX_TIMEOUT = 10.0

# --- Server-side query cache (TTL-based) ---

_query_cache: dict[str, dict] = {}  # key → {"results": [...], "expires_at": float}
CACHE_TTL_SECONDS = 60.0


def _get_cached(query: str) -> Optional[list[dict]]:
    """Return cached results if still valid, else None."""
    key = query.lower().strip()
    entry = _query_cache.get(key)
    if entry and time.time() < entry["expires_at"]:
        return entry["results"]
    if entry:
        del _query_cache[key]
    return None


def _set_cached(query: str, results: list[dict]) -> None:
    """Cache results with TTL. Evict oldest if cache exceeds 200 entries."""
    key = query.lower().strip()
    _query_cache[key] = {"results": results, "expires_at": time.time() + CACHE_TTL_SECONDS}
    # Simple eviction: remove expired entries when cache grows large
    if len(_query_cache) > 200:
        now = time.time()
        expired = [k for k, v in _query_cache.items() if now >= v["expires_at"]]
        for k in expired:
            del _query_cache[k]


# --- Relevance scoring ---

# Source quality multipliers — higher = more trusted
SOURCE_QUALITY = {
    "local": 1.2,
    "usda": 1.1,
    "fatsecret": 1.0,
    "edamam": 1.0,
    "off": 0.9,
    "custom": 0.8,
}


def _score_result(result: dict, query: str) -> float:
    """Compute a relevance score for ranking search results.

    Scoring factors:
    - Match type: exact > prefix > word-boundary > contains
    - Source quality: verified/USDA ranked higher
    - Name length: shorter names preferred (more specific)
    """
    name = result.get("food_name", "").lower()
    q = query.lower().strip()

    # Match type score
    if name == q:
        match_score = 1.0     # exact match
    elif name.startswith(q):
        match_score = 0.85    # prefix match
    elif f" {q}" in f" {name}":
        # Word boundary match — query matches start of any word
        match_score = 0.7
    elif q in name:
        match_score = 0.5     # substring/contains
    else:
        match_score = 0.2     # fuzzy/partial (came from an API that matched it)

    # Source quality multiplier
    source = result.get("source", "custom")
    source_mult = SOURCE_QUALITY.get(source, 0.8)

    # Name length penalty — shorter names are more specific and relevant
    # Normalize: names under 20 chars get full score, longer names get penalized
    name_len = len(name)
    length_factor = max(0.5, 1.0 - (name_len - 20) * 0.01) if name_len > 20 else 1.0

    return match_score * source_mult * length_factor


def _dedupe_and_rank(all_results: list[dict], query: str, limit: int) -> list[dict]:
    """Deduplicate by food_id, score, sort, and return top N results."""
    seen_ids: set[int] = set()
    unique: list[dict] = []

    for r in all_results:
        fid = r.get("food_id")
        if fid and fid not in seen_ids:
            seen_ids.add(fid)
            unique.append(r)

    # Score and sort
    scored = [(r, _score_result(r, query)) for r in unique]
    scored.sort(key=lambda x: x[1], reverse=True)

    return [r for r, _ in scored[:limit]]


# --- Public API ---

async def search_food(db: Session, query: str, limit: int = 20) -> list[dict]:
    """Scatter-gather food search: fans out to all sources in parallel.

    All external APIs are called concurrently via asyncio.gather with a 3s timeout.
    Results are merged, deduplicated, and ranked by relevance score.
    """
    if not query or not query.strip():
        return []

    query = query.strip()

    # Check server-side cache
    cached = _get_cached(query)
    if cached:
        return cached[:limit]

    # Phase 1: Local DB (instant)
    local_results = _search_local(db, query, limit)
    logger.info(f"[search '{query}'] Local DB: {len(local_results)} results")

    # Phase 2: Fan out to all external APIs concurrently
    task_names: list[str] = []
    tasks = []
    if settings.usda_api_key:
        tasks.append(_search_usda(db, query, 10))
        task_names.append("USDA")
    if True:  # Open Food Facts — no key needed
        tasks.append(_search_open_food_facts(db, query, 10))
        task_names.append("OpenFoodFacts")
    if settings.edamam_app_id and settings.edamam_app_key:
        tasks.append(_search_edamam(db, query, 10))
        task_names.append("Edamam")
    if settings.fatsecret_consumer_key and settings.fatsecret_consumer_secret:
        tasks.append(_search_fatsecret(db, query, 10))
        task_names.append("FatSecret")

    external_results: list[dict] = []
    if tasks:
        try:
            async with asyncio.timeout(3.0):
                gathered = await asyncio.gather(*tasks, return_exceptions=True)
                for name, result in zip(task_names, gathered):
                    if isinstance(result, list):
                        logger.info(f"[search '{query}'] {name}: {len(result)} results")
                        external_results.extend(result)
                    elif isinstance(result, Exception):
                        logger.warning(f"[search '{query}'] {name}: FAILED — {result}")
        except asyncio.TimeoutError:
            logger.warning(f"[search '{query}'] Fan-out timed out (3s), using partial results")

    # Merge all results and rank
    all_results = local_results + external_results
    ranked = _dedupe_and_rank(all_results, query, limit)
    logger.info(f"[search '{query}'] Merged: {len(all_results)} total → {len(ranked)} ranked")

    # Cache the merged results
    _set_cached(query, ranked)

    return ranked


async def suggest_food(db: Session, query: str, limit: int = 10) -> list[dict]:
    """Fast typeahead — fans out to all sources with a shorter 1.5s timeout.

    Returns top results ranked by relevance. Uses server-side cache to avoid
    redundant API calls when the user is still typing.
    """
    if not query or not query.strip():
        return []

    query = query.strip()

    # Check server-side cache first
    cached = _get_cached(query)
    if cached:
        return cached[:limit]

    # Also check if a prefix of this query was recently searched
    # e.g., if "chick" was cached, filter those results for "chicken"
    q_lower = query.lower()
    for prefix_len in range(max(1, len(q_lower) - 1), 0, -1):
        prefix = q_lower[:prefix_len]
        prefix_cached = _get_cached(prefix)
        if prefix_cached:
            # Filter cached prefix results that still match
            filtered = [r for r in prefix_cached if query.lower() in r.get("food_name", "").lower()]
            if len(filtered) >= limit:
                return _dedupe_and_rank(filtered, query, limit)
            break

    # Phase 1: Local DB (instant)
    local_results = _search_local(db, query, limit)
    logger.info(f"[suggest '{query}'] Local DB: {len(local_results)} results")

    # Phase 2: Fan out to external APIs with shorter timeout
    task_names: list[str] = []
    tasks = []
    if settings.usda_api_key:
        tasks.append(_search_usda(db, query, 8))
        task_names.append("USDA")
    if True:
        tasks.append(_search_open_food_facts(db, query, 8))
        task_names.append("OpenFoodFacts")
    if settings.edamam_app_id and settings.edamam_app_key:
        tasks.append(_search_edamam(db, query, 8))
        task_names.append("Edamam")
    if settings.fatsecret_consumer_key and settings.fatsecret_consumer_secret:
        tasks.append(_search_fatsecret(db, query, 8))
        task_names.append("FatSecret")

    external_results: list[dict] = []
    if tasks:
        try:
            async with asyncio.timeout(1.5):
                gathered = await asyncio.gather(*tasks, return_exceptions=True)
                for name, result in zip(task_names, gathered):
                    if isinstance(result, list):
                        logger.info(f"[suggest '{query}'] {name}: {len(result)} results")
                        external_results.extend(result)
                    elif isinstance(result, Exception):
                        logger.warning(f"[suggest '{query}'] {name}: FAILED — {result}")
        except asyncio.TimeoutError:
            logger.warning(f"[suggest '{query}'] Fan-out timed out (1.5s), using partial results")

    # Merge and rank
    all_results = local_results + external_results
    ranked = _dedupe_and_rank(all_results, query, limit)
    logger.info(f"[suggest '{query}'] Merged: {len(all_results)} total → {len(ranked)} ranked")

    # Cache results
    _set_cached(query, ranked)

    return ranked


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
