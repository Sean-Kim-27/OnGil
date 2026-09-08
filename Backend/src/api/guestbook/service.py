from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from api.guestbook.models import Guestbook
from api.moderation.models import UserBlock
from api.place.models import ArchivePhoto, PhotoType
from api.scheduler.models import Scheduler, SchedulerPlace


class GuestbookNotFoundError(RuntimeError):
    """Raised when a guestbook cannot be found for the current user."""


class PlaceNotVisitedError(RuntimeError):
    """Raised when the user has never added this place to any of their schedulers.

    사진/방명록은 실제로 여행 일정에 담아 방문 예정/방문한 스팟에만 남길 수 있다.
    """


class PastPhotoRequiresCurrentPhotoError(RuntimeError):
    """Raised when a PAST photo is submitted before a CURRENT photo exists.

    과거-현재 대비를 보여주는 게 목적이라, 과거 사진만 단독으로 등록하는 건 불가.
    """


class PhotoAlreadyExistsError(RuntimeError):
    """Raised when a guestbook already has a photo of the given photo_type.

    스팟(Guestbook) 하나당 현재 사진 1장 + 과거 사진 1장, 총 2장까지만 허용된다.
    """


class GuestbookService:
    """방명록(리뷰 텍스트) + 사진 아카이브(현재/과거) 등록·조회를 담당."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def get_owned(self, user_id: int, place_id: int) -> Guestbook:
        guestbook = self._find(user_id, place_id)
        if guestbook is None:
            raise GuestbookNotFoundError(
                f"장소(id={place_id})에 대한 방명록을 찾을 수 없습니다."
            )
        return guestbook

    def list_owned(self, user_id: int) -> list[Guestbook]:
        return list(
            self.db.scalars(
                select(Guestbook)
                .options(selectinload(Guestbook.photos))
                .where(Guestbook.user_id == user_id)
                .order_by(Guestbook.created_at.desc())
            )
        )

    def list_visible(
        self,
        viewer_user_id: int,
        limit: int,
        offset: int,
    ) -> tuple[list[Guestbook], int]:
        blocked_user_ids = select(UserBlock.blocked_user_id).where(
            UserBlock.blocker_user_id == viewer_user_id
        )
        visible_filter = ~Guestbook.user_id.in_(blocked_user_ids)

        guestbooks = list(
            self.db.scalars(
                select(Guestbook)
                .options(
                    selectinload(Guestbook.photos),
                    selectinload(Guestbook.author),
                    selectinload(Guestbook.place),
                )
                .where(visible_filter)
                .order_by(Guestbook.created_at.desc(), Guestbook.id.desc())
                .limit(limit)
                .offset(offset)
            )
        )
        total = self.db.scalar(select(func.count(Guestbook.id)).where(visible_filter))
        return guestbooks, int(total or 0)

    def get_visible(self, viewer_user_id: int, guestbook_id: int) -> Guestbook:
        blocked_user_ids = select(UserBlock.blocked_user_id).where(
            UserBlock.blocker_user_id == viewer_user_id
        )
        guestbook = self.db.scalar(
            select(Guestbook)
            .options(
                selectinload(Guestbook.photos),
                selectinload(Guestbook.author),
                selectinload(Guestbook.place),
            )
            .where(
                Guestbook.id == guestbook_id,
                ~Guestbook.user_id.in_(blocked_user_ids),
            )
        )
        if guestbook is None:
            # 차단 여부가 외부에 노출되지 않도록 존재하지 않는 항목과 동일하게 처리한다.
            raise GuestbookNotFoundError("방명록을 찾을 수 없습니다.")
        return guestbook

    def update_content(
        self, user_id: int, place_id: int, content: str | None
    ) -> Guestbook:
        self._ensure_place_visited(user_id, place_id)
        guestbook = self._get_or_create(user_id, place_id)
        guestbook.content = content
        self.db.commit()
        self.db.refresh(guestbook)
        return guestbook

    def delete_owned(self, user_id: int, guestbook_id: int) -> None:
        guestbook = self.db.scalar(
            select(Guestbook).where(
                Guestbook.id == guestbook_id,
                Guestbook.user_id == user_id,
            )
        )
        if guestbook is None:
            # 다른 사용자의 글도 미존재와 동일하게 응답한다.
            raise GuestbookNotFoundError("방명록을 찾을 수 없습니다.")

        # 사진 레코드는 ORM cascade로 제거하고 신고는 FK SET NULL로 보존한다.
        # 신고 스냅샷이 참조하는 업로드 원본 파일은 여기서 삭제하지 않는다.
        self.db.delete(guestbook)
        self.db.commit()

    def add_photo(
        self,
        user_id: int,
        place_id: int,
        photo_type: PhotoType,
        image_url: str,
        taken_year: int | None,
    ) -> ArchivePhoto:
        self._ensure_place_visited(user_id, place_id)
        guestbook = self._get_or_create(user_id, place_id)

        if any(photo.photo_type == photo_type for photo in guestbook.photos):
            raise PhotoAlreadyExistsError(
                f"이미 {photo_type.value} 사진이 등록되어 있습니다. "
                "스팟당 현재/과거 사진은 각각 1장까지만 등록할 수 있습니다."
            )

        if photo_type == PhotoType.PAST and not any(
            photo.photo_type == PhotoType.CURRENT for photo in guestbook.photos
        ):
            raise PastPhotoRequiresCurrentPhotoError(
                "과거 사진은 같은 스팟에 현재 사진이 먼저 등록되어 있어야 등록할 수 있습니다."
            )

        photo = ArchivePhoto(
            guestbook_id=guestbook.id,
            photo_type=photo_type,
            image_url=image_url,
            taken_year=taken_year,
        )
        self.db.add(photo)
        try:
            self.db.commit()
        except IntegrityError as exc:
            # 동시 요청으로 같은 photo_type이 경쟁적으로 들어온 경우의 방어선.
            self.db.rollback()
            raise PhotoAlreadyExistsError(
                f"이미 {photo_type.value} 사진이 등록되어 있습니다."
            ) from exc
        self.db.refresh(photo)
        return photo

    def _get_or_create(self, user_id: int, place_id: int) -> Guestbook:
        guestbook = self._find(user_id, place_id)
        if guestbook is not None:
            return guestbook

        guestbook = Guestbook(user_id=user_id, place_id=place_id)
        self.db.add(guestbook)
        self.db.flush()
        guestbook.photos = []
        return guestbook

    def _find(self, user_id: int, place_id: int) -> Guestbook | None:
        return self.db.scalar(
            select(Guestbook)
            .options(selectinload(Guestbook.photos))
            .where(Guestbook.user_id == user_id, Guestbook.place_id == place_id)
        )

    def _ensure_place_visited(self, user_id: int, place_id: int) -> None:
        visited = self.db.scalar(
            select(SchedulerPlace.id)
            .join(Scheduler, SchedulerPlace.scheduler_id == Scheduler.id)
            .where(
                Scheduler.user_id == user_id,
                SchedulerPlace.place_id == place_id,
            )
            .limit(1)
        )
        if visited is None:
            raise PlaceNotVisitedError(
                f"일정에 담아 방문한 적 없는 장소(id={place_id})에는 "
                "방명록/사진을 등록할 수 없습니다."
            )
