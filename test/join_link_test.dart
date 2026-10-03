import 'package:eco/services/join_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// The poster's QR code opens the PWA at /eco-app/?code=… - the join screen starts with that code.
void main() {
  test('the code of the link is read, tidied', () {
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/?code=7GX4K2')), '7GX4K2');
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/?code=7gx4k2')), '7GX4K2');
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/?code=7GX%204K2')), '7GX4K2');
  });

  test('no code, or something that is not one, starts the join screen empty', () {
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/')), isNull);
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/?code=')), isNull);
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/?code=7GX4K')), isNull);
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/?code=7GX4K2X')), isNull);
    expect(joinCodeFromUri(Uri.parse('https://campus.example/eco-app/?code=<b>abc</b>')), isNull);
  });
}
