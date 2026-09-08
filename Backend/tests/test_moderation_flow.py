import os
import unittest
from collections.abc import Generator

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")
os.environ["ENVIRONMENT"] = "test"
os.environ["REDIS_URL"] = ""

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from api.auth.models import User
from api.guestbook.models import Guestbook
from api.moderation.models import GuestbookReport, UserBlock
from api.place.models import ArchivePhoto, PhotoType, Place
from core.database import Base
from core.dependencies import get_current_user, get_db
from main import app


class ModerationFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        with self.engine.connect() as connection:
            connection.exec_driver_sql("PRAGMA foreign_keys=ON")
        self.session_factory = sessionmaker(
            bind=self.engine,
            autoflush=False,
            expire_on_commit=False,
        )
        Base.metadata.create_all(self.engine)
        self._seed_data()

        def override_db() -> Generator[Session, None, None]:
            db = self.session_factory()
            try:
                yield db
            finally:
                db.close()

        app.dependency_overrides[get_db] = override_db
        app.dependency_overrides[get_current_user] = lambda: self.current_user
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()
        app.dependency_overrides.pop(get_db, None)
        app.dependency_overrides.pop(get_current_user, None)
        Base.metadata.drop_all(self.engine)
        self.engine.dispose()

    def _seed_data(self) -> None:
        with self.session_factory() as db:
            self.viewer = User(
                social_provider="google",
                social_id="viewer",
                nickname="viewer",
                status="ACTIVE",
            )
            self.author = User(
                social_provider="google",
                social_id="author",
                nickname="author",
                status="ACTIVE",
            )
            self.other_author = User(
                social_provider="google",
                social_id="other-author",
                nickname="other",
                status="ACTIVE",
            )
            self.admin = User(
                social_provider="google",
                social_id="admin",
                nickname="admin",
                status="ACTIVE",
                is_admin=True,
            )
            db.add_all([self.viewer, self.author, self.other_author, self.admin])
            db.flush()

            places = [
                Place(
                    api_place_id=f"place-{index}",
                    name=f"장소 {index}",
                    category="tourist_attraction",
                    lat=37.5 + index / 100,
                    lng=127.0 + index / 100,
                )
                for index in range(1, 4)
            ]
            db.add_all(places)
            db.flush()

            self.viewer_guestbook = Guestbook(
                user_id=self.viewer.id,
                place_id=places[0].id,
                content="viewer guestbook",
            )
            self.author_guestbook = Guestbook(
                user_id=self.author.id,
                place_id=places[1].id,
                content="reported content",
            )
            self.other_guestbook = Guestbook(
                user_id=self.other_author.id,
                place_id=places[2].id,
                content="other guestbook",
            )
            db.add_all(
                [
                    self.viewer_guestbook,
                    self.author_guestbook,
                    self.other_guestbook,
                ]
            )
            db.flush()
            db.add(
                ArchivePhoto(
                    guestbook_id=self.author_guestbook.id,
                    photo_type=PhotoType.CURRENT,
                    image_url="/media/guestbook-photos/reported.jpg",
                )
            )
            db.commit()

        self.current_user = self.viewer

    def test_block_hides_guestbooks_and_unblock_restores_them(self) -> None:
        initial = self.client.get("/api/v1/guestbooks/feed")
        self.assertEqual(initial.status_code, 200)
        self.assertEqual(initial.json()["total"], 3)

        blocked = self.client.put(f"/api/v1/user-blocks/{self.author.id}")
        self.assertEqual(blocked.status_code, 200)
        block_id = blocked.json()["id"]

        duplicate = self.client.put(f"/api/v1/user-blocks/{self.author.id}")
        self.assertEqual(duplicate.status_code, 200)
        self.assertEqual(duplicate.json()["id"], block_id)

        feed = self.client.get("/api/v1/guestbooks/feed")
        self.assertEqual(feed.status_code, 200)
        self.assertEqual(feed.json()["total"], 2)
        author_ids = {item["author"]["id"] for item in feed.json()["items"]}
        self.assertNotIn(self.author.id, author_ids)

        direct = self.client.get(f"/api/v1/guestbooks/{self.author_guestbook.id}")
        self.assertEqual(direct.status_code, 404)

        block_list = self.client.get("/api/v1/user-blocks")
        self.assertEqual(block_list.status_code, 200)
        self.assertEqual(len(block_list.json()), 1)
        self.assertEqual(block_list.json()[0]["blocked_user"]["id"], self.author.id)

        with self.session_factory() as db:
            count = db.scalar(select(func.count(UserBlock.id)))
            self.assertEqual(count, 1)

        first_unblock = self.client.delete(f"/api/v1/user-blocks/{self.author.id}")
        second_unblock = self.client.delete(f"/api/v1/user-blocks/{self.author.id}")
        self.assertEqual(first_unblock.status_code, 204)
        self.assertEqual(second_unblock.status_code, 204)

        restored = self.client.get(f"/api/v1/guestbooks/{self.author_guestbook.id}")
        self.assertEqual(restored.status_code, 200)

    def test_delete_owned_guestbook_preserves_report_and_removes_photos(self) -> None:
        target = self.author_guestbook
        report = self.client.post(
            f"/api/v1/guestbooks/{target.id}/reports",
            json={"reason": "SPAM"},
        )
        self.assertEqual(report.status_code, 201)
        self.current_user = self.author
        deleted = self.client.delete(f"/api/v1/guestbooks/{target.id}")
        self.assertEqual(deleted.status_code, 204)
        self.assertEqual(deleted.content, b"")
        self.assertEqual(
            self.client.get(f"/api/v1/guestbooks/{target.id}").status_code, 404
        )
        self.assertEqual(
            self.client.get(f"/api/v1/guestbooks/places/{target.place_id}").status_code,
            404,
        )
        self.assertEqual(self.client.get("/api/v1/guestbooks").json(), [])
        self.assertEqual(self.client.get("/api/v1/guestbooks/feed").json()["total"], 2)
        self.assertEqual(
            self.client.delete(f"/api/v1/guestbooks/{target.id}").status_code, 404
        )
        with self.session_factory() as db:
            self.assertIsNone(db.get(Guestbook, target.id))
            self.assertEqual(db.scalar(select(func.count(ArchivePhoto.id))), 0)
            saved_report = db.get(GuestbookReport, report.json()["id"])
            self.assertIsNone(saved_report.guestbook_id)
            self.assertEqual(saved_report.content_snapshot, "reported content")
            self.assertEqual(
                saved_report.photo_urls_snapshot,
                ["/media/guestbook-photos/reported.jpg"],
            )
            self.assertIsNotNone(db.get(Guestbook, self.viewer_guestbook.id))
        self.current_user = self.admin
        reports = self.client.get("/api/v1/admin/guestbook-reports")
        self.assertEqual(reports.status_code, 200)
        self.assertEqual(reports.json()["items"][0]["id"], report.json()["id"])

    def test_delete_rejects_non_owner_missing_and_unauthenticated(self) -> None:
        target_url = f"/api/v1/guestbooks/{self.author_guestbook.id}"
        self.assertEqual(self.client.delete(target_url).status_code, 404)
        self.assertEqual(self.client.delete("/api/v1/guestbooks/999999").status_code, 404)
        self.current_user = self.admin
        self.assertEqual(self.client.delete(target_url).status_code, 404)
        app.dependency_overrides.pop(get_current_user)
        self.assertEqual(self.client.delete(target_url).status_code, 401)
        with self.session_factory() as db:
            self.assertIsNotNone(db.get(Guestbook, self.author_guestbook.id))
            self.assertEqual(db.scalar(select(func.count(ArchivePhoto.id))), 1)

    def test_block_is_directional_and_rejects_invalid_targets(self) -> None:
        response = self.client.put(f"/api/v1/user-blocks/{self.author.id}")
        self.assertEqual(response.status_code, 200)

        self.current_user = self.author
        reverse_feed = self.client.get("/api/v1/guestbooks/feed")
        self.assertEqual(reverse_feed.status_code, 200)
        visible_authors = {
            item["author"]["id"] for item in reverse_feed.json()["items"]
        }
        self.assertIn(self.viewer.id, visible_authors)

        self.current_user = self.viewer
        self_block = self.client.put(f"/api/v1/user-blocks/{self.viewer.id}")
        missing_user = self.client.put("/api/v1/user-blocks/999999")
        self.assertEqual(self_block.status_code, 422)
        self.assertEqual(missing_user.status_code, 404)

    def test_report_preserves_snapshot_and_rejects_duplicates(self) -> None:
        response = self.client.post(
            f"/api/v1/guestbooks/{self.author_guestbook.id}/reports",
            json={
                "reason": "HARASSMENT",
                "details": "  반복적인 괴롭힘 내용  ",
            },
        )
        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["status"], "PENDING")
        report_id = response.json()["id"]

        with self.session_factory() as db:
            report = db.get(GuestbookReport, report_id)
            self.assertIsNotNone(report)
            self.assertEqual(report.details, "반복적인 괴롭힘 내용")
            self.assertEqual(report.content_snapshot, "reported content")
            self.assertEqual(
                report.photo_urls_snapshot,
                ["/media/guestbook-photos/reported.jpg"],
            )

        duplicate = self.client.post(
            f"/api/v1/guestbooks/{self.author_guestbook.id}/reports",
            json={"reason": "SPAM"},
        )
        self.assertEqual(duplicate.status_code, 409)

        self_report = self.client.post(
            f"/api/v1/guestbooks/{self.viewer_guestbook.id}/reports",
            json={"reason": "OTHER"},
        )
        missing = self.client.post(
            "/api/v1/guestbooks/999999/reports",
            json={"reason": "OTHER"},
        )
        self.assertEqual(self_report.status_code, 422)
        self.assertEqual(missing.status_code, 404)

    def test_admin_can_list_and_resolve_reports(self) -> None:
        created = self.client.post(
            f"/api/v1/guestbooks/{self.author_guestbook.id}/reports",
            json={"reason": "PRIVACY", "details": "개인정보 노출"},
        )
        report_id = created.json()["id"]

        forbidden = self.client.get("/api/v1/admin/guestbook-reports")
        self.assertEqual(forbidden.status_code, 403)

        self.current_user = self.admin
        listed = self.client.get(
            "/api/v1/admin/guestbook-reports",
            params={"status": "PENDING"},
        )
        self.assertEqual(listed.status_code, 200)
        self.assertEqual(listed.json()["total"], 1)
        self.assertEqual(listed.json()["items"][0]["id"], report_id)
        self.assertEqual(
            listed.json()["items"][0]["reported_user"]["id"],
            self.author.id,
        )

        reviewing = self.client.patch(
            f"/api/v1/admin/guestbook-reports/{report_id}",
            json={"status": "REVIEWING", "admin_note": "  검토 시작  "},
        )
        self.assertEqual(reviewing.status_code, 200)
        self.assertEqual(reviewing.json()["admin_note"], "검토 시작")
        self.assertIsNone(reviewing.json()["resolved_at"])

        resolved = self.client.patch(
            f"/api/v1/admin/guestbook-reports/{report_id}",
            json={"status": "RESOLVED", "admin_note": "조치 완료"},
        )
        self.assertEqual(resolved.status_code, 200)
        self.assertEqual(resolved.json()["status"], "RESOLVED")
        self.assertEqual(resolved.json()["resolved_by"]["id"], self.admin.id)
        self.assertIsNotNone(resolved.json()["resolved_at"])

        pending_queue = self.client.get(
            "/api/v1/admin/guestbook-reports",
            params={"status": "PENDING"},
        )
        self.assertEqual(pending_queue.status_code, 200)
        self.assertEqual(pending_queue.json()["total"], 0)

    def test_moderation_endpoints_require_authentication(self) -> None:
        app.dependency_overrides.pop(get_current_user, None)
        try:
            feed = self.client.get("/api/v1/guestbooks/feed")
            blocks = self.client.get("/api/v1/user-blocks")
            report = self.client.post(
                f"/api/v1/guestbooks/{self.author_guestbook.id}/reports",
                json={"reason": "SPAM"},
            )
        finally:
            app.dependency_overrides[get_current_user] = lambda: self.current_user

        self.assertEqual(feed.status_code, 401)
        self.assertEqual(blocks.status_code, 401)
        self.assertEqual(report.status_code, 401)


if __name__ == "__main__":
    unittest.main()
