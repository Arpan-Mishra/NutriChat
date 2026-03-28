from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.models import FoodItem
from app.schemas import FoodItemResponse, FoodSearchResult, CustomFoodCreate
from app.middleware.auth import get_current_user_flexible
from app.models import User, FoodServing
from app.services.food_search import search_food, search_by_barcode, suggest_food

router = APIRouter(prefix="/api/v1/food", tags=["food"])


@router.get("/search", response_model=list[FoodSearchResult])
async def food_search(
    q: str = Query(..., min_length=1, description="Search query"),
    limit: int = Query(20, ge=1, le=50),
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Search for foods across local DB, USDA, Open Food Facts, Edamam, and FatSecret."""
    results = await search_food(db, q, limit)
    return results


@router.get("/suggest", response_model=list[FoodSearchResult])
async def food_suggest(
    q: str = Query(..., min_length=1, description="Typeahead query"),
    limit: int = Query(10, ge=1, le=20),
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Lightweight typeahead — local DB only, no external APIs."""
    results = await suggest_food(db, q, limit)
    return results


@router.get("/barcode/{barcode}", response_model=FoodSearchResult)
async def food_by_barcode(
    barcode: str,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Look up a food by barcode (EAN-13, UPC-A, etc.)."""
    result = await search_by_barcode(db, barcode)
    if not result:
        raise HTTPException(status_code=404, detail="Food not found for this barcode")
    return result


@router.get("/{food_id}", response_model=FoodItemResponse)
async def get_food(
    food_id: int,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Get full details of a food item, including available servings."""
    item = (
        db.query(FoodItem)
        .options(joinedload(FoodItem.servings))
        .filter(FoodItem.id == food_id)
        .first()
    )
    if not item:
        raise HTTPException(status_code=404, detail="Food item not found")
    return item


@router.post("/custom", response_model=FoodItemResponse)
async def create_custom_food(
    body: CustomFoodCreate,
    user: User = Depends(get_current_user_flexible),
    db: Session = Depends(get_db),
):
    """Create a custom food item."""
    item = FoodItem(
        source="custom",
        name=body.name,
        brand=body.brand,
        barcode=body.barcode,
        calories_per_100g=body.calories_per_100g,
        protein_per_100g=body.protein_per_100g,
        fat_per_100g=body.fat_per_100g,
        carbs_per_100g=body.carbs_per_100g,
        fiber_per_100g=body.fiber_per_100g,
        sodium_per_100g=body.sodium_per_100g,
        serving_size_g=body.serving_size_g,
        serving_description=body.serving_description,
        is_indian=body.is_indian,
        verified=False,
    )
    db.add(item)
    db.commit()
    db.refresh(item)

    # Create default serving for the custom food
    serving = FoodServing(
        food_item_id=item.id,
        serving_description=body.serving_description,
        serving_size_g=body.serving_size_g,
        metric_serving_amount=body.serving_size_g,
        metric_serving_unit="g",
        is_default=True,
    )
    db.add(serving)
    db.commit()
    db.refresh(item)

    return item
