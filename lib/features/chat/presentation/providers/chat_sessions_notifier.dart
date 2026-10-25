import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/config/env_config.dart';
import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_session_entity.dart';
import '../../domain/repositories/chat_repository.dart';

/// Провайдер настроек подключения к LLM API с сохранением в `SharedPreferences`.
final llmSettingsProvider =
    StateNotifierProvider<LlmSettingsNotifier, LlmConfig>((ref) {
  final notifier = LlmSettingsNotifier();
  notifier.loadSavedSettings();
  return notifier;
});

class LlmSettingsNotifier extends StateNotifier<LlmConfig> {
  static const _providerKey = 'llm_provider_v1';
  static const _apiKeyPref = 'llm_api_key_v1';
  static const _baseUrlKey = 'llm_base_url_v1';
  static const _modelKey = 'llm_model_v1';

  LlmSettingsNotifier() : super(LlmConfig());

  Future<void> loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerName = prefs.getString(_providerKey);
      final savedKey = prefs.getString(_apiKeyPref);
      final savedBaseUrl = prefs.getString(_baseUrlKey);
      final savedModel = prefs.getString(_modelKey);

      final provider = LlmProviderType.values.firstWhere(
        (e) => e.name == providerName,
        orElse: () => LlmProviderType.gemini,
      );

      final defaultBaseUrl = provider == LlmProviderType.gemini
          ? EnvConfig.defaultGeminiBaseUrl
          : EnvConfig.defaultOpenAiBaseUrl;

      final defaultModel = provider == LlmProviderType.gemini
          ? EnvConfig.defaultGeminiModel
          : EnvConfig.defaultOpenAiModel;

      final effectiveModel = (savedModel != null &&
              savedModel.isNotEmpty &&
              savedModel != 'gemini-2.5-flash')
          ? savedModel
          : defaultModel;

      state = state.copyWith(
        provider: provider,
        apiKey: (savedKey != null && savedKey.isNotEmpty)
            ? savedKey
            : EnvConfig.geminiApiKey,
        baseUrl: (savedBaseUrl != null && savedBaseUrl.isNotEmpty)
            ? savedBaseUrl
            : defaultBaseUrl,
        model: effectiveModel,
      );
    } catch (_) {}
  }

  Future<void> updateSettings({
    required LlmProviderType provider,
    required String apiKey,
    required String baseUrl,
    required String model,
  }) async {
    state = state.copyWith(
      provider: provider,
      apiKey: apiKey.trim(),
      baseUrl: baseUrl.trim(),
      model: model.trim(),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_providerKey, provider.name);
      await prefs.setString(_apiKeyPref, apiKey.trim());
      await prefs.setString(_baseUrlKey, baseUrl.trim());
      await prefs.setString(_modelKey, model.trim());
    } catch (_) {}
  }
}

/// Состояние списка сессий чатов.
class ChatSessionsState {
  final List<ChatSessionEntity> sessions;
  final String? activeSessionId;
  final bool isLoading;

  const ChatSessionsState({
    this.sessions = const [],
    this.activeSessionId,
    this.isLoading = false,
  });

  /// Текущая выбранная сессия чата.
  ChatSessionEntity? get activeSession {
    if (activeSessionId == null) return null;
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return sessions.firstOrNull;
  }

  ChatSessionsState copyWith({
    List<ChatSessionEntity>? sessions,
    String? activeSessionId,
    bool? isLoading,
  }) {
    return ChatSessionsState(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Провайдер контроллера сессий чата.
final chatSessionsNotifierProvider =
    StateNotifierProvider<ChatSessionsNotifier, ChatSessionsState>((ref) {
  final notifier = ChatSessionsNotifier(
    chatRepository: ref.watch(chatRepositoryProvider),
  );
  notifier.loadSessions();
  return notifier;
});

/// Контроллер (`StateNotifier`) для управления сессиями чатов и привязанными к ним документами.
class ChatSessionsNotifier extends StateNotifier<ChatSessionsState> {
  final ChatRepository _chatRepository;
  final Uuid _uuid;

  ChatSessionsNotifier({
    required ChatRepository chatRepository,
    Uuid? uuid,
  })  : _chatRepository = chatRepository,
        _uuid = uuid ?? const Uuid(),
        super(const ChatSessionsState(isLoading: true));

  /// Загружает список сессий из локальной БД или создает стартовую сессию, если БД пуста.
  Future<void> loadSessions() async {
    state = state.copyWith(isLoading: true);
    try {
      final saved = await _chatRepository.getAllSessions();
      if (saved.isNotEmpty) {
        state = state.copyWith(
          sessions: saved,
          activeSessionId: state.activeSessionId ?? saved.first.id,
          isLoading: false,
        );
      } else {
        await createNewSession(title: 'Новый аналитический чат');
      }
    } catch (_) {
      await createNewSession(title: 'Новый аналитический чат');
    }
  }

  /// Создает новую сессию чата и делает ее активной.
  Future<ChatSessionEntity> createNewSession({
    String title = 'Новый чат',
    List<String> initialDocumentIds = const [],
  }) async {
    final now = DateTime.now();
    final session = ChatSessionEntity(
      id: _uuid.v4(),
      title: title,
      createdAt: now,
      updatedAt: now,
      documentIds: initialDocumentIds,
    );

    await _chatRepository.saveSession(session);

    final updated = [session, ...state.sessions];
    state = state.copyWith(
      sessions: updated,
      activeSessionId: session.id,
      isLoading: false,
    );
    return session;
  }

  /// Переключает активную сессию чата.
  void selectSession(String sessionId) {
    if (state.activeSessionId == sessionId) return;
    state = state.copyWith(activeSessionId: sessionId);
  }

  /// Обновляет заголовок и превью последнего сообщения сессии.
  Future<void> updateSessionMetadata({
    required String sessionId,
    String? title,
    String? lastMessagePreview,
  }) async {
    final idx = state.sessions.indexWhere((s) => s.id == sessionId);
    if (idx < 0) return;

    final current = state.sessions[idx];
    final updatedSession = current.copyWith(
      title: title ?? current.title,
      lastMessagePreview: lastMessagePreview ?? current.lastMessagePreview,
      updatedAt: DateTime.now(),
    );

    await _chatRepository.saveSession(updatedSession);

    final list = List<ChatSessionEntity>.from(state.sessions);
    list.removeAt(idx);
    list.insert(0, updatedSession);
    state = state.copyWith(sessions: list);
  }

  /// Прикрепляет документ к активной сессии чата.
  Future<void> attachDocumentToActiveSession(String documentId) async {
    var active = state.activeSession;
    active ??= await createNewSession();

    if (active.documentIds.contains(documentId)) return;

    final updatedDocIds = [...active.documentIds, documentId];
    final updatedSession = active.copyWith(
      documentIds: updatedDocIds,
      updatedAt: DateTime.now(),
    );

    await _chatRepository.saveSession(updatedSession);
    _replaceSessionInList(updatedSession);
  }

  /// Переключает привязку документа к активной сессии чата (прикрепить / открепить).
  Future<void> toggleDocumentInActiveSession(String documentId) async {
    final active = state.activeSession;
    if (active == null) return;

    final currentIds = List<String>.from(active.documentIds);
    if (currentIds.contains(documentId)) {
      currentIds.remove(documentId);
    } else {
      currentIds.add(documentId);
    }

    final updatedSession = active.copyWith(
      documentIds: currentIds,
      updatedAt: DateTime.now(),
    );
    await _chatRepository.saveSession(updatedSession);
    _replaceSessionInList(updatedSession);
  }

  /// Удаляет документ из списка прикрепленных во всех сессиях (при удалении самого файла).
  Future<void> removeDocumentFromAllSessions(String documentId) async {
    final updatedList = <ChatSessionEntity>[];
    for (final session in state.sessions) {
      if (session.documentIds.contains(documentId)) {
        final filtered = session.documentIds
            .where((id) => id != documentId)
            .toList(growable: false);
        final updated = session.copyWith(documentIds: filtered);
        await _chatRepository.saveSession(updated);
        updatedList.add(updated);
      } else {
        updatedList.add(session);
      }
    }
    state = state.copyWith(sessions: updatedList);
  }

  /// Удаляет сессию чата и переключается на соседнюю (либо создает новую).
  Future<void> deleteSession(String sessionId) async {
    await _chatRepository.deleteSession(sessionId);
    final remaining = state.sessions
        .where((s) => s.id != sessionId)
        .toList(growable: false);

    if (remaining.isEmpty) {
      state = state.copyWith(sessions: const [], activeSessionId: null);
      await createNewSession(title: 'Новый аналитический чат');
      return;
    }

    final nextActiveId = state.activeSessionId == sessionId
        ? remaining.first.id
        : state.activeSessionId;

    state = state.copyWith(
      sessions: remaining,
      activeSessionId: nextActiveId,
    );
  }

  void _replaceSessionInList(ChatSessionEntity updatedSession) {
    final list = List<ChatSessionEntity>.from(state.sessions);
    final idx = list.indexWhere((s) => s.id == updatedSession.id);
    if (idx >= 0) {
      list[idx] = updatedSession;
    } else {
      list.insert(0, updatedSession);
    }
    state = state.copyWith(sessions: list);
  }
}
