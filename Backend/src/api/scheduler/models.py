import enum

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

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


class ScheduleRole(str, enum.Enum):
    MEAL = "MEAL"
    SNACK = "SNACK"
    GENERAL_VISIT = "GENERAL_VISIT"
    ACCOMMODATION = "ACCOMMODATION"


# 1. 스케줄러 기본 정보 (뼈대)
class Scheduler(Base):
    __tablename__ = "schedulers"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, nullable=False, index=True)
    title = Column(String(100), nullable=False)

    # [추가된 LLM 프롬프트용 데이터들]
    mobility_mode = Column(
        Enum(MobilityMode, native_enum=False, length=50), nullable=False
    )

    search_radius = Column(Float, nullable=False, comment="탐색 반경 (단위: km)")
    trip_type = Column(Enum(TripType, native_enum=False, length=50), nullable=False)

    # memory_places 테이블이랑 연결 (추억의 장소가 스케줄의 중심점 역할)
    memory_place_id = Column(Integer, ForeignKey("memory_places.id"), nullable=True)

    companion_type = Column(
        Enum(CompanionType, native_enum=False, length=50), nullable=False
    )
    companion_count = Column(Integer, nullable=False, default=1)

    start_datetime = Column(
        DateTime(timezone=True), nullable=False, comment="여행 시작 일시"
    )
    end_datetime = Column(
        DateTime(timezone=True), nullable=False, comment="여행 종료 일시"
    )
    optimization_basis = Column(
        String(50),
        nullable=False,
        default="GEODESIC_APPROXIMATION",
        server_default="GEODESIC_APPROXIMATION",
        comment="방문 순서 최적화에 사용한 비용 기준",
    )
    route_verified = Column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
        comment="카카오 경로 API 검증 성공 여부",
    )

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # 관계 설정
    memory_place = relationship("MemoryPlace")
    places = relationship(
        "SchedulerPlace",
        back_populates="scheduler",
        cascade="all, delete-orphan",
        order_by="(SchedulerPlace.day_no, SchedulerPlace.visit_order)",
    )


# 2. 스케줄러 세부 장소 및 순서
class SchedulerPlace(Base):
    __tablename__ = "scheduler_places"

    id = Column(Integer, primary_key=True, autoincrement=True)
    scheduler_id = Column(
        Integer, ForeignKey("schedulers.id", ondelete="CASCADE"), nullable=False
    )
    place_id = Column(Integer, ForeignKey("places.id"), nullable=False)

    # [추가된 세부 일정 데이터]
    day_no = Column(
        Integer, nullable=False, default=1, comment="몇 일차인지 (당일치기는 무조건 1)"
    )
    time_slot = Column(
        Enum(TimeSlot, native_enum=False, length=50),
        nullable=True,
        comment="시간대 (아침, 점심, 저녁 등)",
    )
    visit_order = Column(Integer, nullable=False, comment="해당 일차의 방문 순서")
    scheduled_start_datetime = Column(
        DateTime(timezone=True), nullable=True, comment="자동/수동 배정 방문 시작 일시"
    )
    scheduled_end_datetime = Column(
        DateTime(timezone=True), nullable=True, comment="자동/수동 배정 방문 종료 일시"
    )
    travel_seconds_from_previous = Column(
        Integer, nullable=True, comment="직전 지점부터 예상 이동시간(초)"
    )
    travel_distance_m = Column(
        Integer, nullable=True, comment="직전 지점부터 예상 이동거리(미터)"
    )
    schedule_role = Column(
        Enum(ScheduleRole, native_enum=False, length=50),
        nullable=False,
        default=ScheduleRole.GENERAL_VISIT,
        server_default=ScheduleRole.GENERAL_VISIT.value,
        comment="일정 내 장소 역할(식사/간식/일반 방문/숙박)",
    )
    check_in_datetime = Column(
        DateTime(timezone=True), nullable=True, comment="숙박 체크인 일시"
    )
    check_out_datetime = Column(
        DateTime(timezone=True), nullable=True, comment="숙박 체크아웃 일시"
    )

    scheduler = relationship("Scheduler", back_populates="places")
    place = relationship("Place")
