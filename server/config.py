from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(Path(__file__).parent / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # All values come from server/.env (see .env.example) or real env vars;
    # no defaults are hardcoded here.
    debug: bool
    # Async driver (asyncpg) for the app, sync driver (psycopg2) for Alembic.
    database_url: str
    database_sync_url: str

    # Neo4j is provisioned by docker-compose; the graph projection arrives in
    # Phase 0.8/1a, so only connection coordinates live here for now.
    neo4j_uri: str
    neo4j_user: str
    neo4j_password: str

    # Server configuration
    host: str
    port: int
    log_level: str


settings = Settings()
