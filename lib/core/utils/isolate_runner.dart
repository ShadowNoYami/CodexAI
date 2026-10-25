import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Утилита для запуска ресурсоемких задач (парсинг больших PDF/DOCX, чанкинг, подсчет сходства)
/// в отдельном изоляте без блокировки главного UI-потока (60/120 FPS).
class IsolateRunner {
  const IsolateRunner._();

  /// Выполняет функцию [computation] в фоновом [Isolate] на нативных платформах
  /// или асинхронно через microtask в Web-среде (где `Isolate.run` не поддерживается).
  static Future<R> run<R>(FutureOr<R> Function() computation) async {
    if (kIsWeb) {
      return await Future.microtask(computation);
    }
    return await Isolate.run(computation);
  }

  /// Передает массив байтов [bytes] в фоновый изолят без лишнего копирования в памяти
  /// через [TransferableTypedData] (оптимизация для тяжелых PDF и DOCX до 50 МБ).
  static Future<R> runWithTransferredBytes<R>({
    required Uint8List bytes,
    required FutureOr<R> Function(Uint8List transferredBytes) computation,
  }) async {
    if (kIsWeb) {
      return await Future.microtask(() => computation(bytes));
    }

    final transferable = TransferableTypedData.fromList([bytes]);
    return await Isolate.run(() {
      final materialized = transferable.materialize().asUint8List();
      return computation(materialized);
    });
  }
}
