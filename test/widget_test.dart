import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_doc_assistant/app.dart';
import 'package:ai_doc_assistant/core/config/env_config.dart';
import 'package:ai_doc_assistant/core/error/exceptions.dart';
import 'package:ai_doc_assistant/core/utils/token_estimator.dart';
import 'package:ai_doc_assistant/features/ai_engine/data/datasources/rag_retriever_service.dart';
import 'package:ai_doc_assistant/features/ai_engine/domain/entities/analysis_mode.dart';
import 'package:ai_doc_assistant/features/chat/data/models/chat_message_model.dart';
import 'package:ai_doc_assistant/features/chat/domain/entities/chat_message_entity.dart';
import 'package:ai_doc_assistant/features/documents/data/datasources/document_parser_service.dart';
import 'package:ai_doc_assistant/features/documents/data/datasources/file_picker_service.dart';
import 'package:ai_doc_assistant/features/documents/data/datasources/text_chunker_service.dart';
import 'package:ai_doc_assistant/features/documents/domain/entities/document_chunk_entity.dart';
import 'package:ai_doc_assistant/features/documents/domain/entities/document_entity.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TokenEstimator & Budget Protection Tests', () {
    test('Estimates tokens accurately for Russian and English text', () {
      const ruText = 'Договор поставки оборудования и программного обеспечения';
      const enText = 'Service Level Agreement and technical specification';

      expect(TokenEstimator.estimateTokens(ruText), greaterThan(10));
      expect(TokenEstimator.estimateTokens(enText), greaterThan(8));
      expect(TokenEstimator.estimateTokens(''), equals(0));
    });

    test('Trims conversation history to fit token budget', () {
      final messages = List.generate(
        20,
        (i) => ChatMessageEntity(
          id: 'msg_$i',
          sessionId: 's1',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          content: 'Сообщение номер $i ' * 40,
          timestamp: DateTime.now(),
        ),
      );

      final trimmed = TokenEstimator.trimHistoryToBudget(
        messages,
        maxHistoryTokens: 500,
        maxMessages: 5,
      );

      expect(trimmed.length, lessThanOrEqualTo(5));
      expect(trimmed.last.id, equals('msg_19'));
    });
  });

  group('FilePickerService Validation & Camera/Image Detection', () {
    const pickerService = FilePickerService();

    test('Rejects unsupported file extension', () {
      final badFile = PlatformFile(
        name: 'archive.exe',
        size: 128,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(
        () => pickerService.validatePlatformFile(badFile),
        throwsA(isA<FileValidationException>()),
      );
    });

    test('Rejects corrupted PDF without %PDF magic header', () {
      final fakePdf = PlatformFile(
        name: 'corrupted.pdf',
        size: 32,
        bytes: Uint8List.fromList(utf8.encode('NOT A REAL PDF FILE CONTENT')),
      );

      expect(
        () => pickerService.validatePlatformFile(fakePdf),
        throwsA(isA<FileValidationException>()),
      );
    });

    test('Accepts valid TXT and JPG camera scan files up to 100 MB', () {
      expect(EnvConfig.maxFileSizeBytes, equals(100 * 1024 * 1024));

      final bytes =
          Uint8List.fromList(utf8.encode('Корректный текстовый отчет'));
      final validTxt = PlatformFile(
        name: 'report.txt',
        size: bytes.length,
        bytes: bytes,
      );

      final pickedTxt = pickerService.validatePlatformFile(validTxt);
      expect(pickedTxt.extension, equals('txt'));
      expect(pickedTxt.isImage, isFalse);

      final imgBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final validJpg = PlatformFile(
        name: 'scan_page.jpg',
        size: imgBytes.length,
        bytes: imgBytes,
      );
      final pickedImg = pickerService.validatePlatformFile(validJpg);
      expect(pickedImg.isImage, isTrue);
    });
  });

  group('TextChunkerService, Models & Hybrid RAG Retriever Tests', () {
    test('Splits pages into overlapping semantic chunks with page numbers', () {
      final longPageText = List.generate(
        30,
        (i) =>
            'Абзац номер ${i + 1}. Финансовый показатель выручки составил ${(i + 1) * 10} млн рублей.',
      ).join('\n\n');

      final chunks = TextChunkerService.createChunksSync(
        documentId: 'doc_1',
        documentName: 'Финансовый_отчет.pdf',
        pages: [
          ParsedPage(pageNumber: 3, text: longPageText),
        ],
        maxChunkChars: 600,
        overlapChars: 120,
      );

      expect(chunks.length, greaterThan(2));
      expect(chunks.first.pageNumber, equals(3));
      expect(chunks.first.documentName, equals('Финансовый_отчет.pdf'));
    });

    test('RagRetrieverService ranks chunks and builds CitedSource citations',
        () async {
      const retriever = RagRetrieverService();
      final doc = DocumentEntity(
        id: 'doc_1',
        name: 'Контракт.pdf',
        extension: 'pdf',
        sizeBytes: 4096,
        status: DocumentIndexStatus.ready,
        pageCount: 2,
        fullText: 'Штраф за просрочку составляет 0.5% в день.',
        estimatedTokens: 100,
        createdAt: DateTime.now(),
        chunks: const [
          DocumentChunkEntity(
            id: 'c1',
            documentId: 'doc_1',
            documentName: 'Контракт.pdf',
            index: 0,
            pageNumber: 1,
            content:
                'Общие положения договора о поставке серверного оборудования.',
            estimatedTokens: 30,
          ),
          DocumentChunkEntity(
            id: 'c2',
            documentId: 'doc_1',
            documentName: 'Контракт.pdf',
            index: 1,
            pageNumber: 5,
            content:
                'Ответственность сторон: штраф и пени за просрочку поставки составляют 0.5% от суммы договора.',
            estimatedTokens: 40,
          ),
        ],
      );

      final result = await retriever.retrieve(
        query: 'Какой штраф за просрочку поставки?',
        documents: [doc],
        mode: AnalysisMode.qa,
      );

      expect(result.citations, isNotEmpty);
      expect(result.citations.first.pageNumber, equals(5));
      expect(result.citations.first.displayLabel, contains('Стр. 5'));

      final msgModel = ChatMessageModel(
        id: 'm1',
        sessionId: 's1',
        role: MessageRole.assistant,
        content: 'Штраф составляет 0.5%',
        timestamp: DateTime.now(),
        citations: result.citations,
      );
      final restored = ChatMessageModel.fromJson(msgModel.toJson());
      expect(restored.citations.first.pageNumber, equals(5));
    });
  });

  testWidgets('MainChatScreen initializes and renders workspace UI', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: AiDocAssistantApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Интеллектуальный анализ документов (RAG)'),
      findsOneWidget,
    );
  });
}
