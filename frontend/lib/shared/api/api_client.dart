import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);

  final String message;
  final int statusCode;

  @override
  String toString() => 'Error: $message';
}

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.baseUrl = 'https://api.safernotes.com',
    this.requestTimeout = const Duration(seconds: 5),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;
  final Duration requestTimeout;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required RegistrationKeyMaterial material,
    required String locale,
  }) {
    return _post('/api/v1/auth/register', {
      'email': email,
      'password': password,
      'locale': locale,
      'kdf_algorithm': material.kdfAlgorithm,
      'kdf_params': material.kdfParams,
      'password_salt': material.passwordSalt,
      'public_encryption_key': material.publicEncryptionKey,
      'public_signing_key': material.publicSigningKey,
      'public_encryption_key_fingerprint':
          material.publicEncryptionKeyFingerprint,
      'public_signing_key_fingerprint': material.publicSigningKeyFingerprint,
      'encrypted_master_key': material.encryptedMasterKey.toJson(),
      'encrypted_private_encryption_key':
          material.encryptedPrivateEncryptionKey.toJson(),
      'encrypted_private_signing_key':
          material.encryptedPrivateSigningKey.toJson(),
      'recovery_wrapper': material.recoveryWrapper.toJson(),
      'device_name_ciphertext': material.deviceNameCiphertext.toJson(),
      'device_public_signing_key': material.publicSigningKey,
      'default_tenant_name_ciphertext':
          material.defaultTenantNameCiphertext.toJson(),
    });
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) {
    return _post('/api/v1/auth/login', {
      'email': email,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> startPasswordRecovery({
    required String email,
  }) {
    return _post('/api/v1/auth/recovery/start', {
      'email': email,
    });
  }

  Future<Map<String, dynamic>> resendEmailVerification({
    required String accessToken,
  }) {
    return _post(
      '/api/v1/auth/email/verification/resend',
      {},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> fetchEmailVerificationStatus({
    required String accessToken,
  }) {
    return _get('/api/v1/auth/email/verification/status', accessToken);
  }

  Future<Map<String, dynamic>> confirmEmailVerification({
    required String accessToken,
    required String code,
  }) {
    return _post(
      '/api/v1/auth/email/verification/confirm',
      {'code': code},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> completePasswordRecovery({
    required String email,
    required String code,
    required String password,
    required PasswordWrappedMasterKey wrappedMasterKey,
  }) {
    return _post('/api/v1/auth/recovery/complete', {
      'email': email,
      'code': code,
      'password': password,
      'kdf_algorithm': wrappedMasterKey.kdfAlgorithm,
      'kdf_params': wrappedMasterKey.kdfParams,
      'password_salt': wrappedMasterKey.passwordSalt,
      'encrypted_master_key': wrappedMasterKey.encryptedMasterKey.toJson(),
    });
  }

  Future<Map<String, dynamic>> fetchRecoveryKeyStatus({
    required String accessToken,
  }) {
    return _get('/api/v1/auth/recovery-key', accessToken);
  }

  Future<Map<String, dynamic>> updateRecoveryKey({
    required String accessToken,
    required EncryptedEnvelope recoveryWrapper,
  }) {
    return _patch(
      '/api/v1/auth/recovery-key',
      {'recovery_wrapper': recoveryWrapper.toJson()},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> updatePreferences({
    required String accessToken,
    required String locale,
  }) {
    return _patch(
      '/api/v1/users/me/preferences',
      {'locale': locale},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> fetchMe(String accessToken) {
    return _get('/api/v1/users/me', accessToken);
  }

  Future<Map<String, dynamic>> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
    required PasswordWrappedMasterKey wrappedMasterKey,
  }) {
    return _post(
      '/api/v1/auth/password/change',
      {
        'current_password': currentPassword,
        'new_password': newPassword,
        'kdf_algorithm': wrappedMasterKey.kdfAlgorithm,
        'kdf_params': wrappedMasterKey.kdfParams,
        'password_salt': wrappedMasterKey.passwordSalt,
        'encrypted_master_key': wrappedMasterKey.encryptedMasterKey.toJson(),
      },
      accessToken: accessToken,
    );
  }

  Future<List<RemoteEncryptedNote>> fetchNotes(String accessToken) async {
    final json = await _get('/api/v1/notes/', accessToken);
    final results = json['results'] as List? ?? json as List;
    return results
        .map((item) => RemoteEncryptedNote.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<int> emptyTrash(String accessToken) async {
    final json = await _post(
      '/api/v1/notes/trash/empty/',
      const <String, dynamic>{},
      accessToken: accessToken,
    );
    return json['deleted_count'] as int? ?? 0;
  }

  Future<List<CollaboratorPresence>> fetchPresence(String accessToken) async {
    final json = await _get('/api/v1/collaboration/presence/', accessToken);
    final results = json['results'] as List? ?? json as List;
    return results
        .map((item) => CollaboratorPresence.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<ShareContact>> fetchShareContacts(String accessToken) async {
    final json = await _get('/api/v1/notes/invitations/contacts/', accessToken);
    final results = json['results'] as List? ?? json as List;
    return results
        .map((item) =>
            ShareContact.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<Map<String, dynamic>> fetchPublicKeys({
    required String accessToken,
    required String email,
  }) {
    final path = Uri(path: '/api/v1/users/public-keys', queryParameters: {
      'email': email,
    }).toString();
    return _get(path, accessToken);
  }

  Future<void> storeOwnerNoteKey({
    required String accessToken,
    required String noteId,
    required EncryptedEnvelope encryptedNoteKey,
    required String grantSignature,
  }) async {
    await _post(
      '/api/v1/notes/$noteId/sharing/key/',
      {
        'encrypted_note_key': encryptedNoteKey.toJson(),
        'grant_signature': grantSignature,
      },
      accessToken: accessToken,
    );
  }

  Future<List<ShareParticipant>> fetchNoteSharing({
    required String accessToken,
    required String noteId,
  }) async {
    final json = await _get('/api/v1/notes/$noteId/sharing/', accessToken);
    return (json['results'] as List? ?? const [])
        .map((item) =>
            ShareParticipant.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> removeShareAccess({
    required String accessToken,
    required ShareParticipant participant,
  }) async {
    final collection = participant.type == 'grant' ? 'grants' : 'invitations';
    await _delete('/api/v1/notes/$collection/${participant.id}/', accessToken);
  }

  Future<Map<String, dynamic>> createShareInvitation({
    required String accessToken,
    required String noteId,
    required String recipientUserId,
    required String role,
    required EncryptedEnvelope encryptedNoteKey,
    required String invitationSignature,
  }) {
    return _post(
      '/api/v1/notes/invitations/',
      {
        'note': noteId,
        'recipient_user': recipientUserId,
        'role': role,
        'encrypted_note_key': encryptedNoteKey.toJson(),
        'invitation_signature': invitationSignature,
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> fetchShareInvitation({
    required String accessToken,
    required String invitationId,
  }) {
    return _get(
      '/api/v1/notes/invitations/$invitationId/',
      accessToken,
    );
  }

  Future<Map<String, dynamic>> decideShareInvitation({
    required String accessToken,
    required String invitationId,
    required String decision,
  }) {
    return _post(
      '/api/v1/notes/invitations/$invitationId/decide/',
      {'decision': decision},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> syncBatch({
    required String accessToken,
    required List<Map<String, dynamic>> operations,
  }) {
    return _post(
      '/api/v1/notes/sync/batch',
      {'operations': operations},
      accessToken: accessToken,
    );
  }

  Future<SubscriptionInfo> fetchSubscription({
    required String accessToken,
    required String tenant,
  }) async {
    final response = await _request(
      () => _http.get(
        Uri.parse('$baseUrl/api/v1/subscription').replace(
          queryParameters: {'tenant': tenant},
        ),
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );
    return SubscriptionInfo.fromJson(_decode(response));
  }

  Future<SubscriptionUsage> fetchSubscriptionUsage({
    required String accessToken,
    required String tenant,
  }) async {
    final response = await _request(
      () => _http.get(
        Uri.parse('$baseUrl/api/v1/subscription/usage').replace(
          queryParameters: {'tenant': tenant},
        ),
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );
    return SubscriptionUsage.fromJson(_decode(response));
  }

  Future<CheckoutSession> createCheckout({
    required String accessToken,
    required String tenant,
    required String plan,
  }) async {
    final json = await _post(
      '/api/v1/subscription/checkout',
      {'tenant': tenant, 'plan': plan},
      accessToken: accessToken,
    );
    return CheckoutSession.fromJson(json);
  }

  Future<Map<String, dynamic>> _get(String path, String accessToken) async {
    final response = await _request(
      () => _http.get(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final response = await _request(
      () => _http.post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body, {
    required String accessToken,
  }) async {
    final response = await _request(
      () => _http.patch(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _delete(
    String path,
    String accessToken,
  ) async {
    final response = await _request(
      () => _http.delete(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
    );
    return _decode(response);
  }

  Future<http.Response> _request(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(requestTimeout);
    } on TimeoutException {
      throw ApiException('Server unreachable.', 0);
    } on http.ClientException {
      throw ApiException('Server unreachable.', 0);
    } catch (error) {
      if (error.toString().contains('SocketException')) {
        throw ApiException('Server unreachable.', 0);
      }
      rethrow;
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    late final dynamic body;
    try {
      body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        response.statusCode >= 400
            ? 'Request failed. Please try again.'
            : 'The server returned an invalid response. Please try again.',
        response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(_friendlyErrorMessage(body), response.statusCode);
    }
    if (body is Map<String, dynamic>) return body;
    return {'results': body};
  }

  String _friendlyErrorMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final directMessage = body['detail'] ?? body['error'] ?? body['message'];
      if (directMessage != null) return _stringifyError(directMessage);

      for (final entry in body.entries) {
        final message = _stringifyError(entry.value);
        if (message.isNotEmpty) return message;
      }
    }
    return _stringifyError(body);
  }

  String _stringifyError(dynamic value) {
    if (value is String) return value;
    if (value is List && value.isNotEmpty) {
      return _stringifyError(value.first);
    }
    if (value is Map && value.isNotEmpty) {
      return _stringifyError(value.values.first);
    }
    return 'Request failed. Please try again.';
  }
}

class SubscriptionInfo {
  const SubscriptionInfo({
    required this.plan,
    required this.status,
    this.billingProvider = '',
    this.policy = const {},
  });

  final String plan;
  final String status;
  final String billingProvider;
  final Map<String, dynamic> policy;

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      plan: json['plan'] as String? ?? 'free',
      status: json['status'] as String? ?? 'active',
      billingProvider: json['billing_provider'] as String? ?? '',
      policy: Map<String, dynamic>.from(json['policy'] as Map? ?? const {}),
    );
  }
}

class SubscriptionUsage {
  const SubscriptionUsage({
    required this.plan,
    required this.storageBytesUsed,
    required this.storageBytesLimit,
    required this.notesCount,
    required this.maxNotes,
    this.notesBytesUsed = 0,
    this.attachmentsBytesUsed = 0,
  });

  final String plan;
  final int storageBytesUsed;
  final int storageBytesLimit;
  final int notesCount;
  final int? maxNotes;
  final int notesBytesUsed;
  final int attachmentsBytesUsed;

  Map<String, dynamic> toJson() => {
        'plan': plan,
        'usage': {
          'storage_bytes_used': storageBytesUsed,
          'notes_bytes_used': notesBytesUsed,
          'attachments_bytes_used': attachmentsBytesUsed,
          'notes_count': notesCount,
        },
        'limits': {
          'storage_bytes': storageBytesLimit,
          'max_notes': maxNotes,
        },
      };

  factory SubscriptionUsage.fromJson(Map<String, dynamic> json) {
    final usage = Map<String, dynamic>.from(
      json['usage'] as Map? ?? const {},
    );
    final limits = Map<String, dynamic>.from(
      json['limits'] as Map? ?? const {},
    );
    return SubscriptionUsage(
      plan: json['plan'] as String? ?? 'free',
      storageBytesUsed: _jsonInt(
        usage['storage_bytes_used'] ?? usage['ciphertext_bytes_used'],
      ),
      storageBytesLimit: _jsonInt(limits['storage_bytes']),
      notesCount: _jsonInt(usage['notes_count']),
      maxNotes:
          limits['max_notes'] == null ? null : _jsonInt(limits['max_notes']),
      notesBytesUsed: _jsonInt(usage['notes_bytes_used']),
      attachmentsBytesUsed: _jsonInt(usage['attachments_bytes_used']),
    );
  }
}

int _jsonInt(dynamic value) => switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text) ?? 0,
      _ => 0,
    };

class CheckoutSession {
  const CheckoutSession({
    required this.status,
    required this.provider,
    required this.targetPlan,
    this.checkoutUrl,
  });

  final String status;
  final String provider;
  final String targetPlan;
  final String? checkoutUrl;

  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    return CheckoutSession(
      status: json['status'] as String? ?? 'unknown',
      provider: json['provider'] as String? ?? 'unconfigured',
      targetPlan: json['target_plan'] as String? ?? '',
      checkoutUrl: json['checkout_url'] as String?,
    );
  }
}

class ShareContact {
  const ShareContact({
    required this.email,
    required this.lastRole,
    required this.lastDirection,
  });

  final String email;
  final String lastRole;
  final String lastDirection;

  factory ShareContact.fromJson(Map<String, dynamic> json) {
    return ShareContact(
      email: json['email'] as String? ?? '',
      lastRole: json['last_role'] as String? ?? '',
      lastDirection: json['last_direction'] as String? ?? '',
    );
  }
}

Map<String, dynamic> noteUpsertOperation({
  required String idempotencyKey,
  required String tenant,
  required EncryptedEnvelope encryptedPayload,
  required String payloadHash,
  required DateTime updatedAt,
  String? remoteId,
  int? expectedVersion,
}) {
  return {
    'idempotency_key': idempotencyKey,
    'type': 'upsert_note',
    if (remoteId != null) 'note_id': remoteId,
    'payload': {
      if (remoteId != null) 'id': remoteId,
      'tenant': tenant,
      'encrypted_payload': encryptedPayload.toJson(),
      'payload_hash': payloadHash,
      'client_updated_at': updatedAt.toUtc().toIso8601String(),
      if (expectedVersion != null) 'expected_version': expectedVersion,
    },
  };
}

Map<String, dynamic> noteStateOperation({
  required String idempotencyKey,
  required String remoteId,
  required String state,
}) {
  return {
    'idempotency_key': idempotencyKey,
    'type': 'change_state',
    'note_id': remoteId,
    'payload': {'state': state},
  };
}
