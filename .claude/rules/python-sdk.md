# NutriChat Python SDK — Rules
# .claude/rules/python-sdk.md
#
# Load this file when working in nutrichat-python/

The `nutrichat` PyPI package — an async Python SDK wrapping the NutriChat REST API.
Used by CalorieBot (WhatsApp bot) to search food, log meals, and query daily totals.

---

## Quick-Start

```bash
cd nutrichat-python

# Install uv (once per machine)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtualenv and install with dev extras — never call pip directly
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"

# Run unit tests (no API key required — HTTP is mocked)
uv run pytest tests/unit/ -v

# Run integration tests against the live dev backend
NUTRICHAT_API_KEY=nutrichat_live_xxx uv run pytest tests/integration/ -v

# Build and publish to PyPI
uv run python -m build
uv run twine upload dist/*
```

---

## Project Structure

```
nutrichat-python/
├── nutrichat/
│   ├── __init__.py          # Exports: NutriChatClient + all exception classes
│   ├── client.py            # NutriChatClient — async httpx-based API client
│   ├── models.py            # Pydantic models: FoodItem, MealEntry, DailyTotals
│   ├── exceptions.py        # NutriChatError, AuthError, NotFoundError, RateLimitError
│   └── _compat.py           # Return-shape adapter — MUST match FatSecret dict keys exactly
│
├── tests/
│   ├── conftest.py
│   ├── unit/                # Mocked with respx — no API key required
│   │   ├── test_search.py
│   │   ├── test_log.py
│   │   ├── test_totals.py
│   │   └── test_compat.py   # Asserts every required _compat key is present — contract test
│   └── integration/         # Hits live dev backend — run manually only
│       └── test_live.py
│
├── pyproject.toml           # uv / PEP 517 config, package metadata, ruff settings
├── CHANGELOG.md             # Required — updated on every version bump
├── README.md
└── .env.example
```

---

## Environment Variables

```bash
NUTRICHAT_API_KEY=nutrichat_live_<key>        # required for integration tests
NUTRICHAT_BASE_URL=https://api.nutrichat.app  # optional — defaults to production
```

---

## Python Code Style

### Naming

| Thing | Convention | Example |
|-------|-----------|---------|
| Functions and variables | `snake_case` | `search_food`, `api_key` |
| Classes | `PascalCase` | `NutriChatClient`, `FoodItem` |
| Constants | `UPPER_SNAKE_CASE` | `DEFAULT_TIMEOUT = 10.0` |
| Handler methods | `handle_` prefix | `handle_rate_limit_error` |
| Boolean variables | `is_` / `has_` | `is_revoked`, `has_result` |

### Formatting and tooling

**uv for everything** — never call `pip` directly.

```bash
uv run ruff format .
uv run ruff check . --fix
```

- Line length: 100 characters
- F-strings only — no `%` or `.format()`
- Google-style docstrings on all public classes and methods
- Module-level docstring in `__init__.py` explaining what the package is and does

---

## NutriChatClient API

### Instantiation

```python
from nutrichat import NutriChatClient

client = NutriChatClient(
    api_key="nutrichat_live_xxxx",           # required — per-user key from NutriChat iOS app
    base_url="https://api.nutrichat.app",    # optional — defaults to production
    timeout=10.0,                            # optional — seconds, default 10
)
```

Prefer using the client as an async context manager so the httpx connection pool
is properly closed:

```python
async with NutriChatClient(api_key="nutrichat_live_xxx") as client:
    results = await client.search_food("dal makhani")
```

### Methods

```python
# Food search — returns list[dict] with _compat keys
results = await client.search_food("chicken biryani", limit=5)

# Batch log
logged = await client.log_food_entries_batch(
    items=[{"food_id": 42, "food_name": "Rice", "number_of_units": 1.5, ...}],
    meal_type="lunch",       # breakfast | lunch | dinner | snack
    date="2026-03-22",       # ISO 8601 date string
)

# Today's totals — returns dict with _compat keys
totals = await client.get_today_totals(date="2026-03-22")

# Barcode lookup — bonus method, not in fatsecret
food = await client.get_food_by_barcode("8901491107989")
```

---

## _compat.py — The Critical Contract

`_compat.py` transforms NutriChat API responses into the **exact same dict structure**
that CalorieBot's `nutrition_agent.py` currently receives from `fatsecret.py`.

This guarantees the CalorieBot agent needs **zero code changes** after migration.
Only the import line and client instantiation change in CalorieBot.

**Any change to the shapes below is a BREAKING CHANGE** — see the Breaking Change
Policy at the end of this section.

### Required keys: `search_food()` — each item in the returned list

```python
{
    "food_id":                str,
    "food_name":              str,
    "serving_description":    str,
    "metric_serving_amount":  float,
    "metric_serving_unit":    str,    # "g" or "ml" only
    "calories":               float,
    "protein_g":              float,
    "fat_g":                  float,
    "carbs_g":                float,
    "match_score":            float,  # 0.0–1.0
}
```

### Required keys: `get_today_totals()` — top-level dict

```python
{
    "calories":  float,
    "protein_g": float,
    "fat_g":     float,
    "carbs_g":   float,
    "meals": [
        {
            "meal_type": str,   # breakfast | lunch | dinner | snack
            "entries": [
                {
                    "food_name":           str,
                    "calories":            float,
                    "serving_description": str,
                }
            ],
        }
    ],
}
```

### Breaking change policy

When any key name, type, or structure above changes:

1. Bump the **major** version in `pyproject.toml`
2. Update CalorieBot to use the new shape in the same PR
3. Add a migration note to `CHANGELOG.md`

`tests/unit/test_compat.py` must assert **every required key is present** in the
adapted response — this test is the automated contract enforcement.

---

## Exceptions

```python
from nutrichat import (
    NutriChatError,    # base — catch this for generic handling
    AuthError,         # 401 — invalid or revoked API key
    NotFoundError,     # 404 — food or entry not found
    RateLimitError,    # 429 — has .retry_after attribute (seconds)
)
```

```python
try:
    results = await client.search_food("roti")
except AuthError:
    # API key is invalid or revoked — prompt user to relink bot in NutriChat iOS app
    ...
except RateLimitError as e:
    await asyncio.sleep(e.retry_after)
    results = await client.search_food("roti")
except NutriChatError as e:
    # Unexpected error — log and surface to the user
    logger.error(f"NutriChat SDK error: {e}")
```

---

## Testing

```bash
# Unit tests — mocked HTTP, no API key needed
uv run pytest tests/unit/ -v

# Integration tests — hits live dev backend, requires API key
NUTRICHAT_API_KEY=nutrichat_live_xxx uv run pytest tests/integration/ -v

# All tests with coverage
uv run pytest tests/ --cov=nutrichat --cov-report=term-missing
```

### Unit test pattern

```python
import respx, httpx, pytest
from nutrichat import NutriChatClient

@pytest.mark.asyncio
async def test_search_food_returns_compat_shape(respx_mock):
    respx_mock.get("https://api.nutrichat.app/api/v1/food/search").mock(
        return_value=httpx.Response(200, json={"items": [
            {"id": 1, "name": "Dal", "calories_per_100g": 116.0, ...}
        ]})
    )
    async with NutriChatClient(api_key="test") as client:
        results = await client.search_food("dal")

    assert isinstance(results, list)
    required_keys = {
        "food_id", "food_name", "serving_description",
        "metric_serving_amount", "metric_serving_unit",
        "calories", "protein_g", "fat_g", "carbs_g", "match_score",
    }
    assert required_keys.issubset(results[0].keys()), (
        f"Missing _compat keys: {required_keys - results[0].keys()}"
    )
```

`tests/unit/test_compat.py` runs this assertion for **both** `search_food()` and
`get_today_totals()` on every run — it is the contract test and must never be skipped.

---

## Publishing

```bash
# 1. Bump version in pyproject.toml (follow semver — see below)
# 2. Update CHANGELOG.md with release notes
# 3. Build
uv run python -m build

# 4. Test on TestPyPI first
uv run twine upload --repository testpypi dist/*
pip install --index-url https://test.pypi.org/simple/ nutrichat==<new-version>
# smoke test the new version against dev backend

# 5. Publish to production PyPI
uv run twine upload dist/*
```

### Version policy (semver)

| Change type | Bump |
|-------------|------|
| `_compat.py` key/type/shape change | **MAJOR** |
| New client method | **MINOR** |
| Bug fix, internal refactor | **PATCH** |

---

## Git

```bash
# Always run before and after work
git status && git diff --stat

# Standard commit
git add -A
git commit -m "feat(sdk): <description>"
git push origin main

# Auto-commit when diff >= 10%
git add -A && git commit -m "chore(sdk): auto-commit — diff threshold" && git push origin main
```

Scope for all SDK commits: `(sdk)`.