import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../../ai_engine/domain/entities/cited_source.dart';
import '../../domain/entities/chat_message_entity.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';

/// Провайдер локального источника данных для чатов и сообщений.
final chatLocalDataSourceProvider = Provider<ChatLocalDataSource>((ref) {
  return ChatLocalDataSource(db: ref.watch(appDatabaseProvider));
});

/// Локальное хранилище сессий чата и сообщений в Drift (SQLite).
class ChatLocalDataSource {
  static const String _fallbackSessionsKey = 'cached_chat_sessions_v1';
  static const String _fallbackMessagesPrefix = 'cached_chat_messages_v1_';

  final AppDatabase _db;

  const ChatLocalDataSource({required AppDatabase db}) : _db = db;

  /// Возвращает все сессии чата, отсортированные по дате последнего обновления.
  Future<List<ChatSessionModel>> getAllSessions() async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        return _getSessionsFallback();
      }

      final rows = await _db.select(
        'SELECT * FROM chat_sessions ORDER BY updated_at DESC;',
      );
      return rows.map(_mapSessionRow).toList();
    } catch (e, st) {
      throw DatabaseException(
        'Не удалось загрузить список сессий чата: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Сохраняет или обновляет сессию чата в БД.
  Future<void> saveSession(ChatSessionModel session) async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        await _saveSessionFallback(session);
        return;
      }

      await _db.execute(
        '''
        INSERT OR REPLACE INTO chat_sessions (
          id, title, created_at, updated_at, document_ids_json, last_message_preview
        ) VALUES (?, ?, ?, ?, ?, ?);
        ''',
        [
          session.id,
          session.title,
          session.createdAt.toIso8601String(),
          session.updatedAt.toIso8601String(),
          jsonEncode(session.documentIds),
          session.lastMessagePreview,
        ],
      );
    } catch (e, st) {
      throw DatabaseException(
        'Ошибка сохранения сессии чата "${session.title}": $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Удаляет сессию чата и все связанные с ней сообщения.
  Future<void> deleteSession(String sessionId) async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        final sessions = (await _getSessionsFallback())
            .where((s) => s.id != sessionId)
            .toList();
        await _writeSessionsFallback(sessions);
        final prefs = await _db.prefs;
        await prefs.remove('$_fallbackMessagesPrefix$sessionId');
        return;
      }

      await _db.execute(
        'DELETE FROM chat_messages WHERE session_id = ?;',
        [sessionId],
      );
      await _db.execute(
        'DELETE FROM chat_sessions WHERE id = ?;',
        [sessionId],
      );
    } catch (e, st) {
      throw DatabaseException(
        'Ошибка удаления сессии чата: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Загружает историю сообщений для сессии [sessionId] в хронологическом порядке.
  Future<List<ChatMessageModel>> getMessagesForSession(String sessionId) async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        return _getMessagesFallback(sessionId);
      }

      final rows = await _db.select(
        'SELECT * FROM chat_messages WHERE session_id = ? ORDER BY timestamp ASC;',
        [sessionId],
      );
      return rows.map(_mapMessageRow).toList();
    } catch (e, st) {
      throw DatabaseException(
        'Не удалось загрузить историю сообщений: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Сохраняет или обновляет сообщение в локальной БД.
  Future<void> saveMessage(ChatMessageModel message) async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        await _saveMessageFallback(message);
        return;
      }

      await _db.execute(
        '''
        INSERT OR REPLACE INTO chat_messages (
          id, session_id, role, content, timestamp,
          is_streaming, has_error, attached_document_ids_json,
          citations_json, analysis_mode
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        ''',
        [
          message.id,
          message.sessionId,
          message.role.name,
          message.content,
          message.timestamp.toIso8601String(),
          message.isStreaming ? 1 : 0,
          message.hasError ? 1 : 0,
          jsonEncode(message.attachedDocumentIds),
          jsonEncode(message.citations.map((c) => c.toJson()).toList()),
          message.analysisMode,
        ],
      );
    } catch (e, st) {
      throw DatabaseException(
        'Ошибка сохранения сообщения в БД: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Очищает все сообщения внутри указанной сессии чата.
  Future<void> clearMessagesForSession(String sessionId) async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        final prefs = await _db.prefs;
        await prefs.remove('$_fallbackMessagesPrefix$sessionId');
        return;
      }

      await _db.execute(
        'DELETE FROM chat_messages WHERE session_id = ?;',
        [sessionId],
      );
    } catch (e, st) {
      throw DatabaseException(
        'Ошибка очистки сообщений сессии: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  ChatSessionModel _mapSessionRow(Map<String, Object?> row) {
    List<String> docIds = const [];
    final rawDocIds = row['document_ids_json'] as String?;
    if (rawDocIds != null && rawDocIds.isNotEmpty) {
      try {
        docIds = (jsonDecode(rawDocIds) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    }

    return ChatSessionModel(
      id: row['id'] as String? ?? '',
      title: row['title'] as String? ?? 'Новый чат',
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(row['updated_at'] as String? ?? '') ??
          DateTime.now(),
      documentIds: docIds,
      lastMessagePreview: row['last_message_preview'] as String?,
    );
  }

  ChatMessageModel _mapMessageRow(Map<String, Object?> row) {
    final roleName = row['role'] as String? ?? 'user';
    final role = MessageRole.values.firstWhere(
      (e) => e.name == roleName,
      orElse: () => MessageRole.user,
    );

    List<String> attachedDocIds = const [];
    final rawAttached = row['attached_document_ids_json'] as String?;
    if (rawAttached != null && rawAttached.isNotEmpty) {
      try {
        attachedDocIds = (jsonDecode(rawAttached) as List<dynamic>)
            .map((e) => e.toString())
            .toList();
      } catch (_) {}
    }

    List<CitedSource> citations = const [];
    final rawCitations = row['citations_json'] as String?;
    if (rawCitations != null && rawCitations.isNotEmpty) {
      try {
        citations = (jsonDecode(rawCitations) as List<dynamic>)
            .map((e) => CitedSource.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    return ChatMessageModel(
      id: row['id'] as String? ?? '',
      sessionId: row['session_id'] as String? ?? '',
      role: role,
      content: row['content'] as String? ?? '',
      timestamp: DateTime.tryParse(row['timestamp'] as String? ?? '') ??
          DateTime.now(),
      isStreaming: ((row['is_streaming'] as num?)?.toInt() ?? 0) == 1,
      hasError: ((row['has_error'] as num?)?.toInt() ?? 0) == 1,
      attachedDocumentIds: attachedDocIds,
      citations: citations,
      analysisMode: row['analysis_mode'] as String?,
    );
  }

  Future<List<ChatSessionModel>> _getSessionsFallback() async {
    final prefs = await _db.prefs;
    final raw = prefs.getString(_fallbackSessionsKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    final sessions = list
        .map((e) => ChatSessionModel.fromJson(e as Map<String, dynamic>))
        .toList();
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  Future<void> _saveSessionFallback(ChatSessionModel session) async {
    final sessions = (await _getSessionsFallback()).toList();
    final idx = sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      sessions[idx] = session;
    } else {
      sessions.insert(0, session);
    }
    await _writeSessionsFallback(sessions);
  }

  Future<void> _writeSessionsFallback(List<ChatSessionModel> sessions) async {
    final prefs = await _db.prefs;
    await prefs.setString(
      _fallbackSessionsKey,
      jsonEncode(sessions.map((s) => s.toJson()).toList()),
    );
  }

  Future<List<ChatMessageModel>> _getMessagesFallback(String sessionId) async {
    final prefs = await _db.prefs;
    final raw = prefs.getString('$_fallbackMessagesPrefix$sessionId');
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveMessageFallback(ChatMessageModel message) async {
    final messages = (await _getMessagesFallback(message.sessionId)).toList();
    final idx = messages.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      messages[idx] = message;
    } else {
      messages.add(message);
    }
    final prefs = await _db.prefs;
    await prefs.setString(
      '$_fallbackMessagesPrefix${message.sessionId}',
      jsonEncode(messages.map((m) => m.toJson()).toList()),
    );
  }
}
