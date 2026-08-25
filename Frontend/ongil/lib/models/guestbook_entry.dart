import 'package:flutter/material.dart';

import 'guestbook.dart';

/// 방명록 탭 카드 한 장을 그리기 위한 화면용 모델.
///
/// 서버 응답(`Guestbook`)에는 장소 이름도 작성자도 없어서,
/// 일정 상세의 장소 정보와 내 닉네임을 합쳐 여기서 만들어 쓴다.
/// 장소당 한 건이므로 식별자는 [placeId].
class GuestbookEntry {
  /// 서버 방명록 id.
  final int guestbookId;

  /// places 테이블 PK. 모든 방명록 API의 경로 파라미터.
  final int placeId;

  final String placeName;
  final String authorName;
  final String content;
  final DateTime createdAt;

  /// 카드에 띄울 사진 URL. 지금 사진을 우선하고, 없으면 그때 사진.
  final String? photoUrl;

  /// 사진 후처리(모자이크)가 아직 안 끝난 것으로 보이는 상태.
  final bool isPhotoProcessing;

  const GuestbookEntry({
    required this.guestbookId,
    required this.placeId,
    required this.placeName,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.photoUrl,
    this.isPhotoProcessing = false,
  });

  /// `Guestbook` + 장소 이름 + 작성자 이름 → 화면용 모델.
  factory GuestbookEntry.from(
    Guestbook book, {
    required String placeName,
    required String authorName,
  }) {
    final photo = book.currentPhoto ?? book.pastPhoto;
    return GuestbookEntry(
      guestbookId: book.id,
      placeId: book.placeId,
      placeName: placeName,
      authorName: authorName,
      content: book.content ?? '',
      createdAt: book.createdAt,
      photoUrl: photo?.displayUrl,
      isPhotoProcessing: photo?.isProcessing ?? false,
    );
  }

  ImageProvider? get image {
    final url = photoUrl;
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  bool get hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;

  /// "3일 전" / "2주 전" / "2026.08.15" 같은 짧은 상대 표기.
  String get relativeDate {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return '방금 전';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    if (diff.inDays < 28) return '${diff.inDays ~/ 7}주 전';
    final y = createdAt.year.toString().padLeft(4, '0');
    final m = createdAt.month.toString().padLeft(2, '0');
    final d = createdAt.day.toString().padLeft(2, '0');
    return '$y.$m.$d';
  }
}
