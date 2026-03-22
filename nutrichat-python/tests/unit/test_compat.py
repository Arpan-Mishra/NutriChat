"""Contract tests — assert every required key is present in _compat output.

This file is the automated contract enforcement between the NutriChat SDK
and CalorieBot. It must never be skipped.
"""

import pytest

from nutrichat._compat import adapt_daily_totals, adapt_search_results

SEARCH_REQUIRED_KEYS = {
    "food_id",
    "food_name",
    "serving_description",
    "metric_serving_amount",
    "metric_serving_unit",
    "calories",
    "protein_g",
    "fat_g",
    "carbs_g",
    "match_score",
}

TOTALS_REQUIRED_KEYS = {"calories", "protein_g", "fat_g", "carbs_g", "meals"}

MEAL_ENTRY_REQUIRED_KEYS = {"food_name", "calories", "serving_description"}


def test_search_results_have_all_required_keys():
    api_items = [
        {
            "food_id": 1,
            "food_name": "Dal Makhani",
            "calories_per_100g": 116.0,
            "protein_per_100g": 6.5,
            "fat_per_100g": 4.0,
            "carbs_per_100g": 14.0,
            "serving_size_g": 200,
            "serving_description": "1 bowl",
        },
    ]
    results = adapt_search_results(api_items)
    assert len(results) == 1
    missing = SEARCH_REQUIRED_KEYS - results[0].keys()
    assert not missing, f"Missing _compat keys in search result: {missing}"


def test_search_results_correct_types():
    api_items = [
        {
            "food_id": 42,
            "food_name": "Roti",
            "calories_per_100g": 300.0,
            "protein_per_100g": 9.0,
            "fat_per_100g": 3.0,
            "carbs_per_100g": 55.0,
            "serving_size_g": 40,
            "serving_description": "1 roti",
        },
    ]
    result = adapt_search_results(api_items)[0]
    assert isinstance(result["food_id"], str)
    assert isinstance(result["food_name"], str)
    assert isinstance(result["serving_description"], str)
    assert isinstance(result["metric_serving_amount"], float)
    assert isinstance(result["metric_serving_unit"], str)
    assert result["metric_serving_unit"] in ("g", "ml")
    assert isinstance(result["calories"], float)
    assert isinstance(result["protein_g"], float)
    assert isinstance(result["fat_g"], float)
    assert isinstance(result["carbs_g"], float)
    assert isinstance(result["match_score"], float)
    assert 0.0 <= result["match_score"] <= 1.0


def test_daily_totals_have_all_required_keys():
    api_response = {
        "date": "2026-03-22",
        "meals": {
            "breakfast": [
                {
                    "food_description": "Idli",
                    "calories": 80.0,
                    "serving_size_g": 60,
                },
            ],
            "lunch": [],
            "dinner": [],
            "snack": [],
        },
        "totals": {
            "calories": 80.0,
            "protein_g": 2.0,
            "fat_g": 0.3,
            "carbs_g": 17.0,
        },
    }
    result = adapt_daily_totals(api_response)
    missing = TOTALS_REQUIRED_KEYS - result.keys()
    assert not missing, f"Missing _compat keys in daily totals: {missing}"


def test_daily_totals_meal_entries_have_required_keys():
    api_response = {
        "meals": {
            "lunch": [
                {
                    "food_description": "Chicken Biryani",
                    "calories": 350.0,
                    "serving_size_g": 250,
                },
            ],
            "breakfast": [],
            "dinner": [],
            "snack": [],
        },
        "totals": {"calories": 350.0, "protein_g": 20.0, "fat_g": 12.0, "carbs_g": 40.0},
    }
    result = adapt_daily_totals(api_response)
    assert len(result["meals"]) == 1
    entry = result["meals"][0]["entries"][0]
    missing = MEAL_ENTRY_REQUIRED_KEYS - entry.keys()
    assert not missing, f"Missing _compat keys in meal entry: {missing}"


def test_daily_totals_correct_types():
    api_response = {
        "meals": {"breakfast": [], "lunch": [], "dinner": [], "snack": []},
        "totals": {"calories": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0},
    }
    result = adapt_daily_totals(api_response)
    assert isinstance(result["calories"], float)
    assert isinstance(result["protein_g"], float)
    assert isinstance(result["fat_g"], float)
    assert isinstance(result["carbs_g"], float)
    assert isinstance(result["meals"], list)
