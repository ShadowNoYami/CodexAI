import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../../data/datasources/file_picker_service.dart';
import '../entities/document_entity.dart';

/// Колбэк для отслеживания промежуточных этапов обработки документа (parsing -> chunking -> ready).
typedef DocumentStatusCallback = void Function(DocumentEntity updatedDocument);

/// Контракт репозитория работы с документами, камерой/галереей и локальным кэшем БД (Domain-слой).
abstract interface class DocumentRepository {
  /// Загружает все ранее проиндексированные документы из локальной БД.
  Future<List<DocumentEntity>> getSavedDocuments();

  /// Открывает диалог выбора файлов (PDF, DOCX, TXT, CSV, MD, JPG, PNG).
  Future<List<PickedDocumentFile>> pickFiles({bool allowMultiple = true});

  /// Делает снимок страницы документа с камеры устройства.
  Future<PickedDocumentFile?> captureFromCamera();

  /// Выбирает фото или сканы документов из галереи устройства.
  Future<List<PickedDocumentFile>> pickImagesFromGallery();

  /// Полный цикл обработки выбранного файла или снимка с камеры:
  /// 1) Извлечение текста по страницам в фоновом изоляте (или Vision OCR для фото);
  /// 2) Разбиение на семантические чанки с перекрытием;
  /// 3) Подсчет токенов и сохранение готового [DocumentEntity] в локальную БД.
  Future<DocumentEntity> processPickedFile(
    PickedDocumentFile pickedFile, {
    LlmConfig? llmConfig,
    DocumentStatusCallback? onStatusChanged,
  });

  /// Сохраняет (или обновляет) документ и его чанки в локальной БД.
  Future<void> saveDocument(DocumentEntity document);

  /// Удаляет документ и его чанки из локальной БД.
  Future<void> deleteDocument(String documentId);
}
