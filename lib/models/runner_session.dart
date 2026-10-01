import 'checkpoint.dart';

// Mirrors the JSON shape shared by POST /api/eco/runner/join and GET /api/eco/runner/state - the
// latter is what "reprise après crash" rebuilds the UI from on relaunch, using the persisted
// token (see SessionStore), instead of trusting anything the app remembered locally. Without
// network the relaunch falls back on the last snapshot kept (toJson), until /state answers again.
class RunnerSession {
  final int runnerId;
  final String token;
  final String pseudo;
  final String status; // 'not_started' | 'racing' | 'finished'
  final String courseName;
  final String parcoursName;
  // 'imposed_order' | 'free_order' | 'score'. A « Balises spécifiques » course arrives as one of the
  // first two - in order or not - with its list of checkpoints already cut down by the server.
  final String mode;

  /// The server's wording of the mode (« balises spécifiques · dans l’ordre »); null from a server
  /// older than the field, in which case [modeLabel] words [mode] itself.
  final String? serverModeLabel;
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
    this.serverModeLabel,
    required this.mapVisibility,
    required this.timeLimitMinutes,
    required this.startedAt,
    required this.finishedAt,
    required this.validatedCheckpointIds,
    required this.checkpoints,
  });

  /// The mode's wording, as it reads under the parcours name in the header.
  String get modeLabel => serverModeLabel ?? switch (mode) {
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
        serverModeLabel: json['modeLabel'] as String?,
        mapVisibility: json['mapVisibility'] as String,
        timeLimitMinutes: (json['timeLimitMinutes'] as num?)?.toInt(),
        startedAt: json['startedAt'] != null ? DateTime.parse(json['startedAt'] as String) : null,
        finishedAt: json['finishedAt'] != null ? DateTime.parse(json['finishedAt'] as String) : null,
        validatedCheckpointIds: (json['validatedCheckpointIds'] as List? ?? []).map((e) => e as int).toList(),
        checkpoints: (json['checkpoints'] as List)
            .map((e) => Checkpoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// The same shape as [fromJson] reads - what SessionStore keeps for a relaunch without network.
  Map<String, dynamic> toJson() => {
        'runnerId': runnerId,
        'token': token,
        'pseudo': pseudo,
        'status': status,
        'courseName': courseName,
        'parcoursName': parcoursName,
        'mode': mode,
        if (serverModeLabel != null) 'modeLabel': serverModeLabel,
        'mapVisibility': mapVisibility,
        'timeLimitMinutes': timeLimitMinutes,
        'startedAt': startedAt?.toUtc().toIso8601String(),
        'finishedAt': finishedAt?.toUtc().toIso8601String(),
        'validatedCheckpointIds': validatedCheckpointIds,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
      };

  RunnerSession copyWith({String? status, DateTime? startedAt, DateTime? finishedAt, List<int>? validatedCheckpointIds}) => RunnerSession(
        runnerId: runnerId,
        token: token,
        pseudo: pseudo,
        status: status ?? this.status,
        courseName: courseName,
        parcoursName: parcoursName,
        mode: mode,
        serverModeLabel: serverModeLabel,
        mapVisibility: mapVisibility,
        timeLimitMinutes: timeLimitMinutes,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        validatedCheckpointIds: validatedCheckpointIds ?? this.validatedCheckpointIds,
        checkpoints: checkpoints,
      );
}
