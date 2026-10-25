import '../../domain/entities/chat_session_entity.dart';

/// Модель данных сессии чата.
class ChatSessionModel extends ChatSessionEntity {
  const ChatSessionModel({
    required super.id,
    required super.title,
    required super.createdAt,
    required super.updatedAt,
    super.documentIds = const [],
    super.lastMessagePreview,
  });

  factory ChatSessionModel.fromEntity(ChatSessionEntity entity) {
    return ChatSessionModel(
      id: entity.id,
      title: entity.title,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      documentIds: List<String>.from(entity.documentIds),
      lastMessagePreview: entity.lastMessagePreview,
    );
  }

  factory ChatSessionModel.fromJson(Map<String, dynamic> json) {
    final rawDocIds = json['documentIds'] as List<dynamic>? ?? const [];
    return ChatSessionModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Новый диалог',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      documentIds: rawDocIds.map((e) => e.toString()).toList(),
      lastMessagePreview: json['lastMessagePreview'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'documentIds': documentIds,
        'lastMessagePreview': lastMessagePreview,
      };
}
