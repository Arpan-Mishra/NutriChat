"""FatSecret API integration using OAuth 2.0 client credentials flow."""

import logging
import time
from base64 import b64encode

import httpx

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

HTTPX_TIMEOUT = 10.0
TOKEN_URL = "https://oauth.fatsecret.com/connect/token"
API_URL = "https://platform.fatsecret.com/rest/server.api"

# In-memory token cache
_token_cache: dict = {"access_token": "", "expires_at": 0.0}


async def _get_access_token() -> str:
    """Get a valid OAuth 2.0 access token, refreshing if expired."""
    if not settings.fatsecret_consumer_key or not settings.fatsecret_consumer_secret:
        raise ValueError("FatSecret credentials not configured")

    if _token_cache["access_token"] and time.time() < _token_cache["expires_at"]:
        return _token_cache["access_token"]

    credentials = b64encode(
        f"{settings.fatsecret_consumer_key}:{settings.fatsecret_consumer_secret}".encode()
    ).decode()

    async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
        resp = await client.post(
            TOKEN_URL,
            headers={
                "Authorization": f"Basic {credentials}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data={"grant_type": "client_credentials", "scope": "basic"},
        )
        resp.raise_for_status()
        data = resp.json()

    _token_cache["access_token"] = data["access_token"]
    _token_cache["expires_at"] = time.time() + data.get("expires_in", 86400) - 60
    return _token_cache["access_token"]


async def search_foods(query: str, max_results: int = 10) -> list[dict]:
    """Search FatSecret for food items. Returns raw API response foods."""
    try:
        token = await _get_access_token()
        async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
            resp = await client.post(
                API_URL,
                headers={"Authorization": f"Bearer {token}"},
                data={
                    "method": "foods.search",
                    "search_expression": query,
                    "max_results": str(max_results),
                    "format": "json",
                },
            )
            if resp.status_code != 200:
                logger.warning(f"FatSecret API returned {resp.status_code}")
                return []

            data = resp.json()
            foods = data.get("foods", {}).get("food", [])
            # FatSecret returns a single dict if only 1 result, otherwise a list
            if isinstance(foods, dict):
                foods = [foods]
            return foods
    except Exception as e:
        logger.warning(f"FatSecret search failed: {e}")
        return []


async def get_food_servings(food_id: str) -> list[dict]:
    """Get detailed serving information for a food item."""
    try:
        token = await _get_access_token()
        async with httpx.AsyncClient(timeout=HTTPX_TIMEOUT) as client:
            resp = await client.post(
                API_URL,
                headers={"Authorization": f"Bearer {token}"},
                data={
                    "method": "food.get.v4",
                    "food_id": food_id,
                    "format": "json",
                },
            )
            if resp.status_code != 200:
                return []

            data = resp.json()
            servings = data.get("food", {}).get("servings", {}).get("serving", [])
            if isinstance(servings, dict):
                servings = [servings]
            return servings
    except Exception as e:
        logger.warning(f"FatSecret food.get failed for {food_id}: {e}")
        return []
