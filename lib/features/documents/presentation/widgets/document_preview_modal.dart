import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/document_chunk_entity.dart';
import '../../domain/entities/document_entity.dart';

/// Модальное окно предпросмотра документа: отображает метаданные, статистику токенов,
/// список проиндексированных чанков со страницами и полный извлеченный текст.
class DocumentPreviewModal extends StatefulWidget {
  final DocumentEntity document;
  final int? initialChunkIndex;

  const DocumentPreviewModal({
    super.key,
    required this.document,
    this.initialChunkIndex,
  });

  /// Открывает модальное окно предпросмотра документа.
  static Future<void> show(
    BuildContext context, {
    required DocumentEntity document,
    int? initialChunkIndex,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 880,
            maxHeight: 720,
          ),
          child: DocumentPreviewModal(
            document: document,
            initialChunkIndex: initialChunkIndex,
          ),
        ),
      ),
    );
  }

  @override
  State<DocumentPreviewModal> createState() => _DocumentPreviewModalState();
}

class _DocumentPreviewModalState extends State<DocumentPreviewModal>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<DocumentChunkEntity> get _filteredChunks {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return widget.document.chunks;
    return widget.document.chunks
        .where(
          (c) =>
              c.content.toLowerCase().contains(q) ||
              (c.pageNumber != null && 'стр. ${c.pageNumber}'.contains(q)),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = widget.document;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Верхняя шапка с метаданными документа
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.45,
            ),
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _FileExtensionBadge(extension: doc.extension),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          doc.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _MetaStatChip(
                              icon: LucideIcons.hardDrive,
                              label: doc.formattedSize,
                            ),
                            _MetaStatChip(
                              icon: LucideIcons.bookOpen,
                              label: '${doc.pageCount} стр.',
                            ),
                            _MetaStatChip(
                              icon: LucideIcons.layers,
                              label: '${doc.chunks.length} чанков',
                            ),
                            _MetaStatChip(
                              icon: LucideIcons.cpu,
                              label: '~${doc.estimatedTokens} токенов',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Скопировать весь текст',
                    icon: const Icon(LucideIcons.copy, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: doc.fullText),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Полный текст документа скопирован'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    icon: const Icon(LucideIcons.x),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    icon: const Icon(LucideIcons.layers, size: 16),
                    text: 'Индекс чанков (${doc.chunks.length})',
                  ),
                  const Tab(
                    icon: Icon(LucideIcons.fileText, size: 16),
                    text: 'Полный извлеченный текст',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Содержимое вкладок
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Вкладка 1: Список чанков с поиском по тексту
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Поиск по фрагментам и страницам документа…',
                        prefixIcon: Icon(LucideIcons.search, size: 18),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                    ),
                  ),
                  Expanded(
                    child: _filteredChunks.isEmpty
                        ? Center(
                            child: Text(
                              'Фрагменты по запросу не найдены',
                              style: theme.textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredChunks.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final chunk = _filteredChunks[index];
                              final isHighlighted = widget.initialChunkIndex !=
                                      null &&
                                  chunk.index == widget.initialChunkIndex;
                              return _ChunkCard(
                                chunk: chunk,
                                isHighlighted: isHighlighted,
                              );
                            },
                          ),
                  ),
                ],
              ),

              // Вкладка 2: Полный текст документа
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  doc.fullText.isEmpty
                      ? 'Текст документа пуст.'
                      : doc.fullText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.55,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChunkCard extends StatelessWidget {
  final DocumentChunkEntity chunk;
  final bool isHighlighted;

  const _ChunkCard({
    required this.chunk,
    required this.isHighlighted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: isHighlighted
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlighted
              ? theme.colorScheme.primary
              : theme.dividerColor,
          width: isHighlighted ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Фрагмент #${chunk.index + 1}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (chunk.pageNumber != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Страница ${chunk.pageNumber}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '~${chunk.estimatedTokens} ток.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Скопировать фрагмент',
                visualDensity: VisualDensity.compact,
                icon: const Icon(LucideIcons.copy, size: 15),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: chunk.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Фрагмент #${chunk.index + 1} скопирован в буфер обмена',
                      ),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            chunk.content,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FileExtensionBadge extends StatelessWidget {
  final String extension;

  const _FileExtensionBadge({required this.extension});

  @override
  Widget build(BuildContext context) {
    final ext = extension.toUpperCase();
    final Color color;
    switch (extension.toLowerCase()) {
      case 'pdf':
        color = const Color(0xFFEF4444);
        break;
      case 'docx':
        color = const Color(0xFF2563EB);
        break;
      case 'csv':
        color = const Color(0xFF10B981);
        break;
      default:
        color = const Color(0xFFF59E0B);
    }

    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        ext,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MetaStatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaStatChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.hintColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.hintColor,
          ),
        ),
      ],
    );
  }
}
