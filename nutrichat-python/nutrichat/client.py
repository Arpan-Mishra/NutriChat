"""NutriChatClient — async httpx-based API client for the NutriChat REST API."""

from datetime import date

import httpx

from nutrichat._compat import adapt_daily_totals, adapt_search_results
from nutrichat.exceptions import AuthError, NotFoundError, NutriChatError, RateLimitError

DEFAULT_BASE_URL = "https://api.nutrichat.app"
DEFAULT_TIMEOUT = 10.0


class NutriChatClient:
    """Async client for the NutriChat API.

    Args:
        api_key: Per-user API key (format: nutrichat_live_<32hex>).
        base_url: API base URL. Defaults to production.
        timeout: Request timeout in seconds. Defaults to 10.
    """

    def __init__(
        self,
        api_key: str,
        base_url: str = DEFAULT_BASE_URL,
        timeout: float = DEFAULT_TIMEOUT,
    ):
        self._api_key = api_key
        self._base_url = base_url.rstrip("/")
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=timeout,
        )

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.close()

    async def close(self):
        """Close the underlying httpx connection pool."""
        await self._client.aclose()

    def _handle_error(self, response: httpx.Response) -> None:
        """Raise appropriate exception for non-2xx responses."""
        if response.status_code == 401:
            raise AuthError()
        if response.status_code == 404:
            raise NotFoundError()
        if response.status_code == 429:
            retry_after = float(response.headers.get("retry-after", "60"))
            raise RateLimitError(retry_after=retry_after)
        if response.status_code >= 400:
            raise NutriChatError(
                message=f"API error: {response.status_code} — {response.text}",
                status_code=response.status_code,
            )

    async def search_food(self, query: str, limit: int = 10) -> list[dict]:
        """Search for foods. Returns FatSecret-compatible dicts via _compat.

        Args:
            query: Food name to search for.
            limit: Max number of results (1–50).

        Returns:
            List of dicts with keys: food_id, food_name, serving_description,
            metric_serving_amount, metric_serving_unit, calories, protein_g,
            fat_g, carbs_g, match_score.
        """
        response = await self._client.get(
            "/api/v1/food/search",
            params={"q": query, "limit": limit},
        )
        self._handle_error(response)
        items = response.json()
        return adapt_search_results(items)

    async def log_food_entries_batch(
        self,
        items: list[dict],
        meal_type: str,
        date: str | None = None,
    ) -> list[dict]:
        """Log multiple food entries in a single batch.

        Args:
            items: List of dicts, each with food_id, food_name, number_of_units, etc.
            meal_type: One of breakfast, lunch, dinner, snack.
            date: ISO 8601 date string (YYYY-MM-DD). Defaults to today.

        Returns:
            List of created entry dicts.
        """
        results = []
        for item in items:
            body = {
                "food_item_id": int(item.get("food_id", 0)) or None,
                "meal_type": meal_type,
                "food_description": item.get("food_name", "Unknown food"),
                "serving_size_g": float(item.get("number_of_units", 1))
                * float(item.get("metric_serving_amount", 100)),
                "source": "whatsapp",
            }
            if date:
                body["logged_date"] = date

            # Pass through serving unit + quantity if provided
            if "serving_unit" in item:
                body["serving_unit"] = item["serving_unit"]
                body["serving_quantity"] = float(item.get("number_of_units", 1))

            # Pass through macros if provided
            for key in ("calories", "protein_g", "fat_g", "carbs_g"):
                if key in item:
                    body[key] = float(item[key])

            response = await self._client.post("/api/v1/diary/entries", json=body)
            self._handle_error(response)
            results.append(response.json())
        return results

    async def get_today_totals(self, date: str | None = None) -> dict:
        """Get daily diary totals. Returns FatSecret-compatible dict via _compat.

        Args:
            date: ISO 8601 date string (YYYY-MM-DD). Defaults to today.

        Returns:
            Dict with keys: calories, protein_g, fat_g, carbs_g, meals.
        """
        from datetime import date as date_type

        target = date or date_type.today().isoformat()
        response = await self._client.get(f"/api/v1/diary/{target}")
        self._handle_error(response)
        return adapt_daily_totals(response.json())

    async def get_food_by_barcode(self, barcode: str) -> dict | None:
        """Look up a food by barcode.

        Args:
            barcode: EAN-13, UPC-A, or QR code string.

        Returns:
            FatSecret-compatible food dict, or None if not found.
        """
        try:
            response = await self._client.get(f"/api/v1/food/barcode/{barcode}")
            self._handle_error(response)
            item = response.json()
            results = adapt_search_results([item])
            return results[0] if results else None
        except NotFoundError:
            return None
