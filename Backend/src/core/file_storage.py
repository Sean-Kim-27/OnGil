from __future__ import annotations

import uuid
from pathlib import Path

from fastapi import UploadFile

from core.config import settings

# jpg/png/webp만 허용 — 사진 아카이브 외 용도로 악용되는 걸 막기 위한 화이트리스트.
ALLOWED_CONTENT_TYPES: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
}


class UnsupportedImageTypeError(RuntimeError):
    """Raised when the uploaded file's content-type is not an allowed image type."""


class PhotoTooLargeError(RuntimeError):
    """Raised when the uploaded file exceeds the configured size limit."""


async def save_uploaded_photo(upload_file: UploadFile, subdirectory: str) -> str:
    """업로드된 사진 파일을 검증한 뒤 서버 디스크에 저장하고, 접근 가능한 URL을 반환한다.

    - content-type은 jpg/png/webp만 허용한다.
    - 용량은 settings.MAX_PHOTO_UPLOAD_BYTES를 초과할 수 없다. Content-Length
      헤더는 위조될 수 있으므로, 실제로 읽은 바이트 수를 직접 세어 검증한다
      (RequestBodyLimitMiddleware의 헤더 기반 검사와는 별도의 방어선).
    - 저장 파일명은 원본 파일명을 신뢰하지 않고 uuid4로 새로 생성한다
      (경로 조작·파일명 충돌 방지).
    """
    extension = ALLOWED_CONTENT_TYPES.get(upload_file.content_type or "")
    if extension is None:
        raise UnsupportedImageTypeError(
            f"지원하지 않는 이미지 형식입니다: {upload_file.content_type}"
        )

    max_bytes = settings.MAX_PHOTO_UPLOAD_BYTES
    chunks: list[bytes] = []
    total_bytes = 0
    while True:
        chunk = await upload_file.read(1024 * 1024)
        if not chunk:
            break
        total_bytes += len(chunk)
        if total_bytes > max_bytes:
            raise PhotoTooLargeError(
                f"사진 용량은 최대 {max_bytes // (1024 * 1024)}MB까지 업로드할 수 있습니다."
            )
        chunks.append(chunk)
    await upload_file.close()

    target_dir = Path(settings.UPLOADS_ROOT_DIR) / subdirectory
    target_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{uuid.uuid4().hex}{extension}"
    target_path = target_dir / filename
    target_path.write_bytes(b"".join(chunks))

    return f"{settings.MEDIA_BASE_URL.rstrip('/')}/{subdirectory}/{filename}"