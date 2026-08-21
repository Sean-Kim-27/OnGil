import 'dart:io';
import 'package:flutter/material.dart';

/// 방명록 탭에 보여줄 글 한 건. 기기 로컬(GuestbookService)에 저장됨.
class GuestbookEntry {
  final String id;

  /// 어떤 여정 기준으로 남긴 기억인지.
  final int scheduleId;

  final String placeName;
  final String authorName;
  final String content;
  final DateTime createdAt;

  /// 기기에 저장된 사진 경로. 없으면 null.
  final String? photoPath;

  const GuestbookEntry({
    required this.id,
    required this.scheduleId,
    required this.placeName,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.photoPath,
  });

  ImageProvider? get image {
    final path = photoPath;
    if (path == null || path.isEmpty) return null;
    return FileImage(File(path));
  }

  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;

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

  /// id/작성자/작성시각은 유지하고 내용만 바꿈.
  GuestbookEntry copyWith({
    String? placeName,
    String? content,
    String? photoPath,
    bool clearPhoto = false,
  }) {
    return GuestbookEntry(
      id: id,
      scheduleId: scheduleId,
      placeName: placeName ?? this.placeName,
      authorName: authorName,
      content: content ?? this.content,
      createdAt: createdAt,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'schedule_id': scheduleId,
        'place_name': placeName,
        'author_name': authorName,
        'content': content,
        'created_at': createdAt.toIso8601String(),
        'photo_path': photoPath,
      };

  factory GuestbookEntry.fromJson(Map<String, dynamic> json) {
    return GuestbookEntry(
      id: (json['id'] ?? '').toString(),
      scheduleId: int.tryParse('${json['schedule_id']}') ?? 0,
      placeName: (json['place_name'] ?? '').toString(),
      authorName: (json['author_name'] ?? '나').toString(),
      content: (json['content'] ?? '').toString(),
      createdAt:
          DateTime.tryParse('${json['created_at']}')?.toLocal() ?? DateTime.now(),
      photoPath: (json['photo_path'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['photo_path'] as String,
    );
  }
}
