import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'services/session_store.dart';
import 'services/offline_queue_db.dart';
import 'services/location_service.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/teacher_login_screen.dart';

void main() {
  disableEcoFontFetching();

  final api = ApiClient();
  final sessionStore = SessionStore();
  final queueDb = OfflineQueueDb();
  final navigatorKey = GlobalKey<NavigatorState>();

  // A teacher call refused for its token: forget it, and start the teacher over at the login
  // screen whatever they were looking at.
  api.onTeacherSessionLost = () async {
    await sessionStore.clearTeacherJwt();
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const TeacherLoginScreen(notice: 'Votre session a expiré : reconnectez-vous.')),
      (_) => false,
    );
  };

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<SessionStore>.value(value: sessionStore),
        Provider<OfflineQueueDb>.value(value: queueDb),
        Provider<LocationService>(create: (_) => LocationService(queueDb)),
      ],
      child: EcoApp(navigatorKey: navigatorKey),
    ),
  );
}

class EcoApp extends StatelessWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  const EcoApp({super.key, this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'e-CO',
      navigatorKey: navigatorKey,
      theme: ecoTheme(),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
