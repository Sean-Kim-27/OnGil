class ScheduleItem {
  final int id;
  final int visitOrder;
  final String title;
  final String category;
  final String imageUrl;
  final double latitude;
  final double longitude;

  ScheduleItem({
    required this.id,
    required this.visitOrder,
    required this.title,
    required this.category,
    required this.imageUrl,
    required this.latitude,
    required this.longitude,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    final placeData = json['place'] ?? {};
    return ScheduleItem(
      id: json['id'] ?? 0,
      visitOrder: json['visit_order'] ?? 1,
      title: placeData['title'] ?? '',
      category: placeData['category'] ?? '',
      imageUrl: placeData['image_url'] ?? '',
      latitude: (placeData['latitude'] as num).toDouble(),
      longitude: (placeData['longitude'] as num).toDouble(),
    );
  }
}