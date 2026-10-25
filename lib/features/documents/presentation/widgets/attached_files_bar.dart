import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../chat/presentation/providers/active_chat_notifier.dart';
import '../../../chat/presentation/providers/chat_sessions_notifier.dart';
import '../../domain/entities/document_entity.dart';
import '../providers/documents_notifier.dart';
import 'document_preview_modal.dart';

/// Индикатор прикрепленных к чату документов и статуса их индексации над полем ввода.
class AttachedFilesBar extends ConsumerWidget {
  const AttachedFilesBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsState = ref.watch(documentsNotifierProvider);
    final sessionDocs = ref.watch(activeSessionDocumentsProvider);

    // Если к сессии явно не привязаны файлы, но есть готовые документы в базе — показываем их
    final effectiveDocs =
        sessionDocs.isNotEmpty ? sessionDocs : docsState.readyDocuments;

    if (!docsState.isProcessingFile && effectiveDocs.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Индикатор прогресса парсинга и индексации нового файла
        if (docsState.isProcessingFile)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    '${_statusLabel(docsState.processingStep)}: ${docsState.processingFileName ?? ""}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // Горизонтальная лента прикрепленных файлов
        if (effectiveDocs.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: effectiveDocs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final doc = effectiveDocs[index];
                return _AttachedDocChip(
                  document: doc,
                  onTap: () => DocumentPreviewModal.show(
                    context,
                    document: doc,
                  ),
                  onRemove: sessionDocs.isNotEmpty
                      ? () => ref
                          .read(chatSessionsNotifierProvider.notifier)
                          .toggleDocumentInActiveSession(doc.id)
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }

  String _statusLabel(DocumentIndexStatus? status) {
    switch (status) {
      case DocumentIndexStatus.parsing:
        return 'Извлечение текста (Isolate)';
      case DocumentIndexStatus.chunking:
        return 'Разбиение на чанки (RAG)';
      case DocumentIndexStatus.embedding:
        return 'Генерация эмбеддингов';
      default:
        return 'Обработка документа';
    }
  }
}

class _AttachedDocChip extends StatelessWidget {
  final DocumentEntity document;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _AttachedDocChip({
    required this.document,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _iconForExt(document.extension),
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  document.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '(${document.pageCount} стр.)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: theme.hintColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return LucideIcons.fileText;
      case 'docx':
        return LucideIcons.fileSpreadsheet;
      case 'csv':
        return LucideIcons.table;
      default:
        return LucideIcons.fileCode;
    }
  }
}
