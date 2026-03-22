from datetime import date


ACTIVITY_MULTIPLIERS = {
    "sedentary": 1.2,
    "light": 1.375,
    "moderate": 1.55,
    "active": 1.725,
    "very_active": 1.9,
}

GOAL_ADJUSTMENTS = {
    "lose": -500,      # 500 kcal deficit (~0.5 kg/week loss)
    "maintain": 0,
    "gain": 300,       # 300 kcal surplus (~0.3 kg/week gain)
}


def calculate_age(dob: date) -> int:
    today = date.today()
    return today.year - dob.year - ((today.month, today.day) < (dob.month, dob.day))


def calculate_bmr(weight_kg: float, height_cm: float, age: int, sex: str) -> float:
    """Mifflin-St Jeor equation."""
    if sex == "male":
        return 10 * weight_kg + 6.25 * height_cm - 5 * age + 5
    else:
        return 10 * weight_kg + 6.25 * height_cm - 5 * age - 161


def calculate_tdee(bmr: float, activity_level: str) -> float:
    multiplier = ACTIVITY_MULTIPLIERS.get(activity_level, 1.2)
    return bmr * multiplier


def get_recommended_calories(tdee: float, goal_type: str) -> int:
    adjustment = GOAL_ADJUSTMENTS.get(goal_type, 0)
    recommended = max(1200, tdee + adjustment)  # never below 1200 kcal
    return round(recommended)


def compute_tdee_for_user(
    weight_kg: float,
    height_cm: float,
    dob: date,
    sex: str,
    activity_level: str,
    goal_type: str = "maintain",
) -> dict:
    age = calculate_age(dob)
    bmr = calculate_bmr(weight_kg, height_cm, age, sex)
    tdee = calculate_tdee(bmr, activity_level)
    recommended = get_recommended_calories(tdee, goal_type)

    return {
        "bmr": round(bmr, 1),
        "tdee": round(tdee, 1),
        "recommended_calories": recommended,
        "method": "mifflin_st_jeor",
        "goal_type": goal_type,
    }
