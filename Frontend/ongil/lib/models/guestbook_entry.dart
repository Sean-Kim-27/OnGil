class GuestbookAuthor {
  final int id;
  final String? nickname;
  final String? profileImageUrl;

  const GuestbookAuthor({
    required this.id,
    this.nickname,
    this.profileImageUrl,
  });

  factory GuestbookAuthor.fromJson(Map<String, dynamic> json) {
    return GuestbookAuthor(
      id: json['id'] as int,
      nickname: json['nickname'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
    );
  }
}

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
      id: json['id'] as int,
      name: json['name'] as String,
      category: json['category'] as String,
      imageUrl: json['image_url'] as String?,
    );
  }
}

class GuestbookPhoto {
  final int id;
  final String photoType;
  final String imageUrl;
  final String? mosaicImageUrl;
  final int? takenYear;

  const GuestbookPhoto({
    required this.id,
    required this.photoType,
    required this.imageUrl,
    this.mosaicImageUrl,
    this.takenYear,
  });

  factory GuestbookPhoto.fromJson(Map<String, dynamic> json) {
    return GuestbookPhoto(
      id: json['id'] as int,
      photoType: json['photo_type'] as String,
      imageUrl: json['image_url'] as String,
      mosaicImageUrl: json['mosaic_image_url'] as String?,
      takenYear: json['taken_year'] as int?,
    );
  }
}

class GuestbookEntry {
  final int id;
  final int placeId;
  final String? content;
  final DateTime createdAt;
  final GuestbookAuthor author;
  final GuestbookPlace place;
  final List<GuestbookPhoto> photos;

  const GuestbookEntry({
    required this.id,
    required this.placeId,
    required this.content,
    required this.createdAt,
    required this.author,
    required this.place,
    required this.photos,
  });

  factory GuestbookEntry.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'] as List<dynamic>? ?? const [];
    return GuestbookEntry(
      id: json['id'] as int,
      placeId: json['place_id'] as int,
      content: json['content'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      author: GuestbookAuthor.fromJson(
        json['author'] as Map<String, dynamic>,
      ),
      place: GuestbookPlace.fromJson(json['place'] as Map<String, dynamic>),
      photos: rawPhotos
          .map(
            (photo) => GuestbookPhoto.fromJson(photo as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class GuestbookFeed {
  final List<GuestbookEntry> items;
  final int total;
  final int limit;
  final int offset;

  const GuestbookFeed({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory GuestbookFeed.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return GuestbookFeed(
      items: rawItems
          .map((item) => GuestbookEntry.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      total: json['total'] as int,
      limit: json['limit'] as int,
      offset: json['offset'] as int,
    );
  }
}
