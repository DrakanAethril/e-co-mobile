import 'package:flutter/material.dart';

import '../screens/teacher_parcours_edit_screen.dart';
import '../screens/teacher_parcours_terrain_screen.dart';
import '../theme.dart';

/// The strip under the header of a parcours' screens - locating its flags, running its courses -
/// that opens its two other pages: the flags and their tolerances (web screen 1e), and the IGN's
/// reading of the ground. [onReturn] reloads the host, since a radius may have changed.
class TeacherParcoursLinks extends StatelessWidget {
  final int parcoursId;
  final String parcoursName;
  final VoidCallback? onReturn;

  const TeacherParcoursLinks({super.key, required this.parcoursId, required this.parcoursName, this.onReturn});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _link(context, Icons.tune, 'Modifier le parcours',
                () => TeacherParcoursEditScreen(parcoursId: parcoursId, parcoursName: parcoursName)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _link(context, Icons.landscape_outlined, 'Terrain IGN',
                () => TeacherParcoursTerrainScreen(parcoursId: parcoursId, parcoursName: parcoursName)),
          ),
        ],
      ),
    );
  }

  Widget _link(BuildContext context, IconData icon, String label, Widget Function() screen) {
    return OutlinedButton.icon(
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen()));
        onReturn?.call();
      },
      icon: Icon(icon, size: 17),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: EcoColors.blueDark,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        textStyle: EcoFont.sans(size: 13, weight: FontWeight.w600),
      ),
    );
  }
}
