import httpx
import pytest
import respx

from nutrichat import NutriChatClient


@pytest.mark.asyncio
async def test_get_today_totals(base_url, api_key):
    with respx.mock(base_url=base_url) as mock:
        mock.get("/api/v1/diary/2026-03-22").mock(
            return_value=httpx.Response(200, json={
                "date": "2026-03-22",
                "meals": {
                    "breakfast": [
                        {
                            "id": 1,
                            "food_description": "2 Boiled Eggs",
                            "serving_size_g": 100,
                            "calories": 155.0,
                            "protein_g": 13.0,
                            "fat_g": 11.0,
                            "carbs_g": 1.1,
                        },
                    ],
                    "lunch": [
                        {
                            "id": 2,
                            "food_description": "Dal Makhani",
                            "serving_size_g": 200,
                            "calories": 230.0,
                            "protein_g": 9.0,
                            "fat_g": 10.0,
                            "carbs_g": 25.0,
                        },
                    ],
                    "dinner": [],
                    "snack": [],
                },
                "totals": {
                    "calories": 385.0,
                    "protein_g": 22.0,
                    "fat_g": 21.0,
                    "carbs_g": 26.1,
                },
                "goals": {"calorie_goal": 2000},
                "progress_pct": {"calories": 19.3},
            })
        )

        async with NutriChatClient(api_key=api_key, base_url=base_url) as client:
            totals = await client.get_today_totals(date="2026-03-22")

        assert totals["calories"] == 385.0
        assert totals["protein_g"] == 22.0
        assert isinstance(totals["meals"], list)
        assert len(totals["meals"]) == 2  # only breakfast and lunch have entries


@pytest.mark.asyncio
async def test_get_today_totals_empty_day(base_url, api_key):
    with respx.mock(base_url=base_url) as mock:
        mock.get("/api/v1/diary/2026-03-22").mock(
            return_value=httpx.Response(200, json={
                "date": "2026-03-22",
                "meals": {
                    "breakfast": [],
                    "lunch": [],
                    "dinner": [],
                    "snack": [],
                },
                "totals": {"calories": 0, "protein_g": 0, "fat_g": 0, "carbs_g": 0},
                "goals": {},
                "progress_pct": {},
            })
        )

        async with NutriChatClient(api_key=api_key, base_url=base_url) as client:
            totals = await client.get_today_totals(date="2026-03-22")

        assert totals["calories"] == 0
        assert totals["meals"] == []
