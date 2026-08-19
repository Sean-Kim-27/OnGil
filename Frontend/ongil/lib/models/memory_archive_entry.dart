import 'package:flutter/material.dart';

/// 방명록 '아카이브' 탭의 '그때와 지금' 비교 한 건.
/// 실제 사진/연도 데이터는 아직 서버에 없어서 프론트에서는 더미로 채워둠.
class MemoryArchiveEntry {
  final String id;
  final String placeName;
  final String subtitle;
  final String beforeYear;
  final String afterYear;
  final ImageProvider? beforeImage;
  final ImageProvider? afterImage;

  const MemoryArchiveEntry({
    required this.id,
    required this.placeName,
    required this.subtitle,
    required this.beforeYear,
    required this.afterYear,
    this.beforeImage,
    this.afterImage,
  });
}
