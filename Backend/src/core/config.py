from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # .env 파일에 있는 DATABASE_URL을 이 변수가 쏙 빨아들인다
    DATABASE_URL: str

    class Config:
        env_file = ".env"

# 전역에서 쓸 수 있게 인스턴스 하나 뚫어둠
settings = Settings()