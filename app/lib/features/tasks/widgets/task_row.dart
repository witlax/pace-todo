import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/db/database.dart';
import '../../../core/ui/confirm.dart';
import '../../../core/ui/schedule_sheet.dart';
import '../../focus/focus_controller.dart';
import '../../settings/settings.dart';
import '../../focus/focus_page.dart';
import '../task_repository.dart';
import '../../../core/i18n/i18n.dart';

/// pinch 风格的任务行：一个圆圈 + 一行标题 + 右侧「⋯」。
///
/// 与旧的 `TaskTile` 的区别是「不解释」：不画重要性色条、不写「重要性 低」，
/// 需要的信息都收进「⋯」菜单里。首页任务区一屏能多放 3–4 条。
class TaskRow extends ConsumerStatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpen,
    this.onDelete,
    this.onArchive,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onArchive;

  @override
  ConsumerState<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<TaskRow> {
  bool _expanded = false;

  Task get task => widget.task;
  bool get _done => task.status == 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subs = ref.watch(subtasksProvider(task.id)).value ?? const <Task>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mainRow(context, scheme, subs),
        if (_expanded && subs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(38, 0, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final sub in subs)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => ref
                        .read(taskRepositoryProvider)
                        .setDone(sub.id, sub.status != 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            sub.status == 1
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 14,
                            color: sub.status == 1
                                ? context.appColors.done
                                : scheme.outline,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              sub.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: sub.status == 1
                                    ? scheme.outline
                                    : scheme.onSurfaceVariant,
                                decoration: sub.status == 1
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mainRow(BuildContext context, ColorScheme scheme, List<Task> subs) {
    // 重要性色条：左侧一条竖线 + 卡片极淡的同色底，扫一眼就能分出轻重。
    final palette = ref.watch(paletteProvider);
    final emphasis = Emphasis.fromValue(task.importance);
    final accent = palette.of(emphasis);
    final showAccent = !_done && emphasis != Emphasis.none;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: showAccent
            ? Color.alphaBlend(accent.withValues(alpha: 0.06), scheme.surface)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onOpen,
        onLongPress: () => _menu(context, ref),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 20,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: showAccent ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onToggle();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _Circle(done: _done),
                ),
              ),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.3,
                    color: _done ? scheme.outline : scheme.onSurface,
                    decoration: _done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (task.dueAt != null && !_done)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    DateFormat('M-d').format(task.dueAt!),
                    style: TextStyle(fontSize: 10, color: scheme.outline),
                  ),
                ),
              if (subs.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 17,
                      color: scheme.outline,
                    ),
                  ),
                ),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _menu(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.more_horiz,
                    size: 17,
                    color: scheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.today_outlined, size: 19),
              title: Text(tr('排到今天 18:00'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('today'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.event_outlined, size: 19),
              title: Text(tr('自定义排期…'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('schedule'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.flag_outlined, size: 19),
              title: Text(
                task.importance >= 3 ? tr('取消高重要性') : tr('设为高重要性'),
                style: TextStyle(fontSize: 13.5),
              ),
              onTap: () => Navigator.of(ctx).pop('importance'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.center_focus_strong_outlined, size: 19),
              title: Text(tr('开始专注'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('focus'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.archive_outlined, size: 19),
              title: Text(tr('归档'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('archive'),
            ),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.delete_outline,
                size: 19,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                tr('删除'),
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'today':
        final now = DateTime.now();
        await repo.updateTask(
          task.id,
          dueAt: DateTime(now.year, now.month, now.day, 18),
        );
      case 'schedule':
        final res = await ScheduleSheet.show(context, initialDue: task.dueAt);
        if (res == null || !context.mounted) return;
        if (res.dueAt == null) {
          await repo.updateTask(task.id, clearDue: true);
        } else {
          await repo.updateTask(task.id, dueAt: res.dueAt);
        }
      case 'importance':
        await repo.updateTask(
          task.id,
          importance: task.importance >= 3 ? 0 : 3,
        );
      case 'focus':
        ref.read(focusControllerProvider.notifier).selectTask(
          task.id,
          task.title,
        );
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => FocusPage()),
        );
      case 'archive':
        widget.onArchive?.call();
      case 'delete':
        final ok = await confirmDanger(
          context,
          title: trf('删除「{}」？', [task.title]),
          message: tr('任务会移到回收站，保留 30 天，期间可以恢复。'),
        );
        if (ok) widget.onDelete?.call();
    }
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      key: ValueKey('row-check-$done'),
      tween: Tween<double>(begin: done ? 0.55 : 1.1, end: 1),
      duration: Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: done ? context.appColors.done : Colors.transparent,
          border: Border.all(
            color: done ? context.appColors.done : scheme.outlineVariant,
            width: 1.4,
          ),
        ),
        child: done
            ? Icon(Icons.check, size: 13, color: Colors.white)
            : null,
      ),
    );
  }
}
