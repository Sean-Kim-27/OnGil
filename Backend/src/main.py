from fastapi import FastAPI
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

from api.auth.router import router as auth_router
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
)
app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.allowed_hosts)
if settings.FORCE_HTTPS:
    app.add_middleware(HTTPSRedirectMiddleware)
app.include_router(auth_router, prefix="/api/v1")
