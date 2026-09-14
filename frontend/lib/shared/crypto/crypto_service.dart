// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:hashlib/src/algorithms/argon2/argon2_32bit.dart'
    as hashlib_legacy_web_argon2;
import 'package:hashlib/src/algorithms/argon2/common.dart'
    as hashlib_argon2_common;
import 'package:uuid/uuid.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';

class CryptoService {
  static const passwordKdfAlgorithm = 'pbkdf2-sha256';
  static const passwordKdfParams = <String, Object>{
    'bits': 256,
    'iterations': 210000,
  };

  CryptoService({
    AesGcm? aead,
    Pbkdf2? legacyPbkdf2,
    X25519? x25519,
    Ed25519? ed25519,
  })  : _aead = aead ?? AesGcm.with256bits(),
        _legacyPbkdf2 = legacyPbkdf2 ??
            Pbkdf2(
              macAlgorithm: Hmac.sha256(),
              iterations: 210000,
              bits: 256,
            ),
        _x25519 = x25519 ?? X25519(),
        _ed25519 = ed25519 ?? Ed25519();

  final AesGcm _aead;
  final Pbkdf2 _legacyPbkdf2;
  final X25519 _x25519;
  final Ed25519 _ed25519;
  final _uuid = const Uuid();
  final _random = Random.secure();

  List<int> randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }

  String base64UrlNoPad(List<int> bytes) {
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  List<int> decodeBase64UrlNoPad(String value) {
    final padding = '=' * ((4 - value.length % 4) % 4);
    return base64Url.decode('$value$padding');
  }

  Future<List<int>> derivePasswordKey(
    String password,
    List<int> salt, {
    String algorithm = passwordKdfAlgorithm,
    Map<String, dynamic>? params,
  }) async {
    if (algorithm == 'argon2id') {
      return _deriveArgon2idPasswordKey(password, salt, params);
    }
    if (algorithm == 'pbkdf2-sha256') {
      return _deriveLegacyPbkdf2PasswordKey(password, salt, params);
    }
    throw UnsupportedError('Unsupported password KDF: $algorithm');
  }

  /// Derives a purpose-specific key that can wrap the device-local vault key.
  /// The account scope prevents a wrapper copied between accounts or tenants
  /// from being useful, while HKDF keeps the master key out of local storage.
  Future<List<int>> deriveLocalVaultRecoveryKey({
    required List<int> masterKey,
    required String accountScope,
  }) async {
    final derived = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    ).deriveKey(
      secretKey: SecretKey(masterKey),
      nonce: utf8.encode('safernotes-local-vault-recovery-v1'),
      info: utf8.encode(accountScope),
    );
    return derived.extractBytes();
  }

  List<int> _deriveArgon2idPasswordKey(
    String password,
    List<int> salt,
    Map<String, dynamic>? params,
  ) {
    final merged = {...passwordKdfParams, ...?params};
    final bits = (merged['bits'] as num?)?.toInt() ?? 256;
    final version = (merged['version'] as num?)?.toInt() ?? 19;
    final argon2 = hashlib.Argon2(
      type: hashlib.Argon2Type.argon2id,
      version:
          version == 16 ? hashlib.Argon2Version.v10 : hashlib.Argon2Version.v13,
      hashLength: bits ~/ 8,
      salt: salt,
      iterations: (merged['iterations'] as num?)?.toInt() ?? 3,
      memorySizeKB: (merged['memory'] as num?)?.toInt() ?? 65536,
      parallelism: (merged['parallelism'] as num?)?.toInt() ?? 1,
    );
    return argon2.convert(utf8.encode(password)).bytes;
  }

  List<int> _deriveLegacyWebArgon2idPasswordKey(
    String password,
    List<int> salt,
    Map<String, dynamic>? params,
  ) {
    final merged = {
      'version': 19,
      'memory': 8192,
      'iterations': 2,
      'parallelism': 1,
      'bits': 256,
      ...?params,
    };
    final bits = (merged['bits'] as num?)?.toInt() ?? 256;
    final version = (merged['version'] as num?)?.toInt() ?? 19;
    final context = hashlib_argon2_common.Argon2Context(
      type: hashlib_argon2_common.Argon2Type.argon2id,
      version: version == 16
          ? hashlib_argon2_common.Argon2Version.v10
          : hashlib_argon2_common.Argon2Version.v13,
      hashLength: bits ~/ 8,
      salt: salt,
      iterations: (merged['iterations'] as num?)?.toInt() ?? 2,
      memorySizeKB: (merged['memory'] as num?)?.toInt() ?? 8192,
      parallelism: (merged['parallelism'] as num?)?.toInt() ?? 1,
    );
    return hashlib_legacy_web_argon2.Argon2Internal(context)
        .convert(utf8.encode(password));
  }

  Future<List<int>> _deriveLegacyPbkdf2PasswordKey(
    String password,
    List<int> salt,
    Map<String, dynamic>? params,
  ) async {
    final iterations = (params?['iterations'] as num?)?.toInt();
    final bits = (params?['bits'] as num?)?.toInt();
    final kdf = iterations == null && bits == null
        ? _legacyPbkdf2
        : Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: iterations ?? 210000,
            bits: bits ?? 256,
          );
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }

  Future<EncryptedEnvelope> encryptString(
      String plaintext, List<int> key) async {
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(key),
      nonce: nonce,
    );
    return EncryptedEnvelope(
      version: 1,
      algorithm: 'AES_256_GCM',
      nonce: base64UrlNoPad(nonce),
      ciphertext: base64UrlNoPad([
        ...box.cipherText,
        ...box.mac.bytes,
      ]),
      keyId: _uuid.v4(),
    );
  }

  Future<String> decryptString(
      EncryptedEnvelope envelope, List<int> key) async {
    final combined = decodeBase64UrlNoPad(envelope.ciphertext);
    final macStart = combined.length - 16;
    final box = SecretBox(
      combined.sublist(0, macStart),
      nonce: decodeBase64UrlNoPad(envelope.nonce),
      mac: Mac(combined.sublist(macStart)),
    );
    final clear = await _aead.decrypt(box, secretKey: SecretKey(key));
    return utf8.decode(clear);
  }

  Future<String> sha256Text(String value) async {
    final hash = await Sha256().hash(utf8.encode(value));
    return base64UrlNoPad(hash.bytes);
  }

  Future<List<int>> decryptPrivateEncryptionKey({
    required EncryptedEnvelope encryptedPrivateKey,
    required List<int> masterKey,
  }) async {
    final encoded = await decryptString(encryptedPrivateKey, masterKey);
    return decodeBase64UrlNoPad(encoded);
  }

  Future<EncryptedEnvelope> wrapNoteKey({
    required List<int> noteKey,
    required String recipientPublicKey,
  }) async {
    final ephemeralPair = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeralPair.extractPublicKey();
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralPair,
      remotePublicKey: SimplePublicKey(
        decodeBase64UrlNoPad(recipientPublicKey),
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await _sharingKey(sharedSecret);
    final wrapped = await encryptString(base64UrlNoPad(noteKey), wrappingKey);
    return EncryptedEnvelope(
      version: wrapped.version,
      algorithm: 'X25519_AES_256_GCM',
      nonce: wrapped.nonce,
      ciphertext: wrapped.ciphertext,
      keyId: base64UrlNoPad(ephemeralPublic.bytes),
    );
  }

  Future<List<int>> unwrapNoteKey({
    required EncryptedEnvelope envelope,
    required String privateEncryptionKey,
    required String publicEncryptionKey,
  }) async {
    if (envelope.keyId == null || envelope.keyId!.isEmpty) {
      throw const FormatException('Missing ephemeral sharing key.');
    }
    final keyPair = SimpleKeyPairData(
      decodeBase64UrlNoPad(privateEncryptionKey),
      publicKey: SimplePublicKey(
        decodeBase64UrlNoPad(publicEncryptionKey),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: SimplePublicKey(
        decodeBase64UrlNoPad(envelope.keyId!),
        type: KeyPairType.x25519,
      ),
    );
    final encoded =
        await decryptString(envelope, await _sharingKey(sharedSecret));
    return decodeBase64UrlNoPad(encoded);
  }

  Future<List<int>> _sharingKey(SecretKey sharedSecret) async {
    final sharedBytes = await sharedSecret.extractBytes();
    final digest = await Sha256().hash([
      ...utf8.encode('safernotes-note-share-v1:'),
      ...sharedBytes,
    ]);
    return digest.bytes;
  }

  Future<RegistrationKeyMaterial> createRegistrationMaterial({
    required String password,
    required String deviceName,
    required String tenantName,
  }) async {
    final masterKey = randomBytes(32);
    final passwordSalt = randomBytes(16);
    const kdfParams = passwordKdfParams;
    final passwordKey = await derivePasswordKey(
      password,
      passwordSalt,
      params: kdfParams,
    );
    final recovery = await createRecoveryKey(masterKey: masterKey);
    final encryptionPair = await _x25519.newKeyPair();
    final signingPair = await _ed25519.newKeyPair();
    final encryptionPublic = await encryptionPair.extractPublicKey();
    final signingPublic = await signingPair.extractPublicKey();
    final encryptionPrivate = await encryptionPair.extractPrivateKeyBytes();
    final signingPrivate = await signingPair.extractPrivateKeyBytes();

    final publicEncryptionKey = base64UrlNoPad(encryptionPublic.bytes);
    final publicSigningKey = base64UrlNoPad(signingPublic.bytes);

    return RegistrationKeyMaterial(
      masterKey: masterKey,
      recoveryKey: recovery.recoveryKey,
      kdfAlgorithm: passwordKdfAlgorithm,
      kdfParams: kdfParams,
      passwordSalt: base64UrlNoPad(passwordSalt),
      publicEncryptionKey: publicEncryptionKey,
      publicSigningKey: publicSigningKey,
      publicEncryptionKeyFingerprint: await sha256Text(publicEncryptionKey),
      publicSigningKeyFingerprint: await sha256Text(publicSigningKey),
      encryptedMasterKey:
          await encryptString(base64UrlNoPad(masterKey), passwordKey),
      encryptedPrivateEncryptionKey: await encryptString(
        base64UrlNoPad(encryptionPrivate),
        masterKey,
      ),
      encryptedPrivateSigningKey: await encryptString(
        base64UrlNoPad(signingPrivate),
        masterKey,
      ),
      recoveryWrapper: recovery.recoveryWrapper,
      deviceNameCiphertext: await encryptString(deviceName, masterKey),
      defaultTenantNameCiphertext: await encryptString(tenantName, masterKey),
    );
  }

  Future<({String recoveryKey, EncryptedEnvelope recoveryWrapper})>
      createRecoveryKey({required List<int> masterKey}) async {
    final recoveryKeyBytes = randomBytes(32);
    return (
      recoveryKey: base64UrlNoPad(recoveryKeyBytes),
      recoveryWrapper: await encryptString(
        base64UrlNoPad(masterKey),
        recoveryKeyBytes,
      ),
    );
  }

  Future<List<int>> unlockMasterKey({
    required String password,
    required String passwordSalt,
    required String kdfAlgorithm,
    required Map<String, dynamic> kdfParams,
    required EncryptedEnvelope encryptedMasterKey,
  }) async {
    final passwordKey = await derivePasswordKey(
      password,
      decodeBase64UrlNoPad(passwordSalt),
      algorithm: kdfAlgorithm,
      params: kdfParams,
    );
    try {
      final encodedMaster =
          await decryptString(encryptedMasterKey, passwordKey);
      return decodeBase64UrlNoPad(encodedMaster);
    } on SecretBoxAuthenticationError {
      if (kdfAlgorithm != 'argon2id') rethrow;
      final legacyWebPasswordKey = _deriveLegacyWebArgon2idPasswordKey(
        password,
        decodeBase64UrlNoPad(passwordSalt),
        kdfParams,
      );
      final encodedMaster =
          await decryptString(encryptedMasterKey, legacyWebPasswordKey);
      return decodeBase64UrlNoPad(encodedMaster);
    }
  }

  Future<List<int>> unlockMasterKeyWithRecovery({
    required String recoveryKey,
    required EncryptedEnvelope recoveryWrapper,
  }) async {
    final encodedMaster = await decryptString(
      recoveryWrapper,
      decodeBase64UrlNoPad(recoveryKey.trim()),
    );
    return decodeBase64UrlNoPad(encodedMaster);
  }

  Future<PasswordWrappedMasterKey> wrapMasterKeyWithPassword({
    required List<int> masterKey,
    required String password,
  }) async {
    final passwordSalt = randomBytes(16);
    const kdfParams = passwordKdfParams;
    final passwordKey = await derivePasswordKey(
      password,
      passwordSalt,
      params: kdfParams,
    );
    return PasswordWrappedMasterKey(
      kdfAlgorithm: passwordKdfAlgorithm,
      kdfParams: kdfParams,
      passwordSalt: base64UrlNoPad(passwordSalt),
      encryptedMasterKey: await encryptString(
        base64UrlNoPad(masterKey),
        passwordKey,
      ),
    );
  }

  Future<EncryptedEnvelope> encryptNotePayload({
    required PlainNote note,
    required List<int> masterKey,
  }) {
    return encryptString(jsonEncode(note.encryptedPayloadJson()), masterKey);
  }
}
