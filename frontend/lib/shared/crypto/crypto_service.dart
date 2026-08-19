import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:hashlib/hashlib.dart' as hashlib;
import 'package:uuid/uuid.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';

class CryptoService {
  static const passwordKdfAlgorithm = 'argon2id';
  static const passwordKdfParams = <String, Object>{
    'version': 19,
    'memory': 65536,
    'iterations': 3,
    'parallelism': 1,
    'bits': 256,
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

  Future<RegistrationKeyMaterial> createRegistrationMaterial({
    required String password,
    required String deviceName,
    required String tenantName,
  }) async {
    final masterKey = randomBytes(32);
    final passwordSalt = randomBytes(16);
    final passwordKey = await derivePasswordKey(password, passwordSalt);
    final recoveryKeyBytes = randomBytes(32);
    final recoveryKey = base64UrlNoPad(recoveryKeyBytes);
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
      recoveryKey: recoveryKey,
      kdfAlgorithm: passwordKdfAlgorithm,
      kdfParams: passwordKdfParams,
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
      recoveryWrapper: await encryptString(
        base64UrlNoPad(masterKey),
        recoveryKeyBytes,
      ),
      deviceNameCiphertext: await encryptString(deviceName, masterKey),
      defaultTenantNameCiphertext: await encryptString(tenantName, masterKey),
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
    final encodedMaster = await decryptString(encryptedMasterKey, passwordKey);
    return decodeBase64UrlNoPad(encodedMaster);
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
    final passwordKey = await derivePasswordKey(password, passwordSalt);
    return PasswordWrappedMasterKey(
      kdfAlgorithm: passwordKdfAlgorithm,
      kdfParams: passwordKdfParams,
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
