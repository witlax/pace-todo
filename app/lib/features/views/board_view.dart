import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/today_page.dart' show QuickAddSheet;
import '../tasks/task_repository.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 看板：待处理 / 进行中 / 延迟 / 已完成。
///
/// 手机竖屏放不下四列——横向滑动既看不见全貌，也没法一眼比较。
/// 所以改成「按状态分组的纵向卡片」：一屏内从待处理刷到已完成，
/// 每个分组内部纵向列任务；宽屏（>= 600dp）自动排成 2×2，接近四象限。
class BoardView extends ConsumerStatefulWidget {
  const BoardView({super.key});

  @override
  ConsumerState<BoardView> createState() => _BoardViewState();
}

enum _Range {
  today('今天'),
  week('本周'),
  month('本月');

  const _Range(this._label);
  final String _label;

  String get label => tr(_label);
}

class _BoardViewState extends ConsumerState<BoardView> {
  _Range _range = _Range.today;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(allActiveTasksProvider).value ?? <Task>[];
    final lists = ref.watch(listsProvider).value ?? <TaskList>[];
    final listName = {for (final l in lists) l.id: l.name};

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfRange = switch (_range) {
      _Range.today => today.add(Duration(days: 1)),
      _Range.week => today.add(Duration(days: 7 - (now.weekday - 1))),
      _Range.month => DateTime(now.year, now.month + 1, 1),
    };

    bool inRange(Task t) {
      if (t.status == 1) {
        final at = t.completedAt;
        if (at == null) return false;
        return switch (_range) {
          _Range.today =>
            at.year == now.year && at.month == now.month && at.day == now.day,
          _Range.week => !at.isBefore(
            today.subtract(Duration(days: (now.weekday + 6) % 7)),
          ),
          _Range.month => at.year == now.year && at.month == now.month,
        };
      }
      final due = t.dueAt;
      if (due == null) return _range == _Range.today;
      return due.isBefore(endOfRange);
    }

    final scoped = tasks.where(inRange).toList();
    final overdue =
        scoped
            .where(
              (t) =>
                  t.status == 0 && t.dueAt != null && t.dueAt!.isBefore(today),
            )
            .toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final inProgress =
        scoped
            .where(
              (t) =>
                  t.status == 0 &&
                  t.dueAt != null &&
                  !t.dueAt!.isBefore(today) &&
                  t.dueAt!.isBefore(today.add(Duration(days: 1))),
            )
            .toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    final todo =
        scoped
            .where(
              (t) =>
                  t.status == 0 &&
                  (t.dueAt == null ||
                      !t.dueAt!.isBefore(today.add(Duration(days: 1)))),
            )
            .toList()
          ..sort((a, b) {
            final ad = a.dueAt, bd = b.dueAt;
            if (ad == null && bd == null) {
              return b.importance.compareTo(a.importance);
            }
            if (ad == null) return 1;
            if (bd == null) return -1;
            return ad.compareTo(bd);
          });
    final done = scoped.where((t) => t.status == 1).toList()
      ..sort((a, b) => (b.completedAt ?? now).compareTo(a.completedAt ?? now));

    final groups = [
      _Group('todo', tr('待处理'), todo, context.appColors.palette.none,
          Icons.inbox_outlined),
      _Group(
        'doing',
        tr('进行中'),
        inProgress,
        context.appColors.palette.low,
        Icons.play_circle_outline,
      ),
      _Group('late', tr('延迟'), overdue, context.appColors.warn,
          Icons.error_outline),
      _Group('done', tr('已完成'), done, context.appColors.done,
          Icons.check_circle_outline),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final cards = [
          for (final g in groups)
            _GroupCard(
              group: g,
              listName: listName,
              today: today,
              onAdd: g.id == 'done'
                  ? null
                  : () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => QuickAddSheet(
                        initialDue: g.title == tr('进行中') || g.title == tr('延迟')
                            ? DateTime(today.year, today.month, today.day, 18)
                            : null,
                      ),
                    ),
              onOpen: (t) => openTaskDetail(context, t.id),
              onDropTask: wide ? (t) => _moveToColumn(t, g.id) : null,
            ),
        ];

        return ListView(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 96),
          children: [
            Row(
              children: [
                Text(
                  tr('看板'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Spacer(),
                SegmentedButton<_Range>(
                  segments: [
                    for (final r in _Range.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {_range},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStateProperty.all(
                      TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              trf('按状态分组 · 每组内按时间排序 · 共 {} 项', [scoped.length]),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 12),
            if (scoped.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Column(
                  children: [
                    Icon(
                      Icons.view_kanban_outlined,
                      size: 36,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    SizedBox(height: 10),
                    Text(
                      tr('这个范围里还没有任务'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      tr('切到「本周 / 本月」看看，或去今天页记一条'),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              )
            else if (wide)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in cards)
                    SizedBox(width: (constraints.maxWidth - 52) / 2, child: c),
                ],
              )
            else
              for (final c in cards) ...[c, SizedBox(height: 10)],
          ],
        );
      },
    );
  }

  /// 宽屏拖拽换组：只改「状态 + 必要的时间」，其余字段不动。
  Future<void> _moveToColumn(Task task, String column) async {
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    final today18 = DateTime(now.year, now.month, now.day, 18);

    switch (column) {
      case 'done':
        await repo.setDone(task.id, true);
      case 'todo':
        if (task.status == 1) await repo.setDone(task.id, false);
      case 'doing':
        if (task.status == 1) await repo.setDone(task.id, false);
        await repo.updateTask(task.id, dueAt: today18);
      case 'late':
        if (task.status == 1) await repo.setDone(task.id, false);
        await repo.updateTask(
          task.id,
          dueAt: today18.subtract(Duration(days: 1)),
        );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 2),
          content: Text(
            trf('「{}」已移到「{}」', [task.title, column]),
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      );
  }
}

class _Group {
  _Group(this.id, this.title, this.tasks, this.color, this.icon);

  /// 稳定标识：拖拽换组用它判断去向，不依赖会随语言变化的标题。
  final String id;
  final String title;
  final List<Task> tasks;
  final Color color;
  final IconData icon;
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.listName,
    required this.today,
    required this.onOpen,
    this.onAdd,
    this.onDropTask,
  });

  final _Group group;
  final Map<String, String> listName;
  final DateTime today;
  final void Function(Task) onOpen;
  final VoidCallback? onAdd;

  /// 仅宽屏提供：拖到本组时回调。
  final void Function(Task)? onDropTask;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = group.tasks;

    // 空分组只留一行标题，不占半屏——看板最怕「四块空白」。
    if (tasks.isEmpty) {
      return Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: group.color.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: group.color.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(
              group.icon,
              size: 14,
              color: group.color.withValues(alpha: 0.7),
            ),
            SizedBox(width: 6),
            Text(
              group.title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: group.color.withValues(alpha: 0.75),
              ),
            ),
            SizedBox(width: 6),
            Text('0', style: TextStyle(fontSize: 10, color: scheme.outline)),
            Spacer(),
            Text(tr('暂无'), style: TextStyle(fontSize: 10, color: scheme.outline)),
          ],
        ),
      );
    }

    final card = Container(
      decoration: BoxDecoration(
        color: group.color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: group.color.withValues(alpha: 0.10)),
      ),
      padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(group.icon, size: 15, color: group.color),
              SizedBox(width: 6),
              Text(
                group.title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: group.color,
                ),
              ),
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: group.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${tasks.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: group.color,
                  ),
                ),
              ),
              Spacer(),
              if (group.title == tr('延迟') && tasks.isNotEmpty)
                Text(
                  trf('最早 {}', [DateFormat('M-d').format(tasks.first.dueAt!)]),
                  style: TextStyle(fontSize: 9.5, color: group.color),
                ),
            ],
          ),
          SizedBox(height: 6),
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            _row(context, tasks[i], scheme),
          ],
          if (onAdd != null)
            InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: EdgeInsets.only(top: 7, bottom: 2),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 13, color: scheme.outline),
                    SizedBox(width: 5),
                    Text(
                      tr('添加'),
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (onDropTask == null) return card;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onDropTask!(d.data),
      builder: (context, candidate, _) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: candidate.isEmpty
              ? null
              : Border.all(color: group.color, width: 1.4),
        ),
        child: card,
      ),
    );
  }

  Widget _row(BuildContext context, Task t, ColorScheme scheme) {
    final due = t.dueAt;
    String? when;
    if (due != null) {
      if (due.isBefore(today)) {
        final days = today
            .difference(DateTime(due.year, due.month, due.day))
            .inDays;
        when = days == 1 ? tr('昨天') : trf('逾期 {} 天', [days]);
      } else if (due.year == today.year &&
          due.month == today.month &&
          due.day == today.day) {
        when = trf('今天 {}', [DateFormat('HH:mm').format(due)]);
      } else {
        when = DateFormat('M-d').format(due);
      }
    }
    final isDone = t.status == 1;

    final tile = InkWell(
      onTap: () => onOpen(t),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.appColors.palette.of(
                    Emphasis.fromValue(t.importance),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: isDone ? scheme.outline : scheme.onSurface,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (when != null || listName[t.listId] != null)
                    Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          ?when,
                          if (t.status == 1 && t.completedAt != null)
                            trf('{} 完成', [DateFormat('HH:mm').format(t.completedAt!)]),
                          listName[t.listId] ?? '',
                        ].where((e) => e.isNotEmpty).join(' · '),
                        style: TextStyle(
                          fontSize: 9.5,
                          color: when != null && when.startsWith(tr('逾期'))
                              ? context.appColors.warn
                              : scheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 6),
            Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.chevron_right, size: 15, color: scheme.outline),
            ),
          ],
        ),
      ),
    );

    if (onDropTask == null) return tile;
    return LongPressDraggable<Task>(
      data: t,
      delay: Duration(milliseconds: 200),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 190,
          padding: EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 12,
              ),
            ],
          ),
          child: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: tile),
      child: tile,
    );
  }
}
