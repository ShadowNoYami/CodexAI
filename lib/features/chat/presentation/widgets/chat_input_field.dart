import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../../../documents/presentation/providers/documents_notifier.dart';
import '../../../documents/presentation/widgets/attached_files_bar.dart';
import '../providers/active_chat_notifier.dart';
import 'chat_sidebar.dart';
import 'quick_action_chips.dart';

/// Нижняя панель чата: включает индикатор прикрепленных файлов, выбор режима анализа,
/// быстрые чипы-действия, кнопку камеры/сканера и поле ввода.
class ChatInputField extends ConsumerStatefulWidget {
  const ChatInputField({super.key});

  @override
  ConsumerState<ChatInputField> createState() => _ChatInputFieldState();
}

class _ChatInputFieldState extends ConsumerState<ChatInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    ref.read(activeChatNotifierProvider.notifier).sendMessage(text);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = ref.watch(activeChatNotifierProvider);
    final docsState = ref.watch(documentsNotifierProvider);
    final hasAnyReadyDocs = docsState.readyDocuments.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompactMobile = constraints.maxWidth < 520;

        return Container(
          padding: EdgeInsets.fromLTRB(
            isCompactMobile ? 10 : 16,
            8,
            isCompactMobile ? 10 : 16,
            12,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Индикатор прикрепленных файлов и статуса парсинга / OCR
                  const AttachedFilesBar(),
                  if (hasAnyReadyDocs || docsState.isProcessingFile)
                    const SizedBox(height: 8),

                  // 2. Переключатель режима работы бота + Быстрые чипы-действия
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          'Режим:',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ...AnalysisMode.values.map((mode) {
                          final isSelected = chatState.analysisMode == mode;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                mode.displayName,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: isSelected,
                              visualDensity: VisualDensity.compact,
                              onSelected: chatState.isBusy
                                  ? null
                                  : (_) => ref
                                      .read(activeChatNotifierProvider.notifier)
                                      .setAnalysisMode(mode),
                            ),
                          );
                        }),
                        if (hasAnyReadyDocs) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 1,
                            height: 20,
                            color: theme.dividerColor,
                          ),
                          const SizedBox(width: 10),
                          const QuickActionChips(compact: true),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3. Строка ввода вопроса + Кнопка прикрепления/сканера + Кнопка камеры + Отправить
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Кнопка открытия меню добавления (Камера OCR / Галерея / Файлы)
                      IconButton.filledTonal(
                        tooltip: 'Добавить файл или сканировать документ',
                        visualDensity: isCompactMobile
                            ? VisualDensity.compact
                            : VisualDensity.standard,
                        onPressed: docsState.isProcessingFile
                            ? null
                            : () => ChatSidebar.showDocumentSourceSheet(
                                  context,
                                  ref,
                                ),
                        icon: const Icon(LucideIcons.paperclip, size: 18),
                      ),
                      const SizedBox(width: 6),
                      // Быстрая кнопка запуска камеры для телефона
                      IconButton.filledTonal(
                        tooltip: 'Сфотографировать документ камерой (OCR)',
                        visualDensity: isCompactMobile
                            ? VisualDensity.compact
                            : VisualDensity.standard,
                        onPressed: docsState.isProcessingFile
                            ? null
                            : () => ref
                                .read(documentsNotifierProvider.notifier)
                                .scanDocumentWithCamera(),
                        icon: const Icon(LucideIcons.camera, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.enter):
                                () {
                              if (!chatState.isBusy) {
                                _handleSend();
                              }
                            },
                          },
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) {
                              if (!chatState.isBusy) _handleSend();
                            },
                            decoration: InputDecoration(
                              hintText: hasAnyReadyDocs
                                  ? 'Вопрос по документу…'
                                  : 'Прикрепите файл/фото или введите вопрос…',
                              isDense: isCompactMobile,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: isCompactMobile ? 12 : 16,
                                vertical: isCompactMobile ? 10 : 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (chatState.isBusy)
                        isCompactMobile
                            ? IconButton.filled(
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.errorContainer,
                                  foregroundColor:
                                      theme.colorScheme.onErrorContainer,
                                ),
                                tooltip: 'Остановить генерацию',
                                onPressed: () => ref
                                    .read(activeChatNotifierProvider.notifier)
                                    .stopGeneration(),
                                icon: const Icon(LucideIcons.square, size: 16),
                              )
                            : FilledButton.tonalIcon(
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.errorContainer,
                                  foregroundColor:
                                      theme.colorScheme.onErrorContainer,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: () => ref
                                    .read(activeChatNotifierProvider.notifier)
                                    .stopGeneration(),
                                icon: const Icon(LucideIcons.square, size: 16),
                                label: const Text('Стоп'),
                              )
                      else
                        isCompactMobile
                            ? IconButton.filled(
                                tooltip: 'Отправить',
                                onPressed: _handleSend,
                                icon: const Icon(LucideIcons.send, size: 17),
                              )
                            : FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _handleSend,
                                icon: const Icon(LucideIcons.send, size: 16),
                                label: const Text('Отправить'),
                              ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
