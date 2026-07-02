from core.database import Base

class Place(Base):
    __tablename__ = "places"

    id = Column(Integer, primary_key=True, autoincrement=True)
    api_place_id = Column(String(100), unique=True, nullable=False) # Tour API에서 주는 고유 ID
    name = Column(String(255), nullable=False)
    category = Column(String(50), nullable=False) # 식당, 카페, 숙소 등
    lat = Column(Float, nullable=False) # 위도
    lng = Column(Float, nullable=False) # 경도
    image_url = Column(String(500), nullable=True)