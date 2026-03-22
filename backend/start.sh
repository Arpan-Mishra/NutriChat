#!/bin/bash
set -e

echo "Running Alembic migrations..."
alembic upgrade head

echo "Testing app import..."
python -c "from app.main import app; print('App imported successfully')"

echo "Starting uvicorn on port ${PORT:-8000}..."
exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
