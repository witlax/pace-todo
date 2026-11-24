import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import 'task_repository.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 回收站：软删的任务保留 30 天，可恢复或彻底删除。
class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  static const retentionDays = 30;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deletedTasksProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('回收站'))),
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (tasks) {
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, size: 40, color: scheme.outline),
                  SizedBox(height: 10),
                  Text(
                    tr('回收站是空的'),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        trf('保留 {} 天，到期自动清理', [retentionDays]),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      trf('{} 项', [tasks.length]),
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => SizedBox(height: 8),
                  itemBuilder: (_, i) => _TrashRow(task: tasks[i]),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.appColors.warn,
                        side: BorderSide(color: Color(0xFFF3C7C7)),
                      ),
                      onPressed: () => _confirmClearAll(context, ref),
                      child: Text(tr('清空回收站')),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('清空回收站？')),
        content: Text(tr('所有已删除任务将被永久删除，无法恢复。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.warn,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('清空')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(taskRepositoryProvider).purgeAll();
    }
  }
}

class _TrashRow extends ConsumerWidget {
  const _TrashRow({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final deletedAt = task.deletedAt ?? DateTime.now();
    final left =
        TrashPage.retentionDays - DateTime.now().difference(deletedAt).inDays;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5),
          ),
          SizedBox(height: 4),
          Text(
            trf('{} 删除 · 还剩 {} 天', [dfMonthDayTimeFmt().format(deletedAt), left]),
            style: TextStyle(fontSize: 10.5, color: scheme.outline),
          ),
          SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                onPressed: () =>
                    ref.read(taskRepositoryProvider).restore(task.id),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.symmetric(horizontal: 6),
                ),
                child: Text(tr('恢复'), style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                onPressed: () => _confirmPurge(context, ref),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: context.appColors.warn,
                  padding: EdgeInsets.symmetric(horizontal: 6),
                ),
                child: Text(tr('彻底删除'), style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPurge(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('彻底删除？')),
        content: Text(trf('「{}」将被永久删除，无法恢复。', [task.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.warn,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('删除')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(taskRepositoryProvider).purge(task.id);
    }
  }
}
