import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/providers.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AppSession?>(
  AuthController.new,
);

class RecoveryChallenge {
  const RecoveryChallenge({
    required this.recoveryWrapper,
  });

  final EncryptedEnvelope recoveryWrapper;
}

class AuthController extends AsyncNotifier<AppSession?> {
  @override
  Future<AppSession?> build() async {
    final saved = await ref.watch(offlineStoreProvider).loadSessionJson();
    if (saved == null) return null;
    return AppSession(
      email: saved['email'] as String,
      accessToken: saved['accessToken'] as String,
      refreshToken: saved['refreshToken'] as String,
      defaultTenant: saved['defaultTenant'] as String,
      masterKey: (saved['masterKey'] as List).cast<int>(),
      emailVerified: saved['emailVerified'] as bool? ?? true,
    );
  }

  Future<RegistrationKeyMaterial> prepareRegistration({
    required String password,
    required String workspaceName,
  }) {
    return ref.read(cryptoServiceProvider).createRegistrationMaterial(
          password: password,
          deviceName: 'Primary device',
          tenantName: workspaceName,
        );
  }

  Future<void> completeRegistration({
    required String email,
    required String password,
    required String locale,
    required RegistrationKeyMaterial material,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await ref.read(apiClientProvider).register(
            email: email,
            password: password,
            material: material,
            locale: locale,
          );
      final session = AppSession(
        email: response['email'] as String? ?? email,
        accessToken: response['access_token'] as String,
        refreshToken: response['refresh_token'] as String,
        defaultTenant: response['default_tenant'] as String,
        masterKey: material.masterKey,
        emailVerified: response['email_verified'] as bool? ?? false,
      );
      await ref.read(offlineStoreProvider).saveSessionJson(session.toJson());
      return session;
    });
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await ref.read(apiClientProvider).login(
            email: email,
            password: password,
          );
      final keyMaterial =
          Map<String, dynamic>.from(response['key_material'] as Map);
      final masterKey = await ref.read(cryptoServiceProvider).unlockMasterKey(
            password: password,
            passwordSalt: keyMaterial['password_salt'] as String,
            kdfAlgorithm:
                keyMaterial['kdf_algorithm'] as String? ?? 'pbkdf2-sha256',
            kdfParams: Map<String, dynamic>.from(
              (keyMaterial['kdf_params'] as Map?) ?? const {},
            ),
            encryptedMasterKey: EncryptedEnvelope.fromJson(
              Map<String, dynamic>.from(
                  keyMaterial['encrypted_master_key'] as Map),
            ),
          );
      final session = AppSession(
        email: response['email'] as String? ?? email,
        accessToken: response['access_token'] as String,
        refreshToken: response['refresh_token'] as String,
        defaultTenant: response['default_tenant'] as String,
        masterKey: masterKey,
        emailVerified: response['email_verified'] as bool? ?? true,
      );
      await ref.read(offlineStoreProvider).saveSessionJson(session.toJson());
      return session;
    });
  }

  Future<RecoveryChallenge?> startPasswordRecovery({
    required String email,
  }) async {
    final response = await ref.read(apiClientProvider).startPasswordRecovery(
          email: email,
        );
    if (response['recovery_available'] != true) return null;
    return RecoveryChallenge(
      recoveryWrapper: EncryptedEnvelope.fromJson(
        Map<String, dynamic>.from(response['recovery_wrapper'] as Map),
      ),
    );
  }

  Future<void> completePasswordRecovery({
    required String email,
    required String code,
    required String recoveryKey,
    required String newPassword,
    required EncryptedEnvelope recoveryWrapper,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final crypto = ref.read(cryptoServiceProvider);
      final masterKey = await crypto.unlockMasterKeyWithRecovery(
        recoveryKey: recoveryKey,
        recoveryWrapper: recoveryWrapper,
      );
      final wrappedMasterKey = await crypto.wrapMasterKeyWithPassword(
        masterKey: masterKey,
        password: newPassword,
      );
      final response =
          await ref.read(apiClientProvider).completePasswordRecovery(
                email: email,
                code: code,
                password: newPassword,
                wrappedMasterKey: wrappedMasterKey,
              );
      final session = AppSession(
        email: response['email'] as String? ?? email,
        accessToken: response['access_token'] as String,
        refreshToken: response['refresh_token'] as String,
        defaultTenant: response['default_tenant'] as String? ?? '',
        masterKey: masterKey,
        emailVerified: response['email_verified'] as bool? ?? true,
      );
      await ref.read(offlineStoreProvider).saveSessionJson(session.toJson());
      return session;
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final session = state.valueOrNull;
    if (session == null) {
      throw Exception('Not signed in.');
    }
    final wrappedMasterKey =
        await ref.read(cryptoServiceProvider).wrapMasterKeyWithPassword(
              masterKey: session.masterKey,
              password: newPassword,
            );
    await ref.read(apiClientProvider).changePassword(
          accessToken: session.accessToken,
          currentPassword: currentPassword,
          newPassword: newPassword,
          wrappedMasterKey: wrappedMasterKey,
        );
  }

  Future<void> resendEmailVerification() async {
    final session = state.valueOrNull;
    if (session == null) throw Exception('Not signed in.');
    final response = await ref.read(apiClientProvider).resendEmailVerification(
          accessToken: session.accessToken,
        );
    final next = session.copyWith(
      emailVerified: response['email_verified'] as bool? ?? false,
    );
    await ref.read(offlineStoreProvider).saveSessionJson(next.toJson());
    state = AsyncData(next);
  }

  Future<bool> refreshEmailVerificationStatus() async {
    final session = state.valueOrNull;
    if (session == null) return false;
    if (session.emailVerified) return true;
    final response =
        await ref.read(apiClientProvider).fetchEmailVerificationStatus(
              accessToken: session.accessToken,
            );
    final verified = response['email_verified'] == true;
    if (!verified) return false;
    final next = session.copyWith(emailVerified: true);
    await ref.read(offlineStoreProvider).saveSessionJson(next.toJson());
    state = AsyncData(next);
    return true;
  }

  Future<void> confirmEmailVerification(String code) async {
    final session = state.valueOrNull;
    if (session == null) throw Exception('Not signed in.');
    final response = await ref.read(apiClientProvider).confirmEmailVerification(
          accessToken: session.accessToken,
          code: code,
        );
    final next = session.copyWith(
      emailVerified: response['email_verified'] as bool? ?? true,
    );
    await ref.read(offlineStoreProvider).saveSessionJson(next.toJson());
    state = AsyncData(next);
  }

  Future<void> signOut() async {
    await ref.read(offlineStoreProvider).clear();
    state = const AsyncData(null);
  }
}
