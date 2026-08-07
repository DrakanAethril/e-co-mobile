import 'checkpoint.dart';

// Mirrors the JSON shape shared by POST /api/eco/runner/join and GET /api/eco/runner/state - the
// latter is what "reprise après crash" rebuilds the UI from on relaunch, using the persisted
// token (see SessionStore), instead of trusting anything the app remembered locally.
class RunnerSession {
  final int runnerId;
  final String token;
  final String pseudo;
  final String status; // 'not_started' | 'racing' | 'finished'
  final String courseName;
  final String parcoursName;
  final String mode; // 'imposed_order' | 'free_order' | 'score'
  final String mapVisibility;

  /// Time allowance of the modes played against the clock (screen 2b). Null in imposed order.
  final int? timeLimitMinutes;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final List<int> validatedCheckpointIds;
  final List<Checkpoint> checkpoints;

  RunnerSession({
    required this.runnerId,
    required this.token,
    required this.pseudo,
    required this.status,
    required this.courseName,
    required this.parcoursName,
    required this.mode,
    required this.mapVisibility,
    required this.timeLimitMinutes,
    required this.startedAt,
    required this.finishedAt,
    required this.validatedCheckpointIds,
    required this.checkpoints,
  });

  /// The mode's wording, as it reads under the parcours name in the header.
  String get modeLabel => switch (mode) {
        'free_order' => 'ordre libre',
        'score' => 'course au score',
        _ => 'ordre imposé',
      };

  factory RunnerSession.fromJson(Map<String, dynamic> json) => RunnerSession(
        runnerId: json['runnerId'] as int,
        token: json['token'] as String,
        pseudo: json['pseudo'] as String,
        status: json['status'] as String,
        courseName: json['courseName'] as String,
        parcoursName: json['parcoursName'] as String? ?? '',
        mode: json['mode'] as String,
        mapVisibility: json['mapVisibility'] as String,
        timeLimitMinutes: (json['timeLimitMinutes'] as num?)?.toInt(),
        startedAt: json['startedAt'] != null ? DateTime.parse(json['startedAt'] as String) : null,
        finishedAt: json['finishedAt'] != null ? DateTime.parse(json['finishedAt'] as String) : null,
        validatedCheckpointIds: (json['validatedCheckpointIds'] as List? ?? []).map((e) => e as int).toList(),
        checkpoints: (json['checkpoints'] as List)
            .map((e) => Checkpoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  RunnerSession copyWith({String? status, DateTime? startedAt, List<int>? validatedCheckpointIds}) => RunnerSession(
        runnerId: runnerId,
        token: token,
        pseudo: pseudo,
        status: status ?? this.status,
        courseName: courseName,
        parcoursName: parcoursName,
        mode: mode,
        mapVisibility: mapVisibility,
        timeLimitMinutes: timeLimitMinutes,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt,
        validatedCheckpointIds: validatedCheckpointIds ?? this.validatedCheckpointIds,
        checkpoints: checkpoints,
      );
}
