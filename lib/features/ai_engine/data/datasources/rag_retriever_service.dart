import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/utils/isolate_runner.dart';
import '../../../documents/domain/entities/document_chunk_entity.dart';
import '../../../documents/domain/entities/document_entity.dart';
import '../../domain/entities/analysis_mode.dart';
import '../../domain/entities/cited_source.dart';

/// Результат выборки контекста (Adaptive Full-Context + Hybrid RAG).
class RetrievalResult {
  final List<DocumentChunkEntity> selectedChunks;
  final List<CitedSource> citations;
  final bool isFullDocumentContext;
  final int totalSelectedTokens;

  const RetrievalResult({
    required this.selectedChunks,
    required this.citations,
    required this.isFullDocumentContext,
    required this.totalSelectedTokens,
  });
}

/// Провайдер сервиса гибридного поиска (BM25 + Cosine Similarity).
final ragRetrieverServiceProvider = Provider<RagRetrieverService>((ref) {
  return const RagRetrieverService();
});

/// Клиентский гибридный RAG-ретривер:
/// совмещает лексический поиск (BM25 с поддержкой русских и английских основ слов и чисел)
/// и векторное косинусное сходство (Cosine Similarity), а также адаптивный Full-Context режим.
class RagRetrieverService {
  const RagRetrieverService();

  /// Выбирает оптимальный набор чанков и источников для ответа на запрос [query].
  Future<RetrievalResult> retrieve({
    required String query,
    required List<DocumentEntity> documents,
    required AnalysisMode mode,
    List<double>? queryEmbedding,
    int topK = EnvConfig.defaultRagTopK,
  }) async {
    final readyDocs = documents.where((d) => d.isReady).toList();
    if (readyDocs.isEmpty) {
      return const RetrievalResult(
        selectedChunks: [],
        citations: [],
        isFullDocumentContext: true,
        totalSelectedTokens: 0,
      );
    }

    final allChunks = <DocumentChunkEntity>[
      for (final doc in readyDocs) ...doc.chunks,
    ];

    if (allChunks.isEmpty) {
      return const RetrievalResult(
        selectedChunks: [],
        citations: [],
        isFullDocumentContext: true,
        totalSelectedTokens: 0,
      );
    }

    final totalDocTokens = readyDocs.fold<int>(
      0,
      (sum, doc) => sum + doc.estimatedTokens,
    );

    return IsolateRunner.run(() {
      // Ранжируем все чанки по гибридному скору (BM25 + Cosine Similarity)
      final scoredChunks = _scoreChunksSync(
        query: query,
        chunks: allChunks,
        queryEmbedding: queryEmbedding,
      );

      // Формируем топ источников для отображения в UI (до 5 наиболее релевантных цитат)
      final topCitations = scoredChunks
          .take(math.min(5, scoredChunks.length))
          .map(
            (item) => CitedSource(
              documentId: item.chunk.documentId,
              documentName: item.chunk.documentName,
              chunkId: item.chunk.id,
              chunkIndex: item.chunk.index,
              pageNumber: item.chunk.pageNumber,
              excerpt: _buildExcerpt(item.chunk.content, query),
              relevanceScore: item.score,
            ),
          )
          .toList();

      // Адаптивное решение:
      // 1) Если общий объем документов <= 30 000 токенов
      // 2) Или выбран глобальный режим (Executive Summary / Deep Analysis) и объем в рамках бюджета
      final useFullContext =
          totalDocTokens <= EnvConfig.fullContextTokenThreshold ||
              (mode != AnalysisMode.qa &&
                  totalDocTokens <= EnvConfig.maxPromptTokenBudget);

      if (useFullContext) {
        final budgetedChunks = <DocumentChunkEntity>[];
        var accumulatedTokens = 0;
        for (final chunk in allChunks) {
          if (accumulatedTokens + chunk.estimatedTokens >
              EnvConfig.maxPromptTokenBudget) {
            break;
          }
          budgetedChunks.add(chunk);
          accumulatedTokens += chunk.estimatedTokens;
        }

        return RetrievalResult(
          selectedChunks: budgetedChunks,
          citations: topCitations,
          isFullDocumentContext: true,
          totalSelectedTokens: accumulatedTokens,
        );
      }

      // Иначе — классический гибридный RAG (Top-K наиболее релевантных чанков)
      final selectedTopK = scoredChunks
          .take(math.min(topK, scoredChunks.length))
          .map((e) => e.chunk)
          .toList();

      // Сортируем выбранные чанки в порядке следования в документе для связного чтения моделью
      selectedTopK.sort((a, b) {
        final docCmp = a.documentId.compareTo(b.documentId);
        if (docCmp != 0) return docCmp;
        return a.index.compareTo(b.index);
      });

      final ragTokens = selectedTopK.fold<int>(
        0,
        (sum, c) => sum + c.estimatedTokens,
      );

      return RetrievalResult(
        selectedChunks: selectedTopK,
        citations: topCitations,
        isFullDocumentContext: false,
        totalSelectedTokens: ragTokens,
      );
    });
  }

  static List<_ScoredChunk> _scoreChunksSync({
    required String query,
    required List<DocumentChunkEntity> chunks,
    List<double>? queryEmbedding,
  }) {
    final queryTokens = _tokenize(query);
    if (queryTokens.isEmpty && queryEmbedding == null) {
      return chunks
          .map((c) => _ScoredChunk(chunk: c, score: 1.0))
          .toList(growable: false);
    }

    // Подготовка статистик BM25
    final docTokenLists =
        chunks.map((c) => _tokenize(c.content)).toList(growable: false);
    final totalDocs = chunks.length;
    final avgDocLen = docTokenLists.isEmpty
        ? 1.0
        : docTokenLists.fold<int>(0, (s, list) => s + list.length) / totalDocs;

    // Частота встречаемости термов запроса в чанках (Document Frequency)
    final docFreq = <String, int>{};
    for (final term in queryTokens.toSet()) {
      var df = 0;
      for (final tokens in docTokenLists) {
        if (tokens.contains(term)) df++;
      }
      docFreq[term] = df;
    }

    const k1 = 1.5;
    const b = 0.75;

    final rawBm25 = List<double>.filled(totalDocs, 0.0);
    var maxBm25 = 0.0;

    for (var i = 0; i < totalDocs; i++) {
      final tokens = docTokenLists[i];
      if (tokens.isEmpty) continue;

      final termCounts = <String, int>{};
      for (final t in tokens) {
        termCounts[t] = (termCounts[t] ?? 0) + 1;
      }

      var score = 0.0;
      for (final qTerm in queryTokens) {
        final tf = termCounts[qTerm] ?? 0;
        if (tf == 0) continue;

        final df = docFreq[qTerm] ?? 0;
        final idf = math.log(1.0 + (totalDocs - df + 0.5) / (df + 0.5));
        final numerator = tf * (k1 + 1.0);
        final denominator =
            tf + k1 * (1.0 - b + b * (tokens.length / avgDocLen));
        score += idf * (numerator / denominator);
      }

      rawBm25[i] = score;
      if (score > maxBm25) maxBm25 = score;
    }

    final scored = <_ScoredChunk>[];
    for (var i = 0; i < totalDocs; i++) {
      final chunk = chunks[i];
      final normalizedBm25 = maxBm25 > 0 ? (rawBm25[i] / maxBm25) : 0.0;

      double cosineScore = 0.0;
      if (queryEmbedding != null &&
          chunk.embedding != null &&
          chunk.embedding!.length == queryEmbedding.length) {
        cosineScore = _cosineSimilarity(queryEmbedding, chunk.embedding!);
      }

      final combinedScore = (queryEmbedding != null && chunk.embedding != null)
          ? (0.45 * normalizedBm25 + 0.55 * cosineScore)
          : normalizedBm25;

      scored.add(_ScoredChunk(chunk: chunk, score: combinedScore));
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.chunk.index.compareTo(b.chunk.index);
    });

    return scored;
  }

  /// Токенизация текста с нормализацией регистра и легким стеммингом окончаний RU/EN.
  static List<String> _tokenize(String text) {
    final lower = text.toLowerCase().replaceAll('ё', 'е');
    final matches = RegExp(r'[a-zа-я0-9]{2,}').allMatches(lower);
    final result = <String>[];

    for (final m in matches) {
      final word = m.group(0)!;
      if (_stopWords.contains(word)) continue;
      result.add(_lightStem(word));
    }
    return result;
  }

  static String _lightStem(String word) {
    if (word.length <= 4) return word;
    // Усечение типичных русских и английских флексий для улучшения полноты поиска (Recall)
    final stem = word.replaceFirst(
      RegExp(
        r'(ами|ями|ого|его|ому|ему|ыми|ими|ах|ях|ов|ев|ей|ий|ый|ая|яя|ое|ее|ые|ие|ую|юю|ам|ям|ом|ем|ин|ing|ed|es|tion|ment|s)$',
      ),
      '',
    );
    return stem.length >= 3 ? stem : word;
  }

  static double _cosineSimilarity(List<double> a, List<double> b) {
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0.0 || normB <= 0.0) return 0.0;
    return (dot / (math.sqrt(normA) * math.sqrt(normB))).clamp(0.0, 1.0);
  }

  /// Формирует аккуратную цитату (excerpt) длиной до 240 символов вокруг найденных ключевых слов.
  static String _buildExcerpt(String content, String query) {
    final cleaned = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 240) return cleaned;

    final queryTerms = _tokenize(query);
    final lowerCleaned = cleaned.toLowerCase();

    var bestPos = 0;
    for (final term in queryTerms) {
      final idx = lowerCleaned.indexOf(term);
      if (idx != -1) {
        bestPos = idx;
        break;
      }
    }

    final start = math.max(0, bestPos - 60);
    final end = math.min(cleaned.length, start + 240);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < cleaned.length ? '…' : '';
    return '$prefix${cleaned.substring(start, end).trim()}$suffix';
  }

  static const Set<String> _stopWords = {
    'и',
    'в',
    'во',
    'не',
    'что',
    'он',
    'на',
    'я',
    'с',
    'со',
    'как',
    'а',
    'то',
    'все',
    'она',
    'так',
    'его',
    'но',
    'да',
    'ты',
    'к',
    'у',
    'же',
    'вы',
    'за',
    'бы',
    'по',
    'только',
    'ее',
    'мне',
    'было',
    'вот',
    'от',
    'меня',
    'еще',
    'нет',
    'о',
    'из',
    'ему',
    'теперь',
    'когда',
    'даже',
    'ну',
    'вдруг',
    'ли',
    'если',
    'уже',
    'или',
    'ни',
    'быть',
    'был',
    'него',
    'до',
    'вас',
    'нибудь',
    'для',
    'при',
    'об',
    'этот',
    'эта',
    'это',
    'эти',
    'the',
    'and',
    'for',
    'that',
    'with',
    'this',
    'from',
    'are',
    'was',
    'were',
  };
}

class _ScoredChunk {
  final DocumentChunkEntity chunk;
  final double score;

  const _ScoredChunk({
    required this.chunk,
    required this.score,
  });
}
