import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/join_screen.dart';
import '../services/api_client.dart';
import '../theme.dart';

/// « Se déconnecter », in the app bar of each tab of TeacherHomeScreen. Asked first: a tap by
/// mistake in the middle of a course would mean typing the password again out in the field. The
/// session is closed on the server too (ApiClient.teacherLogout), not just forgotten here.
class TeacherLogoutButton extends StatelessWidget {
  const TeacherLogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Se déconnecter',
      onPressed: () => _logout(context),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final api = context.read<ApiClient>();
    final navigator = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Se déconnecter ?', style: EcoFont.spectral(size: 18)),
        content: Text(
          'Il faudra saisir de nouveau votre identifiant et votre mot de passe. '
          'Les courses en cours continuent sans vous.',
          style: EcoFont.sans(size: 14, color: EcoColors.muted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Annuler', style: EcoFont.sans(size: 14, weight: FontWeight.w600, color: EcoColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Se déconnecter', style: EcoFont.sans(size: 14, weight: FontWeight.w700, color: EcoColors.blueDark)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await api.teacherLogout();
    navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const JoinScreen()), (_) => false);
  }
}
