from fastapi import APIRouter, HTTPException, Response, status

from api.moderation.schemas import (
    GuestbookReportCreateRequest,
    GuestbookReportResponse,
    UserBlockResponse,
)
from api.moderation.service import (
    DuplicateGuestbookReportError,
    GuestbookReportTargetNotFoundError,
    ModerationService,
    ModerationUserNotFoundError,
    SelfBlockError,
    SelfReportError,
)
from core.dependencies import CurrentUser, DatabaseSession

router = APIRouter(tags=["moderation"])


@router.get(
    "/user-blocks",
    response_model=list[UserBlockResponse],
    summary="내가 차단한 사용자 목록 조회",
)
def list_user_blocks(
    current_user: CurrentUser,
    db: DatabaseSession,
) -> list[UserBlockResponse]:
    blocks = ModerationService(db).list_blocked_users(current_user.id)
    return [UserBlockResponse.model_validate(block) for block in blocks]


@router.put(
    "/user-blocks/{blocked_user_id}",
    response_model=UserBlockResponse,
    summary="사용자 차단 (중복 요청 안전)",
)
def block_user(
    blocked_user_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> UserBlockResponse:
    try:
        block = ModerationService(db).block_user(current_user.id, blocked_user_id)
    except ModerationUserNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except SelfBlockError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    return UserBlockResponse.model_validate(block)


@router.delete(
    "/user-blocks/{blocked_user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="사용자 차단 해제 (중복 요청 안전)",
)
def unblock_user(
    blocked_user_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> Response:
    ModerationService(db).unblock_user(current_user.id, blocked_user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/guestbooks/{guestbook_id}/reports",
    response_model=GuestbookReportResponse,
    status_code=status.HTTP_201_CREATED,
    summary="방명록 신고",
)
def report_guestbook(
    guestbook_id: int,
    request: GuestbookReportCreateRequest,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> GuestbookReportResponse:
    try:
        report = ModerationService(db).create_guestbook_report(
            reporter_user_id=current_user.id,
            guestbook_id=guestbook_id,
            reason=request.reason,
            details=request.details,
        )
    except GuestbookReportTargetNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except SelfReportError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    except DuplicateGuestbookReportError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    return GuestbookReportResponse.model_validate(report)
