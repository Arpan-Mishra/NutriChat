"""Response adapter — transforms NutriChat API responses into FatSecret-compatible shapes.

This module is the critical contract between the NutriChat SDK and CalorieBot.
Any change to the output dict keys or types is a BREAKING CHANGE requiring a major
version bump and a coordinated update in CalorieBot.
"""


def adapt_search_results(api_items: list[dict]) -> list[dict]:
    """Convert NutriChat food search results to FatSecret-compatible dicts.

    Required output keys per contract:
        food_id, food_name, serving_description, metric_serving_amount,
        metric_serving_unit, calories, protein_g, fat_g, carbs_g, match_score
    """
    adapted = []
    for item in api_items:
        result = {
            "food_id": str(item["food_id"]),
            "food_name": item["food_name"],
            "serving_description": item.get("serving_description", "100g"),
            "metric_serving_amount": float(item.get("serving_size_g", 100)),
            "metric_serving_unit": "g",
            "calories": float(item.get("calories_per_100g", 0))
            * float(item.get("serving_size_g", 100))
            / 100.0,
            "protein_g": float(item.get("protein_per_100g", 0))
            * float(item.get("serving_size_g", 100))
            / 100.0,
            "fat_g": float(item.get("fat_per_100g", 0))
            * float(item.get("serving_size_g", 100))
            / 100.0,
            "carbs_g": float(item.get("carbs_per_100g", 0))
            * float(item.get("serving_size_g", 100))
            / 100.0,
            "match_score": float(item.get("match_score", 0.8)),
        }

        # Optional: available servings (additive, non-breaking)
        if item.get("servings"):
            result["available_servings"] = [
                {
                    "serving_description": s.get("serving_description", "1 serving"),
                    "serving_size_g": float(s.get("serving_size_g", 100)),
                    "metric_serving_unit": s.get("metric_serving_unit", "g"),
                }
                for s in item["servings"]
            ]

        adapted.append(result)
    return adapted


def adapt_daily_totals(api_response: dict) -> dict:
    """Convert NutriChat diary day response to FatSecret-compatible totals dict.

    Required output keys per contract:
        calories, protein_g, fat_g, carbs_g, meals (list of meal dicts)
    """
    totals = api_response.get("totals", {})
    meals_raw = api_response.get("meals", {})

    meals = []
    for meal_type in ("breakfast", "lunch", "dinner", "snack"):
        entries_raw = meals_raw.get(meal_type, [])
        entries = []
        for entry in entries_raw:
            entries.append({
                "food_name": entry.get("food_description", ""),
                "calories": float(entry.get("calories", 0)),
                "serving_description": f"{entry.get('serving_size_g', 0)}g",
            })
        if entries:
            meals.append({
                "meal_type": meal_type,
                "entries": entries,
            })

    return {
        "calories": float(totals.get("calories", 0)),
        "protein_g": float(totals.get("protein_g", 0)),
        "fat_g": float(totals.get("fat_g", 0)),
        "carbs_g": float(totals.get("carbs_g", 0)),
        "meals": meals,
    }
