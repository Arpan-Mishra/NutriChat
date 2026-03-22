"""nutrichat — Async Python SDK for the NutriChat calorie tracking API.

Used by CalorieBot (WhatsApp bot) to search food, log meals, and query daily totals
via the NutriChat REST API.

Usage:
    async with NutriChatClient(api_key="nutrichat_live_xxx") as client:
        results = await client.search_food("dal makhani")
"""

from nutrichat.client import NutriChatClient
from nutrichat.exceptions import AuthError, NotFoundError, NutriChatError, RateLimitError

__all__ = [
    "NutriChatClient",
    "NutriChatError",
    "AuthError",
    "NotFoundError",
    "RateLimitError",
]
