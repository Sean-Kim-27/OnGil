"""add Kakao place link fields

Revision ID: 91a6f25c4e30
Revises: 7c2b4d9e1a6f
Create Date: 2026-08-11

"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "91a6f25c4e30"
down_revision: str | Sequence[str] | None = "7c2b4d9e1a6f"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "places", sa.Column("kakao_place_id", sa.String(length=100), nullable=True)
    )
    op.add_column(
        "places", sa.Column("kakao_place_url", sa.String(length=500), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("places", "kakao_place_url")
    op.drop_column("places", "kakao_place_id")
