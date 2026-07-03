import enum
from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Enum
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from core.database import Base


# --- Enum 정의 ---
class MobilityMode(str, enum.Enum):
    WALK = "WALK"
    CAR = "CAR"


class TripType(str, enum.Enum):
    DAY_TRIP = "DAY_TRIP"
    OVERNIGHT = "OVERNIGHT"


class CompanionType(str, enum.Enum):
    SOLO = "SOLO"
    COUPLE = "COUPLE"
    FAMILY = "FAMILY"
    FRIEND = "FRIEND"


class TimeSlot(str, enum.Enum):
    MORNING = "MORNING"  # 아침
    LUNCH = "LUNCH"  # 점심
    AFTERNOON = "AFTERNOON"  # 오후
    DINNER = "DINNER"  # 저녁
    NIGHT = "NIGHT"  # 밤


# 1. 스케줄러 기본 정보 (뼈대)
class Scheduler(Base):
    __tablename__ = "schedulers"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, nullable=False, index=True)
    title = Column(String(100), nullable=False)

    # [추가된 LLM 프롬프트용 데이터들]
    mobility_mode = Column(Enum(MobilityMode, native_enum=False, length=50), nullable=False)


    search_radius = Column(Float, nullable=False, comment="탐색 반경 (단위: km)")
    trip_type = Column(Enum(TripType, native_enum=False, length=50), nullable=False)

    # memory_places 테이블이랑 연결 (추억의 장소가 스케줄의 중심점 역할)
    memory_place_id = Column(Integer, ForeignKey("memory_places.id"), nullable=True)

    companion_type = Column(Enum(CompanionType, native_enum=False, length=50), nullable=False)
    companion_count = Column(Integer, nullable=False, default=1)

    start_datetime = Column(DateTime(timezone=True), nullable=False, comment="여행 시작 일시")
    end_datetime = Column(DateTime(timezone=True), nullable=False, comment="여행 종료 일시")

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # 관계 설정
    places = relationship("SchedulerPlace", back_populates="scheduler", cascade="all, delete-orphan")


# 2. 스케줄러 세부 장소 및 순서
class SchedulerPlace(Base):
    __tablename__ = "scheduler_places"

    id = Column(Integer, primary_key=True, autoincrement=True)
    scheduler_id = Column(Integer, ForeignKey("schedulers.id", ondelete="CASCADE"), nullable=False)
    place_id = Column(Integer, ForeignKey("places.id"), nullable=False)

    # [추가된 세부 일정 데이터]
    day_no = Column(Integer, nullable=False, default=1, comment="몇 일차인지 (당일치기는 무조건 1)")
    time_slot = Column(Enum(TimeSlot, native_enum=False, length=50), nullable=True, comment="시간대 (아침, 점심, 저녁 등)")
    visit_order = Column(Integer, nullable=False, comment="해당 일차의 방문 순서")

    scheduler = relationship("Scheduler", back_populates="places")