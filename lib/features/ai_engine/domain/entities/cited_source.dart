/// Ссылка на конкретный фрагмент (источник) документа, использованный ИИ при формировании ответа.
class CitedSource {
  final String documentId;
  final String documentName;
  final String chunkId;
  final int chunkIndex;
  final int? pageNumber;
  final String excerpt;
  final double? relevanceScore;

  const CitedSource({
    required this.documentId,
    required this.documentName,
    required this.chunkId,
    required this.chunkIndex,
    this.pageNumber,
    required this.excerpt,
    this.relevanceScore,
  });

  /// Краткая метка источника для отображения в UI (например: «Договор.pdf • Стр. 4»).
  String get displayLabel {
    if (pageNumber != null) {
      return '$documentName • Стр. $pageNumber';
    }
    return '$documentName • Фрагмент #${chunkIndex + 1}';
  }

  Map<String, dynamic> toJson() => {
        'documentId': documentId,
        'documentName': documentName,
        'chunkId': chunkId,
        'chunkIndex': chunkIndex,
        'pageNumber': pageNumber,
        'excerpt': excerpt,
        'relevanceScore': relevanceScore,
      };

  factory CitedSource.fromJson(Map<String, dynamic> json) {
    return CitedSource(
      documentId: json['documentId'] as String? ?? '',
      documentName: json['documentName'] as String? ?? 'Документ',
      chunkId: json['chunkId'] as String? ?? '',
      chunkIndex: (json['chunkIndex'] as num?)?.toInt() ?? 0,
      pageNumber: (json['pageNumber'] as num?)?.toInt(),
      excerpt: json['excerpt'] as String? ?? '',
      relevanceScore: (json['relevanceScore'] as num?)?.toDouble(),
    );
  }
}
