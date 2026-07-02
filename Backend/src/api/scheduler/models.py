from core.database import Base

class Scheduler(Base):
    __tablename__ = "schedulers"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    title = Column(String(100), nullable=False)  # "제주도 2박 3일 먹방" 같은 거
    created_at = Column(DateTime, default=func.now())


class SchedulerPlace(Base):  # 스케줄러 안에 들어간 장소들 (중간 테이블)
    __tablename__ = "scheduler_places"

    id = Column(Integer, primary_key=True, autoincrement=True)
    scheduler_id = Column(Integer, ForeignKey("schedulers.id"), nullable=False)
    place_id = Column(Integer, ForeignKey("places.id"), nullable=False)

    # 동선 최적화나 알고리즘 짤 때 핵심인 순서와 시간
    visit_order = Column(Integer, nullable=False)  # 방문 순서 (1, 2, 3...)
    recommended_time = Column(String(50), nullable=True)  # LLM이 추천해준 시간 ("14:00~15:30")