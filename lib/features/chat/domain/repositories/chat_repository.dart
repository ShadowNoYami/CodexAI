import '../entities/chat_message_entity.dart';
import '../entities/chat_session_entity.dart';

/// Контракт репозитория сессий чата и истории сообщений (Domain-слой).
abstract interface class ChatRepository {
  /// Загружает все сохраненные сессии чата.
  Future<List<ChatSessionEntity>> getAllSessions();

  /// Сохраняет или обновляет сессию чата.
  Future<void> saveSession(ChatSessionEntity session);

  /// Удаляет сессию чата вместе с ее историей сообщений.
  Future<void> deleteSession(String sessionId);

  /// Загружает все сообщения указанной сессии чата.
  Future<List<ChatMessageEntity>> getMessagesForSession(String sessionId);

  /// Сохраняет или обновляет сообщение в истории.
  Future<void> saveMessage(ChatMessageEntity message);

  /// Очищает все сообщения в указанной сессии.
  Future<void> clearMessagesForSession(String sessionId);
}
