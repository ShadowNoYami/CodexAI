import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../../core/config/env_config.dart';
import '../../../../core/error/exceptions.dart';

/// Контейнер для выбранного и прошедшего первичную валидацию файла или фото со сканера/камеры.
class PickedDocumentFile {
  final String name;
  final String extension;
  final int sizeBytes;
  final Uint8List bytes;
  final String? filePath;

  const PickedDocumentFile({
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.bytes,
    this.filePath,
  });

  bool get isImage =>
      const ['jpg', 'jpeg', 'png', 'webp'].contains(extension.toLowerCase());
}

/// Провайдер сервиса выбора файлов и сканирования документов через камеру/галерею.
final filePickerServiceProvider = Provider<FilePickerService>((ref) {
  return const FilePickerService();
});

/// Сервис выбора и строгой валидации пользовательских документов
/// (PDF, DOCX, TXT, CSV, MD, а также фото/сканов JPG, PNG, WEBP с камеры или галереи).
class FilePickerService {
  const FilePickerService();

  static const List<String> supportedExtensions = [
    'pdf',
    'docx',
    'txt',
    'csv',
    'md',
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  /// Открывает системный диалог выбора файлов и валидирует каждый выбранный документ.
  Future<List<PickedDocumentFile>> pickAndValidateFiles({
    bool allowMultiple = true,
  }) async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedExtensions,
        allowMultiple: allowMultiple,
        withData: true,
      );
    } catch (e, st) {
      throw FileValidationException(
        'Не удалось открыть диалог выбора файлов: $e',
        cause: e,
        stackTrace: st,
      );
    }

    if (result == null || result.files.isEmpty) {
      return const [];
    }

    final validatedFiles = <PickedDocumentFile>[];
    for (final platformFile in result.files) {
      validatedFiles.add(validatePlatformFile(platformFile));
    }

    return validatedFiles;
  }

  /// Открывает камеру телефона/планшета для фотографирования страницы документа (OCR-сканер).
  Future<PickedDocumentFile?> captureDocumentFromCamera() async {
    try {
      final XFile? photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (photo == null) return null;

      return await _validateXFile(photo, isCameraCapture: true);
    } catch (e, st) {
      if (e is FileValidationException) rethrow;
      throw FileValidationException(
        'Не удалось сделать снимок документа с камеры: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  /// Открывает фотогалерею устройства для выбора одного или нескольких фото/сканов документов.
  Future<List<PickedDocumentFile>> pickDocumentImagesFromGallery() async {
    try {
      final List<XFile> images = await ImagePicker().pickMultiImage(
        imageQuality: 90,
        maxWidth: 2400,
        maxHeight: 2400,
      );
      if (images.isEmpty) return const [];

      final results = <PickedDocumentFile>[];
      for (final img in images) {
        results.add(await _validateXFile(img, isCameraCapture: false));
      }
      return results;
    } catch (e, st) {
      if (e is FileValidationException) rethrow;
      throw FileValidationException(
        'Не удалось загрузить фото документа из галереи: $e',
        cause: e,
        stackTrace: st,
      );
    }
  }

  Future<PickedDocumentFile> _validateXFile(
    XFile xFile, {
    required bool isCameraCapture,
  }) async {
    final bytes = await xFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const FileValidationException('Снимок документа пуст.');
    }

    String ext = p.extension(xFile.name).replaceAll('.', '').toLowerCase();
    if (ext.isEmpty || !const ['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      ext = 'jpg';
    }

    final timestamp = DateFormat('dd-MM_HH-mm-ss').format(DateTime.now());
    final displayName = isCameraCapture
        ? 'Скан_камеры_$timestamp.$ext'
        : (xFile.name.isNotEmpty ? xFile.name : 'Фото_документа_$timestamp.$ext');

    return PickedDocumentFile(
      name: displayName,
      extension: ext,
      sizeBytes: bytes.lengthInBytes,
      bytes: bytes,
      filePath: kIsWeb ? null : xFile.path,
    );
  }

  /// Проверяет расширение, размер, наличие байтов и сигнатуру заголовка файла.
  PickedDocumentFile validatePlatformFile(PlatformFile file) {
    final fileName = file.name.trim();
    if (fileName.isEmpty) {
      throw const FileValidationException('Имя выбранного файла пустое.');
    }

    final rawExt = (file.extension ?? p.extension(fileName))
        .replaceAll('.', '')
        .toLowerCase()
        .trim();

    if (!supportedExtensions.contains(rawExt)) {
      throw FileValidationException(
        'Формат ".$rawExt" не поддерживается (файл "$fileName"). '
        'Допустимые форматы: ${supportedExtensions.map((e) => e.toUpperCase()).join(", ")}.',
      );
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty || file.size <= 0) {
      throw FileValidationException(
        'Файл "$fileName" пуст или не удалось прочитать его содержимое.',
      );
    }

    if (bytes.lengthInBytes > EnvConfig.maxFileSizeBytes) {
      final maxMb = EnvConfig.maxFileSizeBytes ~/ (1024 * 1024);
      final actualMb = (bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
      throw FileValidationException(
        'Файл "$fileName" ($actualMb МБ) превышает максимальный лимит $maxMb МБ.',
      );
    }

    _validateMagicBytes(fileName: fileName, extension: rawExt, bytes: bytes);

    return PickedDocumentFile(
      name: fileName,
      extension: rawExt,
      sizeBytes: bytes.lengthInBytes,
      bytes: bytes,
      filePath: kIsWeb ? null : file.path,
    );
  }

  /// Проверяет сигнатуру файла (Magic Bytes), чтобы перехватить переименованные или битые файлы.
  void _validateMagicBytes({
    required String fileName,
    required String extension,
    required Uint8List bytes,
  }) {
    if (extension == 'pdf') {
      final checkLength = bytes.length < 1024 ? bytes.length : 1024;
      bool hasPdfHeader = false;
      for (var i = 0; i <= checkLength - 4; i++) {
        if (bytes[i] == 0x25 &&
            bytes[i + 1] == 0x50 &&
            bytes[i + 2] == 0x44 &&
            bytes[i + 3] == 0x46) {
          hasPdfHeader = true;
          break;
        }
      }
      if (!hasPdfHeader) {
        throw FileValidationException(
          'Файл "$fileName" имеет расширение .pdf, но его заголовок поврежден или не является PDF-документом.',
        );
      }
    } else if (extension == 'docx') {
      if (bytes.length >= 4 &&
          bytes[0] == 0xD0 &&
          bytes[1] == 0xCF &&
          bytes[2] == 0x11 &&
          bytes[3] == 0xE0) {
        throw FileValidationException(
          'Файл "$fileName" имеет старый бинарный формат Word 97–2003 (.doc), переименованный в .docx. Сохраните его в современном формате .docx или .pdf.',
        );
      }

      if (bytes.length < 4 ||
          bytes[0] != 0x50 ||
          bytes[1] != 0x4B ||
          bytes[2] != 0x03 ||
          bytes[3] != 0x04) {
        throw FileValidationException(
          'Файл "$fileName" поврежден или не является корректным документом Word (.docx).',
        );
      }
    } else if (extension == 'txt' || extension == 'csv' || extension == 'md') {
      final sampleLen = bytes.length < 2048 ? bytes.length : 2048;
      var nullBytes = 0;
      for (var i = 0; i < sampleLen; i++) {
        if (bytes[i] == 0x00) nullBytes++;
      }
      if (nullBytes > 2) {
        throw FileValidationException(
          'Файл "$fileName" содержит бинарные данные и не является текстовым файлом (.$extension).',
        );
      }
    }
  }
}
