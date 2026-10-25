import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/isolate_runner.dart';
import '../../../../core/utils/token_estimator.dart';
import '../models/document_chunk_model.dart';
import 'text_chunker_service.dart';

/// Извлеченная страница (или логический раздел) документа.
class ParsedPage {
  final int pageNumber;
  final String text;

  const ParsedPage({
    required this.pageNumber,
    required this.text,
  });
}

/// Результат работы парсера документа.
class ParsedDocumentResult {
  final List<ParsedPage> pages;
  final String fullText;
  final int pageCount;

  const ParsedDocumentResult({
    required this.pages,
    required this.fullText,
    required this.pageCount,
  });
}

/// Результат единого высокопроизводительного конвейера в `Isolate`
/// (парсинг + семантический чанкинг + оценка токенов за один проход без копирования между изолятами).
class IsolatedDocumentPipelineResult {
  final String fullText;
  final int pageCount;
  final int estimatedTokens;
  final List<DocumentChunkModel> chunks;

  const IsolatedDocumentPipelineResult({
    required this.fullText,
    required this.pageCount,
    required this.estimatedTokens,
    required this.chunks,
  });
}

/// Провайдер сервиса парсинга документов.
final documentParserServiceProvider = Provider<DocumentParserService>((ref) {
  return const DocumentParserService();
});

/// Сервис извлечения структурированного текста из PDF, DOCX, CSV, TXT и MD файлов.
/// Все ресурсоемкие операции выполняются в фоновом [Isolate] с передачей памяти через `TransferableTypedData`.
class DocumentParserService {
  const DocumentParserService();

  /// Извлекает текст и постраничную структуру из байтов файла в фоновом изоляте.
  Future<ParsedDocumentResult> parseBytes({
    required String fileName,
    required String extension,
    required Uint8List bytes,
  }) async {
    final ext = extension.toLowerCase().trim();

    return IsolateRunner.runWithTransferredBytes(
      bytes: bytes,
      computation: (transferredBytes) {
        return _parseSync(
          fileName: fileName,
          extension: ext,
          bytes: transferredBytes,
        );
      },
    );
  }

  /// Выполняет полный цикл обработки тяжелого файла (извлечение текста по страницам,
  /// семантический чанкинг с перекрытием и подсчет токенов) внутри ОДНОГО фонового изолята
  /// с zero-copy передачей байтов (`TransferableTypedData`).
  Future<IsolatedDocumentPipelineResult> parseAndChunkInIsolate({
    required String documentId,
    required String fileName,
    required String extension,
    required Uint8List bytes,
    int maxChunkChars = EnvConfig.defaultChunkSizeChars,
    int overlapChars = EnvConfig.defaultChunkOverlapChars,
  }) async {
    final ext = extension.toLowerCase().trim();

    return IsolateRunner.runWithTransferredBytes(
      bytes: bytes,
      computation: (transferredBytes) {
        final parsed = _parseSync(
          fileName: fileName,
          extension: ext,
          bytes: transferredBytes,
        );

        final chunks = TextChunkerService.createChunksSync(
          documentId: documentId,
          documentName: fileName,
          pages: parsed.pages,
          maxChunkChars: maxChunkChars,
          overlapChars: overlapChars,
        );

        final totalTokens = TokenEstimator.estimateTokens(parsed.fullText);

        return IsolatedDocumentPipelineResult(
          fullText: parsed.fullText,
          pageCount: parsed.pageCount,
          estimatedTokens: totalTokens,
          chunks: chunks,
        );
      },
    );
  }

  static ParsedDocumentResult _parseSync({
    required String fileName,
    required String extension,
    required Uint8List bytes,
  }) {
    final List<ParsedPage> pages;

    switch (extension) {
      case 'pdf':
        pages = _extractPdfPages(fileName, bytes);
        break;
      case 'docx':
        pages = _extractDocxPages(fileName, bytes);
        break;
      case 'csv':
        pages = _extractCsvPages(fileName, bytes);
        break;
      case 'txt':
      case 'md':
        pages = _extractPlainTextPages(fileName, bytes);
        break;
      default:
        throw DocumentParseException(
          'Неподдерживаемый формат файла для парсинга: .$extension',
          fileName: fileName,
        );
    }

    final nonEmptyPages =
        pages.where((p) => p.text.trim().isNotEmpty).toList(growable: false);

    if (nonEmptyPages.isEmpty) {
      if (extension == 'pdf' && pages.isNotEmpty) {
        throw ScannedPdfException(
          fileName: fileName,
          pageCount: pages.length,
        );
      }
      throw DocumentParseException(
        'В документе "$fileName" не обнаружен текстовый слой (возможно, это пустой документ).',
        fileName: fileName,
      );
    }

    final buffer = StringBuffer();
    for (var i = 0; i < nonEmptyPages.length; i++) {
      final page = nonEmptyPages[i];
      buffer.writeln('--- [Страница ${page.pageNumber}] ---');
      buffer.writeln(page.text.trim());
      if (i < nonEmptyPages.length - 1) {
        buffer.writeln();
      }
    }

    return ParsedDocumentResult(
      pages: nonEmptyPages,
      fullText: buffer.toString().trim(),
      pageCount: pages.length,
    );
  }

  /// Постраничное извлечение текста из PDF с помощью Syncfusion Flutter PDF.
  static List<ParsedPage> _extractPdfPages(String fileName, Uint8List bytes) {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final pageCount = document.pages.count;
      final pages = <ParsedPage>[];

      for (var i = 0; i < pageCount; i++) {
        final rawText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        final normalized = _normalizeWhitespace(rawText);
        pages.add(
          ParsedPage(
            pageNumber: i + 1,
            text: normalized,
          ),
        );
      }

      return pages;
    } catch (e, st) {
      final errLower = e.toString().toLowerCase();
      if (errLower.contains('password') || errLower.contains('encrypt')) {
        throw DocumentParseException(
          'PDF-документ "$fileName" защищен паролем или зашифрован. Снимите защиту перед загрузкой.',
          fileName: fileName,
          cause: e,
          stackTrace: st,
        );
      }
      throw DocumentParseException(
        'Не удалось прочитать PDF "$fileName": файл поврежден или имеет нестандартную структуру ($e).',
        fileName: fileName,
        cause: e,
        stackTrace: st,
      );
    } finally {
      document?.dispose();
    }
  }

  /// Извлечение текста и таблиц (в формате Markdown) из архива Word (.docx).
  static List<ParsedPage> _extractDocxPages(String fileName, Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docXmlFile = archive.findFile('word/document.xml');
      if (docXmlFile == null) {
        throw DocumentParseException(
          'Файл "$fileName" поврежден: внутри DOCX-архива отсутствует поток word/document.xml.',
          fileName: fileName,
        );
      }

      final xmlContent = utf8.decode(
        docXmlFile.content as List<int>,
        allowMalformed: true,
      );
      final xmlDoc = XmlDocument.parse(xmlContent);
      final body = xmlDoc.findAllElements('w:body').firstOrNull;
      if (body == null) {
        return const [];
      }

      final pages = <ParsedPage>[];
      var currentPageNumber = 1;
      var currentBuffer = StringBuffer();

      void flushPage() {
        final text = currentBuffer.toString().trim();
        if (text.isNotEmpty) {
          pages.add(ParsedPage(pageNumber: currentPageNumber, text: text));
          currentPageNumber++;
          currentBuffer = StringBuffer();
        }
      }

      for (final node in body.children.whereType<XmlElement>()) {
        if (node.name.qualified == 'w:p') {
          final hasPageBreak = node.findAllElements('w:br').any(
                    (el) => el.getAttribute('w:type') == 'page',
                  ) ||
              node.findAllElements('w:lastRenderedPageBreak').isNotEmpty;

          final paragraphText = _extractDocxParagraphText(node);
          if (paragraphText.isNotEmpty) {
            currentBuffer.writeln(paragraphText);
          }

          if (hasPageBreak || currentBuffer.length >= 3200) {
            flushPage();
          }
        } else if (node.name.qualified == 'w:tbl') {
          final markdownTable = _extractDocxTableAsMarkdown(node);
          if (markdownTable.isNotEmpty) {
            currentBuffer.writeln();
            currentBuffer.writeln(markdownTable);
            currentBuffer.writeln();
          }
          if (currentBuffer.length >= 3200) {
            flushPage();
          }
        }
      }

      flushPage();
      return pages;
    } catch (e, st) {
      if (e is DocumentParseException) rethrow;
      throw DocumentParseException(
        'Ошибка чтения документа Word "$fileName": архив поврежден или зашифрован ($e).',
        fileName: fileName,
        cause: e,
        stackTrace: st,
      );
    }
  }

  static String _extractDocxParagraphText(XmlElement paragraph) {
    final buffer = StringBuffer();
    for (final descendant in paragraph.descendants.whereType<XmlElement>()) {
      final tag = descendant.name.qualified;
      if (tag == 'w:t') {
        buffer.write(descendant.innerText);
      } else if (tag == 'w:tab') {
        buffer.write('\t');
      } else if (tag == 'w:br') {
        buffer.write('\n');
      }
    }
    return buffer.toString().trim();
  }

  static String _extractDocxTableAsMarkdown(XmlElement tableNode) {
    final rows = tableNode.findElements('w:tr').toList();
    if (rows.isEmpty) return '';

    final mdBuffer = StringBuffer();
    for (var r = 0; r < rows.length; r++) {
      final cells = rows[r]
          .findElements('w:tc')
          .map((cell) {
            final paragraphs = cell
                .findElements('w:p')
                .map(_extractDocxParagraphText)
                .where((p) => p.isNotEmpty)
                .join(' ');
            return paragraphs.replaceAll('|', r'\|').trim();
          })
          .toList();

      if (cells.isEmpty) continue;
      mdBuffer.writeln('| ${cells.join(' | ')} |');

      if (r == 0) {
        final divider = List.filled(cells.length, '---').join(' | ');
        mdBuffer.writeln('| $divider |');
      }
    }
    return mdBuffer.toString().trim();
  }

  /// Парсинг CSV с автоопределением разделителя (`,` / `;` / `\t`) и генерацией Markdown-таблиц.
  static List<ParsedPage> _extractCsvPages(String fileName, Uint8List bytes) {
    try {
      final rawText = utf8.decode(bytes, allowMalformed: true).trim();
      if (rawText.isEmpty) return const [];

      final firstLine = rawText.split('\n').first;
      final delimiter = _detectCsvDelimiter(firstLine);

      final rows = CsvToListConverter(
        fieldDelimiter: delimiter,
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(rawText.replaceAll('\r\n', '\n'));

      if (rows.isEmpty) return const [];

      final headers = rows.first.map((e) => e.toString().trim()).toList();
      final dataRows =
          rows.length > 1 ? rows.sublist(1) : const <List<dynamic>>[];

      const rowsPerPage = 50;
      final pages = <ParsedPage>[];

      if (dataRows.isEmpty) {
        pages.add(
          ParsedPage(
            pageNumber: 1,
            text: '| ${headers.join(' | ')} |',
          ),
        );
        return pages;
      }

      var pageNum = 1;
      for (var i = 0; i < dataRows.length; i += rowsPerPage) {
        final end = (i + rowsPerPage < dataRows.length)
            ? i + rowsPerPage
            : dataRows.length;
        final slice = dataRows.sublist(i, end);

        final buffer = StringBuffer();
        buffer.writeln(
          'Таблица "$fileName" (строки ${i + 1}–$end из ${dataRows.length}):',
        );
        buffer.writeln('| ${headers.join(' | ')} |');
        buffer.writeln(
          '| ${List.filled(headers.length, '---').join(' | ')} |',
        );

        for (final row in slice) {
          final cells = row
              .map(
                (cell) => cell
                    .toString()
                    .replaceAll('|', r'\|')
                    .replaceAll('\n', ' ')
                    .trim(),
              )
              .toList();
          buffer.writeln('| ${cells.join(' | ')} |');
        }

        pages.add(
          ParsedPage(
            pageNumber: pageNum++,
            text: buffer.toString().trim(),
          ),
        );
      }

      return pages;
    } catch (e, st) {
      throw DocumentParseException(
        'Ошибка чтения CSV-файла "$fileName": $e',
        fileName: fileName,
        cause: e,
        stackTrace: st,
      );
    }
  }

  static String _detectCsvDelimiter(String sampleLine) {
    final semicolons = ';'.allMatches(sampleLine).length;
    final commas = ','.allMatches(sampleLine).length;
    final tabs = '\t'.allMatches(sampleLine).length;
    if (tabs > semicolons && tabs > commas) return '\t';
    if (semicolons > commas) return ';';
    return ',';
  }

  /// Извлечение текста из обычных текстовых и Markdown файлов с разбивкой на логические страницы.
  static List<ParsedPage> _extractPlainTextPages(
    String fileName,
    Uint8List bytes,
  ) {
    final decoded = utf8.decode(bytes, allowMalformed: true);
    final normalized = _normalizeWhitespace(decoded);
    if (normalized.isEmpty) return const [];

    const charsPerPage = 3000;
    final paragraphs = normalized.split('\n\n');
    final pages = <ParsedPage>[];

    var pageNum = 1;
    var currentBuffer = StringBuffer();

    for (final para in paragraphs) {
      if (currentBuffer.length + para.length > charsPerPage &&
          currentBuffer.isNotEmpty) {
        pages.add(
          ParsedPage(
            pageNumber: pageNum++,
            text: currentBuffer.toString().trim(),
          ),
        );
        currentBuffer = StringBuffer();
      }
      currentBuffer.writeln(para);
      currentBuffer.writeln();
    }

    if (currentBuffer.isNotEmpty) {
      pages.add(
        ParsedPage(
          pageNumber: pageNum,
          text: currentBuffer.toString().trim(),
        ),
      );
    }

    return pages;
  }

  static String _normalizeWhitespace(String input) {
    return input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
