# Echo Companion server

Python server for Echo Companion: FastAPI API, Postgres + pgvector evidence ledger,
Neo4j event-graph projection.

## Development

Python runs in the local uv environment (containers are for production packaging
only). Postgres (with pgvector) and Neo4j CE always run in docker-compose, on the
dev PC too — from the repo root:

```bash
docker compose up -d   # Postgres on 5432, Neo4j on 17474/17687
```

From `server/`:

```bash
uv sync                              # install deps (uv creates .venv with Python 3.13)
uv run alembic upgrade head          # apply migrations (also runs at app startup)
uv run uvicorn main:app --reload     # run the API on port 8000

uv run ruff check .                  # lint
uv run pytest                        # unit tests
```

Health endpoint: `GET /health` (checks Postgres connectivity).
