import 'package:dio/dio.dart';

import '../../../chat/domain/entities/chat_message_entity.dart';
import '../../../documents/domain/entities/document_chunk_entity.dart';
import '../../../documents/domain/entities/document_entity.dart';
import '../../data/datasources/rag_retriever_service.dart';
import '../entities/analysis_mode.dart';

/// Контракт репозитория ИИ и аналитического RAG-движка (Domain-слой).
abstract interface class AiRepository {
  /// Выбирает релевантные чанки и формирует список цитируемых источников (`CitedSource`)
  /// с использованием адаптивного гибридного подхода (Full-Context + BM25/Cosine RAG).
  Future<RetrievalResult> retrieveContext({
    required LlmConfig config,
    required String query,
    required List<DocumentEntity> documents,
    required AnalysisMode mode,
  });

  /// Стримит ответ LLM токенами в реальном времени с учетом выбранного режима [mode],
  /// системного промта, истории чата и найденного контекста документа.
  Stream<String> streamChatResponse({
    required LlmConfig config,
    required AnalysisMode mode,
    required RetrievalResult retrievalResult,
    required List<ChatMessageEntity> history,
    required String userPrompt,
    CancelToken? cancelToken,
  });

  /// Опциональное обогащение чанков документа векторными эмбеддингами.
  Future<List<DocumentChunkEntity>> enrichChunksWithEmbeddings({
    required LlmConfig config,
    required List<DocumentChunkEntity> chunks,
  });
}
