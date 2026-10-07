#!/bin/sh
# Run the Alembic migrations, then start the API. In Kubernetes this runs in every
# replica; `alembic upgrade head` is idempotent so the second pod is a no-op.
set -e
echo "[entrypoint] running alembic upgrade head"
alembic upgrade head
echo "[entrypoint] starting uvicorn"
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers "${UVICORN_WORKERS:-1}"
