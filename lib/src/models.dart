/// A message emitted by the merchant's chat widget.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.senderType,
    this.senderName,
    this.createdAt,
    this.hasAttachment = false,
  });
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: switch (json['id']) {
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    },
    body: json['body'] is String ? json['body'] as String : '',
    senderType: json['senderType'] is String
        ? json['senderType'] as String
        : '',
    senderName: _optional(json['senderName']),
    createdAt: _optional(json['createdAt']),
    hasAttachment: json['hasAttachment'] == true,
  );
  final int id;
  final String body, senderType;
  final String? senderName, createdAt;
  final bool hasAttachment;
  static String? _optional(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

enum ChatErrorKind { pageLoad, widget }

class ChatError implements Exception {
  const ChatError(this.kind, this.description);
  final ChatErrorKind kind;
  final String description;
  @override
  String toString() => 'LiveChat ${kind.name}: $description';
}

/// The Android SDK's deployment URL contract, with input validation.
Uri chatUrlOf(String baseUrl, String merchantPublicId) {
  final base = Uri.tryParse(baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''));
  final merchant = merchantPublicId.trim();
  if (base == null ||
      !['http', 'https'].contains(base.scheme) ||
      base.host.isEmpty ||
      base.hasQuery ||
      base.hasFragment ||
      base.userInfo.isNotEmpty) {
    throw ArgumentError.value(
      baseUrl,
      'baseUrl',
      'Expected an HTTP(S) deployment URL without query, fragment or credentials',
    );
  }
  if (merchant.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(merchant)) {
    throw ArgumentError.value(
      merchantPublicId,
      'merchantPublicId',
      'Expected a nonempty public ID',
    );
  }
  return Uri.parse('$base/widget/app/$merchant');
}
