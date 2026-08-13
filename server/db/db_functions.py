from sqlalchemy import text

from db.session import get_db_session


async def check_db_connection() -> None:
    """Raise if Postgres is unreachable."""
    async with get_db_session() as session:
        await session.execute(text("SELECT 1"))
