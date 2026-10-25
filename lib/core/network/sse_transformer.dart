import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Трансформер потока байтов (`Uint8List`) в поток полезных JSON-сообщений Server-Sent Events (SSE).
///
/// Корректно обрабатывает склеенные пакеты, многострочные события и маркер завершения `data: [DONE]`.
class SseStreamTransformer extends StreamTransformerBase<Uint8List, String> {
  const SseStreamTransformer();

  @override
  Stream<String> bind(Stream<Uint8List> stream) {
    return stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .transform(
      StreamTransformer<String, String>.fromHandlers(
        handleData: (String line, EventSink<String> sink) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith(':')) {
            return;
          }
          if (trimmed.startsWith('data:')) {
            final payload = trimmed.substring(5).trim();
            if (payload.isEmpty || payload == '[DONE]') {
              return;
            }
            sink.add(payload);
          }
        },
      ),
    );
  }
}
