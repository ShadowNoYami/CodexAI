/// Описание SQL-схемы таблиц `documents` и `document_chunks` для Drift / SQLite.
class DocumentsTableSchema {
  const DocumentsTableSchema._();

  static const String tableName = 'documents';
  static const String chunksTableName = 'document_chunks';

  static const String createDocumentsTableSql = '''
    CREATE TABLE IF NOT EXISTS documents (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      extension TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      file_path TEXT,
      status TEXT NOT NULL,
      error_message TEXT,
      page_count INTEGER NOT NULL DEFAULT 1,
      full_text TEXT NOT NULL,
      estimated_tokens INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    );
  ''';

  static const String createDocumentChunksTableSql = '''
    CREATE TABLE IF NOT EXISTS document_chunks (
      id TEXT PRIMARY KEY NOT NULL,
      document_id TEXT NOT NULL,
      document_name TEXT NOT NULL,
      chunk_index INTEGER NOT NULL,
      page_number INTEGER,
      content TEXT NOT NULL,
      estimated_tokens INTEGER NOT NULL DEFAULT 0,
      embedding_json TEXT,
      FOREIGN KEY (document_id) REFERENCES documents (id) ON DELETE CASCADE
    );
  ''';

  static const String createChunksIndexSql = '''
    CREATE INDEX IF NOT EXISTS idx_document_chunks_doc_id
    ON document_chunks (document_id, chunk_index);
  ''';
}
