"""add guestbook reports and user blocks

Revision ID: b71c2d4e9f80
Revises: a48f9c1d2e70
Create Date: 2026-08-28
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "b71c2d4e9f80"
down_revision: str | Sequence[str] | None = "a48f9c1d2e70"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "is_admin",
            sa.Boolean(),
            server_default=sa.false(),
            nullable=False,
        ),
    )

    op.create_table(
        "user_blocks",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("blocker_user_id", sa.Integer(), nullable=False),
        sa.Column("blocked_user_id", sa.Integer(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["blocker_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["blocked_user_id"], ["users.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "blocker_user_id <> blocked_user_id",
            name="ck_user_block_not_self",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "blocker_user_id",
            "blocked_user_id",
            name="uq_user_block_blocker_blocked",
        ),
    )
    op.create_index(
        op.f("ix_user_blocks_blocker_user_id"),
        "user_blocks",
        ["blocker_user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_user_blocks_blocked_user_id"),
        "user_blocks",
        ["blocked_user_id"],
        unique=False,
    )

    op.create_table(
        "guestbook_reports",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("reporter_user_id", sa.Integer(), nullable=True),
        sa.Column("reported_user_id", sa.Integer(), nullable=True),
        sa.Column("guestbook_id", sa.Integer(), nullable=True),
        sa.Column(
            "reason",
            sa.Enum(
                "SPAM",
                "HARASSMENT",
                "HATE_SPEECH",
                "SEXUAL_CONTENT",
                "VIOLENCE",
                "PRIVACY",
                "ILLEGAL",
                "OTHER",
                name="reportreason",
                native_enum=False,
                length=30,
            ),
            nullable=False,
        ),
        sa.Column("details", sa.String(length=500), nullable=True),
        sa.Column("content_snapshot", sa.String(length=100), nullable=True),
        sa.Column("photo_urls_snapshot", sa.JSON(), nullable=False),
        sa.Column(
            "status",
            sa.Enum(
                "PENDING",
                "REVIEWING",
                "RESOLVED",
                "DISMISSED",
                name="reportstatus",
                native_enum=False,
                length=20,
            ),
            server_default="PENDING",
            nullable=False,
        ),
        sa.Column("admin_note", sa.Text(), nullable=True),
        sa.Column("resolved_by_user_id", sa.Integer(), nullable=True),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["guestbook_id"], ["guestbooks.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["reported_user_id"], ["users.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["reporter_user_id"], ["users.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["resolved_by_user_id"], ["users.id"], ondelete="SET NULL"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "reporter_user_id",
            "guestbook_id",
            name="uq_guestbook_report_reporter_guestbook",
        ),
    )
    op.create_index(
        op.f("ix_guestbook_reports_reporter_user_id"),
        "guestbook_reports",
        ["reporter_user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_guestbook_reports_reported_user_id"),
        "guestbook_reports",
        ["reported_user_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_guestbook_reports_guestbook_id"),
        "guestbook_reports",
        ["guestbook_id"],
        unique=False,
    )
    op.create_index(
        op.f("ix_guestbook_reports_status"),
        "guestbook_reports",
        ["status"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f("ix_guestbook_reports_status"), table_name="guestbook_reports")
    op.drop_index(
        op.f("ix_guestbook_reports_guestbook_id"), table_name="guestbook_reports"
    )
    op.drop_index(
        op.f("ix_guestbook_reports_reported_user_id"),
        table_name="guestbook_reports",
    )
    op.drop_index(
        op.f("ix_guestbook_reports_reporter_user_id"),
        table_name="guestbook_reports",
    )
    op.drop_table("guestbook_reports")
    op.drop_index(op.f("ix_user_blocks_blocked_user_id"), table_name="user_blocks")
    op.drop_index(op.f("ix_user_blocks_blocker_user_id"), table_name="user_blocks")
    op.drop_table("user_blocks")
    op.drop_column("users", "is_admin")
