import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zknotes_app/shared/models/encrypted_envelope.dart';
import 'package:zknotes_app/shared/models/session.dart';
import 'package:zknotes_app/shared/providers.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AppSession?>(
  AuthController.new,
);

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
    );
  }

  Future<void> register({
    required String email,
    required String password,
    required String workspaceName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final crypto = ref.read(cryptoServiceProvider);
      final material = await crypto.createRegistrationMaterial(
        password: password,
        deviceName: 'Primary device',
        tenantName: workspaceName,
      );
      final response = await ref.read(apiClientProvider).register(
            email: email,
            password: password,
            material: material,
          );
      final session = AppSession(
        email: response['email'] as String? ?? email,
        accessToken: response['access_token'] as String,
        refreshToken: response['refresh_token'] as String,
        defaultTenant: response['default_tenant'] as String,
        masterKey: material.masterKey,
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
      );
      await ref.read(offlineStoreProvider).saveSessionJson(session.toJson());
      return session;
    });
  }

  Future<void> signOut() async {
    await ref.read(offlineStoreProvider).clear();
    state = const AsyncData(null);
  }
}
