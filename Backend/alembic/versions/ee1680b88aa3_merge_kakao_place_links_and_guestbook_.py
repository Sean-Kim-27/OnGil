"""merge kakao place links and guestbook redesign

Revision ID: ee1680b88aa3
Revises: 91a6f25c4e30, a1f3c9e7b204
Create Date: 2026-08-21

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'ee1680b88aa3'
down_revision: Union[str, Sequence[str], None] = ('91a6f25c4e30', 'a1f3c9e7b204')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass