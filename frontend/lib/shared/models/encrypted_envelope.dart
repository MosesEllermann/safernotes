class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.version,
    required this.algorithm,
    required this.nonce,
    required this.ciphertext,
    this.keyId,
  });

  final int version;
  final String algorithm;
  final String nonce;
  final String ciphertext;
  final String? keyId;

  Map<String, dynamic> toJson() => {
        'version': version,
        'algorithm': algorithm,
        'nonce': nonce,
        'ciphertext': ciphertext,
        if (keyId != null) 'key_id': keyId,
      };

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    return EncryptedEnvelope(
      version: json['version'] as int,
      algorithm: json['algorithm'] as String,
      nonce: json['nonce'] as String,
      ciphertext: json['ciphertext'] as String,
      keyId: json['key_id'] as String?,
    );
  }
}
