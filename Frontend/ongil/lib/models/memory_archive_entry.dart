import 'dart:io';
import 'package:flutter/material.dart';

/// 아카이브 탭의 '그때와 지금' 비교 한 건.
class MemoryArchiveEntry {
  final String id;

  /// 어떤 여정 기준인지.
  final int scheduleId;

  final String placeName;
  final String subtitle;
  final String beforeYear;
  final String afterYear;

  /// 사용자가 올린 '그때' 사진의 로컬 파일 경로.
  final String? beforePhotoPath;

  /// 사용자가 카메라로 찍은 '지금' 사진 경로. 아카이브 작성 시 필수.
  final String? afterPhotoPath;

  /// 장소 대표 이미지. '지금' 사진이 없을 때만 쓰는 보조 수단.
  final String? afterImageUrl;

  final String? note;
  final DateTime createdAt;

  const MemoryArchiveEntry({
    required this.id,
    required this.scheduleId,
    required this.placeName,
    required this.subtitle,
    required this.beforeYear,
    required this.afterYear,
    this.beforePhotoPath,
    this.afterPhotoPath,
    this.afterImageUrl,
    this.note,
    required this.createdAt,
  });

  ImageProvider? get beforeImage {
    final path = beforePhotoPath;
    if (path == null || path.isEmpty) return null;
    return FileImage(File(path));
  }

  /// 사용자가 찍은 사진을 우선하고, 없으면 장소 대표 이미지로 대체.
  ImageProvider? get afterImage {
    final path = afterPhotoPath;
    if (path != null && path.isNotEmpty) return FileImage(File(path));
    final url = afterImageUrl;
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }

  bool get hasBeforePhoto => beforePhotoPath != null && beforePhotoPath!.isNotEmpty;
  bool get hasAfterPhoto => afterPhotoPath != null && afterPhotoPath!.isNotEmpty;

  /// 그때-지금이 모두 갖춰진 완성된 비교인지.
  bool get isComplete => hasBeforePhoto && (hasAfterPhoto || (afterImageUrl?.isNotEmpty ?? false));

  MemoryArchiveEntry copyWith({
    String? placeName,
    String? beforeYear,
    String? beforePhotoPath,
    String? afterPhotoPath,
    String? afterImageUrl,
    String? note,
  }) {
    return MemoryArchiveEntry(
      id: id,
      scheduleId: scheduleId,
      placeName: placeName ?? this.placeName,
      subtitle: subtitle,
      beforeYear: beforeYear ?? this.beforeYear,
      afterYear: afterYear,
      beforePhotoPath: beforePhotoPath ?? this.beforePhotoPath,
      afterPhotoPath: afterPhotoPath ?? this.afterPhotoPath,
      afterImageUrl: afterImageUrl ?? this.afterImageUrl,
      note: note ?? this.note,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'schedule_id': scheduleId,
        'place_name': placeName,
        'subtitle': subtitle,
        'before_year': beforeYear,
        'after_year': afterYear,
        'before_photo_path': beforePhotoPath,
        'after_photo_path': afterPhotoPath,
        'after_image_url': afterImageUrl,
        'note': note,
        'created_at': createdAt.toIso8601String(),
      };

  factory MemoryArchiveEntry.fromJson(Map<String, dynamic> json) {
    String? nullIfBlank(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return MemoryArchiveEntry(
      id: (json['id'] ?? '').toString(),
      scheduleId: int.tryParse('${json['schedule_id']}') ?? 0,
      placeName: (json['place_name'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      beforeYear: (json['before_year'] ?? '그때').toString(),
      afterYear: (json['after_year'] ?? '지금').toString(),
      beforePhotoPath: nullIfBlank(json['before_photo_path']),
      afterPhotoPath: nullIfBlank(json['after_photo_path']),
      afterImageUrl: nullIfBlank(json['after_image_url']),
      note: nullIfBlank(json['note']),
      createdAt:
          DateTime.tryParse('${json['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }
}
