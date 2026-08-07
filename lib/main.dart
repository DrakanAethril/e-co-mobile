import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_client.dart';
import 'services/session_store.dart';
import 'services/offline_queue_db.dart';
import 'services/location_service.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';

void main() {
  disableEcoFontFetching();

  final api = ApiClient();
  final sessionStore = SessionStore();
  final queueDb = OfflineQueueDb();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<SessionStore>.value(value: sessionStore),
        Provider<OfflineQueueDb>.value(value: queueDb),
        Provider<LocationService>(create: (_) => LocationService(queueDb)),
      ],
      child: const EcoApp(),
    ),
  );
}

class EcoApp extends StatelessWidget {
  const EcoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'e-CO',
      theme: ecoTheme(),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
