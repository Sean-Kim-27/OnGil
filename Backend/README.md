# 🚀 OnGil 백엔드 개발 및 DB 마이그레이션 가이드

OnGil 백엔드 팀원들을 위한 개발 가이드입니다. 
우리 프로젝트는 `FastAPI` + `SQLAlchemy` + `Alembic` 스택을 사용하며, 패키지 관리는 속도가 빠른 `uv`를 표준으로 합니다. 

---

## 0. 🛠️ 로컬 환경 세팅 (최초 클론 시)

프로젝트를 로컬에 내려받은 후 가장 먼저 해야 할 작업입니다.

1. **가상환경 생성 및 패키지 설치**
   ```bash
   uv venv
   source .venv/bin/activate  # Windows는 .venv\Scripts\activate
   uv pip install -r requirements.txt
   ```

2. **환경변수(`.env`) 세팅 🚨**
   보안을 위해 실제 인증 정보는 깃허브에 올리지 않습니다. `.env.example`을 `.env`로 복사한 뒤 값을 채워 주세요. Google은 Android 클라이언트 ID가 아니라 백엔드의 audience로 사용할 **웹 애플리케이션 클라이언트 ID**를 입력합니다. 운영 환경에서는 `REDIS_URL`, `ALLOWED_HOSTS`, `FORCE_HTTPS=true`, `ENABLE_DOCS=false`도 설정해야 합니다.
   ```bash
   cp .env.example .env
   ```

---

## 1. 🗄️ DB 테이블 수정하기 (`models.py`)

새로운 기능이 추가되어 DB 테이블을 생성하거나 컬럼을 변경해야 할 때 참고해 주세요.

*   **위치:** `src/api/{도메인}/models.py`
*   **주의사항:** 
    *   모든 테이블을 한 곳에 모으지 않고, 기능(도메인)별 폴더에 맞게 분리해서 작성합니다.
    *   파일 상단에 필요한 SQLAlchemy 모듈(Column, String 등)을 꼼꼼히 import 해주세요.
    *   새로운 테이블 클래스는 반드시 `Base`를 상속받아야 합니다.

**[작성 예시]**
```python
from sqlalchemy import Column, Integer, String
from core.database import Base

class NewFeature(Base):
    __tablename__ = "new_features"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(50), nullable=False)
```

---

## 2. 🚀 Alembic 마이그레이션 (DB에 반영하기)

`models.py`를 수정했다면, 해당 변경 사항을 실제 PostgreSQL DB에 반영하는 마이그레이션 작업을 반드시 수행해야 합니다.

1. **마이그레이션 스크립트 생성**
   터미널에 아래 명령어를 입력합니다. `-m` 뒤에는 변경 사항을 알기 쉽게 영어로 적어주세요.
   ```bash
   alembic revision --autogenerate -m "add new_features table"
   ```
   *정상적으로 실행되면 `alembic/versions/` 폴더에 새로운 파이썬 파일이 생성됩니다.*

2. **실제 DB에 적용하기 🚨**
   스크립트만 생성하고 적용을 잊는 경우가 많습니다. 반드시 아래 명령어로 DB에 테이블을 반영해 주세요.
   ```bash
   alembic upgrade head
   ```

3. **[중요]** `alembic/versions/` 폴더에 생성된 마이그레이션 파일들은 **반드시 깃허브에 커밋**해서 다른 팀원들과 DB 히스토리를 공유해야 합니다.

---

## 3. 🔐 소셜 로그인 및 온길 세션

`POST /api/v1/auth/social-login` 요청에는 공급자와 토큰을 명시합니다. Google은 ID token만, Kakao는 access token만 허용합니다.

```json
{
  "provider": "google",
  "token": "provider-token",
  "device_id": "optional-device-id"
}
```

응답의 온길 `access_token`은 API의 `Authorization: Bearer ...` 헤더에 사용하고, `refresh_token`은 앱의 안전한 저장소에 보관합니다. 갱신할 때마다 새 refresh token으로 교체해야 하며 이전 토큰을 재사용하면 해당 토큰 패밀리가 폐기됩니다.

- `POST /api/v1/auth/refresh`: 온길 토큰 갱신
- `POST /api/v1/auth/logout`: refresh token 패밀리 폐기
- `GET /api/v1/auth/me`: 온길 access token 검증

---

## 4. 📦 프론트엔드 통신용 규격 작성 (`schemas.py`)

DB 테이블 세팅이 끝났다면, 클라이언트(앱)와 데이터를 안전하게 주고받기 위한 Pydantic DTO(Data Transfer Object)를 작성합니다.

*   **위치:** `src/api/{도메인}/schemas.py`
*   **주의사항:** 
    *   DB 객체용인 `models.py`와 통신용인 `schemas.py`의 역할을 명확히 분리합니다.
    *   클라이언트로부터 받는 데이터(Request)는 `Field`를 활용해 유효성 검사를 꼼꼼히 설정해 주세요.

**[작성 예시]**
```python
from pydantic import BaseModel, Field
from typing import Optional

# 1. 클라이언트 -> 서버 (Request: 유효성 검사 필수)
class NewFeatureCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=50, description="새 기능 이름")

# 2. 서버 -> 클라이언트 (Response)
class NewFeatureResponse(BaseModel):
    id: int
    name: str

    # DB 모델 객체(SQLAlchemy)를 JSON으로 자동 변환해 주는 필수 옵션입니다.
    class Config:
        from_attributes = True
```
