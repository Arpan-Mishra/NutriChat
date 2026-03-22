# NutriChat Backend — Rules
# .claude/rules/backend.md
#
# Load this file when working in nutrichat-backend/

FastAPI + PostgreSQL backend. Powers the iOS app (JWT auth) and the
nutrichat PyPI package (API key auth). Deployed on Railway.

---

## Quick-Start

```bash
cd nutrichat-backend

# Install uv (once per machine)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create virtualenv and install all deps — never call pip directly
uv venv && source .venv/bin/activate
uv pip install -e ".[dev]"

# Configure environment
cp .env.example .env
# fill in all values before running

# Apply all pending migrations
uv run alembic upgrade head

# Start dev server with hot reload
uv run uvicorn app.main:app --reload --port 8000

# Open interactive API docs
open http://localhost:8000/docs
```

---

## Project Structure

```
nutrichat-backend/
├── app/
│   ├── main.py                  # FastAPI app, lifespan hook, middleware, router registration
│   ├── config.py                # Pydantic Settings — single source for all env vars
│   ├── database.py              # Async engine, AsyncSession factory, get_db dependency
│   ├── dependencies.py          # Shared Depends: get_current_user, pagination params
│   │
│   ├── models/                  # SQLAlchemy ORM — one file per domain table
│   │   ├── base.py              # DeclarativeBase shared by all models
│   │   ├── user.py
│   │   ├── api_key.py
│   │   ├── food_item.py
│   │   ├── meal_entry.py
│   │   ├── goal.py
│   │   ├── weight_log.py
│   │   └── otp_code.py
│   │
│   ├── schemas/                 # Pydantic request / response shapes — one file per domain
│   │   ├── auth.py
│   │   ├── user.py
│   │   ├── food.py
│   │   ├── diary.py
│   │   ├── goals.py
│   │   ├── stats.py
│   │   └── api_key.py
│   │
│   ├── routers/                 # FastAPI APIRouter — thin handlers only, one file per domain
│   │   ├── auth.py
│   │   ├── users.py
│   │   ├── food.py
│   │   ├── diary.py
│   │   ├── goals.py
│   │   ├── stats.py
│   │   ├── weight.py
│   │   └── api_keys.py
│   │
│   ├── services/                # Business logic — no HTTP objects, no DB session
│   │   ├── auth.py              # OTP generation, JWT create/verify
│   │   ├── food_search.py       # Layered search orchestration
│   │   ├── tdee.py              # Mifflin-St Jeor BMR + TDEE
│   │   └── stats.py             # Aggregation helpers
│   │
│   ├── repositories/            # DB queries only — no business logic
│   │   ├── user_repo.py
│   │   ├── food_repo.py
│   │   ├── diary_repo.py
│   │   └── api_key_repo.py
│   │
│   ├── integrations/            # External API clients (never called from routers directly)
│   │   ├── usda.py
│   │   ├── open_food_facts.py
│   │   └── edamam.py
│   │
│   └── utils/
│       ├── security.py          # bcrypt helpers, JWT encode/decode
│       └── timezone.py          # Date normalisation for user timezones
│
├── alembic/
│   ├── env.py
│   └── versions/
│
├── tests/
│   ├── conftest.py              # Fixtures: db_session, test_client, test_user, auth_headers
│   ├── unit/
│   └── integration/
│
├── scripts/
│   └── seed_indian_foods.py     # IFCT + Open Food Facts seed data (Sprint 2)
│
├── pyproject.toml               # uv / PEP 517 config, ruff settings
├── .env.example                 # All vars with placeholder values — always keep up to date
└── .env                         # Never committed
```

---

## Environment Variables

```bash
# .env.example — copy to .env and fill in all values before first run

DATABASE_URL=postgresql+asyncpg://user:pass@localhost:5432/nutrichat

JWT_SECRET_KEY=changeme-replace-with-openssl-rand-hex-32
JWT_ALGORITHM=HS256
JWT_ACCESS_TOKEN_EXPIRE_MINUTES=30
JWT_REFRESH_TOKEN_EXPIRE_DAYS=30

USDA_API_KEY=
EDAMAM_APP_ID=
EDAMAM_APP_KEY=

ANTHROPIC_API_KEY=        # Claude fallback for /diary/quick-log natural-language entry

RAILWAY_ENVIRONMENT=development   # set to 'production' on Railway
```

Never commit `.env`. Always keep `.env.example` in sync when adding new variables.

---

## Python Code Style

### Naming

| Thing | Convention | Example |
|-------|-----------|---------|
| Functions and variables | `snake_case` | `create_meal_entry`, `user_id` |
| Classes | `PascalCase` | `MealEntryCreate`, `UserRepository` |
| Constants | `UPPER_SNAKE_CASE` | `OTP_EXPIRY_SECONDS = 300` |
| Event / action handlers | `handle_` prefix | `handle_otp_request` |
| Boolean variables | `is_` / `has_` / `can_` | `is_revoked`, `has_active_key` |

### Formatting and tooling

**uv for everything** — never call `pip` directly.

```bash
# Format all files
uv run ruff format .

# Lint and auto-fix
uv run ruff check . --fix
```

- Line length: 100 characters
- String formatting: f-strings only — no `%` or `.format()`
- All public functions and classes: Google-style docstrings
- Pydantic schema fields: `Field(description="...")` on every field

---

## FastAPI Patterns

### Async-first — no exceptions

All route handlers and dependency functions must be `async def`.
Sync routes run in a threadpool — unnecessary overhead for a fully async app.

```python
# CORRECT
@router.get("/food/search")
async def search_food(
    q: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[FoodResponse]:
    return await food_repo.search(db, query=q)

# WRONG — sync inside an async app = thread overhead for no reason
@router.get("/food/search")
def search_food(q: str):
    ...
```

### Keep routes thin

Routers own only the HTTP boundary: parse input, call a service or repository,
return the response. Business logic lives in `services/`. DB queries live in
`repositories/`. Nothing else belongs in a router.

```python
@router.post("/entries", response_model=MealEntryResponse, status_code=201)
async def create_meal_entry(
    body: MealEntryCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> MealEntryResponse:
    """Log a food entry to the diary."""
    return await diary_repo.create_entry(db, user_id=user.id, data=body)
```

### Dependency injection

Use `Depends()` for all cross-cutting concerns:

```python
db: AsyncSession       = Depends(get_db)
user: User             = Depends(get_current_user)   # works for both JWT and ApiKey
pagination: PageParams = Depends()
```

`get_current_user` tries JWT Bearer first, then ApiKey header — returns the same
`User` object either way. Routers never need to know which auth method was used.

### Error handling

Raise domain exceptions from services and repositories.
Map them to HTTP responses via global exception handlers in `main.py`.
**Never raise `HTTPException` inside a service or repository.**

```python
# services/auth.py
class OTPExpiredError(Exception): ...
class OTPInvalidError(Exception): ...

# main.py
@app.exception_handler(OTPExpiredError)
async def handle_otp_expired(request: Request, exc: OTPExpiredError):
    return JSONResponse(status_code=400, content={"detail": "OTP has expired"})
```

### API versioning

All routes under `/api/v1/`. Prefix applied in `main.py` via `include_router`.

---

## Database

### Async SQLAlchemy 2.0

```python
# app/database.py
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session
```

### Migrations

```bash
# Create a migration — always review the generated file before applying
uv run alembic revision --autogenerate -m "add weight_logs table"

# Apply all pending migrations
uv run alembic upgrade head

# Roll back one step
uv run alembic downgrade -1
```

Railway runs `alembic upgrade head` automatically on every deploy.

### Model conventions

- Primary key: `id: Mapped[int] = mapped_column(primary_key=True)`
- Every table has `created_at` and `updated_at` timestamp columns
- Never hard-delete API keys — use nullable `revoked_at` timestamp
- Apply soft deletes on user data where legally required

---

## Authentication

Two parallel strategies, identical result:

| Header | Mechanism | Used by |
|--------|-----------|---------|
| `Authorization: Bearer <jwt>` | JWT → user | iOS app |
| `Authorization: ApiKey <key>` | bcrypt hash lookup → user | nutrichat PyPI package |

### API key security rules

- Raw key generated server-side, shown **exactly once**, never stored in plaintext
- Store `bcrypt_hash(raw_key)` in `api_keys.key_hash`
- Key format: `nutrichat_live_<32 random hex chars>`
- Rate limit: 1 000 requests/hr per key (use `slowapi`)
- Revocation is instant — set `revoked_at`, key is immediately rejected on next request

---

## Food Search — Layered Strategy

```
1. Local food_items table       → always first, instant, grows by caching external results
2. USDA FoodData Central        → free, ~380 K foods, 1 K req/hr limit
3. Open Food Facts              → free, 2.8 M products, best coverage for barcodes
4. Edamam                       → free tier 1 K req/day, NLP parsing + Indian food
5. Claude AI fallback           → natural-language quick-log; label result "~estimate" in UI
```

Every external API result is written to `food_items` immediately.
Each food is fetched from an external source **at most once** — never re-fetched.

Sprint 2 seed: 200+ Indian dishes from IFCT + 100+ packaged Indian foods from
Open Food Facts (MTR, Haldiram's, ITC, etc.).

---

## Testing

```bash
# All tests
uv run pytest tests/ -v

# Unit tests only — no database required
uv run pytest tests/unit/ -v

# With coverage report
uv run pytest tests/ --cov=app --cov-report=term-missing
```

### Required fixtures (conftest.py)

```python
@pytest_asyncio.fixture
async def db_session():
    # Separate test DB; every test gets a rolled-back transaction

@pytest_asyncio.fixture
async def test_client(db_session):
    # httpx.AsyncClient pointed at the FastAPI app with overridden DB dependency

@pytest_asyncio.fixture
async def test_user(db_session) -> User:
    # Pre-created User row for use in authenticated tests

@pytest_asyncio.fixture
def auth_headers(test_user) -> dict:
    # {"Authorization": "Bearer <valid_jwt_for_test_user>"}
```

Never run tests against the production database.

---

## Deployment (Railway)

- Start command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
- Pre-start: `alembic upgrade head` — configured in Railway start command or `Procfile`
- All secrets: Railway environment variables panel — never in code or committed `.env`
- Health check endpoint: `GET /health` → `{"status": "ok", "version": "1.0.0"}`

---

## Git

```bash
# Always run before and after work
git status && git diff --stat

# Standard commit
git add -A
git commit -m "feat(backend): <description>"
git push origin main

# Auto-commit when diff >= 10%
git add -A && git commit -m "chore(backend): auto-commit — diff threshold" && git push origin main
```

Scope for all backend commits: `(backend)`.