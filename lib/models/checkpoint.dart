// The server never sends a runner the checkpoint codes (typing one is what validates a flag), so
// this model carries none: the QR or the typed code goes straight to POST /api/eco/runner/scan.
class Checkpoint {
  final int id;
  final String name;
  final int position;
  final String type; // 'start' | 'checkpoint' | 'finish'
  final int toleranceMeters;
  final bool isValidated;
  final bool isNext;
  final double? latitude;
  final double? longitude;

  Checkpoint({
    required this.id,
    required this.name,
    required this.position,
    required this.type,
    required this.toleranceMeters,
    required this.isValidated,
    required this.isNext,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  /// "D", "A" or the number: the label carried by the map pins and the grid chips.
  String get shortLabel => switch (type) {
        'start' => 'D',
        'finish' => 'A',
        _ => '$position',
      };

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
        id: json['id'] as int,
        name: json['name'] as String,
        position: json['position'] as int,
        type: json['type'] as String,
        toleranceMeters: (json['toleranceMeters'] as num?)?.toInt() ?? 20,
        isValidated: json['isValidated'] as bool? ?? false,
        isNext: json['isNext'] as bool? ?? false,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}
