// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashlib/src/algorithms/argon2/argon2_32bit.dart'
    as hashlib_legacy_web_argon2;
import 'package:hashlib/src/algorithms/argon2/common.dart'
    as hashlib_argon2_common;
import 'package:safernotes_app/shared/crypto/crypto_service.dart';

void main() {
  test('new password material unlocks with PBKDF2', () async {
    final crypto = CryptoService();
    final material = await crypto.createRegistrationMaterial(
      password: 'correct horse battery staple',
      deviceName: 'Test device',
      tenantName: 'Test vault',
    );

    expect(material.kdfAlgorithm, 'pbkdf2-sha256');

    final unlocked = await crypto.unlockMasterKey(
      password: 'correct horse battery staple',
      passwordSalt: material.passwordSalt,
      kdfAlgorithm: material.kdfAlgorithm,
      kdfParams: Map<String, dynamic>.from(material.kdfParams),
      encryptedMasterKey: material.encryptedMasterKey,
    );

    expect(unlocked, material.masterKey);
  });

  test('local vault recovery keys are deterministic and account scoped',
      () async {
    final crypto = CryptoService();
    final masterKey = List<int>.generate(32, (index) => index);

    final first = await crypto.deriveLocalVaultRecoveryKey(
      masterKey: masterKey,
      accountScope: 'owner@example.test:personal',
    );
    final repeated = await crypto.deriveLocalVaultRecoveryKey(
      masterKey: masterKey,
      accountScope: 'owner@example.test:personal',
    );
    final otherTenant = await crypto.deriveLocalVaultRecoveryKey(
      masterKey: masterKey,
      accountScope: 'owner@example.test:work',
    );

    expect(first, repeated);
    expect(first, hasLength(32));
    expect(first, isNot(otherTenant));
    expect(first, isNot(masterKey));
  });

  test('recovery-key rotation wraps the same master key with a new local key',
      () async {
    final crypto = CryptoService();
    final masterKey = crypto.randomBytes(32);

    final first = await crypto.createRecoveryKey(masterKey: masterKey);
    final second = await crypto.createRecoveryKey(masterKey: masterKey);

    expect(first.recoveryKey, isNot(second.recoveryKey));
    expect(first.recoveryWrapper.ciphertext,
        isNot(second.recoveryWrapper.ciphertext));
    expect(
      await crypto.unlockMasterKeyWithRecovery(
        recoveryKey: second.recoveryKey,
        recoveryWrapper: second.recoveryWrapper,
      ),
      masterKey,
    );
    await expectLater(
      crypto.unlockMasterKeyWithRecovery(
        recoveryKey: first.recoveryKey,
        recoveryWrapper: second.recoveryWrapper,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('existing native Argon2 material still unlocks', () async {
    final crypto = CryptoService();
    final password = 'correct horse battery staple';
    final masterKey = crypto.randomBytes(32);
    final salt = crypto.randomBytes(16);
    final params = {
      'version': 19,
      'memory': 8192,
      'iterations': 2,
      'parallelism': 1,
      'bits': 256,
    };
    final passwordKey = await crypto.derivePasswordKey(
      password,
      salt,
      algorithm: 'argon2id',
      params: params,
    );
    final encryptedMasterKey = await crypto.encryptString(
      crypto.base64UrlNoPad(masterKey),
      passwordKey,
    );

    final unlocked = await crypto.unlockMasterKey(
      password: password,
      passwordSalt: crypto.base64UrlNoPad(salt),
      kdfAlgorithm: 'argon2id',
      kdfParams: params,
      encryptedMasterKey: encryptedMasterKey,
    );

    expect(unlocked, masterKey);
  });

  test('existing web Argon2 material unlocks through compatibility fallback',
      () async {
    final crypto = CryptoService();
    final password = 'correct horse battery staple';
    final masterKey = crypto.randomBytes(32);
    final salt = crypto.randomBytes(16);
    final params = {
      'version': 19,
      'memory': 8192,
      'iterations': 2,
      'parallelism': 1,
      'bits': 256,
    };
    final context = hashlib_argon2_common.Argon2Context(
      type: hashlib_argon2_common.Argon2Type.argon2id,
      version: hashlib_argon2_common.Argon2Version.v13,
      hashLength: 32,
      salt: salt,
      iterations: 2,
      memorySizeKB: 8192,
      parallelism: 1,
    );
    final legacyWebPasswordKey =
        hashlib_legacy_web_argon2.Argon2Internal(context)
            .convert(utf8.encode(password));
    final encryptedMasterKey = await crypto.encryptString(
      crypto.base64UrlNoPad(masterKey),
      legacyWebPasswordKey,
    );

    final unlocked = await crypto.unlockMasterKey(
      password: password,
      passwordSalt: crypto.base64UrlNoPad(salt),
      kdfAlgorithm: 'argon2id',
      kdfParams: params,
      encryptedMasterKey: encryptedMasterKey,
    );

    expect(unlocked, masterKey);
  });

  test('note keys can be wrapped for and unwrapped by a recipient', () async {
    final crypto = CryptoService();
    final recipient = await crypto.createRegistrationMaterial(
      password: 'recipient-password',
      deviceName: 'Recipient device',
      tenantName: 'Recipient vault',
    );
    final privateKey = await crypto.decryptPrivateEncryptionKey(
      encryptedPrivateKey: recipient.encryptedPrivateEncryptionKey,
      masterKey: recipient.masterKey,
    );
    final noteKey = crypto.randomBytes(32);

    final wrapped = await crypto.wrapNoteKey(
      noteKey: noteKey,
      recipientPublicKey: recipient.publicEncryptionKey,
    );
    final unwrapped = await crypto.unwrapNoteKey(
      envelope: wrapped,
      privateEncryptionKey: crypto.base64UrlNoPad(privateKey),
      publicEncryptionKey: recipient.publicEncryptionKey,
    );

    expect(wrapped.algorithm, 'X25519_AES_256_GCM');
    expect(unwrapped, noteKey);
  });
}
