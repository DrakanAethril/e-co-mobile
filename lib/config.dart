// The Android emulator's loopback alias to the host machine - moncampus runs on the host's
// localhost:80 (FrankenPHP dev container, see compose.override.yaml in the moncampus repo).
// A real device on the same network would need the host's LAN IP instead.
const String apiBaseUrl = 'http://10.0.2.2';
