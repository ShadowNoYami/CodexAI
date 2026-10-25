import '../../../ai_engine/domain/entities/cited_source.dart';
import '../../domain/entities/chat_message_entity.dart';

/// Модель данных сообщения чата с поддержкой сериализации цитат и прикрепленных документов.
class ChatMessageModel extends ChatMessageEntity {
  const ChatMessageModel({
    required super.id,
    required super.sessionId,
    required super.role,
    required super.content,
    required super.timestamp,
    super.isStreaming = false,
    super.hasError = false,
    super.attachedDocumentIds = const [],
    super.citations = const [],
    super.analysisMode,
  });

  factory ChatMessageModel.fromEntity(ChatMessageEntity entity) {
    return ChatMessageModel(
      id: entity.id,
      sessionId: entity.sessionId,
      role: entity.role,
      content: entity.content,
      timestamp: entity.timestamp,
      isStreaming: entity.isStreaming,
      hasError: entity.hasError,
      attachedDocumentIds: List<String>.from(entity.attachedDocumentIds),
      citations: List<CitedSource>.from(entity.citations),
      analysisMode: entity.analysisMode,
    );
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String? ?? 'user';
    final role = MessageRole.values.firstWhere(
      (e) => e.name == roleName,
      orElse: () => MessageRole.user,
    );

    final rawDocIds = json['attachedDocumentIds'] as List<dynamic>? ?? const [];
    final rawCitations = json['citations'] as List<dynamic>? ?? const [];

    return ChatMessageModel(
      id: json['id'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      role: role,
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      isStreaming: json['isStreaming'] as bool? ?? false,
      hasError: json['hasError'] as bool? ?? false,
      attachedDocumentIds: rawDocIds.map((e) => e.toString()).toList(),
      citations: rawCitations
          .map((e) => CitedSource.fromJson(e as Map<String, dynamic>))
          .toList(),
      analysisMode: json['analysisMode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'isStreaming': isStreaming,
        'hasError': hasError,
        'attachedDocumentIds': attachedDocumentIds,
        'citations': citations.map((e) => e.toJson()).toList(),
        'analysisMode': analysisMode,
      };
}
