import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/exceptions.dart';
import '../../domain/entities/document_entity.dart';
import '../models/document_chunk_model.dart';
import '../models/document_model.dart';

/// Провайдер локального источника данных для документов.
final documentsLocalDataSourceProvider =
    Provider<DocumentsLocalDataSource>((ref) {
  return DocumentsLocalDataSource(db: ref.watch(appDatabaseProvider));
});

/// Локальное хранилище проиндексированных документов и их чанков в Drift (SQLite).
class DocumentsLocalDataSource {
  static const String _fallbackPrefsKey = 'cached_documents_v1';

  final AppDatabase _db;

  const DocumentsLocalDataSource({required AppDatabase db}) : _db = db;

  /// Загружает все сохраненные документы вместе с их чанками, отсортированные по дате добавления.
  Future<List<DocumentModel>> getAllDocuments() async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        return _getFromPrefsFallback();
      }

      final docRows = await _db.select(
        'SELECT * FROM documents ORDER BY created_at DESC;',
      );
      if (docRows.isEmpty) return const [];

      final documents = <DocumentModel>[];
      for (final row in docRows) {
        final docId = row['id'] as String;
        final chunkRows = await _db.select(
          'SELECT * FROM document_chunks WHERE document_id = ? ORDER BY chunk_index ASC;',
          [docId],
        );

        final chunks = chunkRows.map(_mapChunkRow).toList();
        documents.add(_mapDocumentRow(row, chunks));
      }

      return documents;
    } catch (e, st) {
      throw DatabaseException(
        'Не удалось загрузить кэш документов из локальной БД: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Сохраняет или обновляет документ и все его чанки в локальной БД.
  Future<void> saveDocument(DocumentModel document) async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        await _saveToPrefsFallback(document);
        return;
      }

      await _db.execute(
        '''
        INSERT OR REPLACE INTO documents (
          id, name, extension, size_bytes, file_path, status,
          error_message, page_count, full_text, estimated_tokens, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        ''',
        [
          document.id,
          document.name,
          document.extension,
          document.sizeBytes,
          document.filePath,
          document.status.name,
          document.errorMessage,
          document.pageCount,
          document.fullText,
          document.estimatedTokens,
          document.createdAt.toIso8601String(),
        ],
      );

      await _db.execute(
        'DELETE FROM document_chunks WHERE document_id = ?;',
        [document.id],
      );

      for (final chunk in document.chunks) {
        final embeddingJson =
            chunk.embedding != null ? jsonEncode(chunk.embedding) : null;
        await _db.execute(
          '''
          INSERT INTO document_chunks (
            id, document_id, document_name, chunk_index,
            page_number, content, estimated_tokens, embedding_json
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
          ''',
          [
            chunk.id,
            chunk.documentId,
            chunk.documentName,
            chunk.index,
            chunk.pageNumber,
            chunk.content,
            chunk.estimatedTokens,
            embeddingJson,
          ],
        );
      }
    } catch (e, st) {
      throw DatabaseException(
        'Ошибка сохранения документа "${document.name}" в БД: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Удаляет документ и его чанки из локальной БД.
  Future<void> deleteDocument(String documentId) async {
    try {
      await _db.ensureInitialized();
      if (_db.isUsingFallback) {
        final existing = await _getFromPrefsFallback();
        final filtered =
            existing.where((d) => d.id != documentId).toList(growable: false);
        await _writeAllToPrefsFallback(filtered);
        return;
      }

      await _db.execute(
        'DELETE FROM document_chunks WHERE document_id = ?;',
        [documentId],
      );
      await _db.execute(
        'DELETE FROM documents WHERE id = ?;',
        [documentId],
      );
    } catch (e, st) {
      throw DatabaseException(
        'Ошибка удаления документа из БД: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  DocumentModel _mapDocumentRow(
    Map<String, Object?> row,
    List<DocumentChunkModel> chunks,
  ) {
    final statusName = row['status'] as String? ?? 'ready';
    final status = DocumentIndexStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => DocumentIndexStatus.ready,
    );

    return DocumentModel(
      id: row['id'] as String? ?? '',
      name: row['name'] as String? ?? 'Документ',
      extension: row['extension'] as String? ?? 'txt',
      sizeBytes: (row['size_bytes'] as num?)?.toInt() ?? 0,
      filePath: row['file_path'] as String?,
      status: status,
      errorMessage: row['error_message'] as String?,
      pageCount: (row['page_count'] as num?)?.toInt() ?? 1,
      fullText: row['full_text'] as String? ?? '',
      estimatedTokens: (row['estimated_tokens'] as num?)?.toInt() ?? 0,
      chunks: chunks,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  DocumentChunkModel _mapChunkRow(Map<String, Object?> row) {
    List<double>? embedding;
    final embRaw = row['embedding_json'] as String?;
    if (embRaw != null && embRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(embRaw) as List<dynamic>;
        embedding = decoded.map((e) => (e as num).toDouble()).toList();
      } catch (_) {}
    }

    return DocumentChunkModel(
      id: row['id'] as String? ?? '',
      documentId: row['document_id'] as String? ?? '',
      documentName: row['document_name'] as String? ?? '',
      index: (row['chunk_index'] as num?)?.toInt() ?? 0,
      pageNumber: (row['page_number'] as num?)?.toInt(),
      content: row['content'] as String? ?? '',
      estimatedTokens: (row['estimated_tokens'] as num?)?.toInt() ?? 0,
      embedding: embedding,
    );
  }

  Future<List<DocumentModel>> _getFromPrefsFallback() async {
    final prefs = await _db.prefs;
    final raw = prefs.getString(_fallbackPrefsKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => DocumentModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveToPrefsFallback(DocumentModel doc) async {
    final current = (await _getFromPrefsFallback()).toList();
    final idx = current.indexWhere((d) => d.id == doc.id);
    if (idx >= 0) {
      current[idx] = doc;
    } else {
      current.insert(0, doc);
    }
    await _writeAllToPrefsFallback(current);
  }

  Future<void> _writeAllToPrefsFallback(List<DocumentModel> docs) async {
    final prefs = await _db.prefs;
    final encoded = jsonEncode(docs.map((d) => d.toJson()).toList());
    await prefs.setString(_fallbackPrefsKey, encoded);
  }
}
