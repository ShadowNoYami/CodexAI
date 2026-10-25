import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/token_estimator.dart';
import '../../../chat/domain/entities/chat_message_entity.dart';
import '../../../documents/domain/entities/document_chunk_entity.dart';
import '../../../documents/domain/entities/document_entity.dart';
import '../../domain/entities/analysis_mode.dart';
import '../../domain/prompts/system_prompts.dart';
import '../../domain/repositories/ai_repository.dart';
import '../datasources/llm_remote_ds.dart';
import '../datasources/rag_retriever_service.dart';

/// Провайдер репозитория ИИ-движка.
final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return AiRepositoryImpl(
    remoteDataSource: ref.watch(llmRemoteDataSourceProvider),
    ragRetriever: ref.watch(ragRetrieverServiceProvider),
  );
});

/// Реализация репозитория ИИ и аналитического RAG-движка (Data-слой).
class AiRepositoryImpl implements AiRepository {
  final LlmRemoteDataSource _remoteDataSource;
  final RagRetrieverService _ragRetriever;

  const AiRepositoryImpl({
    required LlmRemoteDataSource remoteDataSource,
    required RagRetrieverService ragRetriever,
  })  : _remoteDataSource = remoteDataSource,
        _ragRetriever = ragRetriever;

  @override
  Future<RetrievalResult> retrieveContext({
    required LlmConfig config,
    required String query,
    required List<DocumentEntity> documents,
    required AnalysisMode mode,
  }) async {
    List<double>? queryEmbedding;

    final hasAnyEmbeddings = documents.any(
      (doc) => doc.chunks.any((c) => c.embedding != null),
    );
    if (config.hasApiKey && hasAnyEmbeddings && mode == AnalysisMode.qa) {
      queryEmbedding = await _remoteDataSource.generateEmbedding(
        config: config,
        text: query,
      );
    }

    return _ragRetriever.retrieve(
      query: query,
      documents: documents,
      mode: mode,
      queryEmbedding: queryEmbedding,
    );
  }

  @override
  Stream<String> streamChatResponse({
    required LlmConfig config,
    required AnalysisMode mode,
    required RetrievalResult retrievalResult,
    required List<ChatMessageEntity> history,
    required String userPrompt,
    CancelToken? cancelToken,
  }) async* {
    final userTokens = TokenEstimator.estimateTokens(userPrompt);
    final baseSystemTokens =
        TokenEstimator.estimateTokens(SystemPrompts.getPromptForMode(mode));

    // Если сам пользовательский промт превышает лимит контекстного окна модели
    if (userTokens + baseSystemTokens > EnvConfig.maxPromptTokenBudget) {
      throw TokenLimitExceededException(
        estimatedTokens: userTokens + baseSystemTokens,
        maxAllowedTokens: EnvConfig.maxPromptTokenBudget,
      );
    }

    // 1. Усекаем историю диалога до безопасного бюджета (до 12 000 токенов)
    final trimmedHistory = TokenEstimator.trimHistoryToBudget(
      history,
      maxHistoryTokens: 12000,
    );
    final historyTokens = trimmedHistory.fold<int>(
      0,
      (sum, m) => sum + TokenEstimator.estimateTokens(m.content),
    );

    // 2. Вычисляем оставшийся бюджет токенов под фрагменты документа
    final remainingContextBudget = EnvConfig.maxPromptTokenBudget -
        userTokens -
        baseSystemTokens -
        historyTokens -
        500;

    final fittedChunks = TokenEstimator.fitChunksToBudget(
      retrievalResult.selectedChunks,
      availableTokens: remainingContextBudget,
    );

    final systemPromptWithContext = SystemPrompts.buildSystemPromptWithContext(
      mode: mode,
      chunks: fittedChunks,
      isFullDocumentContext: retrievalResult.isFullDocumentContext &&
          fittedChunks.length == retrievalResult.selectedChunks.length,
    );

    yield* _remoteDataSource.streamChatCompletion(
      config: config,
      systemPromptWithContext: systemPromptWithContext,
      history: trimmedHistory,
      userPrompt: userPrompt,
      mode: mode,
      retrievedChunks: fittedChunks,
      cancelToken: cancelToken,
    );
  }

  @override
  Future<List<DocumentChunkEntity>> enrichChunksWithEmbeddings({
    required LlmConfig config,
    required List<DocumentChunkEntity> chunks,
  }) async {
    if (!config.hasApiKey || chunks.isEmpty) return chunks;

    final updated = <DocumentChunkEntity>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      if (i < 40 && chunk.embedding == null) {
        final vector = await _remoteDataSource.generateEmbedding(
          config: config,
          text: chunk.content,
        );
        updated.add(chunk.copyWith(embedding: vector));
      } else {
        updated.add(chunk);
      }
    }
    return updated;
  }
}
