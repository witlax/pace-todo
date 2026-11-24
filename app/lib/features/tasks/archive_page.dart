import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'task_detail_page.dart';
import 'task_repository.dart';
import '../../core/i18n/i18n.dart';

/// 归档：从列表里移走，但不删除、不进回收站。
/// 适合「这周不做但以后可能做」的任务——删了可惜，留着又碍眼。
class ArchivePage extends ConsumerWidget {
  const ArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(archivedTasksProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('归档'))),
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: Text(
                tr('没有归档的任务'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: tasks.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            itemBuilder: (context, i) {
              final t = tasks[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  t.archivedAt == null
                      ? ''
                      : trf('归档于 {}', [dfMonthDayTimeFmt().format(t.archivedAt!)]),
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
                onTap: () => openTaskDetail(context, t.id),
                trailing: TextButton(
                  onPressed: () =>
                      ref.read(taskRepositoryProvider).unarchiveTask(t.id),
                  child: Text(tr('取消归档')),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
