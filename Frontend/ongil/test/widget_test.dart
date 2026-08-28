import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ongil/models/guestbook_entry.dart';
import 'package:ongil/screens/guestbook_screen.dart';
import 'package:ongil/services/guestbook_service.dart';

class FakeGuestbookRepository implements GuestbookRepository {
  final GuestbookFeed feed;
  int? blockedUserId;
  int? unblockedUserId;
  int? reportedGuestbookId;
  GuestbookReportReason? reportedReason;

  FakeGuestbookRepository(this.feed);

  @override
  Future<void> blockUser(int userId) async {
    blockedUserId = userId;
  }

  @override
  Future<GuestbookFeed> fetchFeed({int limit = 50, int offset = 0}) async {
    return feed;
  }

  @override
  Future<int?> fetchCurrentUserId() async => 1;

  @override
  Future<void> reportGuestbook({
    required int guestbookId,
    required GuestbookReportReason reason,
    String? details,
  }) async {
    reportedGuestbookId = guestbookId;
    reportedReason = reason;
  }

  @override
  Future<void> unblockUser(int userId) async {
    unblockedUserId = userId;
  }
}

GuestbookFeed _feed() {
  return GuestbookFeed(
    items: [
      GuestbookEntry(
        id: 10,
        placeId: 20,
        content: '함께 걸었던 골목 이야기',
        createdAt: DateTime.utc(2026, 8, 28),
        author: const GuestbookAuthor(id: 2, nickname: '작성자'),
        place: const GuestbookPlace(
          id: 20,
          name: '추억의 골목',
          category: 'tourist_attraction',
        ),
        photos: const [],
      ),
    ],
    total: 1,
    limit: 50,
    offset: 0,
  );
}

void main() {
  testWidgets('방명록 신고 메뉴에서 신고를 접수한다', (tester) async {
    final repository = FakeGuestbookRepository(_feed());
    await tester.pumpWidget(
      MaterialApp(home: GuestbookScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('함께 걸었던 골목 이야기'), findsOneWidget);
    await tester.tap(find.byTooltip('신고 및 차단 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('신고하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '신고하기'));
    await tester.pumpAndSettle();

    expect(repository.reportedGuestbookId, 10);
    expect(repository.reportedReason, GuestbookReportReason.spam);
    expect(find.text('신고가 접수됐어요. 관리자가 확인할게요.'), findsOneWidget);
  });

  testWidgets('사용자 차단 후 해당 작성자의 방명록을 즉시 숨긴다', (tester) async {
    final repository = FakeGuestbookRepository(_feed());
    await tester.pumpWidget(
      MaterialApp(home: GuestbookScreen(repository: repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('신고 및 차단 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('사용자 차단'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '차단하기'));
    await tester.pumpAndSettle();

    expect(repository.blockedUserId, 2);
    expect(find.text('함께 걸었던 골목 이야기'), findsNothing);
    expect(find.text('사용자를 차단했어요.'), findsOneWidget);
  });
}
