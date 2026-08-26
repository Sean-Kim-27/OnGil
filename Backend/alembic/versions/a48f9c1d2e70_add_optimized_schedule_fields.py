"""add optimized schedule fields

Revision ID: a48f9c1d2e70
Revises: ee1680b88aa3
Create Date: 2026-08-13
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "a48f9c1d2e70"
down_revision: str | Sequence[str] | None = "ee1680b88aa3"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    existing = {
        table_name: {
            column["name"]
            for column in sa.inspect(op.get_bind()).get_columns(table_name)
        }
        for table_name in ("schedulers", "scheduler_places")
    }
    columns = {
        "schedulers": (
            sa.Column(
                "optimization_basis",
                sa.String(length=50),
                server_default="GEODESIC_APPROXIMATION",
                nullable=False,
                comment="방문 순서 최적화에 사용한 비용 기준",
            ),
            sa.Column(
                "route_verified",
                sa.Boolean(),
                server_default=sa.false(),
                nullable=False,
                comment="카카오 경로 API 검증 성공 여부",
            ),
        ),
        "scheduler_places": (
            sa.Column(
                "scheduled_start_datetime",
                sa.DateTime(timezone=True),
                nullable=True,
                comment="자동/수동 배정 방문 시작 일시",
            ),
            sa.Column(
                "schedule_role",
                sa.String(length=50),
                server_default="GENERAL_VISIT",
                nullable=False,
                comment="일정 내 장소 역할(식사/간식/일반 방문/숙박)",
            ),
            sa.Column(
                "check_in_datetime",
                sa.DateTime(timezone=True),
                nullable=True,
                comment="숙박 체크인 일시",
            ),
            sa.Column(
                "check_out_datetime",
                sa.DateTime(timezone=True),
                nullable=True,
                comment="숙박 체크아웃 일시",
            ),
            sa.Column(
                "scheduled_end_datetime",
                sa.DateTime(timezone=True),
                nullable=True,
                comment="자동/수동 배정 방문 종료 일시",
            ),
            sa.Column(
                "travel_seconds_from_previous",
                sa.Integer(),
                nullable=True,
                comment="직전 지점부터 예상 이동시간(초)",
            ),
            sa.Column(
                "travel_distance_m",
                sa.Integer(),
                nullable=True,
                comment="직전 지점부터 예상 이동거리(미터)",
            ),
        ),
    }
    for table_name, table_columns in columns.items():
        for column in table_columns:
            if column.name not in existing[table_name]:
                op.add_column(table_name, column)


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
