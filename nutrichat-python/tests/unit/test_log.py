import httpx
import pytest
import respx

from nutrichat import NutriChatClient


@pytest.mark.asyncio
async def test_log_food_entries_batch(base_url, api_key):
    with respx.mock(base_url=base_url) as mock:
        mock.post("/api/v1/diary/entries").mock(
            return_value=httpx.Response(201, json={
                "id": 1,
                "user_id": 1,
                "food_item_id": 42,
                "meal_type": "lunch",
                "food_description": "Rice",
                "serving_size_g": 150.0,
                "calories": 195.0,
                "protein_g": 4.05,
                "fat_g": 0.45,
                "carbs_g": 43.35,
                "fiber_g": 0.0,
                "sodium_mg": 0.0,
                "source": "whatsapp",
                "logged_date": "2026-03-22",
                "logged_at": "2026-03-22T12:00:00",
            })
        )

        async with NutriChatClient(api_key=api_key, base_url=base_url) as client:
            results = await client.log_food_entries_batch(
                items=[{
                    "food_id": 42,
                    "food_name": "Rice",
                    "number_of_units": 1.5,
                    "metric_serving_amount": 100,
                }],
                meal_type="lunch",
                date="2026-03-22",
            )

        assert len(results) == 1
        assert results[0]["meal_type"] == "lunch"
        assert results[0]["source"] == "whatsapp"


@pytest.mark.asyncio
async def test_log_multiple_entries(base_url, api_key):
    call_count = 0

    with respx.mock(base_url=base_url) as mock:
        def make_response(request):
            nonlocal call_count
            call_count += 1
            return httpx.Response(201, json={
                "id": call_count,
                "user_id": 1,
                "food_item_id": None,
                "meal_type": "lunch",
                "food_description": f"Food {call_count}",
                "serving_size_g": 100.0,
                "calories": 200.0,
                "protein_g": 10.0,
                "fat_g": 5.0,
                "carbs_g": 25.0,
                "fiber_g": 0.0,
                "sodium_mg": 0.0,
                "source": "whatsapp",
                "logged_date": "2026-03-22",
                "logged_at": "2026-03-22T12:00:00",
            })

        mock.post("/api/v1/diary/entries").mock(side_effect=make_response)

        async with NutriChatClient(api_key=api_key, base_url=base_url) as client:
            results = await client.log_food_entries_batch(
                items=[
                    {"food_name": "Rice", "number_of_units": 1, "metric_serving_amount": 100},
                    {"food_name": "Dal", "number_of_units": 1, "metric_serving_amount": 100},
                ],
                meal_type="lunch",
            )

        assert len(results) == 2
        assert call_count == 2
