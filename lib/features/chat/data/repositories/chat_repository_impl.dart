import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/chat_message_entity.dart';
import '../../domain/entities/chat_session_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_local_ds.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';

/// Провайдер репозитория чата.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepositoryImpl(
    localDataSource: ref.watch(chatLocalDataSourceProvider),
  );
});

/// Реализация репозитория чата с сохранением в локальную БД Drift (Data-слой).
class ChatRepositoryImpl implements ChatRepository {
  final ChatLocalDataSource _localDataSource;

  const ChatRepositoryImpl({
    required ChatLocalDataSource localDataSource,
  }) : _localDataSource = localDataSource;

  @override
  Future<List<ChatSessionEntity>> getAllSessions() {
    return _localDataSource.getAllSessions();
  }

  @override
  Future<void> saveSession(ChatSessionEntity session) {
    return _localDataSource.saveSession(ChatSessionModel.fromEntity(session));
  }

  @override
  Future<void> deleteSession(String sessionId) {
    return _localDataSource.deleteSession(sessionId);
  }

  @override
  Future<List<ChatMessageEntity>> getMessagesForSession(String sessionId) {
    return _localDataSource.getMessagesForSession(sessionId);
  }

  @override
  Future<void> saveMessage(ChatMessageEntity message) {
    return _localDataSource.saveMessage(ChatMessageModel.fromEntity(message));
  }

  @override
  Future<void> clearMessagesForSession(String sessionId) {
    return _localDataSource.clearMessagesForSession(sessionId);
  }
}
