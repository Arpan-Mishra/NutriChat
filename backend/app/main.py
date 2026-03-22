from contextlib import asynccontextmanager
import logging
import os

from fastapi import FastAPI

from app.database import engine, Base
from app.routers import auth, users, food, diary, goals, stats, api_keys, weight

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("NutriChat backend starting up...")
    # In production, Alembic handles table creation via start.sh
    # Only use create_all for local dev with SQLite
    if "sqlite" in str(engine.url):
        Base.metadata.create_all(bind=engine)
        logger.info("Database tables created (dev mode).")
    else:
        logger.info("Production mode — tables managed by Alembic.")
    yield
    logger.info("NutriChat backend shutting down.")


app = FastAPI(
    title="NutriChat API",
    description="Backend API for NutriChat calorie tracking app + WhatsApp bot integration",
    version="0.1.0",
    lifespan=lifespan,
)

# Include routers
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(food.router)
app.include_router(diary.router)
app.include_router(goals.router)
app.include_router(stats.router)
app.include_router(api_keys.router)
app.include_router(weight.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "nutrichat-backend"}
