import enum

from sqlalchemy import (
    JSON,
    CheckConstraint,
    Column,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from core.database import Base


class ReportReason(str, enum.Enum):
    SPAM = "SPAM"
    HARASSMENT = "HARASSMENT"
    HATE_SPEECH = "HATE_SPEECH"
    SEXUAL_CONTENT = "SEXUAL_CONTENT"
    VIOLENCE = "VIOLENCE"
    PRIVACY = "PRIVACY"
    ILLEGAL = "ILLEGAL"
    OTHER = "OTHER"


class ReportStatus(str, enum.Enum):
    PENDING = "PENDING"
    REVIEWING = "REVIEWING"
    RESOLVED = "RESOLVED"
    DISMISSED = "DISMISSED"


class UserBlock(Base):
    """방향성 있는 사용자 차단 관계: blocker는 blocked의 방명록을 보지 않는다."""

    __tablename__ = "user_blocks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    blocker_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    blocked_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    blocker = relationship("User", foreign_keys=[blocker_user_id])
    blocked_user = relationship("User", foreign_keys=[blocked_user_id])

    __table_args__ = (
        CheckConstraint(
            "blocker_user_id <> blocked_user_id",
            name="ck_user_block_not_self",
        ),
        UniqueConstraint(
            "blocker_user_id",
            "blocked_user_id",
            name="uq_user_block_blocker_blocked",
        ),
    )


class GuestbookReport(Base):
    """관리자가 별도 큐에서 검토할 수 있도록 보존하는 방명록 신고 기록."""

    __tablename__ = "guestbook_reports"

    id = Column(Integer, primary_key=True, autoincrement=True)
    reporter_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    reported_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    guestbook_id = Column(
        Integer,
        ForeignKey("guestbooks.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    reason = Column(
        Enum(ReportReason, native_enum=False, length=30),
        nullable=False,
    )
    details = Column(String(500), nullable=True)

    # 신고 이후 원문이 수정/삭제되더라도 당시 검토 근거를 보존한다.
    content_snapshot = Column(String(100), nullable=True)
    photo_urls_snapshot = Column(JSON, nullable=False, default=list)

    status = Column(
        Enum(ReportStatus, native_enum=False, length=20),
        nullable=False,
        default=ReportStatus.PENDING,
        server_default=ReportStatus.PENDING.value,
        index=True,
    )
    admin_note = Column(Text, nullable=True)
    resolved_by_user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    resolved_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    reporter = relationship("User", foreign_keys=[reporter_user_id])
    reported_user = relationship("User", foreign_keys=[reported_user_id])
    guestbook = relationship("Guestbook")
    resolved_by = relationship("User", foreign_keys=[resolved_by_user_id])

    __table_args__ = (
        UniqueConstraint(
            "reporter_user_id",
            "guestbook_id",
            name="uq_guestbook_report_reporter_guestbook",
        ),
    )
