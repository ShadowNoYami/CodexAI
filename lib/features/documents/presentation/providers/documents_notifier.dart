import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../ai_engine/data/repositories/ai_repository_impl.dart';
import '../../../ai_engine/domain/repositories/ai_repository.dart';
import '../../../chat/presentation/providers/chat_sessions_notifier.dart';
import '../../data/datasources/file_picker_service.dart';
import '../../data/repositories/document_repository_impl.dart';
import '../../domain/entities/document_entity.dart';
import '../../domain/repositories/document_repository.dart';

/// Состояние менеджера документов.
class DocumentsState {
  final List<DocumentEntity> documents;
  final bool isLoading;
  final bool isProcessingFile;
  final String? processingFileName;
  final DocumentIndexStatus? processingStep;
  final String? errorMessage;

  const DocumentsState({
    this.documents = const [],
    this.isLoading = false,
    this.isProcessingFile = false,
    this.processingFileName,
    this.processingStep,
    this.errorMessage,
  });

  /// Готовые к поиску и анализу документы.
  List<DocumentEntity> get readyDocuments =>
      documents.where((d) => d.isReady).toList(growable: false);

  DocumentsState copyWith({
    List<DocumentEntity>? documents,
    bool? isLoading,
    bool? isProcessingFile,
    String? processingFileName,
    bool clearProcessingInfo = false,
    DocumentIndexStatus? processingStep,
    String? errorMessage,
    bool clearError = false,
  }) {
    return DocumentsState(
      documents: documents ?? this.documents,
      isLoading: isLoading ?? this.isLoading,
      isProcessingFile: isProcessingFile ?? this.isProcessingFile,
      processingFileName: clearProcessingInfo
          ? null
          : (processingFileName ?? this.processingFileName),
      processingStep:
          clearProcessingInfo ? null : (processingStep ?? this.processingStep),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Провайдер состояния загруженных и проиндексированных документов.
final documentsNotifierProvider =
    StateNotifierProvider<DocumentsNotifier, DocumentsState>((ref) {
  final notifier = DocumentsNotifier(
    documentRepository: ref.watch(documentRepositoryProvider),
    aiRepository: ref.watch(aiRepositoryProvider),
    ref: ref,
  );
  notifier.loadSavedDocuments();
  return notifier;
});

/// Контроллер (`StateNotifier`) для управления загрузкой файлов, сканированием с камеры,
/// парсингом, индексацией и кэшированием документов в локальной БД.
class DocumentsNotifier extends StateNotifier<DocumentsState> {
  final DocumentRepository _documentRepository;
  final AiRepository _aiRepository;
  final Ref _ref;

  DocumentsNotifier({
    required DocumentRepository documentRepository,
    required AiRepository aiRepository,
    required Ref ref,
  })  : _documentRepository = documentRepository,
        _aiRepository = aiRepository,
        _ref = ref,
        super(const DocumentsState(isLoading: true));

  /// Загружает ранее сохраненные документы из локальной БД при старте приложения.
  Future<void> loadSavedDocuments() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final saved = await _documentRepository.getSavedDocuments();
      state = state.copyWith(
        documents: saved,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: _formatError(e),
      );
    }
  }

  /// Открывает системный выбор файлов (PDF, DOCX, TXT, CSV, MD, JPG, PNG).
  Future<List<DocumentEntity>> pickAndIndexFiles({
    bool attachToActiveSession = true,
  }) async {
    state = state.copyWith(clearError: true);
    try {
      final pickedFiles = await _documentRepository.pickFiles(
        allowMultiple: true,
      );
      if (pickedFiles.isEmpty) return const [];
      return await _processPickedList(
        pickedFiles,
        attachToActiveSession: attachToActiveSession,
      );
    } catch (e) {
      state = state.copyWith(
        isProcessingFile: false,
        clearProcessingInfo: true,
        errorMessage: _formatError(e),
      );
      return const [];
    }
  }

  /// Сканирует документ через камеру телефона и распознает текст с помощью Vision OCR.
  Future<DocumentEntity?> scanDocumentWithCamera({
    bool attachToActiveSession = true,
  }) async {
    state = state.copyWith(clearError: true);
    try {
      final captured = await _documentRepository.captureFromCamera();
      if (captured == null) return null;
      final processed = await _processPickedList(
        [captured],
        attachToActiveSession: attachToActiveSession,
      );
      return processed.firstOrNull;
    } catch (e) {
      state = state.copyWith(
        isProcessingFile: false,
        clearProcessingInfo: true,
        errorMessage: _formatError(e),
      );
      return null;
    }
  }

  /// Выбирает фотографии/сканы документов из галереи телефона и распознает текст через Vision OCR.
  Future<List<DocumentEntity>> pickPhotosFromGallery({
    bool attachToActiveSession = true,
  }) async {
    state = state.copyWith(clearError: true);
    try {
      final images = await _documentRepository.pickImagesFromGallery();
      if (images.isEmpty) return const [];
      return await _processPickedList(
        images,
        attachToActiveSession: attachToActiveSession,
      );
    } catch (e) {
      state = state.copyWith(
        isProcessingFile: false,
        clearProcessingInfo: true,
        errorMessage: _formatError(e),
      );
      return const [];
    }
  }

  Future<List<DocumentEntity>> _processPickedList(
    List<PickedDocumentFile> pickedFiles, {
    required bool attachToActiveSession,
  }) async {
    final newlyIndexed = <DocumentEntity>[];
    final llmConfig = _ref.read(llmSettingsProvider);

    for (final picked in pickedFiles) {
      state = state.copyWith(
        isProcessingFile: true,
        processingFileName: picked.name,
        processingStep: DocumentIndexStatus.parsing,
      );

      var processedDoc = await _documentRepository.processPickedFile(
        picked,
        llmConfig: llmConfig,
        onStatusChanged: (updatedDoc) {
          _upsertDocumentInMemory(updatedDoc);
          state = state.copyWith(
            isProcessingFile: updatedDoc.isProcessing,
            processingFileName: updatedDoc.name,
            processingStep: updatedDoc.status,
          );
        },
      );

      if (llmConfig.hasApiKey && processedDoc.estimatedTokens > 30000) {
        state = state.copyWith(
          processingStep: DocumentIndexStatus.embedding,
        );
        final enrichedChunks = await _aiRepository.enrichChunksWithEmbeddings(
          config: llmConfig,
          chunks: processedDoc.chunks,
        );
        processedDoc = processedDoc.copyWith(
          chunks: enrichedChunks,
          status: DocumentIndexStatus.ready,
        );
        await _documentRepository.saveDocument(processedDoc);
        _upsertDocumentInMemory(processedDoc);
      }

      newlyIndexed.add(processedDoc);

      if (attachToActiveSession && processedDoc.isReady) {
        await _ref
            .read(chatSessionsNotifierProvider.notifier)
            .attachDocumentToActiveSession(processedDoc.id);
      }
    }

    state = state.copyWith(
      isProcessingFile: false,
      clearProcessingInfo: true,
    );

    return newlyIndexed;
  }

  /// Удаляет документ из локальной БД и открепляет его от всех сессий чатов.
  Future<void> deleteDocument(String documentId) async {
    try {
      await _documentRepository.deleteDocument(documentId);
      final updated = state.documents
          .where((d) => d.id != documentId)
          .toList(growable: false);
      state = state.copyWith(documents: updated, clearError: true);

      await _ref
          .read(chatSessionsNotifierProvider.notifier)
          .removeDocumentFromAllSessions(documentId);
    } catch (e) {
      state = state.copyWith(errorMessage: _formatError(e));
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void _upsertDocumentInMemory(DocumentEntity doc) {
    final list = List<DocumentEntity>.from(state.documents);
    final idx = list.indexWhere((d) => d.id == doc.id);
    if (idx >= 0) {
      list[idx] = doc;
    } else {
      list.insert(0, doc);
    }
    state = state.copyWith(documents: list);
  }

  String _formatError(Object error) {
    if (error is AppException) return error.message;
    return error.toString();
  }
}
