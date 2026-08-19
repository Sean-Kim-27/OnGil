"""redesign guestbook and archive photos

Revision ID: a1f3c9e7b204
Revises: 7c2b4d9e1a6f
Create Date: 2026-08-15

기존 archive_photos는 (user_id, place_id)를 직접 들고 있었으나, 방명록
(Guestbook) 개념이 도입되면서 "스팟 하나당 방명록 1건, 그 방명록에 현재/과거
사진 각 1장까지"로 구조가 바뀌었다. 그래서 구 archive_photos 테이블을 버리고
guestbooks 테이블을 새로 만든 뒤, archive_photos가 guestbook_id로 photo_type
(CURRENT/PAST)을 구분해 붙는 구조로 재설계한다.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = 'a1f3c9e7b204'
down_revision: Union[str, Sequence[str], None] = '7c2b4d9e1a6f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # 구 archive_photos(= user_id/place_id 직접 참조 구조)는 새 구조와 호환되지
    # 않으므로 삭제 후 재생성한다.
    op.drop_index(op.f('ix_archive_photos_user_id'), table_name='archive_photos')
    op.drop_table('archive_photos')

    op.create_table(
        'guestbooks',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('place_id', sa.Integer(), nullable=False),
        sa.Column('content', sa.String(length=100), nullable=True, comment='방명록 텍스트 (선택, 최대 100자)'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.ForeignKeyConstraint(['place_id'], ['places.id'], ),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'place_id', name='uq_guestbook_user_place'),
    )

    op.create_table(
        'archive_photos',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('guestbook_id', sa.Integer(), nullable=False),
        sa.Column('photo_type', sa.Enum('CURRENT', 'PAST', name='phototype', native_enum=False, length=20), nullable=False),
        sa.Column('image_url', sa.String(length=255), nullable=False, comment='원본 사진 URL'),
        sa.Column('mosaic_image_url', sa.String(length=255), nullable=True, comment='모자이크 처리된 사진 URL'),
        sa.Column('taken_year', sa.Integer(), nullable=True, comment='과거(PAST) 사진일 때만 사용. 현재 사진은 불필요'),
        sa.Column('mosaic_status', sa.Enum('PENDING', 'COMPLETED', 'FAILED', name='mosaicstatus', native_enum=False, length=50), nullable=False),
        sa.Column('status', sa.Enum('PENDING', 'APPROVED', 'REJECTED', name='archivestatus', native_enum=False, length=50), nullable=False),
        sa.Column('reward_type', sa.Enum('POINT', 'COUPON', 'LOCAL_CURRENCY', name='rewardtype', native_enum=False, length=50), nullable=True),
        sa.Column('reward_status', sa.Enum('PENDING', 'ISSUED', name='rewardstatus', native_enum=False, length=50), nullable=False),
        sa.Column('rejection_reason', sa.Text(), nullable=True, comment='반려 시 관리자가 남기는 사유'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True, comment='관리자가 심사한 시간'),
        sa.ForeignKeyConstraint(['guestbook_id'], ['guestbooks.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('guestbook_id', 'photo_type', name='uq_archive_photo_guestbook_type'),
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_table('archive_photos')
    op.drop_table('guestbooks')

    op.create_table(
        'archive_photos',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('place_id', sa.Integer(), nullable=False),
        sa.Column('image_url', sa.String(length=255), nullable=False, comment='원본 사진 URL'),
        sa.Column('mosaic_image_url', sa.String(length=255), nullable=True, comment='모자이크 처리된 사진 URL'),
        sa.Column('taken_year', sa.Integer(), nullable=False, comment='사진 찍힌 연도 (ex: 1998)'),
        sa.Column('mosaic_status', sa.Enum('PENDING', 'COMPLETED', 'FAILED', name='mosaicstatus', native_enum=False, length=50), nullable=False),
        sa.Column('status', sa.Enum('PENDING', 'APPROVED', 'REJECTED', name='archivestatus', native_enum=False, length=50), nullable=False),
        sa.Column('reward_type', sa.Enum('POINT', 'COUPON', 'LOCAL_CURRENCY', name='rewardtype', native_enum=False, length=50), nullable=True),
        sa.Column('reward_status', sa.Enum('PENDING', 'ISSUED', name='rewardstatus', native_enum=False, length=50), nullable=False),
        sa.Column('rejection_reason', sa.Text(), nullable=True, comment='반려 시 관리자가 남기는 사유'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True, comment='관리자가 심사한 시간'),
        sa.ForeignKeyConstraint(['place_id'], ['places.id'], ),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_archive_photos_user_id'), 'archive_photos', ['user_id'], unique=False)