import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app.dart';
import '../../../../core/config/env_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../../../documents/domain/entities/document_entity.dart';
import '../../../documents/presentation/providers/documents_notifier.dart';
import '../../../documents/presentation/widgets/document_preview_modal.dart';
import '../../domain/entities/chat_session_entity.dart';
import '../providers/chat_sessions_notifier.dart';

/// Боковая панель (Sidebar / Drawer) для переключения между сессиями чатов,
/// управления загруженными документами и настройки параметров LLM API.
class ChatSidebar extends ConsumerStatefulWidget {
  final bool isDrawer;

  const ChatSidebar({
    super.key,
    this.isDrawer = false,
  });

  /// Открывает диалог настроек LLM API (Gemini / OpenAI-совместимый провайдер).
  static Future<void> showLlmSettingsDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => const _LlmSettingsDialog(),
    );
  }

  /// Открывает презентацию проекта (HTML / PDF / PPTX) через url_launcher.
  static Future<void> openProjectPresentation(BuildContext context) async {
    final uri = kIsWeb
        ? Uri.base.resolve('docs/presentation.html')
        : Uri.file(
            '${Directory.current.path}${Platform.pathSeparator}docs${Platform.pathSeparator}presentation.html',
          );

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Файлы презентации находятся в папке docs/'),
        ),
      );
    }
  }

  /// Открывает нижнюю шторку выбора источника документа: Камера (OCR), Галерея фото или Файлы.
  static Future<void> showDocumentSourceSheet(
    BuildContext context,
    WidgetRef ref,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        final notifier = ref.read(documentsNotifierProvider.notifier);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Добавить документ для ИИ-анализа',
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(sheetCtx)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.14),
                    child: Icon(
                      LucideIcons.camera,
                      color: Theme.of(sheetCtx).colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Сканировать камерой (Vision OCR)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Сфотографировать договор, чек, таблицу или страницу книги',
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    notifier.scanDocumentWithCamera();
                  },
                ),
                const SizedBox(height: 4),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(sheetCtx)
                        .colorScheme
                        .secondary
                        .withValues(alpha: 0.14),
                    child: Icon(
                      LucideIcons.image,
                      color: Theme.of(sheetCtx).colorScheme.secondary,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Выбрать фото / скан из галереи',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Распознать текст и таблицы с готовых фотографий (JPG, PNG)',
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    notifier.pickPhotosFromGallery();
                  },
                ),
                const SizedBox(height: 4),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(sheetCtx)
                        .colorScheme
                        .tertiary
                        .withValues(alpha: 0.14),
                    child: Icon(
                      LucideIcons.fileText,
                      color: Theme.of(sheetCtx).colorScheme.tertiary,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Выбрать файлы (PDF, DOCX, TXT, CSV, MD)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Загрузить документы из памяти телефона или компьютера',
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    notifier.pickAndIndexFiles();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  ConsumerState<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends ConsumerState<ChatSidebar> {
  int _selectedSection = 0; // 0 = Чаты, 1 = Документы

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sessionsState = ref.watch(chatSessionsNotifierProvider);
    final docsState = ref.watch(documentsNotifierProvider);
    final llmConfig = ref.watch(llmSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Container(
      width: 310,
      decoration: BoxDecoration(
        color: isDark ? AppColors.sidebarDark : AppColors.sidebarLight,
        border: widget.isDrawer
            ? null
            : Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Брендовая шапка и кнопка создания нового чата
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          LucideIcons.sparkles,
                          size: 18,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Doc Assistant',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'RAG • Камера OCR • Анализ',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      await ref
                          .read(chatSessionsNotifierProvider.notifier)
                          .createNewSession();
                      if (widget.isDrawer && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Новый диалог'),
                  ),
                ],
              ),
            ),

            // 2. Переключатель разделов: Сессии чатов / База документов
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 0,
                    icon: const Icon(LucideIcons.messageSquare, size: 15),
                    label: Text('Чаты (${sessionsState.sessions.length})'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: const Icon(LucideIcons.folderOpen, size: 15),
                    label: Text('Файлы (${docsState.documents.length})'),
                  ),
                ],
                selected: {_selectedSection},
                onSelectionChanged: (selection) {
                  setState(() => _selectedSection = selection.first);
                },
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),

            // 3. Список сессий чатов или загруженных документов
            Expanded(
              child: _selectedSection == 0
                  ? _SessionsListView(
                      sessions: sessionsState.sessions,
                      activeSessionId: sessionsState.activeSessionId,
                      isDrawer: widget.isDrawer,
                    )
                  : _DocumentsListView(
                      documents: docsState.documents,
                      activeSession: sessionsState.activeSession,
                      isProcessing: docsState.isProcessingFile,
                    ),
            ),

            const Divider(height: 1),

            // 4. Нижняя панель: презентация проекта, статус API-ключа и переключение темы
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    onPressed: () =>
                        ChatSidebar.openProjectPresentation(context),
                    icon: const Icon(LucideIcons.presentation, size: 15),
                    label: const Text(
                      'Открыть презентацию проекта',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              ChatSidebar.showLlmSettingsDialog(context),
                          icon: Icon(
                            LucideIcons.keyRound,
                            size: 15,
                            color: llmConfig.hasApiKey
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                          label: Text(
                            llmConfig.hasApiKey
                                ? llmConfig.model
                                : 'Настроить API',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Переключить тему (Светлая / Темная)',
                        icon: Icon(
                          themeMode == ThemeMode.dark
                              ? LucideIcons.sun
                              : LucideIcons.moon,
                          size: 17,
                        ),
                        onPressed: () {
                          final next = themeMode == ThemeMode.dark
                              ? ThemeMode.light
                              : ThemeMode.dark;
                          ref.read(themeModeProvider.notifier).state = next;
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionsListView extends ConsumerWidget {
  final List<ChatSessionEntity> sessions;
  final String? activeSessionId;
  final bool isDrawer;

  const _SessionsListView({
    required this.sessions,
    required this.activeSessionId,
    required this.isDrawer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          'Нет активных диалогов',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final session = sessions[index];
        final isSelected = session.id == activeSessionId;

        return Material(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              ref
                  .read(chatSessionsNotifierProvider.notifier)
                  .selectSession(session.id);
              if (isDrawer && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.messageSquare,
                    size: 16,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.hintColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (session.lastMessagePreview != null &&
                            session.lastMessagePreview!.isNotEmpty)
                          Text(
                            session.lastMessagePreview!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.hintColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (session.documentIds.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.secondary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${session.documentIds.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.secondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Удалить диалог',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      LucideIcons.trash2,
                      size: 14,
                      color: theme.hintColor,
                    ),
                    onPressed: () => ref
                        .read(chatSessionsNotifierProvider.notifier)
                        .deleteSession(session.id),
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

class _DocumentsListView extends ConsumerWidget {
  final List<DocumentEntity> documents;
  final ChatSessionEntity? activeSession;
  final bool isProcessing;

  const _DocumentsListView({
    required this.documents,
    required this.activeSession,
    required this.isProcessing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(documentsNotifierProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed:
                    isProcessing ? null : () => notifier. pickAndIndexFiles(),
                icon: const Icon(LucideIcons.upload, size: 15),
                label: const Text('Выбрать файл (PDF, DOCX, CSV)'),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () => notifier.scanDocumentWithCamera(),
                      icon: const Icon(LucideIcons.camera, size: 14),
                      label: const Text(
                        'Камера',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () => notifier.pickPhotosFromGallery(),
                      icon: const Icon(LucideIcons.image, size: 14),
                      label: const Text(
                        'Галерея',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: documents.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Загрузите PDF, DOCX, TXT, CSV файлы или сфотографируйте документ камерой телефона.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: documents.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final doc = documents[index];
                    final isAttached =
                        activeSession?.documentIds.contains(doc.id) ?? false;

                    return Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isAttached
                              ? theme.colorScheme.primary.withValues(alpha: 0.5)
                              : theme.dividerColor,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        onTap: doc.isReady
                            ? () => DocumentPreviewModal.show(
                                  context,
                                  document: doc,
                                )
                            : null,
                        leading: Checkbox(
                          visualDensity: VisualDensity.compact,
                          value: isAttached,
                          onChanged: doc.isReady
                              ? (_) => ref
                                  .read(chatSessionsNotifierProvider.notifier)
                                  .toggleDocumentInActiveSession(doc.id)
                              : null,
                        ),
                        title: Text(
                          doc.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          doc.hasError
                              ? 'Ошибка чтения'
                              : '${doc.pageCount} стр. • ${doc.chunks.length} чанк. • ${doc.formattedSize}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: doc.hasError
                                ? theme.colorScheme.error
                                : theme.hintColor,
                            fontSize: 10,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (doc.isReady)
                              IconButton(
                                tooltip: 'Предпросмотр документа',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(LucideIcons.eye, size: 15),
                                onPressed: () => DocumentPreviewModal.show(
                                  context,
                                  document: doc,
                                ),
                              ),
                            IconButton(
                              tooltip: 'Удалить из базы',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(LucideIcons.trash2, size: 14),
                              onPressed: () => ref
                                  .read(documentsNotifierProvider.notifier)
                                  .deleteDocument(doc.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LlmSettingsDialog extends ConsumerStatefulWidget {
  const _LlmSettingsDialog();

  @override
  ConsumerState<_LlmSettingsDialog> createState() => _LlmSettingsDialogState();
}

class _LlmSettingsDialogState extends ConsumerState<_LlmSettingsDialog> {
  late LlmProviderType _provider;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;

  @override
  void initState() {
    super.initState();
    final current = ref.read(llmSettingsProvider);
    _provider = current.provider;
    _apiKeyController = TextEditingController(text: current.apiKey);
    _baseUrlController = TextEditingController(text: current.baseUrl);
    _modelController = TextEditingController(text: current.model);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _onProviderChanged(LlmProviderType? next) {
    if (next == null) return;
    setState(() {
      _provider = next;
      if (next == LlmProviderType.gemini) {
        _baseUrlController.text = EnvConfig.defaultGeminiBaseUrl;
        _modelController.text = EnvConfig.defaultGeminiModel;
      } else {
        _baseUrlController.text = EnvConfig.defaultOpenAiBaseUrl;
        _modelController.text = EnvConfig.defaultOpenAiModel;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Row(
        children: [
          Icon(LucideIcons.settings, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Настройки ИИ (LLM API)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<LlmProviderType>(
                isExpanded: true,
                initialValue: _provider,
                decoration: const InputDecoration(
                  labelText: 'Провайдер API',
                ),
                items: LlmProviderType.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Text(
                      p.displayName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _onProviderChanged,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Ключ',
                  hintText: 'AQ.Ab8... или AIzaSy... или sk-...',
                  prefixIcon: Icon(LucideIcons.key, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: 'Модель LLM',
                  hintText: 'gemini-3.5-flash или gpt-4o-mini',
                  prefixIcon: Icon(LucideIcons.cpu, size: 18),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  prefixIcon: Icon(LucideIcons.globe, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () async {
            await ref.read(llmSettingsProvider.notifier).updateSettings(
                  provider: _provider,
                  apiKey: _apiKeyController.text,
                  baseUrl: _baseUrlController.text,
                  model: _modelController.text,
                );
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
