from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from api.auth.models import User
from api.guestbook.models import Guestbook
from api.moderation.models import (
    GuestbookReport,
    ReportReason,
    ReportStatus,
    UserBlock,
)


class ModerationUserNotFoundError(RuntimeError):
    pass


class GuestbookReportTargetNotFoundError(RuntimeError):
    pass


class SelfBlockError(RuntimeError):
    pass


class SelfReportError(RuntimeError):
    pass


class DuplicateGuestbookReportError(RuntimeError):
    pass


class GuestbookReportNotFoundError(RuntimeError):
    pass


class ModerationService:
    def __init__(self, db: Session) -> None:
        self.db = db

    def block_user(self, blocker_user_id: int, blocked_user_id: int) -> UserBlock:
        if blocker_user_id == blocked_user_id:
            raise SelfBlockError("자기 자신을 차단할 수 없습니다.")
        if self.db.get(User, blocked_user_id) is None:
            raise ModerationUserNotFoundError("차단할 사용자를 찾을 수 없습니다.")

        existing = self.db.scalar(
            select(UserBlock)
            .options(selectinload(UserBlock.blocked_user))
            .where(
                UserBlock.blocker_user_id == blocker_user_id,
                UserBlock.blocked_user_id == blocked_user_id,
            )
        )
        if existing is not None:
            return existing

        block = UserBlock(
            blocker_user_id=blocker_user_id,
            blocked_user_id=blocked_user_id,
        )
        self.db.add(block)
        try:
            self.db.commit()
        except IntegrityError:
            self.db.rollback()
            concurrent = self.db.scalar(
                select(UserBlock)
                .options(selectinload(UserBlock.blocked_user))
                .where(
                    UserBlock.blocker_user_id == blocker_user_id,
                    UserBlock.blocked_user_id == blocked_user_id,
                )
            )
            if concurrent is None:
                raise
            return concurrent

        return self._get_block(block.id)

    def unblock_user(self, blocker_user_id: int, blocked_user_id: int) -> None:
        block = self.db.scalar(
            select(UserBlock).where(
                UserBlock.blocker_user_id == blocker_user_id,
                UserBlock.blocked_user_id == blocked_user_id,
            )
        )
        if block is None:
            return
        self.db.delete(block)
        self.db.commit()

    def list_blocked_users(self, blocker_user_id: int) -> list[UserBlock]:
        return list(
            self.db.scalars(
                select(UserBlock)
                .options(selectinload(UserBlock.blocked_user))
                .where(UserBlock.blocker_user_id == blocker_user_id)
                .order_by(UserBlock.created_at.desc(), UserBlock.id.desc())
            )
        )

    def create_guestbook_report(
        self,
        reporter_user_id: int,
        guestbook_id: int,
        reason: ReportReason,
        details: str | None,
    ) -> GuestbookReport:
        guestbook = self.db.scalar(
            select(Guestbook)
            .options(selectinload(Guestbook.photos))
            .where(Guestbook.id == guestbook_id)
        )
        if guestbook is None:
            raise GuestbookReportTargetNotFoundError(
                "신고할 방명록을 찾을 수 없습니다."
            )
        if guestbook.user_id == reporter_user_id:
            raise SelfReportError("자신의 방명록은 신고할 수 없습니다.")

        report = GuestbookReport(
            reporter_user_id=reporter_user_id,
            reported_user_id=guestbook.user_id,
            guestbook_id=guestbook.id,
            reason=reason,
            details=details,
            content_snapshot=guestbook.content,
            photo_urls_snapshot=[photo.image_url for photo in guestbook.photos],
        )
        self.db.add(report)
        try:
            self.db.commit()
        except IntegrityError as exc:
            self.db.rollback()
            duplicate = self.db.scalar(
                select(GuestbookReport.id).where(
                    GuestbookReport.reporter_user_id == reporter_user_id,
                    GuestbookReport.guestbook_id == guestbook_id,
                )
            )
            if duplicate is not None:
                raise DuplicateGuestbookReportError(
                    "이미 신고한 방명록입니다."
                ) from exc
            raise
        self.db.refresh(report)
        return report

    def list_reports(
        self,
        report_status: ReportStatus | None,
        limit: int,
        offset: int,
    ) -> tuple[list[GuestbookReport], int]:
        filters = []
        if report_status is not None:
            filters.append(GuestbookReport.status == report_status)

        reports = list(
            self.db.scalars(
                select(GuestbookReport)
                .options(
                    selectinload(GuestbookReport.reporter),
                    selectinload(GuestbookReport.reported_user),
                    selectinload(GuestbookReport.resolved_by),
                )
                .where(*filters)
                .order_by(
                    GuestbookReport.created_at.desc(),
                    GuestbookReport.id.desc(),
                )
                .limit(limit)
                .offset(offset)
            )
        )
        total = self.db.scalar(select(func.count(GuestbookReport.id)).where(*filters))
        return reports, int(total or 0)

    def update_report(
        self,
        report_id: int,
        report_status: ReportStatus,
        admin_note: str | None,
        admin_user_id: int,
    ) -> GuestbookReport:
        report = self.db.get(GuestbookReport, report_id)
        if report is None:
            raise GuestbookReportNotFoundError("신고 내역을 찾을 수 없습니다.")

        report.status = report_status
        report.admin_note = admin_note
        if report_status in {ReportStatus.RESOLVED, ReportStatus.DISMISSED}:
            report.resolved_by_user_id = admin_user_id
            report.resolved_at = datetime.now(timezone.utc)
        else:
            report.resolved_by_user_id = None
            report.resolved_at = None
        self.db.commit()
        return self._get_report(report.id)

    def _get_block(self, block_id: int) -> UserBlock:
        block = self.db.scalar(
            select(UserBlock)
            .options(selectinload(UserBlock.blocked_user))
            .where(UserBlock.id == block_id)
        )
        if block is None:
            raise RuntimeError("차단 관계 저장 후 조회에 실패했습니다.")
        return block

    def _get_report(self, report_id: int) -> GuestbookReport:
        report = self.db.scalar(
            select(GuestbookReport)
            .options(
                selectinload(GuestbookReport.reporter),
                selectinload(GuestbookReport.reported_user),
                selectinload(GuestbookReport.resolved_by),
            )
            .where(GuestbookReport.id == report_id)
        )
        if report is None:
            raise GuestbookReportNotFoundError("신고 내역을 찾을 수 없습니다.")
        return report
