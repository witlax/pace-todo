import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/ui/confirm.dart';
import 'task_detail_page.dart';
import 'task_repository.dart';
import '../../core/i18n/i18n.dart';

/// 已完成：按完成日期分组回看，可撤销完成或删除。
/// 这里是「复盘」的入口：一天做完了什么，比待办列表更能说明问题。
/// 已完成的范围筛选：0 本周 / 1 本月 / 2 全部。
class CompletedRange extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

final completedRangeProvider = NotifierProvider<CompletedRange, int>(
  CompletedRange.new,
);

class CompletedPage extends ConsumerWidget {
  const CompletedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(completedTasksProvider);
    final range = ref.watch(completedRangeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('已完成')),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(44),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(tr('本周'))),
                ButtonSegment(value: 1, label: Text(tr('本月'))),
                ButtonSegment(value: 2, label: Text(tr('全部'))),
              ],
              selected: {range},
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  ref.read(completedRangeProvider.notifier).set(v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(
                  TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (allTasks) {
          final now0 = DateTime.now();
          final monday = DateTime(
            now0.year,
            now0.month,
            now0.day,
          ).subtract(Duration(days: now0.weekday - 1));
          final tasks = switch (range) {
            0 =>
              allTasks
                  .where((t) => (t.completedAt ?? t.updatedAt).isAfter(monday))
                  .toList(),
            1 => allTasks.where((t) {
              final at = t.completedAt ?? t.updatedAt;
              return at.year == now0.year && at.month == now0.month;
            }).toList(),
            _ => allTasks,
          };
          if (tasks.isEmpty) {
            return Center(
              child: Text(
                tr('还没有完成的任务'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            );
          }
          final groups = <String, List<Task>>{};
          for (final t in tasks) {
            final at = t.completedAt ?? t.updatedAt;
            final key = dfFullDateWeekFmt().format(at);
            groups.putIfAbsent(key, () => []).add(t);
          }
          final keys = groups.keys.toList();
          // 顶部先给总量与日均：只列明细回答不了“最近产出怎么样”。
          final now = DateTime.now();
          final weekStart = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1));
          final weekCount = tasks
              .where((t) => (t.completedAt ?? t.updatedAt).isAfter(weekStart))
              .length;
          final weekDays = now.weekday.toDouble();
          return ListView.builder(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: keys.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(4, 2, 4, 4),
                  child: Row(
                    children: [
                      Text(
                        trf('本周完成 {} 项', [weekCount]),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Spacer(),
                      Text(
                        trf('日均 {}', [(weekCount / weekDays).toStringAsFixed(1)]),
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ],
                  ),
                );
              }
              final key = keys[i - 1];
              final items = groups[key]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
                    child: Text(
                      '$key · ${items.length}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  for (final t in items)
                    Dismissible(
                      key: ValueKey('done-${t.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: EdgeInsets.only(right: 16),
                        color: scheme.errorContainer,
                        child: Icon(
                          Icons.delete_outline,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        final ok = await confirmDanger(
                          context,
                          title: trf('删除「{}」？', [t.title]),
                          message: tr('这条完成记录会移到回收站，30 天内可以恢复。'),
                        );
                        if (ok) {
                          await ref
                              .read(taskRepositoryProvider)
                              .softDelete(t.id);
                        }
                        return false;
                      },
                      onDismissed: (_) {},
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.check_circle,
                          size: 18,
                          color: scheme.outline,
                        ),
                        title: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.onSurfaceVariant,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: t.completedAt == null
                            ? null
                            : Text(
                                DateFormat('HH:mm').format(t.completedAt!),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.outline,
                                ),
                              ),
                        onTap: () => openTaskDetail(context, t.id),
                        trailing: TextButton(
                          onPressed: () => ref
                              .read(taskRepositoryProvider)
                              .setDone(t.id, false),
                          child: Text(tr('撤销')),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
