import '../../../../core/config/env_config.dart';

/// Режимы аналитической работы ИИ-бота с документами.
enum AnalysisMode {
  /// 1. Свободный вопрос-ответ строго по контексту документа с указанием страниц и источников.
  qa,

  /// 2. Краткая суммаризация (Executive Summary) — выжимка сути, тезисов и выводов.
  executiveSummary,

  /// 3. Глубокий анализ — поиск противоречий, рисков, ключевых метрик и табличных данных.
  deepAnalysis;

  /// Отображаемое название режима в интерфейсе.
  String get displayName {
    switch (this) {
      case AnalysisMode.qa:
        return 'Вопрос-ответ (RAG)';
      case AnalysisMode.executiveSummary:
        return 'Краткая выжимка';
      case AnalysisMode.deepAnalysis:
        return 'Глубокий анализ';
    }
  }

  /// Краткое описание назначения режима.
  String get description {
    switch (this) {
      case AnalysisMode.qa:
        return 'Точные ответы строго по тексту документов с цитированием страниц и фрагментов.';
      case AnalysisMode.executiveSummary:
        return 'Структурированное резюме (Executive Summary): цель, ключевые тезисы и выводы.';
      case AnalysisMode.deepAnalysis:
        return 'Поиск противоречий, скрытых рисков, ключевых метрик и сведение табличных данных.';
    }
  }

  /// Готовый промт для быстрых чипов-действий при загрузке файла.
  String get quickActionPrompt {
    switch (this) {
      case AnalysisMode.qa:
        return 'Выдели самые главные факты, ключевые положения и ответы на основные вопросы по этому документу с указанием страниц.';
      case AnalysisMode.executiveSummary:
        return 'Сделай структурированную краткую выжимку (Executive Summary) загруженного документа: основная суть, ключевые тезисы, важные даты/цифры и итоговые выводы.';
      case AnalysisMode.deepAnalysis:
        return 'Проведи глубокий анализ документа: найди возможные противоречия, узкие места и риски, а также сведи ключевые метрики и табличные данные в структурированный отчет.';
    }
  }
}

/// Тип провайдера LLM API.
enum LlmProviderType {
  /// Официальный Google Gemini REST API (`generativelanguage.googleapis.com`).
  gemini,

  /// Универсальный OpenAI-совместимый API (OpenAI, OpenRouter, DeepSeek, Ollama, vLLM).
  openAiCompatible;

  String get displayName {
    switch (this) {
      case LlmProviderType.gemini:
        return 'Google Gemini API';
      case LlmProviderType.openAiCompatible:
        return 'OpenAI / OpenRouter / DeepSeek';
    }
  }
}

/// Конфигурация подключения к LLM API.
class LlmConfig {
  final LlmProviderType provider;
  final String apiKey;
  final String baseUrl;
  final String model;
  final double temperature;

  LlmConfig({
    this.provider = LlmProviderType.gemini,
    String? apiKey,
    this.baseUrl = EnvConfig.defaultGeminiBaseUrl,
    this.model = EnvConfig.defaultGeminiModel,
    this.temperature = 0.2,
  }) : apiKey = apiKey ?? EnvConfig.geminiApiKey;

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  LlmConfig copyWith({
    LlmProviderType? provider,
    String? apiKey,
    String? baseUrl,
    String? model,
    double? temperature,
  }) {
    return LlmConfig(
      provider: provider ?? this.provider,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
    );
  }
}
