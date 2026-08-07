import threading
import time
from dataclasses import dataclass

from fastapi import HTTPException, Request, status
from redis import Redis
from redis.exceptions import RedisError

from core.config import settings


@dataclass(frozen=True)
class RateLimitResult:
    allowed: bool
    retry_after: int


class AuthRateLimiter:
    """Redis-backed fixed-window limiter with a development-only local fallback."""

    def __init__(self) -> None:
        self._redis = (
            Redis.from_url(
                settings.REDIS_URL,
                decode_responses=True,
                socket_connect_timeout=1,
                socket_timeout=1,
            )
            if settings.REDIS_URL
            else None
        )
        self._local_counts: dict[str, tuple[int, float]] = {}
        self._lock = threading.Lock()

    def check(self, namespace: str, client_ip: str) -> RateLimitResult:
        key = f"ongil:rate-limit:{namespace}:{client_ip}"
        if self._redis is not None:
            try:
                return self._check_redis(key)
            except RedisError as exc:
                if settings.is_production:
                    raise HTTPException(
                        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                        detail="인증 요청 제한 서비스를 사용할 수 없습니다.",
                    ) from exc
        elif settings.is_production:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="인증 요청 제한 서비스가 구성되지 않았습니다.",
            )
        return self._check_local(key)

    def _check_redis(self, key: str) -> RateLimitResult:
        script = """
        local count = redis.call('INCR', KEYS[1])
        if count == 1 then
          redis.call('EXPIRE', KEYS[1], ARGV[1])
        end
        local ttl = redis.call('TTL', KEYS[1])
        return {count, ttl}
        """
        count, ttl = self._redis.eval(
            script,
            1,
            key,
            settings.SOCIAL_LOGIN_RATE_WINDOW_SECONDS,
        )
        return RateLimitResult(
            allowed=int(count) <= settings.SOCIAL_LOGIN_RATE_LIMIT,
            retry_after=max(int(ttl), 1),
        )

    def _check_local(self, key: str) -> RateLimitResult:
        now = time.monotonic()
        window = settings.SOCIAL_LOGIN_RATE_WINDOW_SECONDS
        with self._lock:
            count, window_started = self._local_counts.get(key, (0, now))
            if now - window_started >= window:
                count, window_started = 0, now
            count += 1
            self._local_counts[key] = (count, window_started)
        retry_after = max(int(window - (now - window_started)), 1)
        return RateLimitResult(
            allowed=count <= settings.SOCIAL_LOGIN_RATE_LIMIT,
            retry_after=retry_after,
        )

    def reset_for_tests(self) -> None:
        with self._lock:
            self._local_counts.clear()


auth_rate_limiter = AuthRateLimiter()


def enforce_auth_rate_limit(request: Request, namespace: str) -> None:
    client_ip = request.client.host if request.client is not None else "unknown"
    result = auth_rate_limiter.check(namespace, client_ip)
    if not result.allowed:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="인증 요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.",
            headers={"Retry-After": str(result.retry_after)},
        )
