import 'package:zknotes_app/shared/models/encrypted_envelope.dart';

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.text,
    required this.done,
    required this.indent,
  });

  final String id;
  final String text;
  final bool done;
  final int indent;

  ChecklistItem copyWith({
    String? text,
    bool? done,
    int? indent,
  }) {
    return ChecklistItem(
      id: id,
      text: text ?? this.text,
      done: done ?? this.done,
      indent: indent ?? this.indent,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'indent': indent,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) {
    return ChecklistItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      indent: json['indent'] as int? ?? 0,
    );
  }
}

class PlainNote {
  const PlainNote({
    required this.localId,
    this.remoteId,
    required this.title,
    required this.body,
    required this.checklist,
    required this.updatedAt,
    required this.pinned,
    required this.color,
    required this.sortOrder,
    required this.dirty,
    required this.version,
    this.state = 'active',
    this.conflicted = false,
    this.reminderAt,
    this.shared = false,
  });

  final String localId;
  final String? remoteId;
  final String title;
  final String body;
  final List<ChecklistItem> checklist;
  final DateTime updatedAt;
  final bool pinned;
  final int color;
  final int sortOrder;
  final bool dirty;
  final int version;
  final String state;
  final bool conflicted;
  final DateTime? reminderAt;
  final bool shared;

  PlainNote copyWith({
    String? remoteId,
    String? title,
    String? body,
    List<ChecklistItem>? checklist,
    DateTime? updatedAt,
    bool? pinned,
    int? color,
    int? sortOrder,
    bool? dirty,
    int? version,
    String? state,
    bool? conflicted,
    DateTime? reminderAt,
    bool clearReminder = false,
    bool? shared,
  }) {
    return PlainNote(
      localId: localId,
      remoteId: remoteId ?? this.remoteId,
      title: title ?? this.title,
      body: body ?? this.body,
      checklist: checklist ?? this.checklist,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      dirty: dirty ?? this.dirty,
      version: version ?? this.version,
      state: state ?? this.state,
      conflicted: conflicted ?? this.conflicted,
      reminderAt: clearReminder ? null : reminderAt ?? this.reminderAt,
      shared: shared ?? this.shared,
    );
  }

  Map<String, dynamic> encryptedPayloadJson() => {
        'schema': 2,
        'title': title,
        'body': body,
        'checklist': checklist.map((item) => item.toJson()).toList(),
        'color': color,
        'sortOrder': sortOrder,
        'pinned': pinned,
        'shared': shared,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  Map<String, dynamic> toPlainJson() => {
        'localId': localId,
        'remoteId': remoteId,
        'title': title,
        'body': body,
        'checklist': checklist.map((item) => item.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
        'pinned': pinned,
        'color': color,
        'sortOrder': sortOrder,
        'dirty': dirty,
        'version': version,
        'state': state,
        'conflicted': conflicted,
        'reminderAt': reminderAt?.toUtc().toIso8601String(),
        'shared': shared,
      };

  factory PlainNote.fromPlainJson(Map<String, dynamic> json) {
    return PlainNote(
      localId: json['localId'] as String,
      remoteId: json['remoteId'] as String?,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      checklist: (json['checklist'] as List? ?? [])
          .map((item) =>
              ChecklistItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      pinned: json['pinned'] as bool? ?? false,
      color: json['color'] as int? ?? 0xffffffff,
      sortOrder: json['sortOrder'] as int? ??
          -DateTime.parse(json['updatedAt'] as String).microsecondsSinceEpoch,
      dirty: json['dirty'] as bool? ?? false,
      version: json['version'] as int? ?? 1,
      state: json['state'] as String? ?? 'active',
      conflicted: json['conflicted'] as bool? ?? false,
      reminderAt: DateTime.tryParse(json['reminderAt'] as String? ?? ''),
      shared: json['shared'] as bool? ?? false,
    );
  }

  factory PlainNote.fromEncryptedPayload({
    required String localId,
    required String remoteId,
    required DateTime updatedAt,
    required int version,
    required Map<String, dynamic> json,
  }) {
    return PlainNote(
      localId: localId,
      remoteId: remoteId,
      title: json['title'] as String? ?? 'Untitled note',
      body: json['body'] as String? ?? '',
      checklist: (json['checklist'] as List? ?? [])
          .map((item) =>
              ChecklistItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? updatedAt,
      pinned: json['pinned'] as bool? ?? false,
      color: json['color'] as int? ?? 0xffffffff,
      sortOrder: json['sortOrder'] as int? ?? -updatedAt.microsecondsSinceEpoch,
      dirty: false,
      version: version,
      state: json['state'] as String? ?? 'active',
      shared: json['shared'] as bool? ?? false,
    );
  }
}

class RemoteEncryptedNote {
  const RemoteEncryptedNote({
    required this.id,
    required this.tenant,
    required this.encryptedPayload,
    required this.payloadHash,
    required this.version,
    required this.updatedAt,
    required this.state,
  });

  final String id;
  final String tenant;
  final EncryptedEnvelope encryptedPayload;
  final String payloadHash;
  final int version;
  final DateTime updatedAt;
  final String state;

  factory RemoteEncryptedNote.fromJson(Map<String, dynamic> json) {
    return RemoteEncryptedNote(
      id: json['id'] as String,
      tenant: json['tenant'] as String,
      encryptedPayload: EncryptedEnvelope.fromJson(
        Map<String, dynamic>.from(json['encrypted_payload'] as Map),
      ),
      payloadHash: json['payload_hash'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      state: json['state'] as String? ?? 'active',
    );
  }
}

class CollaboratorPresence {
  const CollaboratorPresence({
    required this.id,
    required this.noteId,
    required this.userId,
    required this.status,
    required this.updatedAt,
  });

  final String id;
  final String noteId;
  final String userId;
  final String status;
  final DateTime updatedAt;

  factory CollaboratorPresence.fromJson(Map<String, dynamic> json) {
    return CollaboratorPresence(
      id: json['id'] as String,
      noteId: json['note'] as String,
      userId: json['user'] as String,
      status: json['status'] as String? ?? 'offline',
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
