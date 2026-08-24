import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/main.dart';

void main() {
  test('reads a valid invitation UUID from a public app URL', () {
    final uri = Uri.parse(
      'https://app.safernotes.com/?invitation=123e4567-e89b-42d3-a456-426614174000',
    );

    expect(
      invitationIdFromUri(uri),
      '123e4567-e89b-42d3-a456-426614174000',
    );
  });

  test('rejects malformed invitation identifiers and ignores other data', () {
    expect(
      invitationIdFromUri(
        Uri.parse('https://app.safernotes.com/?invitation=secret-token'),
      ),
      isNull,
    );
    expect(
      invitationIdFromUri(
        Uri.parse('https://app.safernotes.com/?note=plaintext'),
      ),
      isNull,
    );
  });
}
