import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

/// Base URL resolution for the moncampus e-CO API - mirrors moncampus-mobile's
/// lib/services/api_config.dart. Kept as a top-level getter (not a class) since this app has a
/// single config value rather than a growing config surface.
///
/// Production builds must pass the real domain at compile time:
///   flutter build apk --release --dart-define=API_BASE_URL=https://your-domain.tld
///
/// Without that flag, this falls back to the dev-only addresses (FrankenPHP dev server, plain
/// HTTP - see the moncampus repo's CLAUDE.md, automatic HTTPS is disabled entirely in dev). The
/// Android emulator runs in its own network namespace where "10.0.2.2" is its fixed alias for the
/// host loopback; a real device on dev instead needs the host's LAN IP - not handled here, pass
/// --dart-define=API_BASE_URL=http://<lan-ip> for that case too.
///
/// The PWA is served by moncampus itself (public/eco-app/), so in the browser the API is the
/// page's own origin - no flag, no CORS, and the same answer in dev and in production. Its
/// service worker (web/eco_sw.js) sends to that origin too, which is why a web build must never be
/// given API_BASE_URL.
const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

String get apiBaseUrl {
  if (_apiBaseUrlOverride.isNotEmpty) {
    return _apiBaseUrlOverride;
  }

  if (kIsWeb) {
    return Uri.base.origin;
  }

  if (Platform.isAndroid) {
    return 'http://10.0.2.2';
  }

  return 'http://localhost';
}
