import 'package:zknotes_app/shared/models/encrypted_envelope.dart';

class AppSession {
  const AppSession({
    required this.email,
    required this.accessToken,
    required this.refreshToken,
    required this.defaultTenant,
    required this.masterKey,
  });

  final String email;
  final String accessToken;
  final String refreshToken;
  final String defaultTenant;
  final List<int> masterKey;

  Map<String, dynamic> toJson() => {
        'email': email,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'defaultTenant': defaultTenant,
        'masterKey': masterKey,
      };
}

class RegistrationKeyMaterial {
  const RegistrationKeyMaterial({
    required this.masterKey,
    required this.recoveryKey,
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
    required this.passwordSalt,
    required this.encryptedMasterKey,
  });

  final String passwordSalt;
  final EncryptedEnvelope encryptedMasterKey;
}
