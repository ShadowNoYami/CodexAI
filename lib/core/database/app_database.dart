import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tables/chat_tables.dart';
import 'tables/documents_table.dart';

/// Провайдер локальной базы данных приложения (Drift SQLite + Fallback кэш).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Локальная реляционная база данных на основе Drift (`drift_flutter` / SQLite).
///
/// Обеспечивает надежное хранение истории сессий чатов, сообщений с цитатами
/// и проиндексированных документов с их чанками и векторными эмбеддингами.
class AppDatabase {
  QueryExecutor? _executor;
  SharedPreferences? _prefs;
  bool _initialized = false;
  bool _usePrefsFallback = false;
  Future<void>? _initFuture;

  AppDatabase();

  /// Признак работы через резервное хранилище (например, в среде widget-тестов или Web без WASM).
  bool get isUsingFallback => _usePrefsFallback;

  /// Гарантирует однократную инициализацию соединения с SQLite и создание таблиц.
  Future<void> ensureInitialized() {
    return _initFuture ??= _initInternal();
  }

  Future<void> _initInternal() async {
    if (_initialized) return;

    try {
      final executor = driftDatabase(name: 'ai_doc_assistant_db');
      final opened = await executor.ensureOpen(_DummyDatabaseUser());
      if (!opened) {
        throw StateError('Не удалось открыть соединение Drift.');
      }
      _executor = executor;

      await executor.runCustom('PRAGMA foreign_keys = ON;', const []);
      await executor.runCustom(
        DocumentsTableSchema.createDocumentsTableSql,
        const [],
      );
      await executor.runCustom(
        DocumentsTableSchema.createDocumentChunksTableSql,
        const [],
      );
      await executor.runCustom(
        DocumentsTableSchema.createChunksIndexSql,
        const [],
      );
      await executor.runCustom(
        ChatTablesSchema.createSessionsTableSql,
        const [],
      );
      await executor.runCustom(
        ChatTablesSchema.createMessagesTableSql,
        const [],
      );
      await executor.runCustom(
        ChatTablesSchema.createMessagesIndexSql,
        const [],
      );

      _initialized = true;
    } catch (e) {
      debugPrint(
        '[AppDatabase] Переключение на локальное KV-хранилище (SharedPreferences): $e',
      );
      _usePrefsFallback = true;
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  /// Выполняет SQL-запрос `SELECT` и возвращает список строк.
  Future<List<Map<String, Object?>>> select(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    await ensureInitialized();
    final exec = _executor;
    if (exec == null || _usePrefsFallback) return const [];
    return exec.runSelect(sql, args);
  }

  /// Выполняет модифицирующий SQL-запрос (`INSERT`, `UPDATE`, `DELETE`).
  Future<void> execute(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    await ensureInitialized();
    final exec = _executor;
    if (exec == null || _usePrefsFallback) return;
    await exec.runCustom(sql, args);
  }

  /// Доступ к `SharedPreferences` для хранения настроек и резервной сериализации.
  Future<SharedPreferences> get prefs async {
    await ensureInitialized();
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> close() async {
    try {
      await _executor?.close();
    } catch (_) {}
  }
}

class _DummyDatabaseUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
