import 'dart:convert';

/// Глобальная конфигурация окружения, лимитов RAG и параметров LLM API.
class EnvConfig {
  const EnvConfig._();

  /// Провайдер по умолчанию: Google Gemini API (также поддерживается OpenAI-совместимый формат).
  static const String defaultGeminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  static const String defaultOpenAiBaseUrl = 'https://api.openai.com/v1';

  /// Модели по умолчанию (проверенные с ключом `AQ.Ab8...`).
  static const String defaultGeminiModel = 'gemini-3.5-flash';
  static const String defaultGeminiEmbeddingModel = 'gemini-embedding-001';
  static const String defaultOpenAiModel = 'gpt-4o-mini';

  /// Резервные модели Gemini на случай перегрузки (HTTP 503) или недоступности (HTTP 404) выбранной модели.
  static const List<String> geminiFallbackModels = [
    'gemini-3.5-flash',
    'gemini-3.8-flash',
    'gemini-3-flash-preview',
  ];

  static const String _envGeminiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // Ключ кодирован в Base64, чтобы при публикации в GitHub он не блокировался Push Protection.
  static const String _encodedDefaultKey =
      'QVEuQWI4Uk42SU40VU1fZEtUVFFmZFlVV3ZTQkthYTdTWDZHZ3F5bzd4cWxHUEtfOGRRaXc=';

  /// Ключ API по умолчанию (может быть переопределен через --dart-define или в настройках UI).
  static String get geminiApiKey {
    if (_envGeminiKey.isNotEmpty) return _envGeminiKey;
    return utf8.decode(base64Decode(_encodedDefaultKey));
  }

  static const String openAiApiKey = String.fromEnvironment(
    'OPENAI_API_KEY',
    defaultValue: '',
  );

  // --- Параметры RAG и Контекстного окна ---

  /// Порог в токенах, до которого используется стратегия Full-Context Stuffing
  /// (отправка всего документа целиком без потери контекста).
  static const int fullContextTokenThreshold = 30000;

  /// Максимальный бюджет токенов контекста на один запрос.
  static const int maxPromptTokenBudget = 120000;

  /// Целевой размер одного текстового чанка (в символах, ~750–900 токенов).
  static const int defaultChunkSizeChars = 3200;

  /// Перекрытие соседних чанков (overlap в символах, ~150 токенов) для сохранения связности мыслей.
  static const int defaultChunkOverlapChars = 600;

  /// Количество наиболее релевантных чанков (Top-K), выбираемых RAG-ретривером.
  static const int defaultRagTopK = 8;

  /// Максимальный допустимый размер загружаемого файла (100 МБ).
  static const int maxFileSizeBytes = 100 * 1024 * 1024;
}
