import '../../../ai_engine/domain/entities/cited_source.dart';

/// Роль автора сообщения в диалоге.
enum MessageRole {
  user,
  assistant,
  system,
}

/// Доменная сущность сообщения в чате.
class ChatMessageEntity {
  final String id;
  final String sessionId;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isStreaming;
  final bool hasError;
  final List<String> attachedDocumentIds;
  final List<CitedSource> citations;
  final String? analysisMode;

  const ChatMessageEntity({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isStreaming = false,
    this.hasError = false,
    this.attachedDocumentIds = const [],
    this.citations = const [],
    this.analysisMode,
  });

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  ChatMessageEntity copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isStreaming,
    bool? hasError,
    List<String>? attachedDocumentIds,
    List<CitedSource>? citations,
    String? analysisMode,
  }) {
    return ChatMessageEntity(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      hasError: hasError ?? this.hasError,
      attachedDocumentIds: attachedDocumentIds ?? this.attachedDocumentIds,
      citations: citations ?? this.citations,
      analysisMode: analysisMode ?? this.analysisMode,
    );
  }
}
