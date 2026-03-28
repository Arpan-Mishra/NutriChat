"""FatSecret API integration using the fatsecret Python package (OAuth 1.0)."""

import asyncio
import logging

from fatsecret import Fatsecret

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

# Lazy-initialized client (created on first use)
_client: Fatsecret | None = None


def _get_client() -> Fatsecret:
    """Get or create the FatSecret client singleton."""
    global _client
    if _client is None:
        if not settings.fatsecret_consumer_key or not settings.fatsecret_consumer_secret:
            raise ValueError("FatSecret credentials not configured")
        _client = Fatsecret(settings.fatsecret_consumer_key, settings.fatsecret_consumer_secret)
    return _client


async def search_foods(query: str, max_results: int = 10) -> list[dict]:
    """Search FatSecret for food items. Returns raw API response foods."""
    try:
        client = _get_client()
        # fatsecret package is sync — run in thread to avoid blocking
        results = await asyncio.to_thread(
            client.foods_search, query, max_results=max_results
        )
        if not results:
            return []
        return results if isinstance(results, list) else [results]
    except Exception as e:
        logger.warning(f"FatSecret search failed: {e}")
        return []


async def get_food_servings(food_id: str) -> list[dict]:
    """Get detailed serving information for a food item."""
    try:
        client = _get_client()
        food = await asyncio.to_thread(client.food_get, food_id)
        if not food:
            return []
        servings = food.get("servings", {}).get("serving", [])
        if isinstance(servings, dict):
            servings = [servings]
        return servings
    except Exception as e:
        logger.warning(f"FatSecret food.get failed for {food_id}: {e}")
        return []
