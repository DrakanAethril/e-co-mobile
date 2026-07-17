class Checkpoint {
  final int id;
  final String shortCode;
  final String name;
  final int position;
  final String type; // 'start' | 'checkpoint' | 'finish'
  final double? latitude;
  final double? longitude;

  Checkpoint({
    required this.id,
    required this.shortCode,
    required this.name,
    required this.position,
    required this.type,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
        id: json['id'] as int,
        shortCode: json['shortCode'] as String,
        name: json['name'] as String,
        position: json['position'] as int,
        type: json['type'] as String,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}
