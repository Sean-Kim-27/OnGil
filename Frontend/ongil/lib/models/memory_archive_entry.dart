import 'package:flutter/material.dart';

import 'guestbook.dart';

/// 아카이브 탭의 '그때와 지금' 비교 한 건.
///
/// 방명록과 같은 레코드(장소당 1건)의 사진 쪽 단면이라 식별자는 [placeId].
/// 메모는 방명록 텍스트와 같은 필드를 공유한다 — 여기서 고치면 방명록 탭 글도 바뀜.
class MemoryArchiveEntry {
  final int guestbookId;
  final int placeId;

  final String placeName;
  final String subtitle;

  /// 그때 사진의 촬영 연도 라벨. 서버에 연도가 없으면 '그때'.
  final String beforeYear;
  final String afterYear;

  /// 그때(PAST) 사진 URL.
  final String? beforeUrl;

  /// 지금(CURRENT) 사진 URL.
  final String? afterUrl;

  /// 장소 대표 이미지. 지금 사진이 아직 없을 때만 쓰는 보조 수단.
  final String? placeImageUrl;

  /// 방명록 텍스트와 같은 값.
  final String? note;

  final DateTime createdAt;

  /// 사진 중 하나라도 후처리가 안 끝난 것으로 보이는 상태.
  final bool isProcessing;

  const MemoryArchiveEntry({
    required this.guestbookId,
    required this.placeId,
    required this.placeName,
    required this.subtitle,
    required this.beforeYear,
    this.afterYear = '지금',
    this.beforeUrl,
    this.afterUrl,
    this.placeImageUrl,
    this.note,
    required this.createdAt,
    this.isProcessing = false,
  });

  factory MemoryArchiveEntry.from(
    Guestbook book, {
    required String placeName,
    required String subtitle,
    String? placeImageUrl,
  }) {
    final past = book.pastPhoto;
    final current = book.currentPhoto;

    return MemoryArchiveEntry(
      guestbookId: book.id,
      placeId: book.placeId,
      placeName: placeName,
      subtitle: subtitle,
      beforeYear: past?.takenYear?.toString() ?? '그때',
      beforeUrl: past?.displayUrl,
      afterUrl: current?.displayUrl,
      placeImageUrl: placeImageUrl,
      note: book.hasContent ? book.content : null,
      createdAt: book.createdAt,
      isProcessing:
          (past?.isProcessing ?? false) || (current?.isProcessing ?? false),
    );
  }

  ImageProvider? _network(String? url) {
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  ImageProvider? get beforeImage => _network(beforeUrl);

  /// 내가 찍은 지금 사진을 우선하고, 없으면 장소 대표 이미지로 대체.
  ImageProvider? get afterImage => _network(afterUrl) ?? _network(placeImageUrl);

  bool get hasBeforePhoto => beforeUrl != null && beforeUrl!.isNotEmpty;
  bool get hasAfterPhoto => afterUrl != null && afterUrl!.isNotEmpty;

  /// 슬라이더로 비교할 수 있는 상태.
  bool get isComparable => hasBeforePhoto && hasAfterPhoto;

  /// 그때 사진만 남으면 완성되는 상태.
  bool get needsPastPhoto => hasAfterPhoto && !hasBeforePhoto;
}
