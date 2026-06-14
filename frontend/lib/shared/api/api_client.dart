import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:zknotes_app/shared/models/encrypted_envelope.dart';
import 'package:zknotes_app/shared/models/note.dart';
import 'package:zknotes_app/shared/models/session.dart';

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);

  final String message;
  final int statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.baseUrl = 'http://127.0.0.1:8000',
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required RegistrationKeyMaterial material,
  }) {
    return _post('/api/v1/auth/register', {
      'email': email,
      'password': password,
      'kdf_algorithm': 'pbkdf2-sha256',
      'kdf_params': {'iterations': 210000, 'bits': 256},
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

  Future<List<RemoteEncryptedNote>> fetchNotes(String accessToken) async {
    final json = await _get('/api/v1/notes/', accessToken);
    final results = json['results'] as List? ?? json as List;
    return results
        .map((item) => RemoteEncryptedNote.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<CollaboratorPresence>> fetchPresence(String accessToken) async {
    final json = await _get('/api/v1/collaboration/presence/', accessToken);
    final results = json['results'] as List? ?? json as List;
    return results
        .map((item) => CollaboratorPresence.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
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

  Future<Map<String, dynamic>> _get(String path, String accessToken) async {
    final response = await _http.get(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body =
        response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(body.toString(), response.statusCode);
    }
    if (body is Map<String, dynamic>) return body;
    return {'results': body};
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
