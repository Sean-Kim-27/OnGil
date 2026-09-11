import 'guestbook.dart';

/// 신고·차단(moderation) 관련 모델.
///
/// 서버 스키마를 그대로 옮긴 계층이라 파싱은 전부 여기서 담당한다.
/// (`Guestbook`, `ArchivePhoto`와 같은 역할)

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
// 신고 사유
// ---------------------------------------------------------------------------

/// 서버 `ReportReason` enum. 전송값은 반드시 대문자.
enum ReportReason {
  spam('SPAM', '스팸 또는 광고'),
  harassment('HARASSMENT', '괴롭힘 또는 욕설'),
  hateSpeech('HATE_SPEECH', '혐오 표현'),
  sexualContent('SEXUAL_CONTENT', '선정적인 내용'),
  violence('VIOLENCE', '폭력적인 내용'),
  privacy('PRIVACY', '개인정보 노출'),
  illegal('ILLEGAL', '불법적인 내용'),
  other('OTHER', '기타');

  /// 서버로 보내는 값.
  final String wire;

  /// 화면에 띄울 이름.
  final String label;

  const ReportReason(this.wire, this.label);

  static ReportReason? tryParse(String? raw) {
    final upper = raw?.trim().toUpperCase();
    for (final r in values) {
      if (r.wire == upper) return r;
    }
    return null;
  }
}

/// 서버 `ReportStatus` enum.
enum ReportStatus {
  pending('PENDING'),
  reviewing('REVIEWING'),
  resolved('RESOLVED'),
  dismissed('DISMISSED');

  final String wire;
  const ReportStatus(this.wire);

  static ReportStatus? tryParse(String? raw) {
    final upper = raw?.trim().toUpperCase();
    for (final s in values) {
      if (s.wire == upper) return s;
    }
    return null;
  }
}

/// 신고 접수 결과(`GuestbookReportResponse`).
class GuestbookReport {
  final int id;
  final int? guestbookId;
  final int? reportedUserId;
  final ReportReason reason;
  final String? details;
  final ReportStatus status;
  final DateTime createdAt;

  const GuestbookReport({
    required this.id,
    this.guestbookId,
    this.reportedUserId,
    required this.reason,
    this.details,
    required this.status,
    required this.createdAt,
  });

  factory GuestbookReport.fromJson(Map<String, dynamic> json) {
    return GuestbookReport(
      id: _toInt(json['id']) ?? 0,
      guestbookId: _toInt(json['guestbook_id']),
      reportedUserId: _toInt(json['reported_user_id']),
      reason: ReportReason.tryParse(_toStringOrNull(json['reason'])) ??
          ReportReason.other,
      details: _toStringOrNull(json['details']),
      status: ReportStatus.tryParse(_toStringOrNull(json['status'])) ??
          ReportStatus.pending,
      createdAt: _toDateTime(json['created_at']),
    );
  }
}

// ---------------------------------------------------------------------------
// 사용자 (작성자 / 차단 대상)
// ---------------------------------------------------------------------------

/// `GuestbookAuthorResponse`와 `ModerationUserResponse`가 모양이 같아 하나로 씀.
class ModerationUser {
  final int id;
  final String? nickname;
  final String? profileImageUrl;

  const ModerationUser({
    required this.id,
    this.nickname,
    this.profileImageUrl,
  });

  /// 닉네임이 비어 있을 수 있어 화면에 쓸 이름을 따로 만든다.
  String get displayName {
    final n = nickname?.trim();
    return (n == null || n.isEmpty) ? '이름 없는 여행자' : n;
  }

  /// 프로필 이미지가 없을 때 아바타에 넣을 첫 글자.
  String get initial {
    final n = displayName;
    return n.isEmpty ? '?' : n.substring(0, 1);
  }

  factory ModerationUser.fromJson(Map<String, dynamic> json) {
    return ModerationUser(
      id: _toInt(json['id']) ?? 0,
      nickname: _toStringOrNull(json['nickname']),
      profileImageUrl: _toStringOrNull(json['profile_image_url']),
    );
  }
}

/// 내가 차단한 사용자 한 명(`UserBlockResponse`).
class UserBlock {
  final int id;
  final ModerationUser blockedUser;
  final DateTime createdAt;

  const UserBlock({
    required this.id,
    required this.blockedUser,
    required this.createdAt,
  });

  factory UserBlock.fromJson(Map<String, dynamic> json) {
    final raw = json['blocked_user'];
    return UserBlock(
      id: _toInt(json['id']) ?? 0,
      blockedUser: raw is Map<String, dynamic>
          ? ModerationUser.fromJson(raw)
          : const ModerationUser(id: 0),
      createdAt: _toDateTime(json['created_at']),
    );
  }
}

// ---------------------------------------------------------------------------
// 피드
// ---------------------------------------------------------------------------

/// 피드 아이템에 실려 오는 장소 정보(`GuestbookPlaceResponse`).
///
/// 기존 `GuestbookResponse`에는 `place_id`만 있어서 이번 여정 밖 장소는
/// 이름을 못 채웠는데, 피드에서는 서버가 이름과 이미지를 같이 준다.
class GuestbookPlace {
  final int id;
  final String name;
  final String category;
  final String? imageUrl;

  const GuestbookPlace({
    required this.id,
    required this.name,
    required this.category,
    this.imageUrl,
  });

  factory GuestbookPlace.fromJson(Map<String, dynamic> json) {
    return GuestbookPlace(
      id: _toInt(json['id']) ?? 0,
      name: _toStringOrNull(json['name']) ?? '이름 없는 장소',
      category: _toStringOrNull(json['category']) ?? '',
      imageUrl: _toStringOrNull(json['image_url']),
    );
  }
}

/// 피드 한 건(`GuestbookFeedItemResponse`).
///
/// `Guestbook`과 달리 작성자·장소가 함께 온다. 신고·차단은 이 작성자를 대상으로 함.
class GuestbookFeedItem {
  final int id;
  final int placeId;
  final String? content;
  final DateTime createdAt;
  final List<ArchivePhoto> photos;
  final ModerationUser author;
  final GuestbookPlace place;

  const GuestbookFeedItem({
    required this.id,
    required this.placeId,
    this.content,
    required this.createdAt,
    this.photos = const [],
    required this.author,
    required this.place,
  });

  ArchivePhoto? _photoOf(ArchivePhotoType type) {
    for (final p in photos) {
      if (p.type == type) return p;
    }
    return null;
  }

  ArchivePhoto? get currentPhoto => _photoOf(ArchivePhotoType.current);
  ArchivePhoto? get pastPhoto => _photoOf(ArchivePhotoType.past);

  /// 카드에 띄울 사진. 지금 사진을 우선하고 없으면 그때 사진.
  ArchivePhoto? get coverPhoto => currentPhoto ?? pastPhoto;

  bool get hasContent => (content ?? '').trim().isNotEmpty;

  /// 그때-지금을 나란히 볼 수 있는 상태.
  bool get isComparable => currentPhoto != null && pastPhoto != null;

  factory GuestbookFeedItem.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    final rawAuthor = json['author'];
    final rawPlace = json['place'];

    return GuestbookFeedItem(
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
      author: rawAuthor is Map<String, dynamic>
          ? ModerationUser.fromJson(rawAuthor)
          : const ModerationUser(id: 0),
      place: rawPlace is Map<String, dynamic>
          ? GuestbookPlace.fromJson(rawPlace)
          : const GuestbookPlace(id: 0, name: '이름 없는 장소', category: ''),
    );
  }
}

/// 피드 한 페이지(`GuestbookFeedResponse`).
class GuestbookFeedPage {
  final List<GuestbookFeedItem> items;
  final int total;
  final int limit;
  final int offset;

  const GuestbookFeedPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  /// 다음 페이지가 남아 있는지.
  bool get hasMore => offset + items.length < total;

  /// 다음 요청에 쓸 offset.
  int get nextOffset => offset + items.length;

  factory GuestbookFeedPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return GuestbookFeedPage(
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(GuestbookFeedItem.fromJson)
              .toList()
          : const [],
      total: _toInt(json['total']) ?? 0,
      limit: _toInt(json['limit']) ?? 20,
      offset: _toInt(json['offset']) ?? 0,
    );
  }
}
