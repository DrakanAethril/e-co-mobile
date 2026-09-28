/// One leg of the recap: from one validated flag to the next, in the order the runner ran them.
class RaceLeg {
  final String fromName;
  final String toName;
  final int seconds;
  final int distanceMeters;

  RaceLeg({required this.fromName, required this.toName, required this.seconds, required this.distanceMeters});

  factory RaceLeg.fromJson(Map<String, dynamic> json) => RaceLeg(
        fromName: json['fromName'] as String? ?? '',
        toName: json['toName'] as String? ?? '',
        seconds: (json['seconds'] as num?)?.toInt() ?? 0,
        distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      );
}

// Mirrors GET /api/eco/runner/summary (App\Service\EcoRunnerSummaryBuilder in moncampus): the
// recap of a runner who has scanned the finish. Every figure the server could not work out comes
// back null - a phone that never sent an altitude has no climb - and reads « — » on screen.
class RaceSummary {
  final String pseudo;
  final String courseName;
  final String parcoursName;
  final String mode;
  final DateTime? finishedAt;
  final int? durationSeconds;
  final int distanceMeters;
  final double? averageSpeedKmh;
  final int? elevationGain;

  /// 'gps' while the course runs, 'ign' once the IGN has read the trace after it is closed.
  final String? elevationSource;
  final int checkpointsValidated;
  final int checkpointsTotal;
  final int scanFailureCount;
  final int stopCount;
  final int stopSeconds;
  final List<RaceLeg> legs;

  RaceSummary({
    required this.pseudo,
    required this.courseName,
    required this.parcoursName,
    required this.mode,
    required this.finishedAt,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.averageSpeedKmh,
    required this.elevationGain,
    required this.elevationSource,
    required this.checkpointsValidated,
    required this.checkpointsTotal,
    required this.scanFailureCount,
    required this.stopCount,
    required this.stopSeconds,
    required this.legs,
  });

  factory RaceSummary.fromJson(Map<String, dynamic> json) => RaceSummary(
        pseudo: json['pseudo'] as String? ?? '',
        courseName: json['courseName'] as String? ?? '',
        parcoursName: json['parcoursName'] as String? ?? '',
        mode: json['mode'] as String? ?? 'imposed_order',
        finishedAt: json['finishedAt'] != null ? DateTime.parse(json['finishedAt'] as String) : null,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
        distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
        averageSpeedKmh: (json['averageSpeedKmh'] as num?)?.toDouble(),
        elevationGain: (json['elevationGain'] as num?)?.toInt(),
        elevationSource: json['elevationSource'] as String?,
        checkpointsValidated: (json['checkpointsValidated'] as num?)?.toInt() ?? 0,
        checkpointsTotal: (json['checkpointsTotal'] as num?)?.toInt() ?? 0,
        scanFailureCount: (json['scanFailureCount'] as num?)?.toInt() ?? 0,
        stopCount: (json['stopCount'] as num?)?.toInt() ?? 0,
        stopSeconds: (json['stopSeconds'] as num?)?.toInt() ?? 0,
        legs: (json['legs'] as List? ?? []).map((e) => RaceLeg.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
