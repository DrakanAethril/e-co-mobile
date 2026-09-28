import 'package:flutter/material.dart';

import '../theme.dart';
import 'teacher_live_list_screen.dart';
import 'teacher_parcours_list_screen.dart';
import 'teacher_ready_parcours_screen.dart';

// Entry point after teacher login: the three things a teacher does with e-CO on the ground, one
// tab each - lay the flags out (4b), run courses on the parcours that are ready, and watch / stop
// the courses under way (4d).
class TeacherHomeScreen extends StatefulWidget {
  final String jwt;
  const TeacherHomeScreen({super.key, required this.jwt});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // Only the visible tab is built, and rebuilt on every switch: a course started from « Parcours
    // prêts » must already be under « En cours » when the teacher turns to it.
    final tab = switch (_index) {
      1 => TeacherReadyParcoursScreen(key: const ValueKey('ready'), jwt: widget.jwt),
      2 => TeacherLiveListScreen(key: const ValueKey('live'), jwt: widget.jwt),
      _ => TeacherParcoursListScreen(key: const ValueKey('locate'), jwt: widget.jwt),
    };

    return Scaffold(
      body: tab,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        backgroundColor: Colors.white,
        indicatorColor: EcoColors.blueBg,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_searching),
            selectedIcon: Icon(Icons.my_location, color: EcoColors.blueDark),
            label: 'À localiser',
          ),
          NavigationDestination(
            icon: Icon(Icons.flag_outlined),
            selectedIcon: Icon(Icons.flag, color: EcoColors.blueDark),
            label: 'Parcours prêts',
          ),
          NavigationDestination(
            icon: Icon(Icons.podcasts_outlined),
            selectedIcon: Icon(Icons.podcasts, color: EcoColors.blueDark),
            label: 'En cours',
          ),
        ],
      ),
    );
  }
}
