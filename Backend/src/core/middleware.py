from starlette.datastructures import Headers
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send


class RequestBodyLimitMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        max_body_bytes: int,
        path_overrides: dict[str, int] | None = None,
    ) -> None:
        self.app = app
        self.max_body_bytes = max_body_bytes
        # 경로별로 다른 상한을 적용하기 위한 override 맵.
        # 로그인 등 가벼운 JSON 요청은 기본 max_body_bytes(수 KB)로 충분하지만,
        # 사진 업로드처럼 수 MB짜리 멀티파트 요청은 별도로 큰 제한이 필요하다.
        # 접두사(prefix) 매칭: "/api/v1/guestbooks"로 등록하면 그 하위 경로
        # (예: /api/v1/guestbooks/places/1/photos)에도 동일하게 적용된다.
        self.path_overrides = path_overrides or {}

    def _limit_for(self, path: str) -> int:
        matched_limit = self.max_body_bytes
        matched_prefix_length = -1
        for prefix, limit in self.path_overrides.items():
            if path.startswith(prefix) and len(prefix) > matched_prefix_length:
                matched_limit = limit
                matched_prefix_length = len(prefix)
        return matched_limit

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        limit = self._limit_for(scope.get("path", ""))

        content_length = Headers(scope=scope).get("content-length")
        if content_length is not None:
            try:
                parsed_length = int(content_length)
                too_large = parsed_length < 0 or parsed_length > limit
            except ValueError:
                too_large = True
            if too_large:
                await self._reject(scope, receive, send)
                return

        received = 0

        async def limited_receive() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    raise _RequestBodyTooLarge
            return message

        try:
            await self.app(scope, limited_receive, send)
        except _RequestBodyTooLarge:
            await self._reject(scope, receive, send)

    @staticmethod
    async def _reject(scope: Scope, receive: Receive, send: Send) -> None:
        response = JSONResponse(
            {"detail": "요청 본문이 너무 큽니다."},
            status_code=413,
        )
        await response(scope, receive, send)


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp, enable_hsts: bool = False) -> None:
        self.app = app
        self.enable_hsts = enable_hsts

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        async def add_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.extend(
                    [
                        (b"x-content-type-options", b"nosniff"),
                        (b"x-frame-options", b"DENY"),
                        (b"referrer-policy", b"no-referrer"),
                        (b"cache-control", b"no-store"),
                    ]
                )
                if self.enable_hsts:
                    headers.append((b"strict-transport-security", b"max-age=31536000"))
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, add_headers)


class _RequestBodyTooLarge(Exception):
    pass