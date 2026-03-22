import httpx
import pytest
import respx

from nutrichat import NutriChatClient, AuthError


@pytest.mark.asyncio
async def test_search_food_returns_list(base_url, api_key):
    with respx.mock(base_url=base_url) as mock:
        mock.get("/api/v1/food/search").mock(
            return_value=httpx.Response(200, json=[
                {
                    "food_id": 1,
                    "food_name": "Paneer Butter Masala",
                    "brand": None,
                    "source": "ifct",
                    "calories_per_100g": 260.0,
                    "protein_per_100g": 11.0,
                    "fat_per_100g": 20.0,
                    "carbs_per_100g": 8.0,
                    "serving_size_g": 150.0,
                    "serving_description": "1 serving",
                },
            ])
        )

        async with NutriChatClient(api_key=api_key, base_url=base_url) as client:
            results = await client.search_food("paneer")

        assert isinstance(results, list)
        assert len(results) == 1
        assert results[0]["food_name"] == "Paneer Butter Masala"
        # Verify calories are computed for serving size (150g)
        assert results[0]["calories"] == 260.0 * 150.0 / 100.0


@pytest.mark.asyncio
async def test_search_food_empty_results(base_url, api_key):
    with respx.mock(base_url=base_url) as mock:
        mock.get("/api/v1/food/search").mock(
            return_value=httpx.Response(200, json=[])
        )

        async with NutriChatClient(api_key=api_key, base_url=base_url) as client:
            results = await client.search_food("nonexistent")

        assert results == []


@pytest.mark.asyncio
async def test_search_food_auth_error(base_url, api_key):
    with respx.mock(base_url=base_url) as mock:
        mock.get("/api/v1/food/search").mock(
            return_value=httpx.Response(401, json={"detail": "Invalid API key"})
        )

        async with NutriChatClient(api_key=api_key, base_url=base_url) as client:
            with pytest.raises(AuthError):
                await client.search_food("paneer")
