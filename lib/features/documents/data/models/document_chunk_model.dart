import '../../domain/entities/document_chunk_entity.dart';

/// Модель данных фрагмента (чанка) документа с поддержкой сериализации.
class DocumentChunkModel extends DocumentChunkEntity {
  const DocumentChunkModel({
    required super.id,
    required super.documentId,
    required super.documentName,
    required super.index,
    super.pageNumber,
    required super.content,
    required super.estimatedTokens,
    super.embedding,
  });

  factory DocumentChunkModel.fromEntity(DocumentChunkEntity entity) {
    return DocumentChunkModel(
      id: entity.id,
      documentId: entity.documentId,
      documentName: entity.documentName,
      index: entity.index,
      pageNumber: entity.pageNumber,
      content: entity.content,
      estimatedTokens: entity.estimatedTokens,
      embedding: entity.embedding,
    );
  }

  factory DocumentChunkModel.fromJson(Map<String, dynamic> json) {
    return DocumentChunkModel(
      id: json['id'] as String? ?? '',
      documentId: json['documentId'] as String? ?? '',
      documentName: json['documentName'] as String? ?? '',
      index: (json['index'] as num?)?.toInt() ?? 0,
      pageNumber: (json['pageNumber'] as num?)?.toInt(),
      content: json['content'] as String? ?? '',
      estimatedTokens: (json['estimatedTokens'] as num?)?.toInt() ?? 0,
      embedding: (json['embedding'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'documentName': documentName,
        'index': index,
        'pageNumber': pageNumber,
        'content': content,
        'estimatedTokens': estimatedTokens,
        'embedding': embedding,
      };
}
