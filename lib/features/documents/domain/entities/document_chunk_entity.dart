/// Доменная сущность смыслового фрагмента (чанка) документа для RAG и контекстного поиска.
class DocumentChunkEntity {
  final String id;
  final String documentId;
  final String documentName;
  final int index;
  final int? pageNumber;
  final String content;
  final int estimatedTokens;
  final List<double>? embedding;

  const DocumentChunkEntity({
    required this.id,
    required this.documentId,
    required this.documentName,
    required this.index,
    this.pageNumber,
    required this.content,
    required this.estimatedTokens,
    this.embedding,
  });

  DocumentChunkEntity copyWith({
    String? id,
    String? documentId,
    String? documentName,
    int? index,
    int? pageNumber,
    String? content,
    int? estimatedTokens,
    List<double>? embedding,
  }) {
    return DocumentChunkEntity(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      documentName: documentName ?? this.documentName,
      index: index ?? this.index,
      pageNumber: pageNumber ?? this.pageNumber,
      content: content ?? this.content,
      estimatedTokens: estimatedTokens ?? this.estimatedTokens,
      embedding: embedding ?? this.embedding,
    );
  }
}
