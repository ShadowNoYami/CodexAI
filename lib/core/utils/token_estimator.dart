import '../../features/chat/domain/entities/chat_message_entity.dart';
import '../../features/documents/domain/entities/document_chunk_entity.dart';

/// Утилита для быстрой оценки количества токенов и контроля лимитов контекстного окна.
///
/// Используется для принятия решения между Full-Context Stuffing и гибридным RAG,
/// а также для предотвращения ошибок переполнения контекстного окна LLM.
class TokenEstimator {
  const TokenEstimator._();

  /// Оценивает количество токенов в строке [text].
  ///
  /// Для латиницы в среднем ~3.8 символа на токен, для кириллицы в современных
  /// токенизаторах (Gemini / Tiktoken o200k) ~2.8 символа на токен.
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;

    int cyrillicCount = 0;
    final codeUnits = text.codeUnits;
    for (var i = 0; i < codeUnits.length; i++) {
      final unit = codeUnits[i];
      if (unit >= 0x0400 && unit <= 0x04FF) {
        cyrillicCount++;
      }
    }

    final nonCyrillicCount = text.length - cyrillicCount;
    final estimated = (cyrillicCount / 2.8) + (nonCyrillicCount / 3.8);
    return estimated.ceil();
  }

  /// Усекает историю сообщений чата с конца (сохраняя самые свежие реплики),
  /// чтобы суммарный объем истории не превышал [maxHistoryTokens].
  static List<ChatMessageEntity> trimHistoryToBudget(
    List<ChatMessageEntity> history, {
    int maxHistoryTokens = 12000,
    int maxMessages = 12,
  }) {
    final validMessages = history
        .where((m) => m.content.trim().isNotEmpty && !m.hasError)
        .toList();
    if (validMessages.isEmpty) return const [];

    final selectedReversed = <ChatMessageEntity>[];
    var usedTokens = 0;

    for (var i = validMessages.length - 1; i >= 0; i--) {
      if (selectedReversed.length >= maxMessages) break;
      final msg = validMessages[i];
      final msgTokens = estimateTokens(msg.content) + 12;
      if (usedTokens + msgTokens > maxHistoryTokens &&
          selectedReversed.isNotEmpty) {
        break;
      }
      selectedReversed.add(msg);
      usedTokens += msgTokens;
    }

    return selectedReversed.reversed.toList(growable: false);
  }

  /// Ограничивает список чанков документа так, чтобы они гарантированно поместились
  /// в выделенный бюджет [availableTokens].
  static List<DocumentChunkEntity> fitChunksToBudget(
    List<DocumentChunkEntity> chunks, {
    required int availableTokens,
  }) {
    if (chunks.isEmpty || availableTokens <= 0) return const [];

    final fitted = <DocumentChunkEntity>[];
    var usedTokens = 0;

    for (final chunk in chunks) {
      final chunkCost = chunk.estimatedTokens + 24; // +24 токена на XML-теги <source>
      if (usedTokens + chunkCost > availableTokens) {
        // Если даже первый чанк слишком велик, усекаем его текст под бюджет
        if (fitted.isEmpty && availableTokens > 150) {
          final maxChars = (availableTokens * 2.6).floor();
          final truncatedText = chunk.content.length > maxChars
              ? '${chunk.content.substring(0, maxChars)}…'
              : chunk.content;
          fitted.add(
            chunk.copyWith(
              content: truncatedText,
              estimatedTokens: estimateTokens(truncatedText),
            ),
          );
        }
        break;
      }
      fitted.add(chunk);
      usedTokens += chunkCost;
    }

    return fitted;
  }
}
