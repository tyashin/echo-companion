import logging
import os
import subprocess
import sys
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI

from api.routes import health
from config import settings
from db.session import engine

logger = logging.getLogger("echo_server")


def run_migrations() -> None:
    """Run Alembic migrations on startup."""
    try:
        project_root = os.path.dirname(os.path.abspath(__file__))
        subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            check=True,
            cwd=project_root,
        )
        logger.info("Alembic migrations applied successfully.")
    except subprocess.CalledProcessError as e:
        logger.error("Failed to apply migrations: %s", e, exc_info=True)
        raise


@asynccontextmanager
async def lifespan(_: FastAPI):
    run_migrations()
    yield
    await engine.dispose()
    logger.info("Database engine disposed, shutdown complete.")


app = FastAPI(title="Echo Companion server", version="0.1.0", lifespan=lifespan)

app.include_router(health.router)

if __name__ == "__main__":
    logging.basicConfig(level=settings.log_level)
    uvicorn.run(app, host=settings.host, port=settings.port)
