import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../../../ai_engine/domain/entities/cited_source.dart';
import '../../../documents/presentation/providers/documents_notifier.dart';
import '../../../documents/presentation/widgets/document_preview_modal.dart';
import '../../domain/entities/chat_message_entity.dart';
import '../providers/active_chat_notifier.dart';

/// Пузырь сообщения чата с рендерингом Markdown, таблиц, копированием блоков кода
/// и интерактивными ссылками на процитированные страницы документов.
class MessageBubble extends ConsumerWidget {
  final ChatMessageEntity message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final timeStr = DateFormat('HH:mm').format(message.timestamp);

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SelectableText(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.72),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Сообщение ИИ-ассистента
    final modeLabel = _resolveModeLabel(message.analysisMode);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: message.hasError
                ? theme.colorScheme.errorContainer.withValues(alpha: 0.25)
                : theme.colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
              color: message.hasError
                  ? theme.colorScheme.error.withValues(alpha: 0.5)
                  : theme.dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Верхняя строка: аватар ИИ, режим анализа, индикатор стриминга и кнопка копирования
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.bot,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          'AI Analyst',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (modeLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              modeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (message.isStreaming)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Печатает…',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  else ...[
                    Text(
                      timeStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Скопировать ответ целиком',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(LucideIcons.copy, size: 15),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: message.content),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ответ скопирован в буфер обмена'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Основное тело ответа с поддержкой Markdown, таблиц и копирования кода
              if (message.content.isEmpty && message.isStreaming)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Анализирую контекст документов и формирую ответ…',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.hintColor,
                    ),
                  ),
                )
              else
                MarkdownBody(
                  data: message.content,
                  selectable: true,
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  builders: {
                    'pre': _CodeBlockMarkdownBuilder(theme: theme),
                  },
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                    h1: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    h2: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    h3: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    blockquoteDecoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        left: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 3,
                        ),
                      ),
                    ),
                    tableBorder: TableBorder.all(
                      color: theme.dividerColor,
                      width: 1,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tableHead: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    tableBody: theme.textTheme.bodySmall,
                    tableCellsPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    code: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),

              // Кнопка повторного запроса при сетевой ошибке или таймауте
              if (message.hasError) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(activeChatNotifierProvider.notifier)
                        .retryLastMessage(),
                    icon: const Icon(LucideIcons.refreshCw, size: 14),
                    label: const Text('Повторить запрос'),
                  ),
                ),
              ],

              // Блок прикрепленных ссылок на источники (CitedSource)
              if (message.citations.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        LucideIcons.bookmark,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Процитированные источники и страницы (нажмите для предпросмотра):',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.hintColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: message.citations.map((citation) {
                    return _CitationChip(
                      citation: citation,
                      onTap: () => _openCitedDocument(context, ref, citation),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _resolveModeLabel(String? modeName) {
    if (modeName == null) return null;
    for (final m in AnalysisMode.values) {
      if (m.name == modeName) return m.displayName;
    }
    return null;
  }

  void _openCitedDocument(
    BuildContext context,
    WidgetRef ref,
    CitedSource citation,
  ) {
    final docs = ref.read(documentsNotifierProvider).documents;
    final doc = docs.where((d) => d.id == citation.documentId).firstOrNull;

    if (doc != null) {
      DocumentPreviewModal.show(
        context,
        document: doc,
        initialChunkIndex: citation.chunkIndex,
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(citation.displayLabel),
        content: SelectableText(citation.excerpt),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _CitationChip extends StatelessWidget {
  final CitedSource citation;
  final VoidCallback onTap;

  const _CitationChip({
    required this.citation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: citation.excerpt,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 270),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.fileSearch,
                  size: 13,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    citation.displayLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кастомный рендерер блоков кода `<pre><code>` с шапкой и кнопкой «Копировать код».
class _CodeBlockMarkdownBuilder extends MarkdownElementBuilder {
  final ThemeData theme;

  _CodeBlockMarkdownBuilder({required this.theme});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final codeText = element.textContent.trimRight();
    String language = 'code';

    if (element.children != null && element.children!.isNotEmpty) {
      final firstChild = element.children!.first;
      if (firstChild is md.Element &&
          firstChild.attributes['class'] != null) {
        language = firstChild.attributes['class']!
            .replaceFirst('language-', '')
            .trim();
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.terminal, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    language.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _CopyCodeButton(code: codeText),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              codeText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyCodeButton extends StatefulWidget {
  final String code;

  const _CopyCodeButton({required this.code});

  @override
  State<_CopyCodeButton> createState() => _CopyCodeButtonState();
}

class _CopyCodeButtonState extends State<_CopyCodeButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        if (!mounted) return;
        setState(() => _copied = true);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _copied = false);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? LucideIcons.check : LucideIcons.copy,
              size: 13,
              color: _copied ? Colors.green : theme.hintColor,
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Скопировано' : 'Копировать',
              style: theme.textTheme.labelSmall?.copyWith(
                color: _copied ? Colors.green : theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
