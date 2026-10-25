import 'document_chunk_entity.dart';

/// Статус обработки и индексации документа.
enum DocumentIndexStatus {
  /// Ожидает обработки.
  pending,

  /// Извлечение текста из файла (PDF/DOCX/TXT/CSV).
  parsing,

  /// Разбиение на перекрывающиеся чанки и подсчет токенов.
  chunking,

  /// Генерация векторных эмбеддингов (при необходимости).
  embedding,

  /// Полностью готов к анализу и поиску.
  ready,

  /// Ошибка чтения или индексации документа.
  error,
}

/// Доменная сущность загруженного документа.
class DocumentEntity {
  final String id;
  final String name;
  final String extension;
  final int sizeBytes;
  final String? filePath;
  final DocumentIndexStatus status;
  final String? errorMessage;
  final int pageCount;
  final String fullText;
  final int estimatedTokens;
  final List<DocumentChunkEntity> chunks;
  final DateTime createdAt;

  const DocumentEntity({
    required this.id,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    this.filePath,
    required this.status,
    this.errorMessage,
    required this.pageCount,
    required this.fullText,
    required this.estimatedTokens,
    required this.chunks,
    required this.createdAt,
  });

  bool get isReady => status == DocumentIndexStatus.ready;
  bool get hasError => status == DocumentIndexStatus.error;
  bool get isProcessing =>
      status == DocumentIndexStatus.pending ||
      status == DocumentIndexStatus.parsing ||
      status == DocumentIndexStatus.chunking ||
      status == DocumentIndexStatus.embedding;

  /// Человекочитаемый размер файла (КБ / МБ).
  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes Б';
    final kb = sizeBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} КБ';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} МБ';
  }

  DocumentEntity copyWith({
    String? id,
    String? name,
    String? extension,
    int? sizeBytes,
    String? filePath,
    DocumentIndexStatus? status,
    String? errorMessage,
    int? pageCount,
    String? fullText,
    int? estimatedTokens,
    List<DocumentChunkEntity>? chunks,
    DateTime? createdAt,
  }) {
    return DocumentEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      extension: extension ?? this.extension,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      pageCount: pageCount ?? this.pageCount,
      fullText: fullText ?? this.fullText,
      estimatedTokens: estimatedTokens ?? this.estimatedTokens,
      chunks: chunks ?? this.chunks,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
