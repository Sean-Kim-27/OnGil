from fastapi import APIRouter, File, Form, HTTPException, UploadFile, status

from api.guestbook.schemas import (
    ArchivePhotoResponse,
    GuestbookContentUpdateRequest,
    GuestbookResponse,
)
from api.guestbook.service import (
    GuestbookNotFoundError,
    GuestbookService,
    PastPhotoRequiresCurrentPhotoError,
    PhotoAlreadyExistsError,
    PlaceNotVisitedError,
)
from api.place.models import PhotoType
from core.dependencies import CurrentUser, DatabaseSession
from core.file_storage import (
    PhotoTooLargeError,
    UnsupportedImageTypeError,
    save_uploaded_photo,
)

router = APIRouter(prefix="/guestbooks", tags=["guestbooks"])


@router.get("", response_model=list[GuestbookResponse], summary="내 방명록 목록 조회")
def list_guestbooks(
    current_user: CurrentUser, db: DatabaseSession
) -> list[GuestbookResponse]:
    service = GuestbookService(db)
    guestbooks = service.list_owned(current_user.id)
    return [GuestbookResponse.model_validate(guestbook) for guestbook in guestbooks]


@router.get(
    "/places/{place_id}",
    response_model=GuestbookResponse,
    summary="특정 장소의 방명록 조회",
)
def get_guestbook(
    place_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> GuestbookResponse:
    service = GuestbookService(db)
    try:
        guestbook = service.get_owned(current_user.id, place_id)
    except GuestbookNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    return GuestbookResponse.model_validate(guestbook)


@router.put(
    "/places/{place_id}",
    response_model=GuestbookResponse,
    summary="방명록 텍스트 작성/수정 (최대 100자, 선택사항)",
)
def upsert_guestbook_content(
    place_id: int,
    request: GuestbookContentUpdateRequest,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> GuestbookResponse:
    service = GuestbookService(db)
    try:
        guestbook = service.update_content(current_user.id, place_id, request.content)
    except PlaceNotVisitedError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)
        ) from exc
    return GuestbookResponse.model_validate(guestbook)


@router.post(
    "/places/{place_id}/photos",
    response_model=ArchivePhotoResponse,
    status_code=status.HTTP_201_CREATED,
    summary="현재/과거 사진 업로드 (스팟당 각 1장, 과거 사진은 현재 사진이 먼저 있어야 함)",
)
async def upload_archive_photo(
    place_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
    photo_type: PhotoType = Form(...),
    taken_year: int | None = Form(default=None, ge=1900),
    image: UploadFile = File(...),
) -> ArchivePhotoResponse:
    try:
        image_url = await save_uploaded_photo(image, subdirectory="guestbook-photos")
    except UnsupportedImageTypeError as exc:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE, detail=str(exc)
        ) from exc
    except PhotoTooLargeError as exc:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail=str(exc)
        ) from exc

    service = GuestbookService(db)
    try:
        photo = service.add_photo(
            current_user.id, place_id, photo_type, image_url, taken_year
        )
    except PlaceNotVisitedError as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)
        ) from exc
    except PastPhotoRequiresCurrentPhotoError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(exc)
        ) from exc
    except PhotoAlreadyExistsError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(exc)
        ) from exc
    return ArchivePhotoResponse.model_validate(photo)