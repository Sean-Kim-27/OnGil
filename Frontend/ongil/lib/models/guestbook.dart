import 'package:flutter/foundation.dart';

/// `/api/v1/guestbooks` 응답을 그대로 옮긴 모델.
///
/// 서버 기준으로 방명록은 **장소(place_id)당 한 건**이고,
/// 그 한 건이 글(content)과 사진(photos)을 함께 들고 있다.
/// 화면의 '방명록' 탭과 '아카이브' 탭은 같은 레코드의 다른 단면임.

// ---------------------------------------------------------------------------
// 공용 파서
// ---------------------------------------------------------------------------

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _toStringOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime _toDateTime(dynamic v) {
  final s = _toStringOrNull(v);
  return DateTime.tryParse(s ?? '')?.toLocal() ?? DateTime.now();
}

// ---------------------------------------------------------------------------
// 사진
// ---------------------------------------------------------------------------

/// 서버 `PhotoType` enum. 전송값은 반드시 대문자.
enum ArchivePhotoType {
  /// 지금 모습. 스팟당 1장이고, 과거 사진보다 먼저 올라가야 함.
  current('CURRENT'),

  /// 그때 모습. 현재 사진이 이미 있어야 올릴 수 있음.
  past('PAST');

  final String wire;
  const ArchivePhotoType(this.wire);

  static ArchivePhotoType? tryParse(String? raw) {
    final upper = raw?.trim().toUpperCase();
    for (final t in values) {
      if (t.wire == upper) return t;
    }
    return null;
  }
}

/// 서버가 후처리(모자이크)를 끝냈다고 볼 수 있는 status 값들.
///
/// 실제 enum을 아직 못 받아서 넉넉하게 잡아둠. 백엔드에서 확정되면 좁힐 것.
const _settledStatuses = {
  'DONE',
  'COMPLETED',
  'COMPLETE',
  'SUCCESS',
  'SUCCEEDED',
  'READY',
  'FAILED',
  'FAILURE',
  'ERROR',
  'SKIPPED',
  'NONE',
};

class ArchivePhoto {
  final int id;
  final ArchivePhotoType type;

  /// 원본 이미지 URL.
  final String imageUrl;

  /// 모자이크 처리본. 처리 전이거나 대상이 없으면 null.
  final String? mosaicImageUrl;

  /// 그때 사진의 촬영 연도. 현재 사진에는 보통 없음.
  final int? takenYear;

  /// 서버 처리 상태 원본 문자열.
  final String status;

  final DateTime createdAt;

  const ArchivePhoto({
    required this.id,
    required this.type,
    required this.imageUrl,
    this.mosaicImageUrl,
    this.takenYear,
    this.status = '',
    required this.createdAt,
  });

  /// 화면에 띄울 URL. 모자이크본이 있으면 그쪽을 우선함.
  String get displayUrl {
    final mosaic = mosaicImageUrl;
    if (mosaic != null && mosaic.isNotEmpty) return mosaic;
    return imageUrl;
  }

  /// 모자이크 처리가 아직 안 끝난 것으로 보이는 상태.
  bool get isProcessing {
    if (mosaicImageUrl != null && mosaicImageUrl!.isNotEmpty) return false;
    return !_settledStatuses.contains(status.trim().toUpperCase());
  }

  factory ArchivePhoto.fromJson(Map<String, dynamic> json) {
    final rawType = _toStringOrNull(json['photo_type']);
    final type = ArchivePhotoType.tryParse(rawType);

    if (kDebugMode && type == null) {
      debugPrint('⚠️ [ArchivePhoto] 모르는 photo_type: $rawType → CURRENT로 간주');
    }

    final status = _toStringOrNull(json['status']) ?? '';
    if (kDebugMode &&
        status.isNotEmpty &&
        !_settledStatuses.contains(status.toUpperCase())) {
      // 연동하면서 실제 status 값을 확인하려고 남겨둠.
      debugPrint('ℹ️ [ArchivePhoto] 처리 중으로 본 status 값: $status');
    }

    return ArchivePhoto(
      id: _toInt(json['id']) ?? 0,
      type: type ?? ArchivePhotoType.current,
      imageUrl: _toStringOrNull(json['image_url']) ?? '',
      mosaicImageUrl: _toStringOrNull(json['mosaic_image_url']),
      takenYear: _toInt(json['taken_year']),
      status: status,
      createdAt: _toDateTime(json['created_at']),
    );
  }
}

// ---------------------------------------------------------------------------
// 방명록 (장소당 1건)
// ---------------------------------------------------------------------------

class Guestbook {
  final int id;
  final int placeId;

  /// 방명록 텍스트. 최대 100자이고 비어 있을 수 있음.
  final String? content;

  final DateTime createdAt;
  final List<ArchivePhoto> photos;

  const Guestbook({
    required this.id,
    required this.placeId,
    this.content,
    required this.createdAt,
    this.photos = const [],
  });

  ArchivePhoto? _photoOf(ArchivePhotoType type) {
    for (final p in photos) {
      if (p.type == type) return p;
    }
    return null;
  }

  /// 지금 사진. 스팟당 1장이므로 있으면 하나뿐.
  ArchivePhoto? get currentPhoto => _photoOf(ArchivePhotoType.current);

  /// 그때 사진.
  ArchivePhoto? get pastPhoto => _photoOf(ArchivePhotoType.past);

  bool get hasContent => (content ?? '').trim().isNotEmpty;
  bool get hasCurrentPhoto => currentPhoto != null;
  bool get hasPastPhoto => pastPhoto != null;

  /// 그때-지금 슬라이더를 띄울 수 있는 상태.
  bool get isComparable => hasCurrentPhoto && hasPastPhoto;

  /// 글도 사진도 없는 껍데기 레코드(글을 지운 뒤 등).
  bool get isEmpty => !hasContent && photos.isEmpty;

  factory Guestbook.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    return Guestbook(
      id: _toInt(json['id']) ?? 0,
      placeId: _toInt(json['place_id']) ?? 0,
      content: _toStringOrNull(json['content']),
      createdAt: _toDateTime(json['created_at']),
      photos: rawPhotos is List
          ? rawPhotos
              .whereType<Map<String, dynamic>>()
              .map(ArchivePhoto.fromJson)
              .toList()
          : const [],
    );
  }
}
