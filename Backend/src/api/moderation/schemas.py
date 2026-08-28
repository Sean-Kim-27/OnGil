from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from api.moderation.models import ReportReason, ReportStatus


class ModerationUserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    nickname: str | None
    profile_image_url: str | None


class GuestbookReportCreateRequest(BaseModel):
    reason: ReportReason
    details: str | None = Field(default=None, max_length=500)

    @field_validator("details")
    @classmethod
    def normalize_details(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None


class GuestbookReportResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    guestbook_id: int | None
    reported_user_id: int | None
    reason: ReportReason
    details: str | None
    status: ReportStatus
    created_at: datetime


class UserBlockResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    blocked_user: ModerationUserResponse
    created_at: datetime


class AdminGuestbookReportResponse(GuestbookReportResponse):
    reporter: ModerationUserResponse | None
    reported_user: ModerationUserResponse | None
    content_snapshot: str | None
    photo_urls_snapshot: list[str]
    admin_note: str | None
    resolved_by: ModerationUserResponse | None
    resolved_at: datetime | None
    updated_at: datetime


class AdminGuestbookReportListResponse(BaseModel):
    items: list[AdminGuestbookReportResponse]
    total: int
    limit: int
    offset: int


class AdminGuestbookReportUpdateRequest(BaseModel):
    status: ReportStatus
    admin_note: str | None = Field(default=None, max_length=2000)

    @field_validator("admin_note")
    @classmethod
    def normalize_admin_note(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None
