"""add optimized schedule fields

Revision ID: a48f9c1d2e70
Revises: 91a6f25c4e30
Create Date: 2026-08-13
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a48f9c1d2e70"
down_revision: str | Sequence[str] | None = "91a6f25c4e30"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "schedulers",
        sa.Column(
            "optimization_basis",
            sa.String(length=50),
            server_default="GEODESIC_APPROXIMATION",
            nullable=False,
            comment="방문 순서 최적화에 사용한 비용 기준",
        ),
    )
    op.add_column(
        "schedulers",
        sa.Column(
            "route_verified",
            sa.Boolean(),
            server_default=sa.false(),
            nullable=False,
            comment="카카오 경로 API 검증 성공 여부",
        ),
    )
    op.add_column(
        "scheduler_places",
        sa.Column(
            "scheduled_start_datetime",
            sa.DateTime(timezone=True),
            nullable=True,
            comment="자동/수동 배정 방문 시작 일시",
        ),
    )
    op.add_column(
        "scheduler_places",
        sa.Column(
            "schedule_role",
            sa.String(length=50),
            server_default="GENERAL_VISIT",
            nullable=False,
            comment="일정 내 장소 역할(식사/간식/일반 방문/숙박)",
        ),
    )
    op.add_column(
        "scheduler_places",
        sa.Column(
            "check_in_datetime",
            sa.DateTime(timezone=True),
            nullable=True,
            comment="숙박 체크인 일시",
        ),
    )
    op.add_column(
        "scheduler_places",
        sa.Column(
            "check_out_datetime",
            sa.DateTime(timezone=True),
            nullable=True,
            comment="숙박 체크아웃 일시",
        ),
    )
    op.add_column(
        "scheduler_places",
        sa.Column(
            "scheduled_end_datetime",
            sa.DateTime(timezone=True),
            nullable=True,
            comment="자동/수동 배정 방문 종료 일시",
        ),
    )
    op.add_column(
        "scheduler_places",
        sa.Column(
            "travel_seconds_from_previous",
            sa.Integer(),
            nullable=True,
            comment="직전 지점부터 예상 이동시간(초)",
        ),
    )
    op.add_column(
        "scheduler_places",
        sa.Column(
            "travel_distance_m",
            sa.Integer(),
            nullable=True,
            comment="직전 지점부터 예상 이동거리(미터)",
        ),
    )


def downgrade() -> None:
    op.drop_column("scheduler_places", "check_out_datetime")
    op.drop_column("scheduler_places", "check_in_datetime")
    op.drop_column("scheduler_places", "schedule_role")
    op.drop_column("scheduler_places", "travel_distance_m")
    op.drop_column("scheduler_places", "travel_seconds_from_previous")
    op.drop_column("scheduler_places", "scheduled_end_datetime")
    op.drop_column("scheduler_places", "scheduled_start_datetime")
    op.drop_column("schedulers", "route_verified")
    op.drop_column("schedulers", "optimization_basis")
