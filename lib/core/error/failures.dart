/// Представление ошибок уровня Domain и Presentation (Clean Architecture).
sealed class Failure {
  final String title;
  final String message;

  const Failure({
    required this.title,
    required this.message,
  });
}

class FileValidationFailure extends Failure {
  const FileValidationFailure(String message)
      : super(
          title: 'Ошибка валидации файла',
          message: message,
        );
}

class DocumentParseFailure extends Failure {
  const DocumentParseFailure(String message)
      : super(
          title: 'Ошибка чтения документа',
          message: message,
        );
}

class LlmNetworkFailure extends Failure {
  final int? statusCode;

  const LlmNetworkFailure(
    String message, {
    this.statusCode,
  }) : super(
          title: 'Ошибка обращения к ИИ',
          message: message,
        );
}

class TokenLimitFailure extends Failure {
  final int estimatedTokens;
  final int maxAllowedTokens;

  const TokenLimitFailure({
    required this.estimatedTokens,
    required this.maxAllowedTokens,
  }) : super(
          title: 'Превышен лимит контекста',
          message:
              'Объем запроса (~$estimatedTokens токенов) превышает лимит ($maxAllowedTokens). Попробуйте переключиться в режим точечного поиска (Вопрос-Ответ) или уменьшить число активных файлов.',
        );
}

class StorageFailure extends Failure {
  const StorageFailure(String message)
      : super(
          title: 'Ошибка локального хранилища',
          message: message,
        );
}
