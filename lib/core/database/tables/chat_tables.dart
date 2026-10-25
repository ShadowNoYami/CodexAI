/// Описание SQL-схемы таблиц `chat_sessions` и `chat_messages` для Drift / SQLite.
class ChatTablesSchema {
  const ChatTablesSchema._();

  static const String sessionsTableName = 'chat_sessions';
  static const String messagesTableName = 'chat_messages';

  static const String createSessionsTableSql = '''
    CREATE TABLE IF NOT EXISTS chat_sessions (
      id TEXT PRIMARY KEY NOT NULL,
      title TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      document_ids_json TEXT NOT NULL DEFAULT '[]',
      last_message_preview TEXT
    );
  ''';

  static const String createMessagesTableSql = '''
    CREATE TABLE IF NOT EXISTS chat_messages (
      id TEXT PRIMARY KEY NOT NULL,
      session_id TEXT NOT NULL,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      timestamp TEXT NOT NULL,
      is_streaming INTEGER NOT NULL DEFAULT 0,
      has_error INTEGER NOT NULL DEFAULT 0,
      attached_document_ids_json TEXT NOT NULL DEFAULT '[]',
      citations_json TEXT NOT NULL DEFAULT '[]',
      analysis_mode TEXT,
      FOREIGN KEY (session_id) REFERENCES chat_sessions (id) ON DELETE CASCADE
    );
  ''';

  static const String createMessagesIndexSql = '''
    CREATE INDEX IF NOT EXISTS idx_chat_messages_session_id
    ON chat_messages (session_id, timestamp);
  ''';
}
