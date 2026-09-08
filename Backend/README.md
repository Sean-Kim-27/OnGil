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

### 장소 주변 추천 데이터 조회

국문관광정보서비스 환경변수를 설정하면 로그인한 사용자가 기준 장소 주변
3~5km의 관광지, 문화시설, 숙박, 음식점, 카페 등 관광 데이터를 거리순으로
통합 조회할 수 있습니다. 카카오 로컬 검색을 함께 설정하면 학교, 아파트,
상가처럼 TourAPI에 없는 일반 장소도 기준점으로 사용할 수 있습니다.

```dotenv
KOR_SERVICE_BASE_URL=https://apis.data.go.kr/B551011/KorService2
KOR_RELATE_BASE_URL=https://apis.data.go.kr/B551011/TarRlteTarService1
KOR_DATA_API_KEY=발급받은_인증키
KAKAO_REST_API_KEY=카카오디벨로퍼스_REST_API_키
KAKAO_ROUTE_TIMEOUT_SECONDS=8
TOUR_API_PAGE_SIZE=1000
```

```http
GET /api/v1/places/nearby?query=경복궁&radius_m=5000
Authorization: Bearer <OnGil access token>
```

`KAKAO_REST_API_KEY`는 카카오 로그인 액세스 토큰이나 숫자 앱 ID가 아니라
카카오디벨로퍼스 앱의 **REST API 키**입니다. 백엔드는 카카오 로컬 검색 결과의
장소명, 지번·도로명 주소, 전체 카테고리를 함께 비교하여 기준점을 선택합니다.
키가 없거나 카카오 검색이 실패하면 기존 TourAPI 키워드 검색으로 대체하지만,
이 경우 일반 학교·아파트 검색은 제한될 수 있습니다.

TourAPI `locationBasedList2`에는 `contentTypeId`를 전달하지 않아 모든 관광타입을
한 결과로 요청합니다. `TOUR_API_PAGE_SIZE=1000`이면 결과가 1,000건 이하인
지역은 주변 조회가 한 번의 원천 API 요청으로 끝나며, 초과하는 경우에만 다음
페이지를 추가 요청합니다.

nearby 결과의 한 장소를 눌렀을 때는 장소명과 좌표를 카카오 링크 조회 API에
전달합니다. 백엔드는 해당 좌표 300m 안에서 이름이 일치하는 후보만 선택하며,
카카오 장소 ID와 HTTPS 상세 페이지 링크를 반환합니다. 이 호출은 `places` 테이블에
장소를 저장하지 않습니다.

```http
POST /api/v1/places/kakao-links/resolve
Authorization: Bearer <OnGil access token>
Content-Type: application/json

{
  "title": "국립민속박물관",
  "latitude": 37.582,
  "longitude": 126.979
}
```

```json
{
  "kakao_place_id": "123456789",
  "place_url": "https://place.map.kakao.com/123456789"
}
```

응답의 `category`는 다음 온길 분류 중 하나입니다.

- `restaurant`, `cafe`
- `tourist_attraction`, `cultural_facility`
- `festival`, `travel_course`, `leisure_sports`
- `accommodation`, `shopping`, `other`

### 최적화된 일정 생성 및 수정

`POST /api/v1/schedulers`의 `places`에는 사용자가 선택한 장소 정보만 전달합니다.
`day_no`, `time_slot`, `visit_order`는 프론트에서 받지 않고 서버가 자동 생성합니다.

서버는 추억 장소를 출발점으로 최근접 이웃 + 2-opt로 방문 순서를 정한 뒤, 그
순서를 카카오 자동차/도보 경로 API로 한 번 검증합니다. 카카오 응답의 구간별
이동시간과 카테고리별 체류시간을 `start_datetime`부터 순차 배치하며, 마지막
방문이 `end_datetime`을 넘으면 422를 반환하고 아무 레코드도 저장하지 않습니다.
카카오 API가 일시적으로 실패하거나 키가 없으면 직선거리와 이동 방식별 기본
속도로 이동시간을 추정하고 `route_verified=false`로 저장합니다.

여러 날짜에 걸친 일정은 첫날 `start_datetime`에서 시작하고, 최종일 전에는
20:00까지만 배치한 뒤 다음 날 09:00부터 이어집니다. 최종일에는 프론트가 보낸
`end_datetime`을 그대로 마감으로 사용합니다. 이 기본 활동시간 정책은 향후
사용자 설정이나 숙박·영업시간 규칙으로 교체할 수 있도록 플래너에 분리되어 있습니다.

음식점은 활동시간과 겹치는 식사 시간창에 우선 배치합니다. 아침은
07:30~10:00, 점심은 11:30~14:00, 저녁은 17:30~20:30이며 각 식사는 60분입니다.
식사 슬롯보다 음식점이 많거나 남은 슬롯에 도착할 수 없으면 해당 장소를 버리지
않고 `schedule_role=SNACK`인 45분 일반 방문으로 배치합니다. 카페·관광지 등은
식사 슬롯 사이의 빈 시간에 먼저 채워집니다.

숙박 장소는 날짜가 다른 `OVERNIGHT` 일정에서 여행 박 수만큼 선택할 수 있습니다.
1박2일은 최대 1곳, 2박3일은 최대 2곳이며 선택한 숙소 순서대로 각 숙박일에
할당됩니다. 각 숙박일 체크인은 15:00을 목표로 하고 15:00~16:00 도착을 우선하는
소프트 제약이며, 이동 때문에 늦으면 해당 날짜 활동시간 안에서 가장 가까운 가능한
시각으로 밀립니다. 체크아웃은 각 다음 날 11:00을 기본값으로 저장하며, 체크아웃
날짜의 식사·카페·관광 일정도 11:00 이후부터 배치합니다. 응답의
`check_in_datetime`, `check_out_datetime`, `schedule_role=ACCOMMODATION`으로 확인할
수 있습니다. 여행 박 수보다 숙소가 많으면 저장과 카카오 호출 전에 422로
거절합니다.

숙소 수가 박 수보다 적으면 마지막으로 선택한 숙소가 남은 숙박일을 연박으로
담당합니다. 예를 들어 3박4일에 숙소 2곳을 고르면 첫 숙소에서 1박하고 두 번째
숙소에서 2박한 뒤 마지막 날 체크아웃합니다.

```json
{
  "title": "추억 여행",
  "mobility_mode": "WALK",
  "search_radius": 3,
  "trip_type": "DAY_TRIP",
  "memory_place": {
    "name": "옛날 학교",
    "latitude": 37.5665,
    "longitude": 126.978
  },
  "places": [
    {
      "content_id": "tour-1",
      "title": "오래된 냉면집",
      "category": "restaurant",
      "latitude": 37.567,
      "longitude": 126.979
    }
  ],
  "companion_type": "FAMILY",
  "companion_count": 3,
  "start_datetime": "2026-09-01T09:00:00+09:00",
  "end_datetime": "2026-09-01T18:00:00+09:00"
}
```

생성 후 장소의 순서와 시간은
`PATCH /api/v1/schedulers/{scheduler_id}/places/{scheduler_place_id}`로 수정할 수
있습니다. `scheduled_start_datetime`과 `scheduled_end_datetime`은 전체 일정 범위
안에 있어야 합니다. 선택 장소는 최대 31개까지 허용합니다. 도보 장소가 카카오
1회 경로 검증 한도인 6개를 초과하면 요청을 거절하지 않고 로컬 거리·이동시간
추정으로 일정을 생성하며, 이때 `route_verified`는 `false`입니다.

숙박 범위와 숙소 순서는 전체 교체 API로 함께 수정합니다. 최초 일정 생성에는
`stays`를 보내지 않아도 되며, 생성 응답의 숙소 `SchedulerPlace.id`를 수정 요청에
사용합니다. 날짜 범위가 실제 순서를 결정하므로 아래처럼 숙소 B를 첫 범위에 두면
기존 A → B 일정도 B → A로 바뀝니다. 서버는 모든 여행 박이 빈 날짜나 중복 없이
연속 배정됐는지 검증한 뒤 전체 일정을 다시 최적화하고, 카카오 경로 API는 수정
요청당 최대 한 번 호출합니다.

```http
PUT /api/v1/schedulers/{scheduler_id}/stays
Authorization: Bearer <OnGil access token>
Content-Type: application/json
```

```json
{
  "stays": [
    {
      "scheduler_place_id": 202,
      "check_in_date": "2026-09-01",
      "check_out_date": "2026-09-03"
    },
    {
      "scheduler_place_id": 101,
      "check_in_date": "2026-09-03",
      "check_out_date": "2026-09-04"
    }
  ]
}
```

카페는 TourAPI 분류체계의 `FD05`를 기준으로 음식점과 분리합니다. 캠핑·카라반·
글램핑(`AC05`)은 원본 관광타입이 레포츠(28)이지만 온길 응답에서는 숙박으로
분류합니다. 각 장소에는 원본 `content_type_id`도 포함됩니다. 연관관광지 정보를
가져올 수 있으면 `related_rank`와 `related_category`가 함께 제공됩니다.

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

---

## 5. 방명록 신고·사용자 차단·관리자 처리

방명록 탭은 인증된 사용자가 다른 사용자의 공개 방명록을 열람하고, 부적절한
콘텐츠를 신고하거나 작성자를 차단할 수 있도록 구성되어 있습니다.

### 사용자 API

| Method | Path | 설명 |
| --- | --- | --- |
| `GET` | `/api/v1/guestbooks/feed` | 내가 차단한 작성자를 제외한 방명록 피드 |
| `GET` | `/api/v1/guestbooks/{guestbook_id}` | 차단 필터가 적용된 방명록 단건 조회 |
| `DELETE` | `/api/v1/guestbooks/{guestbook_id}` | 작성자 본인의 방명록 및 연결된 사진 레코드 삭제 |
| `POST` | `/api/v1/guestbooks/{guestbook_id}/reports` | 방명록 신고 |
| `GET` | `/api/v1/user-blocks` | 내가 차단한 사용자 목록 |
| `PUT` | `/api/v1/user-blocks/{blocked_user_id}` | 사용자 차단(중복 요청 안전) |
| `DELETE` | `/api/v1/user-blocks/{blocked_user_id}` | 사용자 차단 해제(중복 요청 안전) |

신고 사유는 `SPAM`, `HARASSMENT`, `HATE_SPEECH`, `SEXUAL_CONTENT`,
`VIOLENCE`, `PRIVACY`, `ILLEGAL`, `OTHER` 중 하나입니다. 같은 사용자가 같은
방명록을 중복 신고하면 `409 Conflict`를 반환합니다. 신고 시점의 텍스트와 사진
URL은 별도 스냅샷으로 보존되어 원문 수정 후에도 관리자가 검토할 수 있습니다.

차단은 방향성이 있습니다. A가 B를 차단하면 A의 피드와 단건 조회에서 B의
방명록만 제외되며, B가 A를 자동으로 차단하는 것은 아닙니다. 차단된 방명록의
단건 조회는 차단 관계 노출을 막기 위해 일반적인 미존재 응답과 동일하게 `404`를
반환합니다.

방명록 삭제는 Bearer 인증이 필요하며 성공 시 본문 없이 `204 No Content`를
반환합니다. 타인의 글, 존재하지 않는 글, 이미 삭제한 글은 모두 `404`를 반환하고,
미인증 요청은 `401`을 반환합니다. 경로의 ID는 장소 ID가 아닌 방명록 ID입니다.
삭제된 글은 내 목록·장소별 조회·공개 피드·단건 조회에서 사라집니다.
기존 신고는 `guestbook_id = null`로 유지되며 신고 당시 텍스트와 사진 URL,
관리자 처리 상태를 보존합니다. 사진 DB 레코드는 삭제하지만 업로드 원본 파일은
신고 증거 보존을 위해 삭제하지 않으므로 기존 파일 URL은 계속 접근 가능합니다.
삭제 API 추가 자체에는 별도 DB 마이그레이션이 필요하지 않습니다.

### 관리자 API

| Method | Path | 설명 |
| --- | --- | --- |
| `GET` | `/api/v1/admin/guestbook-reports` | 상태별 신고 큐 조회 및 페이지네이션 |
| `PATCH` | `/api/v1/admin/guestbook-reports/{report_id}` | 상태와 관리자 메모 갱신 |

처리 상태는 `PENDING`, `REVIEWING`, `RESOLVED`, `DISMISSED`입니다. 관리자
API는 `users.is_admin = true`인 계정만 접근할 수 있고, 공개 승격 API는 제공하지
않습니다. 최초 관리자는 운영자가 신뢰할 수 있는 사용자 ID를 확인한 뒤 DB에서
명시적으로 지정합니다.

```sql
UPDATE users SET is_admin = true WHERE id = <trusted_user_id>;
```

배포 전 새 테이블과 관리자 컬럼을 적용합니다.

```bash
alembic upgrade head
```

Flutter 방명록 탭에는 각 타인 방명록의 메뉴에서 `신고하기`와 `사용자 차단`을
직접 실행할 수 있는 UI가 연결되어 있습니다. 차단 성공 시 해당 작성자의 모든
방명록을 즉시 화면에서 제거하며, 스낵바의 실행 취소로 차단을 되돌릴 수 있습니다.
