import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../ai_engine/domain/entities/analysis_mode.dart';
import 'document_parser_service.dart';

/// Провайдер сервиса оптического распознавания текста (Vision OCR) для фото и сканов документов (включая скан-PDF).
final imageOcrServiceProvider = Provider<ImageOcrService>((ref) {
  return ImageOcrService(dio: ref.watch(dioClientProvider));
});

/// Сервис распознавания текста и таблиц с фотографий (JPG, PNG, WEBP) и отсканированных PDF-документов
/// с использованием мультимодальной модели Gemini Vision (`gemini-3.5-flash`).
class ImageOcrService {
  final Dio _dio;

  const ImageOcrService({required Dio dio}) : _dio = dio;

  static const String _ocrPrompt = '''
Ты — профессиональная система оптического распознавания документов (Vision OCR).
Перед тобой фотография или скан документа.

Твоя задача:
1. Извлеки ВЕСЬ видимый текст максимально точно, сохраняя структуру заголовков, списков и абзацев.
2. Если на страницах есть таблицы, чеки, прайс-листы или ведомости — преобразуй их в аккуратную Markdown-таблицу (`| Столбец 1 | Столбец 2 |`).
3. Сохраняй все цифры, даты, суммы, номера договоров, ИНН, артикулы и ФИО со 100% точностью.
4. Если документ многостраничный, разделяй страницы маркером `=== СТРАНИЦА N ===` (где N — номер страницы).
5. Выводи ТОЛЬКО распознанный текст документа в формате Markdown без вводных комментариев от себя.
''';

  /// Распознает текст с фотографии или скана (JPG, PNG, WEBP).
  Future<ParsedDocumentResult> extractTextFromImage({
    required String fileName,
    required String extension,
    required Uint8List bytes,
    required LlmConfig config,
  }) async {
    final mimeType = _resolveMimeType(extension);
    final base64Image = base64Encode(bytes);

    if (!config.hasApiKey) {
      throw DocumentParseException(
        'Для OCR-распознавания фото/сканов требуется API-ключ Gemini или OpenAI.',
        fileName: fileName,
      );
    }

    final String extractedText;
    if (config.provider == LlmProviderType.gemini) {
      extractedText = await _recognizeWithGeminiMultimodal(
        config: config,
        parts: [
          {'text': _ocrPrompt},
          {
            'inlineData': {
              'mimeType': mimeType,
              'data': base64Image,
            },
          },
        ],
        fileName: fileName,
      );
    } else {
      extractedText = await _recognizeWithOpenAiVision(
        config: config,
        mimeType: mimeType,
        base64Image: base64Image,
        fileName: fileName,
      );
    }

    final cleaned = extractedText.trim();
    if (cleaned.isEmpty) {
      throw DocumentParseException(
        'На изображении "$fileName" не удалось распознать текст. Попробуйте сделать более четкое фото.',
        fileName: fileName,
      );
    }

    final page = ParsedPage(pageNumber: 1, text: cleaned);
    final fullText = '--- [Скан / Фото: $fileName (Страница 1)] ---\n$cleaned';

    return ParsedDocumentResult(
      pages: [page],
      fullText: fullText,
      pageCount: 1,
    );
  }

  /// Распознает текст из отсканированного PDF-документа (где отсутствует текстовый слой)
  /// с помощью мультимодального Gemini Vision OCR (`application/pdf` или извлечение JPEG-страниц).
  Future<ParsedDocumentResult> extractTextFromScannedPdf({
    required String fileName,
    required Uint8List bytes,
    required int totalPageCount,
    required LlmConfig config,
  }) async {
    if (!config.hasApiKey) {
      throw DocumentParseException(
        'PDF "$fileName" является сканом без текстового слоя. Для его OCR-распознавания укажите API-ключ в настройках.',
        fileName: fileName,
      );
    }

    String extractedText = '';

    // Вариант 1: Если размер PDF до 14 МБ, отправляем весь PDF-контейнер напрямую в Gemini (application/pdf)
    if (bytes.lengthInBytes <= 14 * 1024 * 1024) {
      try {
        extractedText = await _recognizeWithGeminiMultimodal(
          config: config,
          parts: [
            {
              'text':
                  '$_ocrPrompt\nЭто отсканированный PDF-документ "$fileName" ($totalPageCount стр.). Извлеки текст и основные положения со страниц документа, разделяя их маркером `=== СТРАНИЦА N ===`.',
            },
            {
              'inlineData': {
                'mimeType': 'application/pdf',
                'data': base64Encode(bytes),
              },
            },
          ],
          fileName: fileName,
        );
      } catch (_) {
        // Если прямой PDF превысил лимит страниц Gemini, переходим к извлечению встроенных JPEG-сканов
        extractedText = '';
      }
    }

    // Вариант 2: Для тяжелых скан-книг (> 14 МБ или многостраничных сканов) извлекаем встроенные JPEG-страницы из потока PDF
    if (extractedText.trim().isEmpty) {
      final embeddedJpegs = _extractEmbeddedJpegsFromPdf(
        bytes,
        maxImages: 15,
        maxTotalBytes: 12 * 1024 * 1024,
      );

      if (embeddedJpegs.isNotEmpty) {
        final parts = <Map<String, dynamic>>[
          {
            'text':
                '$_ocrPrompt\nПеред тобой отсканированные страницы из PDF-книги/документа "$fileName" (показаны первые ${embeddedJpegs.length} отсканированных страниц из $totalPageCount). Распознай весь текст с каждой страницы и разделяй страницы маркером `=== СТРАНИЦА N ===`.',
          },
          for (final jpeg in embeddedJpegs)
            {
              'inlineData': {
                'mimeType': 'image/jpeg',
                'data': base64Encode(jpeg),
              },
            },
        ];

        extractedText = await _recognizeWithGeminiMultimodal(
          config: config,
          parts: parts,
          fileName: fileName,
        );
      }
    }

    final cleaned = extractedText.trim();
    if (cleaned.isEmpty) {
      throw DocumentParseException(
        'Документ "$fileName" является сканом без текстового слоя, и не удалось автоматически извлечь изображения страниц для OCR.',
        fileName: fileName,
      );
    }

    final pages = _splitOcrTextIntoPages(cleaned);
    final buffer = StringBuffer();
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      buffer.writeln('--- [Страница ${p.pageNumber} (OCR)] ---');
      buffer.writeln(p.text);
      if (i < pages.length - 1) buffer.writeln();
    }

    return ParsedDocumentResult(
      pages: pages,
      fullText: buffer.toString().trim(),
      pageCount: totalPageCount > pages.length ? totalPageCount : pages.length,
    );
  }

  /// Разбивает распознанный OCR-текст с маркерами `=== СТРАНИЦА N ===` на список [ParsedPage].
  List<ParsedPage> _splitOcrTextIntoPages(String ocrText) {
    final pageRegex = RegExp(
      r'===\s*СТРАНИЦА\s*(\d+)\s*===',
      caseSensitive: false,
    );
    final matches = pageRegex.allMatches(ocrText).toList();

    if (matches.isEmpty) {
      // Если модель вернула единый текст без маркеров — делим на логические страницы по 3000 символов
      const pageLen = 3000;
      final pages = <ParsedPage>[];
      var pageNum = 1;
      for (var i = 0; i < ocrText.length; i += pageLen) {
        final end =
            (i + pageLen < ocrText.length) ? i + pageLen : ocrText.length;
        pages.add(
          ParsedPage(
            pageNumber: pageNum++,
            text: ocrText.substring(i, end).trim(),
          ),
        );
      }
      return pages;
    }

    final pages = <ParsedPage>[];
    for (var i = 0; i < matches.length; i++) {
      final currentMatch = matches[i];
      final pageNum = int.tryParse(currentMatch.group(1) ?? '') ?? (i + 1);
      final start = currentMatch.end;
      final end =
          (i + 1 < matches.length) ? matches[i + 1].start : ocrText.length;
      final content = ocrText.substring(start, end).trim();
      if (content.isNotEmpty) {
        pages.add(ParsedPage(pageNumber: pageNum, text: content));
      }
    }

    return pages.isEmpty
        ? [ParsedPage(pageNumber: 1, text: ocrText)]
        : pages;
  }

  /// Быстрое извлечение встроенных JPEG-изображений (`DCTDecode` / `FF D8 FF ... FF D9`)
  /// из бинарного потока отсканированного PDF-файла.
  List<Uint8List> _extractEmbeddedJpegsFromPdf(
    Uint8List pdfBytes, {
    int maxImages = 15,
    int maxTotalBytes = 12 * 1024 * 1024,
  }) {
    final extracted = <Uint8List>[];
    var accumulatedBytes = 0;
    final len = pdfBytes.length;

    var i = 0;
    while (i < len - 4 &&
        extracted.length < maxImages &&
        accumulatedBytes < maxTotalBytes) {
      // Ищем заголовок JPEG SOI: FF D8 FF (0xFF 0xD8 0xFF)
      if (pdfBytes[i] == 0xFF &&
          pdfBytes[i + 1] == 0xD8 &&
          pdfBytes[i + 2] == 0xFF) {
        final start = i;
        var end = -1;
        // Ищем маркер конца JPEG EOI: FF D9 (начиная хотя бы через 2 КБ, чтобы пропустить мини-превью)
        var j = start + 2048;
        if (j >= len - 1) break;

        while (j < len - 1) {
          if (pdfBytes[j] == 0xFF && pdfBytes[j + 1] == 0xD9) {
            end = j + 2;
            break;
          }
          j++;
        }

        if (end != -1) {
          final jpegLen = end - start;
          // Берем только полноценные сканы страниц (от 4 КБ до 4 МБ на страницу)
          if (jpegLen >= 4096 && jpegLen <= 4 * 1024 * 1024) {
            final slice = Uint8List.sublistView(pdfBytes, start, end);
            extracted.add(slice);
            accumulatedBytes += jpegLen;
          }
          i = end;
          continue;
        }
      }
      i++;
    }

    return extracted;
  }

  Future<String> _recognizeWithGeminiMultimodal({
    required LlmConfig config,
    required List<Map<String, dynamic>> parts,
    required String fileName,
  }) async {
    final baseUrl = config.baseUrl.replaceAll(RegExp(r'/$'), '');
    final candidateModels = <String>{
      config.model.trim(),
      ...EnvConfig.geminiFallbackModels,
    }.where((m) => m.isNotEmpty).toList();

    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': parts,
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 8192,
      },
    };

    DioException? lastError;

    for (final modelName in candidateModels) {
      final url =
          '$baseUrl/models/$modelName:generateContent?key=${config.apiKey.trim()}';
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: jsonEncode(body),
        );

        final candidates = response.data?['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) continue;

        final content = (candidates.first as Map<String, dynamic>)['content']
            as Map<String, dynamic>?;
        final respParts = content?['parts'] as List<dynamic>?;
        if (respParts == null || respParts.isEmpty) continue;

        final buffer = StringBuffer();
        for (final p in respParts) {
          final text = (p as Map<String, dynamic>)['text'] as String?;
          if (text != null) buffer.write(text);
        }

        if (buffer.isNotEmpty) {
          return buffer.toString();
        }
      } on DioException catch (e) {
        lastError = e;
        final code = e.response?.statusCode;
        if (code == 404 || code == 503) continue;
        break;
      }
    }

    throw DocumentParseException(
      'Ошибка Vision OCR при распознавании "$fileName": ${lastError?.message ?? "Неизвестная ошибка API"}',
      fileName: fileName,
      cause: lastError,
    );
  }

  Future<String> _recognizeWithOpenAiVision({
    required LlmConfig config,
    required String mimeType,
    required String base64Image,
    required String fileName,
  }) async {
    final baseUrl = config.baseUrl.replaceAll(RegExp(r'/$'), '');
    final url = '$baseUrl/chat/completions';

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        url,
        data: jsonEncode({
          'model': config.model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': _ocrPrompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mimeType;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'temperature': 0.1,
        }),
        options: Options(
          headers: {'Authorization': 'Bearer ${config.apiKey.trim()}'},
        ),
      );

      final choices = response.data?['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return '';
      final msg = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      return msg?['content'] as String? ?? '';
    } catch (e, st) {
      throw DocumentParseException(
        'Ошибка распознавания изображения "$fileName": $e',
        fileName: fileName,
        cause: e,
        stackTrace: st,
      );
    }
  }

  String _resolveMimeType(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
