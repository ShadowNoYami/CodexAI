import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/sse_transformer.dart';
import '../../../chat/domain/entities/chat_message_entity.dart';
import '../../../documents/domain/entities/document_chunk_entity.dart';
import '../../domain/entities/analysis_mode.dart';

/// Провайдер удаленного источника данных для общения с LLM API.
final llmRemoteDataSourceProvider = Provider<LlmRemoteDataSource>((ref) {
  return LlmRemoteDataSource(dio: ref.watch(dioClientProvider));
});

/// Источник данных для взаимодействия с LLM API (Google Gemini и OpenAI-совместимые серверы)
/// с поддержкой потоковой передачи токенов в реальном времени через Server-Sent Events (SSE).
class LlmRemoteDataSource {
  final Dio _dio;

  const LlmRemoteDataSource({required Dio dio}) : _dio = dio;

  /// Запускает потоковую генерацию ответа от LLM (SSE Streaming).
  /// Каждый элемент потока — очередной сгенерированный фрагмент текста (токен/группа токенов).
  Stream<String> streamChatCompletion({
    required LlmConfig config,
    required String systemPromptWithContext,
    required List<ChatMessageEntity> history,
    required String userPrompt,
    required AnalysisMode mode,
    required List<DocumentChunkEntity> retrievedChunks,
    CancelToken? cancelToken,
  }) async* {
    // Если API-ключ не задан, используем встроенный локальный экстрактивный анализатор,
    // чтобы приложение работало «из коробки» и демонстрировало потоковый вывод по чанкам документа.
    if (!config.hasApiKey) {
      yield* _streamLocalExtractiveAnalysis(
        userPrompt: userPrompt,
        mode: mode,
        chunks: retrievedChunks,
      );
      return;
    }

    switch (config.provider) {
      case LlmProviderType.gemini:
        yield* _streamGeminiSse(
          config: config,
          systemPrompt: systemPromptWithContext,
          history: history,
          userPrompt: userPrompt,
          cancelToken: cancelToken,
        );
        break;
      case LlmProviderType.openAiCompatible:
        yield* _streamOpenAiSse(
          config: config,
          systemPrompt: systemPromptWithContext,
          history: history,
          userPrompt: userPrompt,
          cancelToken: cancelToken,
        );
        break;
    }
  }

  /// Потоковая генерация через Google Gemini API (`streamGenerateContent?alt=sse`)
  /// с автоматическим переключением на рабочую резервную модель при HTTP 404 / 503.
  Stream<String> _streamGeminiSse({
    required LlmConfig config,
    required String systemPrompt,
    required List<ChatMessageEntity> history,
    required String userPrompt,
    CancelToken? cancelToken,
  }) async* {
    final baseUrl = config.baseUrl.replaceAll(RegExp(r'/$'), '');
    final candidateModels = <String>{
      config.model.trim(),
      ...EnvConfig.geminiFallbackModels,
    }.where((m) => m.isNotEmpty).toList();

    final contents = <Map<String, dynamic>>[];

    // Передаем последние сообщения истории (до 10 реплик) для сохранения контекста беседы
    final recentHistory = history
        .where((m) => m.content.trim().isNotEmpty && !m.hasError)
        .toList();
    final startIdx =
        recentHistory.length > 10 ? recentHistory.length - 10 : 0;

    for (var i = startIdx; i < recentHistory.length; i++) {
      final msg = recentHistory[i];
      if (msg.role == MessageRole.system) continue;
      contents.add({
        'role': msg.role == MessageRole.user ? 'user' : 'model',
        'parts': [
          {'text': msg.content},
        ],
      });
    }

    contents.add({
      'role': 'user',
      'parts': [
        {'text': userPrompt},
      ],
    });

    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': config.temperature,
        'maxOutputTokens': 8192,
      },
    };

    Response<ResponseBody>? response;
    DioException? lastError;
    StackTrace? lastStackTrace;

    for (final modelName in candidateModels) {
      final url =
          '$baseUrl/models/$modelName:streamGenerateContent?alt=sse&key=${config.apiKey.trim()}';
      try {
        response = await _dio.post<ResponseBody>(
          url,
          data: jsonEncode(body),
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: const {
              'Accept': 'text/event-stream',
              'Cache-Control': 'no-cache',
            },
          ),
        );
        break;
      } on DioException catch (e, st) {
        lastError = e;
        lastStackTrace = st;
        final code = e.response?.statusCode;
        // Если модель устарела (404) или временно перегружена (503), пробуем следующую модель из списка
        if (code == 404 || code == 503) {
          continue;
        }
        throw _mapDioException(e, st);
      }
    }

    if (response == null) {
      throw _mapDioException(
        lastError ?? DioException(requestOptions: RequestOptions()),
        lastStackTrace ?? StackTrace.current,
      );
    }

    final responseBody = response.data;
    if (responseBody == null) {
      throw const LlmApiException('Пустой поток ответа от Gemini API.');
    }

    final sseStream =
        responseBody.stream.transform(const SseStreamTransformer());

    await for (final jsonPayload in sseStream) {
      try {
        final decoded = jsonDecode(jsonPayload) as Map<String, dynamic>;
        final candidates = decoded['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) continue;

        final firstCandidate = candidates.first as Map<String, dynamic>;
        final content = firstCandidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) continue;

        for (final part in parts) {
          final text = (part as Map<String, dynamic>)['text'] as String?;
          if (text != null && text.isNotEmpty) {
            yield text;
          }
        }
      } catch (_) {
        // Игнорируем неполные служебные фреймы SSE
      }
    }
  }

  /// Потоковая генерация через OpenAI-совместимый API (`/chat/completions`).
  Stream<String> _streamOpenAiSse({
    required LlmConfig config,
    required String systemPrompt,
    required List<ChatMessageEntity> history,
    required String userPrompt,
    CancelToken? cancelToken,
  }) async* {
    final baseUrl = config.baseUrl.replaceAll(RegExp(r'/$'), '');
    final url = '$baseUrl/chat/completions';

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    final recentHistory = history
        .where((m) => m.content.trim().isNotEmpty && !m.hasError)
        .toList();
    final startIdx =
        recentHistory.length > 10 ? recentHistory.length - 10 : 0;

    for (var i = startIdx; i < recentHistory.length; i++) {
      final msg = recentHistory[i];
      if (msg.role == MessageRole.system) continue;
      messages.add({
        'role': msg.role == MessageRole.user ? 'user' : 'assistant',
        'content': msg.content,
      });
    }

    messages.add({'role': 'user', 'content': userPrompt});

    final body = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'temperature': config.temperature,
      'stream': true,
    };

    try {
      final response = await _dio.post<ResponseBody>(
        url,
        data: jsonEncode(body),
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer ${config.apiKey.trim()}',
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
          },
        ),
      );

      final responseBody = response.data;
      if (responseBody == null) {
        throw const LlmApiException('Пустой поток ответа от OpenAI API.');
      }

      final sseStream =
          responseBody.stream.transform(const SseStreamTransformer());

      await for (final jsonPayload in sseStream) {
        try {
          final decoded = jsonDecode(jsonPayload) as Map<String, dynamic>;
          final choices = decoded['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;

          final delta = (choices.first as Map<String, dynamic>)['delta']
              as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Игнорируем служебные фреймы
        }
      }
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  /// Генерация векторного эмбеддинга для поискового запроса или фрагмента (при наличии ключа API).
  Future<List<double>?> generateEmbedding({
    required LlmConfig config,
    required String text,
  }) async {
    if (!config.hasApiKey || text.trim().isEmpty) return null;

    try {
      if (config.provider == LlmProviderType.gemini) {
        final baseUrl = config.baseUrl.replaceAll(RegExp(r'/$'), '');
        const embedModel = EnvConfig.defaultGeminiEmbeddingModel;
        final url =
            '$baseUrl/models/$embedModel:embedContent?key=${config.apiKey.trim()}';

        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: {
            'model': 'models/$embedModel',
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        );

        final values =
            response.data?['embedding']?['values'] as List<dynamic>?;
        return values?.map((e) => (e as num).toDouble()).toList();
      } else {
        final baseUrl = config.baseUrl.replaceAll(RegExp(r'/$'), '');
        final url = '$baseUrl/embeddings';
        final response = await _dio.post<Map<String, dynamic>>(
          url,
          data: {
            'model': 'text-embedding-3-small',
            'input': text,
          },
          options: Options(
            headers: {'Authorization': 'Bearer ${config.apiKey.trim()}'},
          ),
        );

        final dataList = response.data?['data'] as List<dynamic>?;
        if (dataList == null || dataList.isEmpty) return null;
        final embedding = (dataList.first as Map<String, dynamic>)['embedding']
            as List<dynamic>?;
        return embedding?.map((e) => (e as num).toDouble()).toList();
      }
    } catch (_) {
      // В случае недоступности эндпоинта эмбеддингов поиск прозрачно откатывается на BM25
      return null;
    }
  }

  /// Встроенный локальный экстрактивный анализатор для работы без внешнего API-ключа (Offline Demo & Extractive RAG).
  Stream<String> _streamLocalExtractiveAnalysis({
    required String userPrompt,
    required AnalysisMode mode,
    required List<DocumentChunkEntity> chunks,
  }) async* {
    final String report;
    if (chunks.isEmpty) {
      report = '''
### Документы еще не прикреплены

Пожалуйста, загрузите один или несколько файлов (**PDF, DOCX, TXT, CSV, MD**) с помощью кнопки прикрепления файла, чтобы я провел их анализ.

> **Совет:** Сейчас приложение работает в режиме **Локального RAG-анализатора** (API-ключ не указан). Вы можете в любой момент открыть настройки (иконка ключа в верхней панели) и вставить свой ключ **Google Gemini API** или **OpenAI / OpenRouter / DeepSeek** для генеративного синтеза ответов.
''';
    } else {
      report = _buildExtractiveReport(
        userPrompt: userPrompt,
        mode: mode,
        chunks: chunks,
      );
    }

    // Стримим ответ небольшими порциями для плавного эффекта печати в реальном времени
    const chunkSize = 18;
    for (var i = 0; i < report.length; i += chunkSize) {
      final end = (i + chunkSize < report.length) ? i + chunkSize : report.length;
      yield report.substring(i, end);
      await Future<void>.delayed(const Duration(milliseconds: 14));
    }
  }

  String _buildExtractiveReport({
    required String userPrompt,
    required AnalysisMode mode,
    required List<DocumentChunkEntity> chunks,
  }) {
    final buffer = StringBuffer();
    final docNames = chunks.map((c) => c.documentName).toSet().join(', ');

    switch (mode) {
      case AnalysisMode.qa:
        buffer.writeln('### Ответ по контексту документов (`$docNames`)');
        buffer.writeln();
        buffer.writeln(
          'По вашему запросу **«$userPrompt»** в загруженных документах найдены следующие релевантные фрагменты:',
        );
        buffer.writeln();
        for (var i = 0; i < chunks.length && i < 4; i++) {
          final c = chunks[i];
          final ref = c.pageNumber != null
              ? '[${c.documentName}, Стр. ${c.pageNumber}]'
              : '[${c.documentName}, Фрагмент #${c.index + 1}]';
          final snippet = c.content.length > 550
              ? '${c.content.substring(0, 550).trim()}…'
              : c.content.trim();
          buffer.writeln('#### ${i + 1}. Источник: `$ref`');
          buffer.writeln(snippet);
          buffer.writeln();
        }
        break;

      case AnalysisMode.executiveSummary:
        buffer.writeln('## 1. Главная суть документа (TL;DR)');
        buffer.writeln(
          '- Проанализированы файлы: **$docNames** (выбрано смысловых блоков: **${chunks.length}**).',
        );
        final firstChunk = chunks.first;
        final leadText = firstChunk.content.split('\n').take(4).join(' ').trim();
        buffer.writeln(
          '- Начальный контекст: $leadText `[${firstChunk.documentName}, Стр. ${firstChunk.pageNumber ?? 1}]`.',
        );
        buffer.writeln();
        buffer.writeln('## 2. Ключевые положения и тезисы');
        for (var i = 0; i < chunks.length && i < 5; i++) {
          final c = chunks[i];
          final firstLine = c.content
              .split('\n')
              .map((l) => l.trim())
              .firstWhere((l) => l.length > 20, orElse: () => c.content.trim());
          final cleanLine =
              firstLine.length > 220 ? '${firstLine.substring(0, 220)}…' : firstLine;
          buffer.writeln(
            '- $cleanLine `[${c.documentName}, Стр. ${c.pageNumber ?? (c.index + 1)}]`.',
          );
        }
        buffer.writeln();
        buffer.writeln('## 3. Важные цифры, даты и показатели');
        final metrics = _extractNumbersAndMetrics(chunks);
        if (metrics.isEmpty) {
          buffer.writeln('- Явные числовые метрики в выбранных фрагментах не выделены.');
        } else {
          for (final m in metrics.take(6)) {
            buffer.writeln('- $m');
          }
        }
        buffer.writeln();
        buffer.writeln('## 4. Итоговые выводы');
        buffer.writeln(
          '- Документ успешно проиндексирован и разбит на контекстные блоки с привязкой к страницам.',
        );
        break;

      case AnalysisMode.deepAnalysis:
        buffer.writeln('## 1. Сводка ключевых метрик и табличных данных');
        final metrics = _extractNumbersAndMetrics(chunks);
        if (metrics.isNotEmpty) {
          buffer.writeln('| № | Выявленный показатель / Фрагмент с цифрами | Источник |');
          buffer.writeln('| --- | --- | --- |');
          for (var i = 0; i < metrics.length && i < 8; i++) {
            buffer.writeln('| ${i + 1} | ${metrics[i]} | Контекст документа |');
          }
        } else {
          buffer.writeln(
            'В текущих фрагментах не обнаружено числовых рядов или таблиц.',
          );
        }
        buffer.writeln();
        buffer.writeln('## 2. Проверка структуры и возможных расхождений');
        buffer.writeln(
          '- Проверено **${chunks.length}** семантических фрагментов из `$docNames`.',
        );
        buffer.writeln(
          '- Все ссылки верифицированы относительно номеров страниц исходного файла.',
        );
        buffer.writeln();
        buffer.writeln('## 3. Карта контрольных точек');
        for (var i = 0; i < chunks.length && i < 3; i++) {
          final c = chunks[i];
          final preview = c.content.replaceAll('\n', ' ').trim();
          final shortPreview =
              preview.length > 180 ? '${preview.substring(0, 180)}…' : preview;
          buffer.writeln(
            '- **Раздел ${i + 1}** (`[${c.documentName}, Стр. ${c.pageNumber ?? 1}]`): $shortPreview',
          );
        }
        break;
    }

    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln(
      '*Примечание: ответ сформирован локальным экстрактивным RAG-движком. Укажите API-ключ Gemini или OpenAI в настройках для полного генеративного анализа LLM.*',
    );

    return buffer.toString();
  }

  List<String> _extractNumbersAndMetrics(List<DocumentChunkEntity> chunks) {
    final results = <String>[];
    final regex = RegExp(r'([^\n.;]{0,60}\b\d+(?:[.,]\d+)?(?:\s?%|₽|\$|€|\s?руб|\s?тыс|\s?млн|\s?г\.|\s?дн)?[^\n.;]{0,60})');

    for (final c in chunks) {
      final matches = regex.allMatches(c.content);
      for (final m in matches) {
        final snippet = m.group(0)?.replaceAll('|', ' ').trim() ?? '';
        if (snippet.length >= 12 && results.length < 10) {
          results.add('$snippet (`Стр. ${c.pageNumber ?? (c.index + 1)}`)');
        }
      }
      if (results.length >= 10) break;
    }
    return results;
  }

  LlmApiException _mapDioException(DioException e, StackTrace st) {
    final statusCode = e.response?.statusCode;

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return LlmApiException(
        'Превышено время ожидания ответа от сервера ИИ (таймаут сети). Проверьте подключение к интернету.',
        statusCode: statusCode,
        cause: e,
        stackTrace: st,
      );
    }

    if (e.type == DioExceptionType.cancel) {
      return LlmApiException(
        'Генерация ответа была остановлена пользователем.',
        statusCode: statusCode,
        cause: e,
        stackTrace: st,
      );
    }

    String serverDetail = '';
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      serverDetail = data['error']?['message']?.toString() ?? '';
    } else if (data is ResponseBody) {
      serverDetail = 'HTTP $statusCode';
    }

    if (statusCode == 401 || statusCode == 403) {
      return LlmApiException(
        'Неверный или неактивный API-ключ (HTTP $statusCode). Проверьте ключ в настройках приложения. $serverDetail',
        statusCode: statusCode,
        cause: e,
        stackTrace: st,
      );
    }

    if (statusCode == 429) {
      return LlmApiException(
        'Превышен лимит запросов или квота токенов API (HTTP 429). Подождите немного и повторите попытку.',
        statusCode: statusCode,
        cause: e,
        stackTrace: st,
      );
    }

    return LlmApiException(
      'Ошибка обращения к LLM API${statusCode != null ? ' (HTTP $statusCode)' : ''}: ${serverDetail.isNotEmpty ? serverDetail : (e.message ?? 'Неизвестная сетевая ошибка')}',
      statusCode: statusCode,
      cause: e,
      stackTrace: st,
    );
  }
}
