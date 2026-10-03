/// The course code a link carries: `/eco-app/?code=7GX4K2`, the address the QR code of a course's
/// poster holds (moncampus, « Affiche QR » on the course list). Only the web build is opened by an
/// address, so only it is ever handed one; the phone app reads none.
///
/// Anything that is not six letters or digits once tidied (spaces and case forgiven) is no code:
/// the join screen then starts empty, as it would have without the link.
String? joinCodeFromUri(Uri uri) {
  final raw = uri.queryParameters['code'];
  if (raw == null) return null;

  final code = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();

  return RegExp(r'^[A-Z0-9]{6}$').hasMatch(code) ? code : null;
}
