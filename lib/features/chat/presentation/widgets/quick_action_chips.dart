import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../ai_engine/domain/entities/analysis_mode.dart';
import '../providers/active_chat_notifier.dart';

/// Быстрые чипы-действия («Сделать выжимку», «Выделить главное», «Найти риски»),
/// позволяющие в один клик запустить анализ загруженных документов.
class QuickActionChips extends ConsumerWidget {
  final bool compact;

  const QuickActionChips({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = ref.watch(
      activeChatNotifierProvider.select((s) => s.isBusy),
    );
    final notifier = ref.read(activeChatNotifierProvider.notifier);

    final actions = [
      (
        label: 'Сделать выжимку',
        icon: LucideIcons.sparkles,
        mode: AnalysisMode.executiveSummary,
      ),
      (
        label: 'Выделить главное',
        icon: LucideIcons.listChecks,
        mode: AnalysisMode.qa,
      ),
      (
        label: 'Найти риски',
        icon: LucideIcons.shieldAlert,
        mode: AnalysisMode.deepAnalysis,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions.map((item) {
        return ActionChip(
          avatar: Icon(
            item.icon,
            size: compact ? 14 : 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          label: Text(
            item.label,
            style: TextStyle(
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: isBusy ? null : () => notifier.runQuickAction(item.mode),
        );
      }).toList(),
    );
  }
}
