from datetime import datetime, date
from typing import Optional
from pydantic import BaseModel, Field


# --- Auth ---

class OTPRequest(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=20, examples=["+919958325792"])


class OTPVerify(BaseModel):
    phone_number: str = Field(..., min_length=10, max_length=20)
    code: str = Field(..., min_length=6, max_length=6)


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshRequest(BaseModel):
    refresh_token: str


# --- Users ---

class UserProfile(BaseModel):
    id: int
    phone_number: str
    email: Optional[str] = None
    display_name: Optional[str] = None
    date_of_birth: Optional[date] = None
    sex: Optional[str] = None
    height_cm: Optional[float] = None
    weight_kg: Optional[float] = None
    activity_level: Optional[str] = None
    goal_type: Optional[str] = None
    daily_calorie_goal: Optional[int] = None
    protein_goal_g: Optional[int] = None
    carbs_goal_g: Optional[int] = None
    fat_goal_g: Optional[int] = None
    timezone: str
    created_at: datetime

    model_config = {"from_attributes": True}


class UserUpdate(BaseModel):
    email: Optional[str] = None
    display_name: Optional[str] = None
    date_of_birth: Optional[date] = None
    sex: Optional[str] = Field(None, pattern="^(male|female|other)$")
    height_cm: Optional[float] = Field(None, gt=0, le=300)
    weight_kg: Optional[float] = Field(None, gt=0, le=500)
    activity_level: Optional[str] = Field(None, pattern="^(sedentary|light|moderate|active|very_active)$")
    goal_type: Optional[str] = Field(None, pattern="^(lose|maintain|gain)$")
    daily_calorie_goal: Optional[int] = Field(None, gt=0, le=10000)
    protein_goal_g: Optional[int] = Field(None, ge=0, le=1000)
    carbs_goal_g: Optional[int] = Field(None, ge=0, le=2000)
    fat_goal_g: Optional[int] = Field(None, ge=0, le=1000)
    timezone: Optional[str] = None


# --- TDEE ---

class TDEEResponse(BaseModel):
    bmr: float
    tdee: float
    recommended_calories: int
    method: str = "mifflin_st_jeor"
    goal_type: Optional[str] = None


# --- Food ---

class FoodServingResponse(BaseModel):
    id: int
    serving_description: str
    serving_size_g: float
    metric_serving_amount: Optional[float] = None
    metric_serving_unit: Optional[str] = None
    is_default: bool

    model_config = {"from_attributes": True}


class FoodItemResponse(BaseModel):
    id: int
    external_id: Optional[str] = None
    source: str
    name: str
    brand: Optional[str] = None
    barcode: Optional[str] = None
    calories_per_100g: float
    protein_per_100g: float
    fat_per_100g: float
    carbs_per_100g: float
    fiber_per_100g: float
    sodium_per_100g: float
    serving_size_g: float
    serving_description: str
    is_indian: bool
    verified: bool
    servings: list[FoodServingResponse] = []

    model_config = {"from_attributes": True}


class FoodSearchResult(BaseModel):
    food_id: int
    food_name: str
    brand: Optional[str] = None
    source: str
    calories_per_100g: float
    protein_per_100g: float
    fat_per_100g: float
    carbs_per_100g: float
    serving_size_g: float
    serving_description: str
    servings: list[FoodServingResponse] = []


class CustomFoodCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=500)
    brand: Optional[str] = None
    barcode: Optional[str] = None
    calories_per_100g: float = Field(..., ge=0)
    protein_per_100g: float = Field(0, ge=0)
    fat_per_100g: float = Field(0, ge=0)
    carbs_per_100g: float = Field(0, ge=0)
    fiber_per_100g: float = Field(0, ge=0)
    sodium_per_100g: float = Field(0, ge=0)
    serving_size_g: float = Field(100, gt=0)
    serving_description: str = "100g"
    is_indian: bool = False


# --- Meal Entries ---

class MealEntryCreate(BaseModel):
    food_item_id: Optional[int] = None
    meal_type: str = Field(..., pattern="^(breakfast|lunch|dinner|snack)$")
    food_description: str = Field(..., min_length=1)
    serving_size_g: float = Field(..., gt=0)
    serving_unit: Optional[str] = Field(None, pattern="^(g|ml|cup|tbsp|tsp|serving|piece)$")
    serving_quantity: Optional[float] = Field(None, gt=0)
    calories: Optional[float] = None  # auto-computed from food_item if not provided
    protein_g: Optional[float] = None
    fat_g: Optional[float] = None
    carbs_g: Optional[float] = None
    fiber_g: Optional[float] = None
    sodium_mg: Optional[float] = None
    source: str = Field("app", pattern="^(app|whatsapp|barcode)$")
    logged_date: Optional[date] = None  # defaults to today


class MealEntryResponse(BaseModel):
    id: int
    user_id: int
    food_item_id: Optional[int] = None
    meal_type: str
    food_description: str
    serving_size_g: float
    serving_unit: Optional[str] = None
    serving_quantity: Optional[float] = None
    calories: float
    protein_g: float
    fat_g: float
    carbs_g: float
    fiber_g: float
    sodium_mg: float
    source: str
    logged_date: date
    logged_at: datetime

    model_config = {"from_attributes": True}


class MealEntryUpdate(BaseModel):
    meal_type: Optional[str] = Field(None, pattern="^(breakfast|lunch|dinner|snack)$")
    serving_size_g: Optional[float] = Field(None, gt=0)
    food_description: Optional[str] = None


class DayDiaryResponse(BaseModel):
    date: date
    meals: dict[str, list[MealEntryResponse]]  # breakfast, lunch, dinner, snack
    totals: dict[str, float]  # calories, protein_g, fat_g, carbs_g
    goals: dict[str, Optional[int]]  # calorie_goal, protein_goal, etc.
    progress_pct: dict[str, Optional[float]]


# --- API Keys ---

class ApiKeyCreate(BaseModel):
    label: str = Field("caloriebot", max_length=100)


class ApiKeyResponse(BaseModel):
    id: int
    key_prefix: str
    label: str
    created_at: datetime
    last_used_at: Optional[datetime] = None
    revoked_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class ApiKeyCreated(BaseModel):
    id: int
    api_key: str  # shown only once
    label: str
    created_at: datetime


# --- Goals ---

class GoalCreate(BaseModel):
    goal_type: str = Field(..., pattern="^(calorie|protein|carbs|fat|weight)$")
    target_value: float = Field(..., gt=0)
    unit: str = Field(..., pattern="^(kcal|g|kg)$")
    start_date: Optional[date] = None
    end_date: Optional[date] = None


class GoalResponse(BaseModel):
    id: int
    user_id: int
    goal_type: str
    target_value: float
    unit: str
    active: bool
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class GoalUpdate(BaseModel):
    target_value: Optional[float] = Field(None, gt=0)
    active: Optional[bool] = None
    end_date: Optional[date] = None


# --- Stats ---

class DailyStatsResponse(BaseModel):
    date: date
    calories: float
    protein_g: float
    fat_g: float
    carbs_g: float
    entry_count: int
    calorie_goal: Optional[int] = None
    calorie_goal_pct: Optional[float] = None


class WeeklyStatsResponse(BaseModel):
    start_date: date
    end_date: date
    total_days: int
    days_logged: int
    total_calories: float
    avg_calories: float
    avg_protein_g: float
    avg_fat_g: float
    avg_carbs_g: float
    total_entries: int
    calorie_goal: Optional[int] = None


# --- Weight ---

class WeightLogCreate(BaseModel):
    weight_kg: float = Field(..., gt=0, le=500)
    notes: Optional[str] = None


class WeightLogResponse(BaseModel):
    id: int
    user_id: int
    weight_kg: float
    notes: Optional[str] = None
    logged_at: datetime

    model_config = {"from_attributes": True}
