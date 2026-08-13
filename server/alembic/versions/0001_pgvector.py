"""enable pgvector extension

Revision ID: 0001_pgvector
Revises:
Create Date: 2026-08-13

The evidence ledger stores embeddings via pgvector (architecture §5.2).
The extension must exist before any model defines a Vector column.
"""
from collections.abc import Sequence

from alembic import op

revision: str = "0001_pgvector"
down_revision: str | Sequence[str] | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")


def downgrade() -> None:
    op.execute("DROP EXTENSION IF EXISTS vector")
