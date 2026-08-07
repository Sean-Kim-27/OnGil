from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from core.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    social_provider = Column(String(20), nullable=False)  # 'KAKAO' or 'GOOGLE'
    social_id = Column(String(255), nullable=False)  # 카카오/구글에서 주는 고유 ID 값
    email = Column(String(255), nullable=True)  # 선택 동의 안 할 수도 있으니 Nullable

    # 최초 로그인 시점에 채워넣을 데이터
    nickname = Column(String(50), nullable=True)
    profile_image_url = Column(String(500), nullable=True)

    # 가입 상태 관리 (핵심)
    status = Column(
        String(20), default="PENDING"
    )  # PENDING(프로필 미설정), ACTIVE(정상가입완료)

    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())

    # 복합 유니크 제약조건 (동일한 구글 아이디로 두 번 가입되면 좆되니까)
    __table_args__ = (
        UniqueConstraint("social_provider", "social_id", name="uix_provider_social_id"),
    )


class RefreshSession(Base):
    __tablename__ = "refresh_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    token_hash = Column(String(64), nullable=False, unique=True)
    token_family = Column(String(36), nullable=False, index=True)
    device_id = Column(String(255), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=False, index=True)
    revoked_at = Column(DateTime(timezone=True), nullable=True)
    revoked_reason = Column(String(32), nullable=True)
    replaced_by_token_hash = Column(String(64), nullable=True)
    last_used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
