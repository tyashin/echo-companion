from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=str(Path(__file__).parent / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    debug: bool = True
    # Async driver (asyncpg) for the app, sync driver (psycopg2) for Alembic.
    database_url: str = "postgresql+asyncpg://echo:echo@localhost:5432/echo"
    database_sync_url: str = "postgresql+psycopg2://echo:echo@localhost:5432/echo"

    # Neo4j is provisioned by docker-compose; the graph projection arrives in
    # Phase 0.8/1a, so only connection coordinates live here for now.
    neo4j_uri: str = "bolt://localhost:17687"
    neo4j_user: str = "neo4j"
    neo4j_password: str = "echo-graph-dev"

    # Server configuration
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "INFO"


settings = Settings()
