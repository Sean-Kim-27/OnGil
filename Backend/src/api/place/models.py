import enum
from sqlalchemy import Column, Integer, String, Float, DateTime, Text, ForeignKey, UniqueConstraint, Enum
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from core.database import Base

class MosaicStatus(str, enum.Enum):
    PENDING = "PENDING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"

class ArchiveStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"

class RewardType(str, enum.Enum):
    POINT = "POINT"
    COUPON = "COUPON"
    LOCAL_CURRENCY = "LOCAL_CURRENCY"

class RewardStatus(str, enum.Enum):
    PENDING = "PENDING"
    ISSUED = "ISSUED"

class Place(Base):
    __tablename__ = "places"

    id = Column(Integer, primary_key=True, autoincrement=True)
    api_place_id = Column(String(100), unique=True, nullable=False) # Tour API에서 주는 고유 ID
    name = Column(String(255), nullable=False)
    category = Column(String(50), nullable=False) # 식당, 카페, 숙소 등
    lat = Column(Float, nullable=False) # 위도
    lng = Column(Float, nullable=False) # 경도
    image_url = Column(String(500), nullable=True)


# 1. 사용자가 직접 입력한 장소 (할머니 댁, 옛날 학교 등)
class MemoryPlace(Base):
    __tablename__ = "memory_places"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, nullable=False, index=True)  # 나중에 User 테이블이랑 FK 연결해라
    name = Column(String(100), nullable=False, comment="유저가 부르는 장소 이름")
    address = Column(String(255), nullable=False, comment="실제 지번/도로명 주소")
    lat = Column(Float, nullable=False)
    lng = Column(Float, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


# 2. 옛날 사진 제출 및 보상 처리 아카이브
class ArchivePhoto(Base):
    __tablename__ = "archive_photos"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, nullable=False, index=True)
    place_id = Column(Integer, ForeignKey("places.id"), nullable=False)

    image_url = Column(String(255), nullable=False, comment="원본 사진 URL")
    mosaic_image_url = Column(String(255), nullable=True, comment="모자이크 처리된 사진 URL")
    taken_year = Column(Integer, nullable=False, comment="사진 찍힌 연도 (ex: 1998)")

    mosaic_status = Column(Enum(MosaicStatus, native_enum=False, length=50), default=MosaicStatus.PENDING,
                           nullable=False)
    status = Column(Enum(ArchiveStatus, native_enum=False, length=50), default=ArchiveStatus.PENDING, nullable=False)

    reward_type = Column(Enum(RewardType, native_enum=False, length=50), nullable=True)
    reward_status = Column(Enum(RewardStatus, native_enum=False, length=50), default=RewardStatus.PENDING,
                           nullable=False)

    rejection_reason = Column(Text, nullable=True, comment="반려 시 관리자가 남기는 사유")


    created_at = Column(DateTime(timezone=True), server_default=func.now())
    reviewed_at = Column(DateTime(timezone=True), nullable=True, comment="관리자가 심사한 시간")

    # 관계 설정
    place = relationship("Place")