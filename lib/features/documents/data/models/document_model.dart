import '../../domain/entities/document_entity.dart';
import 'document_chunk_model.dart';

/// Модель данных загруженного документа (метаданные, статус индексации, полный текст и чанки).
class DocumentModel extends DocumentEntity {
  const DocumentModel({
    required super.id,
    required super.name,
    required super.extension,
    required super.sizeBytes,
    super.filePath,
    required super.status,
    super.errorMessage,
    required super.pageCount,
    required super.fullText,
    required super.estimatedTokens,
    required super.chunks,
    required super.createdAt,
  });

  factory DocumentModel.fromEntity(DocumentEntity entity) {
    return DocumentModel(
      id: entity.id,
      name: entity.name,
      extension: entity.extension,
      sizeBytes: entity.sizeBytes,
      filePath: entity.filePath,
      status: entity.status,
      errorMessage: entity.errorMessage,
      pageCount: entity.pageCount,
      fullText: entity.fullText,
      estimatedTokens: entity.estimatedTokens,
      chunks: entity.chunks.map(DocumentChunkModel.fromEntity).toList(),
      createdAt: entity.createdAt,
    );
  }

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'ready';
    final status = DocumentIndexStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => DocumentIndexStatus.ready,
    );

    final rawChunks = json['chunks'] as List<dynamic>? ?? const [];

    return DocumentModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Без имени',
      extension: json['extension'] as String? ?? 'txt',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      filePath: json['filePath'] as String?,
      status: status,
      errorMessage: json['errorMessage'] as String?,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
      fullText: json['fullText'] as String? ?? '',
      estimatedTokens: (json['estimatedTokens'] as num?)?.toInt() ?? 0,
      chunks: rawChunks
          .map((e) => DocumentChunkModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'extension': extension,
        'sizeBytes': sizeBytes,
        'filePath': filePath,
        'status': status.name,
        'errorMessage': errorMessage,
        'pageCount': pageCount,
        'fullText': fullText,
        'estimatedTokens': estimatedTokens,
        'chunks': chunks
            .map((e) => DocumentChunkModel.fromEntity(e).toJson())
            .toList(),
        'createdAt': createdAt.toIso8601String(),
      };
}
