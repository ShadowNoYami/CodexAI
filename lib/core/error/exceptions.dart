/// Базовый класс для всех исключений уровня Data-слоя.
sealed class AppException implements Exception {
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  const AppException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() => '$runtimeType: $message';
}

/// Ошибка при выборе или первичной валидации файла (размер, формат, пустой файл).
class FileValidationException extends AppException {
  const FileValidationException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}

/// Ошибка чтения или извлечения текста из документа (поврежденный PDF/DOCX, зашифрованный файл).
class DocumentParseException extends AppException {
  final String? fileName;

  const DocumentParseException(
    super.message, {
    this.fileName,
    super.cause,
    super.stackTrace,
  });
}

/// Специальное исключение: PDF-файл корректен и содержит страницы, но не имеет текстового слоя (это скан-копия),
/// поэтому требует автоматического распознавания через Gemini Vision OCR.
class ScannedPdfException extends DocumentParseException {
  final int pageCount;

  const ScannedPdfException({
    required String fileName,
    required this.pageCount,
  }) : super(
          'PDF "$fileName" является сканом без текстового слоя ($pageCount стр.). Требуется OCR.',
          fileName: fileName,
        );
}

/// Ошибка сетевого взаимодействия с LLM API (таймаут, неверный ключ, ошибка сервера).
class LlmApiException extends AppException {
  final int? statusCode;

  const LlmApiException(
    super.message, {
    this.statusCode,
    super.cause,
    super.stackTrace,
  });
}

/// Ошибка превышения лимита токенов контекстного окна модели.
class TokenLimitExceededException extends AppException {
  final int estimatedTokens;
  final int maxAllowedTokens;

  const TokenLimitExceededException({
    required this.estimatedTokens,
    required this.maxAllowedTokens,
    String message = 'Превышен лимит токенов для выбранной модели.',
  }) : super(message);
}

/// Ошибка работы с локальной базой данных.
class DatabaseException extends AppException {
  const DatabaseException(
    super.message, {
    super.cause,
    super.stackTrace,
  });
}
