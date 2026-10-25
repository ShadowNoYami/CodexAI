import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/utils/isolate_runner.dart';
import '../../../../core/utils/token_estimator.dart';
import '../models/document_chunk_model.dart';
import 'document_parser_service.dart';

/// Провайдер сервиса семантического разбиения текста на чанки.
final textChunkerServiceProvider = Provider<TextChunkerService>((ref) {
  return const TextChunkerService();
});

/// Сервис разбиения постраничного текста документа на смысловые фрагменты (chunks)
/// с перекрытием (overlap) для сохранения контекста на границах абзацев.
class TextChunkerService {
  const TextChunkerService();

  /// Асинхронно разбивает список страниц [pages] на чанки в фоновом изоляте.
  Future<List<DocumentChunkModel>> createChunks({
    required String documentId,
    required String documentName,
    required List<ParsedPage> pages,
    int maxChunkChars = EnvConfig.defaultChunkSizeChars,
    int overlapChars = EnvConfig.defaultChunkOverlapChars,
  }) async {
    return IsolateRunner.run(() {
      return createChunksSync(
        documentId: documentId,
        documentName: documentName,
        pages: pages,
        maxChunkChars: maxChunkChars,
        overlapChars: overlapChars,
      );
    });
  }

  /// Синхронная версия чанкинга (может вызываться напрямую внутри уже запущенного изолята).
  static List<DocumentChunkModel> createChunksSync({
    required String documentId,
    required String documentName,
    required List<ParsedPage> pages,
    int maxChunkChars = EnvConfig.defaultChunkSizeChars,
    int overlapChars = EnvConfig.defaultChunkOverlapChars,
  }) {
    final chunks = <DocumentChunkModel>[];
    var globalChunkIndex = 0;

    for (final page in pages) {
      final pageText = page.text.trim();
      if (pageText.isEmpty) continue;

      if (pageText.length <= maxChunkChars) {
        chunks.add(
          DocumentChunkModel(
            id: '${documentId}_chunk_$globalChunkIndex',
            documentId: documentId,
            documentName: documentName,
            index: globalChunkIndex,
            pageNumber: page.pageNumber,
            content: pageText,
            estimatedTokens: TokenEstimator.estimateTokens(pageText),
          ),
        );
        globalChunkIndex++;
        continue;
      }

      // Если страница превышает размер одного чанка — режем по смысловым границам с перекрытием
      var start = 0;
      while (start < pageText.length) {
        var end = start + maxChunkChars;
        if (end >= pageText.length) {
          end = pageText.length;
        } else {
          end = _findSemanticSplitIndex(pageText, start, end);
        }

        final segment = pageText.substring(start, end).trim();
        if (segment.isNotEmpty) {
          chunks.add(
            DocumentChunkModel(
              id: '${documentId}_chunk_$globalChunkIndex',
              documentId: documentId,
              documentName: documentName,
              index: globalChunkIndex,
              pageNumber: page.pageNumber,
              content: segment,
              estimatedTokens: TokenEstimator.estimateTokens(segment),
            ),
          );
          globalChunkIndex++;
        }

        if (end >= pageText.length) break;

        final nextStart = end - overlapChars;
        start = nextStart > start ? _alignToWordStart(pageText, nextStart) : end;
      }
    }

    return chunks;
  }

  /// Находит ближайшую естественную границу текста (абзац, перенос строки, конец предложения, пробел).
  static int _findSemanticSplitIndex(String text, int start, int targetEnd) {
    final minAcceptableEnd = start + ((targetEnd - start) * 0.55).round();

    // 1. Двойной перенос строки (граница абзаца)
    final paraBreak = text.lastIndexOf('\n\n', targetEnd);
    if (paraBreak >= minAcceptableEnd) return paraBreak;

    // 2. Одиночный перенос строки (граница строки / таблицы)
    final lineBreak = text.lastIndexOf('\n', targetEnd);
    if (lineBreak >= minAcceptableEnd) return lineBreak;

    // 3. Конец предложения (. / ! / ?)
    for (var i = targetEnd; i >= minAcceptableEnd; i--) {
      final char = text[i - 1];
      final nextChar = i < text.length ? text[i] : ' ';
      if ((char == '.' || char == '!' || char == '?') &&
          (nextChar == ' ' || nextChar == '\n')) {
        return i;
      }
    }

    // 4. Ближайший пробел
    final spaceBreak = text.lastIndexOf(' ', targetEnd);
    if (spaceBreak >= minAcceptableEnd) return spaceBreak;

    return targetEnd;
  }

  /// Выравнивает начало перекрывающегося фрагмента по началу слова.
  static int _alignToWordStart(String text, int index) {
    var i = index;
    while (i < text.length && text[i] != ' ' && text[i] != '\n') {
      i++;
    }
    while (i < text.length && (text[i] == ' ' || text[i] == '\n')) {
      i++;
    }
    return i < text.length ? i : index;
  }
}
