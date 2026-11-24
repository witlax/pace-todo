import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../settings/settings.dart';
import '../tasks/task_repository.dart';
import 'list_tasks_page.dart';
import '../../core/i18n/i18n.dart';

/// 清单管理：新建、改名、排序、归档。
///
/// 归档只删清单本身，里面的任务回落到收件箱（不连带删除）。
/// 新建入口放在列表末尾的虚线行，避免 FAB 盖住最后一个清单。
class ListsPage extends ConsumerWidget {
  const ListsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(listsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('清单'))),
      body: listsAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (lists) {
          final tasks =
              ref.watch(allActiveTasksProvider).value ?? <Task>[];
          final now = DateTime.now();
          final today0 = DateTime(now.year, now.month, now.day);
          final tomorrow = today0.add(Duration(days: 1));

          /// 一行摘要：不点进清单也知道哪里堆了事。
          String summaryOf(String listId, {required bool inbox}) {
            if (inbox) return tr('默认清单 · 不可删除');
            final mine = tasks.where((t) => t.listId == listId);
            var today = 0, late = 0, noDate = 0;
            for (final t in mine) {
              final due = t.dueAt;
              if (due == null) {
                noDate++;
              } else if (due.isBefore(today0)) {
                late++;
              } else if (due.isBefore(tomorrow)) {
                today++;
              }
            }
            final parts = <String>[
              if (today > 0) trf('今天 {}', [today]),
              if (late > 0) trf('逾期 {}', [late]),
              if (noDate > 0) trf('无日期 {}', [noDate]),
            ];
            return parts.isEmpty ? tr('还没有任务') : parts.join(' · ');
          }

          int countOf(String listId) =>
              tasks.where((t) => t.listId == listId).length;

          /// 智能清单的实时计数：不建实体，只按规则筛。
          final weekEnd = today0.add(Duration(days: 7));
          final smartCounts = <SmartListKind, int>{
            SmartListKind.today: tasks
                .where(
                  (t) =>
                      t.status == 0 &&
                      t.dueAt != null &&
                      t.dueAt!.isBefore(tomorrow),
                )
                .length,
            SmartListKind.week: tasks
                .where(
                  (t) =>
                      t.status == 0 &&
                      t.dueAt != null &&
                      !t.dueAt!.isBefore(today0) &&
                      t.dueAt!.isBefore(weekEnd),
                )
                .length,
            SmartListKind.overdue: tasks
                .where(
                  (t) =>
                      t.status == 0 &&
                      t.dueAt != null &&
                      t.dueAt!.isBefore(today0),
                )
                .length,
          };
          final settings = ref.watch(settingsProvider);
          final visibleSmart = SmartListKind.values.where((kind) {
            final v = settings.visibilityOf(kind);
            if (v == SmartVisibility.hidden) return false;
            if (v == SmartVisibility.always) return true;
            return (smartCounts[kind] ?? 0) > 0;
          }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (visibleSmart.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: Row(
                    children: [
                      for (var i = 0; i < visibleSmart.length; i++) ...[
                        if (i > 0) SizedBox(width: 8),
                        Expanded(
                          child: _SmartCard(
                            kind: visibleSmart[i],
                            count: smartCounts[visibleSmart[i]] ?? 0,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ListTasksPage.smart(
                                  smart: visibleSmart[i],
                                  name: visibleSmart[i].label,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 6),
                child: Text(
                  tr('拖动把手排序；长按清单可改名或归档（归档不删任务）'),
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: lists.length + 1,
                  onReorderItem: (from, to) {
                    if (from >= lists.length) return;
                    final ids = lists.map((l) => l.id).toList();
                    final moved = ids.removeAt(from);
                    ids.insert(to.clamp(0, ids.length), moved);
                    ref.read(taskRepositoryProvider).reorderLists(ids);
                  },
                  itemBuilder: (context, i) {
                    if (i == lists.length) {
                      return _NewListRow(
                        key: ValueKey('__new_list__'),
                        onCreate: () => _create(context, ref),
                      );
                    }
                    final list = lists[i];
                    return Card(
                      key: ValueKey(list.id),
                      elevation: 0,
                      margin: EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusCard,
                        ),
                        side: BorderSide(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppTokens.radiusCard,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ListTasksPage(listId: list.id, name: list.name),
                          ),
                        ),
                        onLongPress: list.isInbox
                            ? null
                            : () => _showListActions(context, ref, list),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(10, 8, 6, 8),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: list.isInbox
                                      ? scheme.primaryContainer.withValues(
                                          alpha: 0.55,
                                        )
                                      : scheme.surfaceContainerHighest
                                            .withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  list.isInbox
                                      ? Icons.inbox_outlined
                                      : Icons.folder_outlined,
                                  size: 18,
                                  color: list.isInbox
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      list.name,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    SizedBox(height: 1),
                                    Text(
                                      summaryOf(list.id, inbox: list.isInbox),
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: scheme.outline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${countOf(list.id)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: scheme.outline,
                              ),
                              ReorderableDragStartListener(
                                index: i,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Icon(
                                    Icons.drag_indicator,
                                    size: 18,
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await _prompt(context, tr('新建清单'));
    if (name == null) return;
    await ref.read(taskRepositoryProvider).createList(name);
  }

  /// 长按清单：改名 / 归档。卡片上不再放两个按钮，行更干净。
  Future<void> _showListActions(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: Icon(Icons.edit_outlined, size: 19),
              title: Text(tr('重命名'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.archive_outlined, size: 19),
              title: Text(tr('归档'), style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                tr('清单里的任务会移回收件箱'),
                style: TextStyle(fontSize: 10.5),
              ),
              onTap: () => Navigator.of(ctx).pop('archive'),
            ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      await _rename(context, ref, list);
    } else if (action == 'archive') {
      if (!context.mounted) return;
      await _archive(context, ref, list);
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
  ) async {
    final name = await _prompt(context, tr('重命名清单'), initial: list.name);
    if (name == null) return;
    await ref.read(taskRepositoryProvider).renameList(list.id, name);
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    TaskList list,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('归档「{}」？', [list.name])),
        content: Text(tr('清单里的任务会移回收件箱，不会被删除。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('归档')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(taskRepositoryProvider).archiveList(list.id);
  }

  Future<String?> _prompt(
    BuildContext context,
    String title, {
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('名称')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.of(ctx).pop(v.isEmpty ? null : v);
            },
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
    return result;
  }
}

/// 智能清单小卡：三个横排，带实时计数。
class _SmartCard extends StatelessWidget {
  const _SmartCard({
    required this.kind,
    required this.count,
    required this.onTap,
  });

  final SmartListKind kind;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alert = kind == SmartListKind.overdue && count > 0;
    final accent = alert ? context.appColors.warn : scheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 8, 10, 9),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (kind) {
                    SmartListKind.today => Icons.today_outlined,
                    SmartListKind.week => Icons.date_range_outlined,
                    SmartListKind.overdue => Icons.error_outline,
                  },
                  size: 13,
                  color: accent,
                ),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    kind.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 2),
            Text(
              trf('{} 项', [count]),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewListRow extends StatelessWidget {
  const _NewListRow({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: onCreate,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.8),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: scheme.onSurfaceVariant),
              SizedBox(width: 6),
              Text(
                tr('新建清单'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
