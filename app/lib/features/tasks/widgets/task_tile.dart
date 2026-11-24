import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/db/database.dart';
import '../../../core/ui/confirm.dart';
import '../../../core/ui/schedule_sheet.dart';
import '../../settings/settings.dart';
import '../task_repository.dart';
import '../../../core/i18n/i18n.dart';

/// 任务行。
///
/// 交互约定（改自 0.2.0 的长按删除）：
/// - 点圆圈：完成/取消完成；
/// - 点整行：进详情；
/// - **向左滑动**：弹出「归档 / 删除」选择，不做二选一的猜测；
/// - 已完成的任务留在原地变灰，显示完成时间，而不是直接消失。
class TaskTile extends ConsumerWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpen,
    required this.onDelete,
    this.onArchive,
    this.trailing,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;

  /// 行尾附加控件（目前用于「展开子任务」箭头）。
  final Widget? trailing;

  bool get _done => task.status == 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    final emphasis = Emphasis.fromValue(task.importance);
    final accent = palette.of(emphasis);
    final scheme = Theme.of(context).colorScheme;
    final swipeAction = ref.watch(settingsProvider).leftSwipeAction;

    return Dismissible(
      key: ValueKey('tile-${task.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) => direction == DismissDirection.startToEnd
          ? _quickSchedule(context, ref)
          : _leftSwipe(context, ref, swipeAction),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        child: Row(
          children: [
            Icon(
              Icons.today_outlined,
              size: 16,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 6),
            Text(
              _dueToday ? tr('排到明天') : tr('排到今天'),
              style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 16),
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        child: Row(
          children: [
            Icon(
              switch (swipeAction) {
                'complete' => _done ? Icons.undo : Icons.check_circle_outline,
                'delete' => Icons.delete_outline,
                _ => Icons.archive_outlined,
              },
              size: 16,
              color: scheme.onSecondaryContainer,
            ),
            SizedBox(width: 6),
            Text(
              switch (swipeAction) {
                'complete' => _done ? tr('取消完成') : tr('完成'),
                'delete' => tr('删除'),
                _ => tr('归档 / 删除'),
              },
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        onLongPress: () => _showQuickMenu(context, ref),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(4, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 34,
                margin: EdgeInsets.only(top: 2, right: 12),
                decoration: BoxDecoration(
                  color: _done || emphasis == Emphasis.none
                      ? Colors.transparent
                      : accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              GestureDetector(
                key: ValueKey('check-${task.id}'),
                onTap: () {
                  HapticFeedback.lightImpact();
                  onToggle();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(right: 0, top: 1),
                  child: _CheckCircle(
                    active: _done,
                    color: accent,
                    emphasis: emphasis,
                    doneColor: scheme.outline,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.35,
                        color: _done ? scheme.outline : null,
                        decoration: _done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    SizedBox(height: 3),
                    Row(
                      children: [
                        if (_done && task.completedAt != null) ...[
                          Icon(
                            Icons.check_circle_outline,
                            size: 12,
                            color: scheme.outline,
                          ),
                          SizedBox(width: 3),
                          Text(
                            trf('完成于 {}', [DateFormat('HH:mm').format(task.completedAt!)]),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                            ),
                          ),
                          SizedBox(width: 8),
                        ] else if (task.dueAt != null) ...[
                          _DueLabel(dueAt: task.dueAt!),
                          SizedBox(width: 8),
                        ],
                        if (!_done)
                          Text(
                            emphasis.label == tr('无')
                                ? tr('未评估')
                                : trf('重要性 {}', [emphasis.label]),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (task.repeatRule != null) ...[
                          SizedBox(width: 6),
                          Icon(Icons.repeat, size: 11, color: scheme.outline),
                        ],
                      ],
                    ),
                    if (_done && (task.completedSummary ?? '').isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        task.completedSummary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }

  bool get _dueToday {
    final d = task.dueAt;
    if (d == null) return false;
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  /// 右滑：排到今天；已经是今天则排到明天。松手即生效，给 4 秒撤销。
  Future<bool> _quickSchedule(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day, 18);
    final target = _dueToday ? base.add(Duration(days: 1)) : base;
    final before = task.dueAt;

    await repo.updateTask(task.id, dueAt: target);
    if (!context.mounted) return false;

    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 4),
          content: Text(trf('已排到{} 18:00', [_dueToday ? tr('明天') : tr('今天')])),
          action: SnackBarAction(
            label: tr('撤销'),
            onPressed: () => before == null
                ? repo.updateTask(task.id, clearDue: true)
                : repo.updateTask(task.id, dueAt: before),
          ),
        ),
      );
    return false;
  }

  /// 长按：给一条不依赖手势的完整入口。
  Future<void> _showQuickMenu(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 18);

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.today_outlined, size: 20),
              title: Text(tr('排到今天 18:00')),
              onTap: () => Navigator.of(ctx).pop('today'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.event_outlined, size: 20),
              title: Text(tr('排到明天 18:00')),
              onTap: () => Navigator.of(ctx).pop('tomorrow'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.calendar_month_outlined, size: 20),
              title: Text(tr('自定义排期…')),
              onTap: () => Navigator.of(ctx).pop('custom'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.flag_outlined, size: 20),
              title: Text(task.importance >= 3 ? tr('取消高重要性') : tr('设为高重要性')),
              onTap: () => Navigator.of(ctx).pop('importance'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.archive_outlined, size: 20),
              title: Text(tr('归档')),
              onTap: () => Navigator.of(ctx).pop('archive'),
            ),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.delete_outline,
                size: 20,
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
        await repo.updateTask(task.id, dueAt: today);
      case 'tomorrow':
        await repo.updateTask(
          task.id,
          dueAt: today.add(Duration(days: 1)),
        );
      case 'custom':
        final res = await ScheduleSheet.show(context, initialDue: task.dueAt);
        if (res != null && context.mounted) {
          if (res.dueAt == null) {
            await repo.updateTask(task.id, clearDue: true);
          } else {
            await repo.updateTask(task.id, dueAt: res.dueAt);
          }
        }
      case 'importance':
        await repo.updateTask(
          task.id,
          importance: task.importance >= 3 ? 0 : 3,
        );
      case 'archive':
        onArchive?.call();
      case 'delete':
        final ok = await confirmDanger(
          context,
          title: trf('删除「{}」？', [task.title]),
          message: tr('任务会移到回收站，保留 30 天，期间可以恢复。'),
        );
        if (ok) onDelete();
    }
  }

  /// 左滑按设置执行：归档面板 / 直接完成 / 直接删除。
  Future<bool> _leftSwipe(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final repo = ref.read(taskRepositoryProvider);
    switch (action) {
      case 'complete':
        await repo.setDone(task.id, !_done);
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              persist: false,
              duration: Duration(seconds: 4),
              content: Text(_done ? tr('已恢复为未完成') : trf('已完成「{}」', [task.title])),
              action: SnackBarAction(
                label: tr('撤销'),
                onPressed: () => repo.setDone(task.id, _done),
              ),
            ),
          );
        return false;
      case 'delete':
        final ok = await confirmDanger(
          context,
          title: trf('删除「{}」？', [task.title]),
          message: tr('任务会移到回收站，保留 30 天，期间可以恢复。'),
        );
        if (!ok) return false;
        await repo.softDelete(task.id);
        return false;
      default:
        return _confirmAction(context);
    }
  }

  Future<bool> _confirmAction(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.archive_outlined, size: 20),
              title: Text(tr('归档')),
              subtitle: Text(
                tr('移出列表，保留在「归档」里'),
                style: TextStyle(fontSize: 11),
              ),
              onTap: () => Navigator.of(ctx).pop('archive'),
            ),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.delete_outline,
                size: 20,
                color: scheme.error,
              ),
              title: Text(tr('删除'), style: TextStyle(color: scheme.error)),
              subtitle: Text(
                tr('进回收站，30 天内可恢复'),
                style: TextStyle(fontSize: 11),
              ),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return false;
    if (action == 'archive') onArchive?.call();
    if (action == 'delete') {
      // 进回收站虽然可恢复，但仍是「看不见的位移」，值得一次确认。
      final ok = await confirmDanger(
        context,
        title: trf('删除「{}」？', [task.title]),
        message: tr('任务会移到回收站，保留 30 天，期间可以恢复。\n子任务会一起移走。'),
        confirmLabel: tr('删除'),
      );
      if (ok) onDelete();
    }
    // 返回 false：不交给 Dismissible 移除，让数据流决定行是否消失。
    return false;
  }
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({
    required this.active,
    required this.color,
    required this.emphasis,
    required this.doneColor,
  });

  final bool active;
  final Color color;
  final Emphasis emphasis;
  final Color doneColor;

  @override
  Widget build(BuildContext context) {
    final borderColor = active
        ? doneColor
        : (emphasis == Emphasis.none
              ? Theme.of(context).colorScheme.outline
              : color);
    // 勾选是最高频的正反馈动作，值得一次 200ms 的缩放入场。
    // key 跟着 active 变，切到「完成」时动画会重新播一遍。
    return TweenAnimationBuilder<double>(
      key: ValueKey('check-anim-$active'),
      tween: Tween<double>(begin: active ? 0.5 : 1.12, end: 1),
      duration: Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 20,
        height: 20,
        margin: EdgeInsets.only(top: 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.6),
          color: active ? doneColor : Colors.transparent,
        ),
        child: active
            ? Icon(Icons.check, size: 13, color: Colors.white)
            : null,
      ),
    );
  }
}

class _DueLabel extends StatelessWidget {
  const _DueLabel({required this.dueAt});

  final DateTime dueAt;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueAt.year, dueAt.month, dueAt.day);
    final diff = dueDay.difference(today).inDays;

    String text;
    var overdue = false;
    if (diff < 0) {
      overdue = true;
      text = trf('逾期 {} 天', [-diff]);
    } else if (diff == 0) {
      text = trf('今天 {}', [DateFormat('HH:mm').format(dueAt)]);
    } else if (diff == 1) {
      text = trf('明天 {}', [DateFormat('HH:mm').format(dueAt)]);
    } else {
      text = dfMonthDayTimeFmt().format(dueAt);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.schedule,
          size: 12,
          color: overdue
              ? context.appColors.warn
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: overdue
                ? context.appColors.warn
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
