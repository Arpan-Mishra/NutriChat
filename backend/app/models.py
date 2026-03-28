from datetime import datetime, date
from sqlalchemy import (
    Column, Integer, String, Float, Boolean, DateTime, Date,
    Text, ForeignKey, UniqueConstraint
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String(20), unique=True, nullable=False, index=True)
    email = Column(String(255), unique=True, nullable=True)
    display_name = Column(String(100), nullable=True)
    date_of_birth = Column(Date, nullable=True)
    sex = Column(String(10), nullable=True)  # 'male', 'female', 'other'
    height_cm = Column(Float, nullable=True)
    weight_kg = Column(Float, nullable=True)
    activity_level = Column(String(20), nullable=True)  # sedentary, light, moderate, active, very_active
    goal_type = Column(String(20), nullable=True)  # lose, maintain, gain
    daily_calorie_goal = Column(Integer, nullable=True)
    protein_goal_g = Column(Integer, nullable=True)
    carbs_goal_g = Column(Integer, nullable=True)
    fat_goal_g = Column(Integer, nullable=True)
    timezone = Column(String(50), default="Asia/Kolkata")
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    meal_entries = relationship("MealEntry", back_populates="user", cascade="all, delete-orphan")
    api_keys = relationship("ApiKey", back_populates="user", cascade="all, delete-orphan")
    goals = relationship("Goal", back_populates="user", cascade="all, delete-orphan")
    weight_logs = relationship("WeightLog", back_populates="user", cascade="all, delete-orphan")


class OTPCode(Base):
    __tablename__ = "otp_codes"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String(20), nullable=False, index=True)
    code_hash = Column(String(255), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())


class ApiKey(Base):
    __tablename__ = "api_keys"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    key_prefix = Column(String(25), nullable=False)  # "nutrichat_live_" + first 5 hex chars
    key_hash = Column(String(255), nullable=False)
    label = Column(String(100), default="caloriebot")
    created_at = Column(DateTime, server_default=func.now())
    last_used_at = Column(DateTime, nullable=True)
    revoked_at = Column(DateTime, nullable=True)

    user = relationship("User", back_populates="api_keys")


class FoodItem(Base):
    __tablename__ = "food_items"

    id = Column(Integer, primary_key=True, index=True)
    external_id = Column(String(255), nullable=True)
    source = Column(String(20), nullable=False)  # usda, off, edamam, custom
    name = Column(String(500), nullable=False, index=True)
    brand = Column(String(255), nullable=True)
    barcode = Column(String(50), unique=True, nullable=True, index=True)
    calories_per_100g = Column(Float, nullable=False)
    protein_per_100g = Column(Float, default=0)
    fat_per_100g = Column(Float, default=0)
    carbs_per_100g = Column(Float, default=0)
    fiber_per_100g = Column(Float, default=0)
    sodium_per_100g = Column(Float, default=0)
    serving_size_g = Column(Float, default=100)
    serving_description = Column(String(100), default="100g")
    is_indian = Column(Boolean, default=False)
    verified = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    meal_entries = relationship("MealEntry", back_populates="food_item")
    servings = relationship("FoodServing", back_populates="food_item", cascade="all, delete-orphan")


class FoodServing(Base):
    """Available serving sizes for a food item (e.g. 1 cup = 240g, 1 tbsp = 15g)."""
    __tablename__ = "food_servings"

    id = Column(Integer, primary_key=True, index=True)
    food_item_id = Column(Integer, ForeignKey("food_items.id", ondelete="CASCADE"), nullable=False, index=True)
    serving_description = Column(String(200), nullable=False)  # "1 cup", "1 tbsp", "100g"
    serving_size_g = Column(Float, nullable=False)  # gram equivalent
    metric_serving_amount = Column(Float, nullable=True)  # e.g. 240 for "240ml"
    metric_serving_unit = Column(String(10), nullable=True)  # "g" or "ml"
    is_default = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())

    food_item = relationship("FoodItem", back_populates="servings")


class MealEntry(Base):
    __tablename__ = "meal_entries"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    food_item_id = Column(Integer, ForeignKey("food_items.id"), nullable=True)
    meal_type = Column(String(20), nullable=False)  # breakfast, lunch, dinner, snack
    food_description = Column(Text, nullable=False)
    serving_size_g = Column(Float, nullable=False)
    serving_unit = Column(String(20), nullable=True)  # g, ml, cup, tbsp, tsp, serving
    serving_quantity = Column(Float, nullable=True)  # e.g. 1.5 cups
    calories = Column(Float, nullable=False)
    protein_g = Column(Float, default=0)
    fat_g = Column(Float, default=0)
    carbs_g = Column(Float, default=0)
    fiber_g = Column(Float, default=0)
    sodium_mg = Column(Float, default=0)
    source = Column(String(20), default="app")  # app, whatsapp, barcode
    logged_date = Column(Date, nullable=False)
    logged_at = Column(DateTime, server_default=func.now())

    user = relationship("User", back_populates="meal_entries")
    food_item = relationship("FoodItem", back_populates="meal_entries")


class Goal(Base):
    __tablename__ = "goals"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    goal_type = Column(String(20), nullable=False)  # calorie, protein, carbs, fat, weight
    target_value = Column(Float, nullable=False)
    unit = Column(String(20), nullable=False)  # kcal, g, kg
    active = Column(Boolean, default=True)
    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    user = relationship("User", back_populates="goals")


class WeightLog(Base):
    __tablename__ = "weight_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    weight_kg = Column(Float, nullable=False)
    logged_at = Column(DateTime, server_default=func.now())
    notes = Column(Text, nullable=True)

    user = relationship("User", back_populates="weight_logs")
