from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from core.database import Base


class Guestbook(Base):
    """사용자가 방문한 장소(place) 한 곳당 남기는 방명록 1건.

    텍스트(리뷰)와 사진(과거/현재)은 각각 독립적으로 선택사항이며,
    같은 (user_id, place_id) 조합으로는 하나만 존재한다 — 스팟당 방명록 1개.
    """

    __tablename__ = "guestbooks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    place_id = Column(Integer, ForeignKey("places.id"), nullable=False)
    content = Column(
        String(100), nullable=True, comment="방명록 텍스트 (선택, 최대 100자)"
    )
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    photos = relationship(
        "ArchivePhoto", back_populates="guestbook", cascade="all, delete-orphan"
    )

    __table_args__ = (
        UniqueConstraint("user_id", "place_id", name="uq_guestbook_user_place"),
    )