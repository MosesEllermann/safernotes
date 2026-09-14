import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
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
    expect(
      invitationIdFromUri(
        Uri.parse(
          'https://attacker.example/?invitation=123e4567-e89b-42d3-a456-426614174000',
        ),
      ),
      isNull,
    );
  });

  test('normalizes repeated Android app links without exposing note data', () {
    final uri = Uri.parse(
      'http://app.safernotes.com/?invitation=123E4567-E89B-42D3-A456-426614174000',
    );

    for (var index = 0; index < 1000; index += 1) {
      expect(
        invitationIdFromUri(uri),
        '123e4567-e89b-42d3-a456-426614174000',
      );
    }
  });

  test('retries delayed shared-note visibility under a concurrent burst',
      () async {
    final attemptCounts = List<int>.filled(100, 0);

    await Future.wait([
      for (var index = 0; index < attemptCounts.length; index += 1)
        retrySharedNoteImport(
          () async {
            attemptCounts[index] += 1;
            if (attemptCounts[index] < 3) {
              throw StateError('grant has not propagated yet');
            }
          },
          retryDelays: const [Duration.zero, Duration.zero],
          wait: (_) async {},
        ),
    ]);

    expect(attemptCounts, everyElement(3));
  });

  test('surfaces a persistent shared-note import failure after bounded retries',
      () async {
    var attempts = 0;

    await expectLater(
      retrySharedNoteImport(
        () async {
          attempts += 1;
          throw StateError('invalid encrypted grant');
        },
        retryDelays: const [Duration.zero, Duration.zero],
        wait: (_) async {},
      ),
      throwsStateError,
    );
    expect(attempts, 3);
  });

  test('retries lost invitation responses but not permanent rejection',
      () async {
    var attempts = 0;
    final result = await retryInvitationDecision(
      () async {
        attempts += 1;
        if (attempts < 3) throw ApiException('response lost', 0);
        return 'accepted';
      },
      retryDelays: const [Duration.zero, Duration.zero],
      wait: (_) async {},
    );
    expect(result, 'accepted');
    expect(attempts, 3);

    attempts = 0;
    await expectLater(
      retryInvitationDecision<void>(
        () async {
          attempts += 1;
          throw ApiException('wrong account', 404);
        },
        wait: (_) async {},
      ),
      throwsA(isA<ApiException>()),
    );
    expect(attempts, 1);
  });
}
