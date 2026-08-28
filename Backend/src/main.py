from fastapi import FastAPI
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.staticfiles import StaticFiles

from api.auth.router import router as auth_router
from api.guestbook.router import router as guestbook_router
from api.moderation.admin_router import router as admin_moderation_router
from api.moderation.router import router as moderation_router
from api.place.router import router as place_router
from api.scheduler.router import router as scheduler_router
from core.config import settings
from core.middleware import RequestBodyLimitMiddleware, SecurityHeadersMiddleware

app = FastAPI(
    title="OnGil API",
    docs_url="/docs" if settings.ENABLE_DOCS else None,
    redoc_url="/redoc" if settings.ENABLE_DOCS else None,
    openapi_url="/openapi.json" if settings.ENABLE_DOCS else None,
)
app.add_middleware(SecurityHeadersMiddleware, enable_hsts=settings.FORCE_HTTPS)
app.add_middleware(
    RequestBodyLimitMiddleware,
    max_body_bytes=settings.MAX_REQUEST_BODY_BYTES,
    # 사진 업로드(멀티파트, 수 MB)는 기본 JSON 요청 상한보다 훨씬 커야 하므로
    # /api/v1/guestbooks 하위 경로만 MAX_PHOTO_UPLOAD_BYTES를 적용한다.
    path_overrides={"/api/v1/guestbooks": settings.MAX_PHOTO_UPLOAD_BYTES},
)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.allowed_hosts)
if settings.FORCE_HTTPS:
    app.add_middleware(HTTPSRedirectMiddleware)
app.include_router(auth_router, prefix="/api/v1")
app.include_router(place_router, prefix="/api/v1")
app.include_router(scheduler_router, prefix="/api/v1")
app.include_router(guestbook_router, prefix="/api/v1")
app.include_router(moderation_router, prefix="/api/v1")
app.include_router(admin_moderation_router, prefix="/api/v1")

# 사진 업로드 인프라: 디스크에 저장된 파일을 /media/... 경로로 그대로 서빙한다.
app.mount(
    "/media",
    StaticFiles(directory=settings.UPLOADS_ROOT_DIR, check_dir=False),
    name="media",
)
