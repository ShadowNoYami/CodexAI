import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/exceptions.dart';
import '../../../ai_engine/data/repositories/ai_repository_impl.dart';
import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../../../ai_engine/domain/repositories/ai_repository.dart';
import '../../../documents/domain/entities/document_entity.dart';
import '../../../documents/presentation/providers/documents_notifier.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_message_entity.dart';
import '../../domain/repositories/chat_repository.dart';
import 'chat_sessions_notifier.dart';

/// Статус генерации ответа ИИ в активном чате.
enum ChatGenerationStatus {
  /// Ожидание ввода пользователя.
  idle,

  /// Подготовка контекста и RAG-поиск по чанкам документа.
  loading,

  /// Потоковая генерация ответа токенами в реальном времени (SSE Streaming).
  streaming,

  /// Ошибка генерации или превышение лимитов.
  error,
}

/// Состояние активного чата.
class ActiveChatState {
  final String? sessionId;
  final List<ChatMessageEntity> messages;
  final AnalysisMode analysisMode;
  final ChatGenerationStatus generationStatus;
  final String? errorMessage;
  final bool isHistoryLoading;

  const ActiveChatState({
    this.sessionId,
    this.messages = const [],
    this.analysisMode = AnalysisMode.qa,
    this.generationStatus = ChatGenerationStatus.idle,
    this.errorMessage,
    this.isHistoryLoading = false,
  });

  bool get isBusy =>
      generationStatus == ChatGenerationStatus.loading ||
      generationStatus == ChatGenerationStatus.streaming;

  ActiveChatState copyWith({
    String? sessionId,
    List<ChatMessageEntity>? messages,
    AnalysisMode? analysisMode,
    ChatGenerationStatus? generationStatus,
    String? errorMessage,
    bool clearError = false,
    bool? isHistoryLoading,
  }) {
    return ActiveChatState(
      sessionId: sessionId ?? this.sessionId,
      messages: messages ?? this.messages,
      analysisMode: analysisMode ?? this.analysisMode,
      generationStatus: generationStatus ?? this.generationStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isHistoryLoading: isHistoryLoading ?? this.isHistoryLoading,
    );
  }
}

/// Провайдер списка документов, прикрепленных к текущей активной сессии чата.
final activeSessionDocumentsProvider = Provider<List<DocumentEntity>>((ref) {
  final activeSession = ref.watch(
    chatSessionsNotifierProvider.select((s) => s.activeSession),
  );
  final allDocs = ref.watch(
    documentsNotifierProvider.select((s) => s.documents),
  );

  if (activeSession == null || activeSession.documentIds.isEmpty) {
    return const [];
  }

  final attachedIds = activeSession.documentIds.toSet();
  return allDocs
      .where((doc) => attachedIds.contains(doc.id))
      .toList(growable: false);
});

/// Провайдер контроллера активного чата.
final activeChatNotifierProvider =
    StateNotifierProvider<ActiveChatNotifier, ActiveChatState>((ref) {
  final notifier = ActiveChatNotifier(
    chatRepository: ref.watch(chatRepositoryProvider),
    aiRepository: ref.watch(aiRepositoryProvider),
    ref: ref,
  );

  // Реактивно отслеживаем переключение активной сессии чата
  ref.listen<String?>(
    chatSessionsNotifierProvider.select((s) => s.activeSessionId),
    (previous, next) {
      if (next != null && next != previous) {
        notifier.loadSessionMessages(next);
      }
    },
    fireImmediately: true,
  );

  return notifier;
});

/// Контроллер (`StateNotifier`) для управления сообщениями активного чата,
/// выбором режима анализа и потоковой генерацией ответа от LLM.
class ActiveChatNotifier extends StateNotifier<ActiveChatState> {
  final ChatRepository _chatRepository;
  final AiRepository _aiRepository;
  final Ref _ref;
  final Uuid _uuid;

  CancelToken? _activeCancelToken;

  ActiveChatNotifier({
    required ChatRepository chatRepository,
    required AiRepository aiRepository,
    required Ref ref,
    Uuid? uuid,
  })  : _chatRepository = chatRepository,
        _aiRepository = aiRepository,
        _ref = ref,
        _uuid = uuid ?? const Uuid(),
        super(const ActiveChatState());

  /// Загружает сохраненную историю сообщений для выбранной сессии [sessionId].
  Future<void> loadSessionMessages(String sessionId) async {
    stopGeneration();
    state = state.copyWith(
      sessionId: sessionId,
      isHistoryLoading: true,
      generationStatus: ChatGenerationStatus.idle,
      clearError: true,
    );

    try {
      final history = await _chatRepository.getMessagesForSession(sessionId);
      if (state.sessionId != sessionId) return;

      state = state.copyWith(
        messages: history,
        isHistoryLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isHistoryLoading: false,
        generationStatus: ChatGenerationStatus.error,
        errorMessage: _formatError(e),
      );
    }
  }

  /// Изменяет активный аналитический режим бота (QA / Executive Summary / Deep Analysis).
  void setAnalysisMode(AnalysisMode mode) {
    state = state.copyWith(analysisMode: mode, clearError: true);
  }

  /// Запускает быстрое действие по чипу («Сделать выжимку», «Выделить главное», «Найти риски»).
  Future<void> runQuickAction(AnalysisMode mode) async {
    setAnalysisMode(mode);
    await sendMessage(
      mode.quickActionPrompt,
      overrideMode: mode,
    );
  }

  /// Отправляет сообщение пользователя, выполняет RAG-поиск по прикрепленным документам
  /// и запускает потоковую генерацию ответа в реальном времени.
  Future<void> sendMessage(
    String rawText, {
    AnalysisMode? overrideMode,
  }) async {
    final text = rawText.trim();
    if (text.isEmpty || state.isBusy) return;

    var sessionId = state.sessionId;
    if (sessionId == null) {
      final created = await _ref
          .read(chatSessionsNotifierProvider.notifier)
          .createNewSession();
      sessionId = created.id;
    }

    final effectiveMode = overrideMode ?? state.analysisMode;
    final attachedDocs = _resolveContextDocuments();
    final attachedDocIds = attachedDocs.map((d) => d.id).toList();
    final previousHistory = List<ChatMessageEntity>.from(state.messages);

    // 1. Создаем и сохраняем сообщение пользователя
    final userMsg = ChatMessageEntity(
      id: _uuid.v4(),
      sessionId: sessionId,
      role: MessageRole.user,
      content: text,
      timestamp: DateTime.now(),
      attachedDocumentIds: attachedDocIds,
      analysisMode: effectiveMode.name,
    );

    final updatedAfterUser = [...previousHistory, userMsg];
    state = state.copyWith(
      sessionId: sessionId,
      messages: updatedAfterUser,
      analysisMode: effectiveMode,
      generationStatus: ChatGenerationStatus.loading,
      clearError: true,
    );

    await _chatRepository.saveMessage(userMsg);

    // Автоматически формируем осмысленный заголовок сессии по первому вопросу
    final isFirstMessage = previousHistory.isEmpty;
    final autoTitle = isFirstMessage
        ? (text.length > 44 ? '${text.substring(0, 44).trim()}…' : text)
        : null;

    await _ref.read(chatSessionsNotifierProvider.notifier).updateSessionMetadata(
          sessionId: sessionId,
          title: autoTitle,
          lastMessagePreview: text,
        );

    final assistantMsgId = _uuid.v4();
    _activeCancelToken = CancelToken();

    try {
      final llmConfig = _ref.read(llmSettingsProvider);

      // 2. Выполняем адаптивный гибридный RAG-поиск по документам
      final retrievalResult = await _aiRepository.retrieveContext(
        config: llmConfig,
        query: text,
        documents: attachedDocs,
        mode: effectiveMode,
      );

      // 3. Создаем сообщение ассистента в состоянии стриминга с прикрепленными цитатами
      var assistantMsg = ChatMessageEntity(
        id: assistantMsgId,
        sessionId: sessionId,
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
        isStreaming: true,
        attachedDocumentIds: attachedDocIds,
        citations: retrievalResult.citations,
        analysisMode: effectiveMode.name,
      );

      state = state.copyWith(
        messages: [...updatedAfterUser, assistantMsg],
        generationStatus: ChatGenerationStatus.streaming,
      );

      // 4. Подписываемся на поток токенов (SSE Streaming)
      final buffer = StringBuffer();
      final responseStream = _aiRepository.streamChatResponse(
        config: llmConfig,
        mode: effectiveMode,
        retrievalResult: retrievalResult,
        history: previousHistory,
        userPrompt: text,
        cancelToken: _activeCancelToken,
      );

      await for (final tokenChunk in responseStream) {
        if (state.sessionId != sessionId) break;
        buffer.write(tokenChunk);
        assistantMsg = assistantMsg.copyWith(
          content: buffer.toString(),
          isStreaming: true,
        );
        _updateMessageInState(assistantMsg);
      }

      // 5. Завершаем стриминг и сохраняем итоговый ответ в локальную БД
      final finalContent = buffer.toString().trim().isEmpty
          ? 'Ответ не содержит текста.'
          : buffer.toString();

      final completedAssistantMsg = assistantMsg.copyWith(
        content: finalContent,
        isStreaming: false,
      );

      _updateMessageInState(completedAssistantMsg);
      state = state.copyWith(generationStatus: ChatGenerationStatus.idle);

      await _chatRepository.saveMessage(completedAssistantMsg);
      await _ref
          .read(chatSessionsNotifierProvider.notifier)
          .updateSessionMetadata(
            sessionId: sessionId,
            lastMessagePreview: finalContent.length > 90
                ? '${finalContent.substring(0, 90).replaceAll('\n', ' ')}…'
                : finalContent.replaceAll('\n', ' '),
          );
    } catch (e) {
      final errText = _formatError(e);
      final existingIdx =
          state.messages.indexWhere((m) => m.id == assistantMsgId);

      if (existingIdx >= 0) {
        final partial = state.messages[existingIdx];
        final failedMsg = partial.copyWith(
          content: partial.content.isNotEmpty
              ? '${partial.content}\n\n*[Прервано: $errText]*'
              : '⚠️ $errText',
          isStreaming: false,
          hasError: true,
        );
        _updateMessageInState(failedMsg);
        await _chatRepository.saveMessage(failedMsg);
      } else {
        final errorBubble = ChatMessageEntity(
          id: assistantMsgId,
          sessionId: sessionId,
          role: MessageRole.assistant,
          content: '⚠️ $errText',
          timestamp: DateTime.now(),
          isStreaming: false,
          hasError: true,
        );
        state = state.copyWith(messages: [...state.messages, errorBubble]);
        await _chatRepository.saveMessage(errorBubble);
      }

      state = state.copyWith(
        generationStatus: ChatGenerationStatus.error,
        errorMessage: errText,
      );
    } finally {
      _activeCancelToken = null;
    }
  }

  /// Принудительно останавливает текущую потоковую генерацию ответа.
  void stopGeneration() {
    final token = _activeCancelToken;
    if (token != null && !token.isCancelled) {
      token.cancel('Остановлено пользователем');
    }
    _activeCancelToken = null;
  }

  /// Повторяет отправку последнего пользовательского запроса после сетевой ошибки или таймаута.
  Future<void> retryLastMessage() async {
    if (state.isBusy) return;
    final lastUserMsg = state.messages
        .lastWhere(
          (m) => m.isUser,
          orElse: () => ChatMessageEntity(
            id: '',
            sessionId: '',
            role: MessageRole.user,
            content: '',
            timestamp: DateTime.now(),
          ),
        );
    if (lastUserMsg.content.trim().isEmpty) return;

    // Удаляем последнее ошибочное сообщение ассистента и дубликат вопроса перед повтором
    final cleaned = List<ChatMessageEntity>.from(state.messages);
    if (cleaned.isNotEmpty && cleaned.last.hasError) {
      cleaned.removeLast();
    }
    if (cleaned.isNotEmpty && cleaned.last.id == lastUserMsg.id) {
      cleaned.removeLast();
    }
    state = state.copyWith(
      messages: cleaned,
      generationStatus: ChatGenerationStatus.idle,
      clearError: true,
    );

    await sendMessage(lastUserMsg.content);
  }

  /// Очищает историю сообщений в текущем активном чате.
  Future<void> clearActiveChatHistory() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    stopGeneration();
    await _chatRepository.clearMessagesForSession(sessionId);
    state = state.copyWith(
      messages: const [],
      generationStatus: ChatGenerationStatus.idle,
      clearError: true,
    );
  }

  void clearError() {
    state = state.copyWith(
      generationStatus: ChatGenerationStatus.idle,
      clearError: true,
    );
  }

  /// Определяет документы для контекста: сначала привязанные к сессии,
  /// а если к сессии еще ничего не привязано — все готовые документы в рабочей области.
  List<DocumentEntity> _resolveContextDocuments() {
    final sessionDocs = _ref.read(activeSessionDocumentsProvider);
    if (sessionDocs.isNotEmpty) {
      return sessionDocs.where((d) => d.isReady).toList();
    }
    return _ref.read(documentsNotifierProvider).readyDocuments;
  }

  void _updateMessageInState(ChatMessageEntity updated) {
    final list = List<ChatMessageEntity>.from(state.messages);
    final idx = list.indexWhere((m) => m.id == updated.id);
    if (idx >= 0) {
      list[idx] = updated;
      state = state.copyWith(messages: list);
    }
  }

  String _formatError(Object error) {
    if (error is AppException) return error.message;
    return error.toString();
  }
}
