import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../documents/domain/entities/document_entity.dart';
import '../../../documents/presentation/providers/documents_notifier.dart';
import '../../../documents/presentation/widgets/document_preview_modal.dart';
import '../providers/active_chat_notifier.dart';
import '../providers/chat_sessions_notifier.dart';
import '../widgets/chat_input_field.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/quick_action_chips.dart';

/// Главный адаптивный экран приложения:
/// объединяет боковую панель (Sidebar / Drawer), ленту сообщений чата,
/// стартовый экран быстрых действий и панель ввода с прикрепленными документами.
class MainChatScreen extends ConsumerStatefulWidget {
  const MainChatScreen({super.key});

  @override
  ConsumerState<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends ConsumerState<MainChatScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      activeChatNotifierProvider.select((s) => s.messages.length),
      (_, __) => _scrollToBottom(),
    );

    final sessionsState = ref.watch(chatSessionsNotifierProvider);
    final chatState = ref.watch(activeChatNotifierProvider);
    final docsState = ref.watch(documentsNotifierProvider);
    final sessionDocs = ref.watch(activeSessionDocumentsProvider);

    final effectiveDocs =
        sessionDocs.isNotEmpty ? sessionDocs : docsState.readyDocuments;
    final activeTitle =
        sessionsState.activeSession?.title ?? 'AI Document Assistant';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 860;
        final theme = Theme.of(context);

        return Scaffold(
          drawer: isDesktop
              ? null
              : const Drawer(
                  width: 310,
                  child: ChatSidebar(isDrawer: true),
                ),
          body: Row(
            children: [
              if (isDesktop) const ChatSidebar(),
              Expanded(
                child: Column(
                  children: [
                    // Верхний AppBar активной сессии чата
                    _ChatTopBar(
                      isDesktop: isDesktop,
                      title: activeTitle,
                      activeDocs: effectiveDocs,
                      hasMessages: chatState.messages.isNotEmpty,
                    ),

                    // Баннер ошибок парсинга/валидации файлов (если возникли)
                    if (docsState.errorMessage != null)
                      _ErrorBanner(
                        message: docsState.errorMessage!,
                        onDismiss: () => ref
                            .read(documentsNotifierProvider.notifier)
                            .clearError(),
                      ),

                    // Основная область сообщений или приветственный экран с быстрыми действиями
                    Expanded(
                      child: chatState.isHistoryLoading
                          ? const Center(child: CircularProgressIndicator())
                          : chatState.messages.isEmpty
                              ? _EmptyChatWorkspace(
                                  readyDocs: effectiveDocs,
                                  isProcessingFile: docsState.isProcessingFile,
                                )
                              : Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 880,
                                    ),
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      itemCount: chatState.messages.length,
                                      itemBuilder: (context, index) {
                                        final msg = chatState.messages[index];
                                        return MessageBubble(message: msg);
                                      },
                                    ),
                                  ),
                                ),
                    ),

                    // Нижняя панель с индикатором прикрепленных файлов, чипами и полем ввода
                    Container(
                      color: theme.colorScheme.surface,
                      child: const ChatInputField(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatTopBar extends ConsumerWidget {
  final bool isDesktop;
  final String title;
  final List<DocumentEntity> activeDocs;
  final bool hasMessages;

  const _ChatTopBar({
    required this.isDesktop,
    required this.title,
    required this.activeDocs,
    required this.hasMessages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            Builder(
              builder: (ctx) => IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Меню чатов и документов',
                icon: const Icon(LucideIcons.menu),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  activeDocs.isEmpty
                      ? 'Документы не выбраны • PDF, DOCX, TXT, CSV или Камера'
                      : 'В контексте: ${activeDocs.length} док. (~${activeDocs.fold<int>(0, (s, d) => s + d.estimatedTokens)} ток.)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.hintColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (activeDocs.isNotEmpty)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Предпросмотр документа',
              onPressed: () => DocumentPreviewModal.show(
                context,
                document: activeDocs.first,
              ),
              icon: const Icon(LucideIcons.fileSearch, size: 18),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Сканировать документ камерой',
            icon: const Icon(LucideIcons.camera, size: 18),
            onPressed: () => ref
                .read(documentsNotifierProvider.notifier)
                .scanDocumentWithCamera(),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Добавить документ или фото',
            icon: const Icon(LucideIcons.upload, size: 18),
            onPressed: () => ChatSidebar.showDocumentSourceSheet(context, ref),
          ),
          if (hasMessages)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Очистить историю текущего чата',
              icon: const Icon(LucideIcons.eraser, size: 18),
              onPressed: () => ref
                  .read(activeChatNotifierProvider.notifier)
                  .clearActiveChatHistory(),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Настройки LLM API',
            icon: const Icon(LucideIcons.sliders, size: 18),
            onPressed: () => ChatSidebar.showLlmSettingsDialog(context),
          ),
        ],
      ),
    );
  }
}

class _EmptyChatWorkspace extends ConsumerWidget {
  final List<DocumentEntity> readyDocs;
  final bool isProcessingFile;

  const _EmptyChatWorkspace({
    required this.readyDocs,
    required this.isProcessingFile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final docsNotifier = ref.read(documentsNotifierProvider.notifier);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  LucideIcons.fileSpreadsheet,
                  size: 30,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Интеллектуальный анализ документов (RAG)',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Загрузите файлы (PDF, DOCX, TXT, CSV, MD) или сфотографируйте документ камерой телефона для мгновенного Vision OCR распознавания и анализа.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              if (readyDocs.isEmpty) ...[
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: isProcessingFile
                          ? null
                          : () => docsNotifier.pickAndIndexFiles(),
                      icon: const Icon(LucideIcons.filePlus2, size: 18),
                      label: const Text('Выбрать файлы (PDF, DOCX, TXT, CSV)'),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      onPressed: isProcessingFile
                          ? null
                          : () => docsNotifier.scanDocumentWithCamera(),
                      icon: const Icon(LucideIcons.camera, size: 18),
                      label: const Text('Сканировать камерой'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                      ),
                      onPressed: isProcessingFile
                          ? null
                          : () => docsNotifier.pickPhotosFromGallery(),
                      icon: const Icon(LucideIcons.image, size: 18),
                      label: const Text('Фото из галереи'),
                    ),
                  ],
                ),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.checkCircle2,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Готово к анализу документов: ${readyDocs.length}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => DocumentPreviewModal.show(
                                context,
                                document: readyDocs.first,
                              ),
                              icon: const Icon(LucideIcons.eye, size: 15),
                              label: const Text('Открыть'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Быстрые действия с загруженным документом:',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const QuickActionChips(),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            LucideIcons.alertTriangle,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              LucideIcons.x,
              size: 16,
              color: theme.colorScheme.onErrorContainer,
            ),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
