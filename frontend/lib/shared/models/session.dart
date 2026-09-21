import 'package:safernotes_app/shared/models/encrypted_envelope.dart';

enum AppSessionMode { server, offline }

class AppSession {
  const AppSession({
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.defaultTenant,
    required this.masterKey,
    this.userId = '',
    this.publicEncryptionKey = '',
    this.privateEncryptionKey = '',
    this.emailVerified = true,
    this.mode = AppSessionMode.server,
  });

  final String email;
  final String accessToken;
  final String refreshToken;
  final String defaultTenant;
  final List<int> masterKey;
  final String userId;
  final String publicEncryptionKey;
  final String privateEncryptionKey;
  final bool emailVerified;
  final AppSessionMode mode;

  bool get isOfflineOnly => mode == AppSessionMode.offline;

  Map<String, dynamic> toJson() => {
        'email': email,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'defaultTenant': defaultTenant,
        'masterKey': masterKey,
        'userId': userId,
        'publicEncryptionKey': publicEncryptionKey,
        'privateEncryptionKey': privateEncryptionKey,
        'emailVerified': emailVerified,
        'mode': mode.name,
      };

  AppSession copyWith({
    String? email,
    String? accessToken,
    String? refreshToken,
    String? defaultTenant,
    List<int>? masterKey,
    String? userId,
    String? publicEncryptionKey,
    String? privateEncryptionKey,
    bool? emailVerified,
    AppSessionMode? mode,
  }) {
    return AppSession(
      email: email ?? this.email,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      defaultTenant: defaultTenant ?? this.defaultTenant,
      masterKey: masterKey ?? this.masterKey,
      userId: userId ?? this.userId,
      publicEncryptionKey: publicEncryptionKey ?? this.publicEncryptionKey,
      privateEncryptionKey: privateEncryptionKey ?? this.privateEncryptionKey,
      emailVerified: emailVerified ?? this.emailVerified,
      mode: mode ?? this.mode,
    );
  }
}

class RegistrationKeyMaterial {
  const RegistrationKeyMaterial({
    required this.masterKey,
    required this.recoveryKey,
    required this.kdfAlgorithm,
    required this.kdfParams,
    required this.passwordSalt,
    required this.publicEncryptionKey,
    required this.publicSigningKey,
    required this.publicEncryptionKeyFingerprint,
    required this.publicSigningKeyFingerprint,
    required this.encryptedMasterKey,
    required this.encryptedPrivateEncryptionKey,
    required this.encryptedPrivateSigningKey,
    required this.recoveryWrapper,
    required this.deviceNameCiphertext,
    required this.defaultTenantNameCiphertext,
  });

  final List<int> masterKey;
  final String recoveryKey;
  final String kdfAlgorithm;
  final Map<String, Object> kdfParams;
  final String passwordSalt;
  final String publicEncryptionKey;
  final String publicSigningKey;
  final String publicEncryptionKeyFingerprint;
  final String publicSigningKeyFingerprint;
  final EncryptedEnvelope encryptedMasterKey;
  final EncryptedEnvelope encryptedPrivateEncryptionKey;
  final EncryptedEnvelope encryptedPrivateSigningKey;
  final EncryptedEnvelope recoveryWrapper;
  final EncryptedEnvelope deviceNameCiphertext;
  final EncryptedEnvelope defaultTenantNameCiphertext;
}

class PasswordWrappedMasterKey {
  const PasswordWrappedMasterKey({
    required this.kdfAlgorithm,
    required this.kdfParams,
    required this.passwordSalt,
    required this.encryptedMasterKey,
  });

  final String kdfAlgorithm;
  final Map<String, Object> kdfParams;
  final String passwordSalt;
  final EncryptedEnvelope encryptedMasterKey;
}
