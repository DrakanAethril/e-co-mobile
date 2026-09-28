import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../theme.dart';

// The two steps of a course's manual cycle (Préparée -> En cours -> Clôturée), shared by every
// teacher screen that offers them - the parcours' course list, the live list and the live screen -
// so « Arrêter » asks the same question wherever it is pressed.

/// Starts a prepared course. Answers the course as the server now has it, or null on failure
/// (already said in a snackbar).
Future<Map<String, dynamic>?> startCourse(BuildContext context, String jwt, int courseId) async {
  final api = context.read<ApiClient>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    final json = await api.teacherStartCourse(jwt, courseId);
    messenger.showSnackBar(const SnackBar(content: Text('Course démarrée : les coureurs peuvent la rejoindre.')));

    return (json['course'] as Map).cast<String, dynamic>();
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(e.error == 'courseNotPrepared' ? 'Cette course a déjà été démarrée.' : 'Démarrage impossible.'),
    ));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Démarrage impossible — vérifiez la connexion.')));
  }

  return null;
}

/// Asks first, then closes a running course. Answers true once it is closed.
Future<bool> confirmAndCloseCourse(BuildContext context, String jwt, int courseId, String courseName) async {
  final api = context.read<ApiClient>();
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Arrêter la course ?', style: EcoFont.spectral(size: 18)),
      content: Text(
        '« $courseName » sera clôturée : plus personne ne pourra la rejoindre, '
        'et une course arrêtée ne se redémarre pas. Les résultats restent consultables sur MonCampus.',
        style: EcoFont.sans(size: 14, color: EcoColors.muted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Annuler', style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: EcoColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Arrêter', style: EcoFont.sans(size: 14, weight: FontWeight.w700, color: EcoColors.red)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await api.teacherCloseCourse(jwt, courseId);
    messenger.showSnackBar(SnackBar(content: Text('« $courseName » est arrêtée.')));

    return true;
  } on ApiException catch (e) {
    // Already closed elsewhere (the web screen, another phone): the list simply catches up.
    if (e.error == 'courseNotInProgress') {
      messenger.showSnackBar(const SnackBar(content: Text("Cette course n'est plus en cours.")));

      return true;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Arrêt impossible.')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Arrêt impossible — vérifiez la connexion.')));
  }

  return false;
}

/// The status pill of a course card: blue while prepared, green while running, grey once closed.
class CourseStatusBadge extends StatelessWidget {
  final String status;
  final String label;
  const CourseStatusBadge({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      'in_progress' => (EcoColors.greenBg, EcoColors.greenTx),
      'closed' => (EcoColors.borderSoft, EcoColors.muted),
      _ => (EcoColors.blueBg, EcoColors.blueDark),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: EcoFont.sans(size: 11.5, weight: FontWeight.w700, color: foreground)),
    );
  }
}
