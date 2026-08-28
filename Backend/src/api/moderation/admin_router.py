from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from api.moderation.models import ReportStatus
from api.moderation.schemas import (
    AdminGuestbookReportListResponse,
    AdminGuestbookReportResponse,
    AdminGuestbookReportUpdateRequest,
)
from api.moderation.service import (
    GuestbookReportNotFoundError,
    ModerationService,
)
from core.dependencies import CurrentAdmin, DatabaseSession

router = APIRouter(prefix="/admin/guestbook-reports", tags=["admin-moderation"])


@router.get(
    "",
    response_model=AdminGuestbookReportListResponse,
    summary="관리자용 방명록 신고 목록 조회",
)
def list_guestbook_reports(
    current_admin: CurrentAdmin,
    db: DatabaseSession,
    report_status: Annotated[
        ReportStatus | None,
        Query(alias="status"),
    ] = None,
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> AdminGuestbookReportListResponse:
    reports, total = ModerationService(db).list_reports(
        report_status=report_status,
        limit=limit,
        offset=offset,
    )
    return AdminGuestbookReportListResponse(
        items=[
            AdminGuestbookReportResponse.model_validate(report) for report in reports
        ],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.patch(
    "/{report_id}",
    response_model=AdminGuestbookReportResponse,
    summary="관리자용 방명록 신고 상태 처리",
)
def update_guestbook_report(
    report_id: int,
    request: AdminGuestbookReportUpdateRequest,
    current_admin: CurrentAdmin,
    db: DatabaseSession,
) -> AdminGuestbookReportResponse:
    try:
        report = ModerationService(db).update_report(
            report_id=report_id,
            report_status=request.status,
            admin_note=request.admin_note,
            admin_user_id=current_admin.id,
        )
    except GuestbookReportNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    return AdminGuestbookReportResponse.model_validate(report)
