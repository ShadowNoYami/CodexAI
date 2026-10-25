import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/utils/token_estimator.dart';
import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../../domain/entities/document_entity.dart';
import '../../domain/repositories/document_repository.dart';
import '../datasources/document_parser_service.dart';
import '../datasources/documents_local_ds.dart';
import '../datasources/file_picker_service.dart';
import '../datasources/image_ocr_service.dart';
import '../datasources/text_chunker_service.dart';
import '../models/document_model.dart';

/// Провайдер репозитория документов.
final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepositoryImpl(
    filePickerService: ref.watch(filePickerServiceProvider),
    parserService: ref.watch(documentParserServiceProvider),
    imageOcrService: ref.watch(imageOcrServiceProvider),
    chunkerService: ref.watch(textChunkerServiceProvider),
    localDataSource: ref.watch(documentsLocalDataSourceProvider),
  );
});

/// Реализация репозитория документов с поддержкой Vision OCR для фото с камеры,
/// автоматическим OCR для отсканированных PDF без текстового слоя
/// и единым оптимизированным Isolate-конвейером для файлов (Data-слой).
class DocumentRepositoryImpl implements DocumentRepository {
  final FilePickerService _filePickerService;
  final DocumentParserService _parserService;
  final ImageOcrService _imageOcrService;
  final TextChunkerService _chunkerService;
  final DocumentsLocalDataSource _localDataSource;
  final Uuid _uuid;

  DocumentRepositoryImpl({
    required FilePickerService filePickerService,
    required DocumentParserService parserService,
    required ImageOcrService imageOcrService,
    required TextChunkerService chunkerService,
    required DocumentsLocalDataSource localDataSource,
    Uuid? uuid,
  })  : _filePickerService = filePickerService,
        _parserService = parserService,
        _imageOcrService = imageOcrService,
        _chunkerService = chunkerService,
        _localDataSource = localDataSource,
        _uuid = uuid ?? const Uuid();

  @override
  Future<List<DocumentEntity>> getSavedDocuments() {
    return _localDataSource.getAllDocuments();
  }

  @override
  Future<List<PickedDocumentFile>> pickFiles({bool allowMultiple = true}) {
    return _filePickerService.pickAndValidateFiles(
      allowMultiple: allowMultiple,
    );
  }

  @override
  Future<PickedDocumentFile?> captureFromCamera() {
    return _filePickerService.captureDocumentFromCamera();
  }

  @override
  Future<List<PickedDocumentFile>> pickImagesFromGallery() {
    return _filePickerService.pickDocumentImagesFromGallery();
  }

  @override
  Future<DocumentEntity> processPickedFile(
    PickedDocumentFile pickedFile, {
    LlmConfig? llmConfig,
    DocumentStatusCallback? onStatusChanged,
  }) async {
    final docId = _uuid.v4();
    final now = DateTime.now();

    var currentDoc = DocumentModel(
      id: docId,
      name: pickedFile.name,
      extension: pickedFile.extension,
      sizeBytes: pickedFile.sizeBytes,
      filePath: pickedFile.filePath,
      status: DocumentIndexStatus.parsing,
      pageCount: 0,
      fullText: '',
      estimatedTokens: 0,
      chunks: const [],
      createdAt: now,
    );
    onStatusChanged?.call(currentDoc);

    try {
      // 1. Если это фотография или скан (JPG, PNG, WEBP) — используем мультимодальный Vision OCR
      if (pickedFile.isImage) {
        final parsedResult = await _imageOcrService.extractTextFromImage(
          fileName: pickedFile.name,
          extension: pickedFile.extension,
          bytes: pickedFile.bytes,
          config: llmConfig ?? LlmConfig(),
        );

        return await _finalizeOcrDocument(
          docId: docId,
          currentDoc: currentDoc,
          parsedResult: parsedResult,
          onStatusChanged: onStatusChanged,
        );
      }

      // 2. Пробуем быстрый локальный парсинг текста в фоновом изоляте (PDF, DOCX, CSV, TXT, MD)
      try {
        final pipelineResult = await _parserService.parseAndChunkInIsolate(
          documentId: docId,
          fileName: pickedFile.name,
          extension: pickedFile.extension,
          bytes: pickedFile.bytes,
        );

        currentDoc = DocumentModel.fromEntity(
          currentDoc.copyWith(
            status: DocumentIndexStatus.ready,
            pageCount: pipelineResult.pageCount,
            fullText: pipelineResult.fullText,
            chunks: pipelineResult.chunks,
            estimatedTokens: pipelineResult.estimatedTokens,
          ),
        );

        await _localDataSource.saveDocument(currentDoc);
        onStatusChanged?.call(currentDoc);
        return currentDoc;
      } on ScannedPdfException catch (scannedEx) {
        // 3. Если PDF оказался сканом без текстового слоя (например, отсканированная книга),
        // автоматически переключаемся на Gemini Vision OCR!
        final ocrResult = await _imageOcrService.extractTextFromScannedPdf(
          fileName: pickedFile.name,
          bytes: pickedFile.bytes,
          totalPageCount: scannedEx.pageCount,
          config: llmConfig ?? LlmConfig(),
        );

        return await _finalizeOcrDocument(
          docId: docId,
          currentDoc: currentDoc,
          parsedResult: ocrResult,
          onStatusChanged: onStatusChanged,
        );
      }
    } catch (e) {
      final errorDoc = DocumentModel.fromEntity(
        currentDoc.copyWith(
          status: DocumentIndexStatus.error,
          errorMessage: e.toString(),
        ),
      );
      onStatusChanged?.call(errorDoc);
      rethrow;
    }
  }

  Future<DocumentEntity> _finalizeOcrDocument({
    required String docId,
    required DocumentModel currentDoc,
    required ParsedDocumentResult parsedResult,
    DocumentStatusCallback? onStatusChanged,
  }) async {
    var updatedDoc = DocumentModel.fromEntity(
      currentDoc.copyWith(
        status: DocumentIndexStatus.chunking,
        pageCount: parsedResult.pageCount,
        fullText: parsedResult.fullText,
      ),
    );
    onStatusChanged?.call(updatedDoc);

    final chunks = await _chunkerService.createChunks(
      documentId: docId,
      documentName: currentDoc.name,
      pages: parsedResult.pages,
    );

    final totalTokens = TokenEstimator.estimateTokens(parsedResult.fullText);

    updatedDoc = DocumentModel.fromEntity(
      updatedDoc.copyWith(
        status: DocumentIndexStatus.ready,
        chunks: chunks,
        estimatedTokens: totalTokens,
      ),
    );

    await _localDataSource.saveDocument(updatedDoc);
    onStatusChanged?.call(updatedDoc);
    return updatedDoc;
  }

  @override
  Future<void> saveDocument(DocumentEntity document) {
    return _localDataSource.saveDocument(DocumentModel.fromEntity(document));
  }

  @override
  Future<void> deleteDocument(String documentId) {
    return _localDataSource.deleteDocument(documentId);
  }
}
