/// Доменная сущность сессии чата с привязанными к ней документами.
class ChatSessionEntity {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> documentIds;
  final String? lastMessagePreview;

  const ChatSessionEntity({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.documentIds = const [],
    this.lastMessagePreview,
  });

  ChatSessionEntity copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? documentIds,
    String? lastMessagePreview,
  }) {
    return ChatSessionEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      documentIds: documentIds ?? this.documentIds,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
    );
  }
}
