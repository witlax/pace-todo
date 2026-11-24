import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../settings/settings.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/task_repository.dart';
import '../tasks/today_page.dart' show QuickAddSheet;
import '../tasks/widgets/task_tile.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 单个清单里的任务。
///
/// 顶部三段筛选（未完成 / 已完成 / 全部）+ 排序（时间 / 重要性 / 手动）。
/// 手动排序时不分组，直接拖行写 sortOrder——分组会挡住跨组拖动。
///
/// 同一个页面也承载智能清单（今天 / 最近 7 天 / 已逾期）：
/// 两者只差「任务从哪来」，筛选、排序、拖拽完全一致，没必要写两份。
class ListTasksPage extends ConsumerStatefulWidget {
  const ListTasksPage({super.key, required this.listId, required this.name})
    : smart = null;

  const ListTasksPage.smart({super.key, required this.smart, required this.name})
    : listId = '';

  final String listId;
  final SmartListKind? smart;
  final String name;

  @override
  ConsumerState<ListTasksPage> createState() => _ListTasksPageState();
}

enum _Filter { open, done, all }

enum _Sort {
  time('按时间'),
  importance('按重要性'),
  manual('手动排序');

  const _Sort(this._label);
  final String _label;

  String get label => tr(_label);
}

class _ListTasksPageState extends ConsumerState<ListTasksPage> {
  _Filter _filter = _Filter.open;
  _Sort _sort = _Sort.time;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final source = ref.watch(allActiveTasksProvider).value ?? <Task>[];
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final tomorrow = today0.add(Duration(days: 1));
    final weekEnd = today0.add(Duration(days: 7));

    final all = source.where((t) {
      final smart = widget.smart;
      if (smart == null) return t.listId == widget.listId;
      final due = t.dueAt;
      if (due == null || t.status != 0) return false;
      return switch (smart) {
        // 今天 = 今天到期 + 已逾期（滴答口径：先清欠账）
        SmartListKind.today => due.isBefore(tomorrow),
        SmartListKind.week =>
          !due.isBefore(today0) && due.isBefore(weekEnd),
        SmartListKind.overdue => due.isBefore(today0),
      };
    }).toList();

    final open = all.where((t) => t.status == 0).toList();
    final done = all.where((t) => t.status == 1).toList();
    final shown = switch (_filter) {
      _Filter.open => open,
      _Filter.done => done,
      _Filter.all => all,
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => QuickAddSheet(
            initialListId: widget.smart == null
                ? widget.listId
                : ref.read(settingsProvider).defaultListId,
          ),
        ),
        child: Icon(Icons.add),
      ),
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.name),
            SizedBox(width: 8),
            Text(
              trf('{} 项', [all.length]),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<_Sort>(
            tooltip: tr('排序'),
            initialValue: _sort,
            icon: Icon(Icons.sort, size: 20),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final s in _Sort.values)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      Text(s.label),
                      Spacer(),
                      if (_sort == s) Icon(Icons.check, size: 16),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Row(
              children: [
                _seg(trf('未完成 {}', [open.length]), _Filter.open),
                SizedBox(width: 6),
                _seg(trf('已完成 {}', [done.length]), _Filter.done),
                SizedBox(width: 6),
                _seg(tr('全部'), _Filter.all),
                Spacer(),
                Text(
                  _sort.label,
                  style: TextStyle(fontSize: 10, color: scheme.outline),
                ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 38,
                          color: scheme.outline,
                        ),
                        SizedBox(height: 10),
                        Text(
                          _filter == _Filter.done ? tr('还没有完成的任务') : tr('这个清单是空的'),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        SizedBox(height: 4),
                        Text(
                          tr('点右下角 + 往这里加一条'),
                          style: TextStyle(fontSize: 11, color: scheme.outline),
                        ),
                      ],
                    ),
                  )
                : _sort == _Sort.manual
                ? _manualList(shown)
                : _list(shown),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, _Filter f) {
    final scheme = Theme.of(context).colorScheme;
    final on = _filter == f;
    return InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(7),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? scheme.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 手动排序：平铺 + 长按拖动，松手后立刻写库。
  Widget _manualList(List<Task> tasks) {
    final ordered = [...tasks]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(20, 2, 20, 96),
      itemCount: ordered.length,
      onReorderItem: (from, to) {
        final ids = ordered.map((t) => t.id).toList();
        final moved = ids.removeAt(from);
        ids.insert(to, moved);
        ref.read(taskRepositoryProvider).reorderTasks(ids);
      },
      itemBuilder: (context, i) {
        final t = ordered[i];
        return Container(
          key: ValueKey('manual-${t.id}'),
          color: Theme.of(context).colorScheme.surface,
          child: TaskTile(
            task: t,
            onToggle: () =>
                ref.read(taskRepositoryProvider).setDone(t.id, t.status != 1),
            onOpen: () => openTaskDetail(context, t.id),
            onArchive: () => ref.read(taskRepositoryProvider).archiveTask(t.id),
            onDelete: () => ref.read(taskRepositoryProvider).softDelete(t.id),
          ),
        );
      },
    );
  }

  Widget _list(List<Task> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));

    final groups = <String, List<Task>>{
      tr('逾期'): [],
      tr('今天'): [],
      tr('之后'): [],
      tr('未排期'): [],
      tr('已完成'): [],
    };
    for (final t in tasks) {
      if (t.status == 1) {
        groups[tr('已完成')]!.add(t);
        continue;
      }
      final due = t.dueAt;
      if (due == null) {
        groups[tr('未排期')]!.add(t);
      } else if (due.isBefore(today)) {
        groups[tr('逾期')]!.add(t);
      } else if (due.isBefore(tomorrow)) {
        groups[tr('今天')]!.add(t);
      } else {
        groups[tr('之后')]!.add(t);
      }
    }
    for (final l in groups.values) {
      l.sort((a, b) {
        if (_sort == _Sort.time) {
          final ad = a.dueAt, bd = b.dueAt;
          if (ad == null && bd == null) {
            return b.importance.compareTo(a.importance);
          }
          if (ad == null) return 1;
          if (bd == null) return -1;
          final c = ad.compareTo(bd);
          if (c != 0) return c;
          return b.importance.compareTo(a.importance);
        }
        final imp = b.importance.compareTo(a.importance);
        if (imp != 0) return imp;
        final ad = a.dueAt, bd = b.dueAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    }

    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      children.add(
        Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 2),
          child: Text(
            '${entry.key} · ${entry.value.length}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: entry.key == tr('逾期')
                  ? context.appColors.warn
                  : scheme.outline,
            ),
          ),
        ),
      );
      for (final t in entry.value) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: TaskTile(
              task: t,
              onToggle: () =>
                  ref.read(taskRepositoryProvider).setDone(t.id, t.status != 1),
              onOpen: () => openTaskDetail(context, t.id),
              onArchive: () =>
                  ref.read(taskRepositoryProvider).archiveTask(t.id),
              onDelete: () => ref.read(taskRepositoryProvider).softDelete(t.id),
            ),
          ),
        );
      }
    }
    if (children.isEmpty) return SizedBox.shrink();
    return ListView(
      padding: EdgeInsets.only(bottom: 96),
      children: children,
    );
  }
}
