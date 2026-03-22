# NutriChat Backend

FastAPI backend for the NutriChat calorie tracking iOS app + WhatsApp bot integration.

## Quick Start

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # edit with your values
python -m scripts.seed_indian_foods  # seed 100 Indian foods
uvicorn app.main:app --reload --port 8000
```

API docs at http://localhost:8000/docs

## Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI app, lifespan, router includes
│   ├── config.py             # Pydantic settings (reads .env)
│   ├── database.py           # SQLAlchemy engine, session, Base
│   ├── models.py             # All SQLAlchemy models
│   ├── schemas.py            # Pydantic request/response schemas
│   ├── routers/
│   │   ├── auth.py           # POST /api/v1/auth/otp/request, /otp/verify, /refresh, /logout
│   │   ├── users.py          # GET/PATCH /api/v1/users/me, GET /users/me/tdee
│   │   └── food.py           # GET /api/v1/food/search, /barcode/{code}, /{id}, POST /custom
│   ├── services/
│   │   ├── auth.py           # OTP generation, JWT creation, API key hashing
│   │   ├── tdee.py           # Mifflin-St Jeor BMR + TDEE calculation
│   │   └── food_search.py    # Layered search: local DB → USDA → OFF → Edamam
│   └── middleware/
│       └── auth.py           # JWT Bearer + API key auth dependencies
├── alembic/                  # Database migrations
├── scripts/
│   └── seed_indian_foods.py  # 100 common Indian foods from IFCT data
├── tests/
├── requirements.txt
├── .env.example
└── alembic.ini
```

## Auth

Two auth mechanisms (both use `Authorization: Bearer <token>` header):
- **JWT tokens**: for iOS app users. Obtained via OTP verify flow.
- **API keys**: for WhatsApp bot (nutrichat PyPI package). Format: `nutrichat_live_<32hex>`. Generated in app, shown once.

The `get_current_user_flexible` dependency accepts either auth type.

## Food Search Strategy

Layered search with automatic caching:
1. Local `food_items` table (ILIKE search) — instant, free
2. USDA FoodData Central API — authoritative, free (1K req/hr)
3. Open Food Facts API — barcodes, international, free
4. Edamam API — NLP queries, Indian food coverage (1K req/day free)

Every external API result is cached into `food_items` so it's only fetched once.

## Database

SQLite for local dev, PostgreSQL for production. Tables:
- `users` — phone number as primary identity
- `otp_codes` — short-lived OTP storage
- `api_keys` — hashed keys for bot integration
- `food_items` — cached food database (replaces FatSecret)
- `meal_entries` — user's food diary
- `goals` — calorie/macro targets
- `weight_logs` — weight history

## Environment Variables

See `.env.example`. Key ones:
- `DATABASE_URL` — PostgreSQL connection string (or `sqlite:///./nutrichat.db` for dev)
- `JWT_SECRET_KEY` — random 32-byte hex string
- `USDA_API_KEY` — free from api.data.gov
- `EDAMAM_APP_ID` / `EDAMAM_APP_KEY` — free from developer.edamam.com

## Testing

```bash
pytest tests/ -v
```
