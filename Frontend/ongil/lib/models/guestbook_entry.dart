import 'package:flutter/material.dart';

/// 방명록 탭에 보여줄 글 한 건.
/// 지금은 백엔드 연동 전이라 화면 안에서만 만들어지는 더미 모델임 (홈 화면에서 서버 데이터를
/// 붙일 때는 이 클래스에 fromJson 정도만 추가하면 됨).
class GuestbookEntry {
  final String id;
  final String placeName;
  final String authorName;
  final String content;
  final DateTime createdAt;
  final ImageProvider? image;

  const GuestbookEntry({
    required this.id,
    required this.placeName,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.image,
  });

  /// "3일 전" / "2주 전" / "2026.08.15" 같은 짧은 상대 표기. intl 패키지 없이 직접 계산함.
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
