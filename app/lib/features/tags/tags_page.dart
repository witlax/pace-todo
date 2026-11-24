import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/task_repository.dart';
import '../tasks/widgets/task_tile.dart';
import '../../core/i18n/i18n.dart';

/// 标签总览：每个标签有多少进行中、多少已完成。
/// 标签只有出现在统计里才有意义，否则就只是一个不会用的过滤器。
class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(tagStatsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('标签'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _create(context, ref),
        child: Icon(Icons.add),
      ),
      body: statsAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (stats) {
          if (stats.isEmpty) {
            return Center(
              child: Text(
                tr('还没有标签\n在任务详情或右下角 + 创建'),
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.8, color: scheme.onSurfaceVariant),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 96),
            itemCount: stats.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            itemBuilder: (context, i) {
              final stat = stats[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.local_offer_outlined, size: 18),
                title: Text(
                  stat.tag.name,
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  trf('进行 {} · 完成 {}', [stat.openCount, stat.doneCount]),
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TagTasksPage(
                      tagId: stat.tag.id,
                      tagName: stat.tag.name,
                    ),
                  ),
                ),
                trailing: IconButton(
                  tooltip: tr('删除标签'),
                  icon: Icon(Icons.close, size: 16, color: scheme.outline),
                  onPressed: () => _confirmDelete(context, ref, stat),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('新建标签')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('标签名')),
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
            child: Text(tr('创建')),
          ),
        ],
      ),
    );
    if (name == null) return;
    await ref.read(taskRepositoryProvider).createTag(name);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TagStat stat,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('删除标签「{}」？', [stat.tag.name])),
        content: Text(tr('只删除标签本身，任务不会被删除或改动。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('删除')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(taskRepositoryProvider).deleteTag(stat.tag.id);
  }
}

/// 某个标签下的全部任务：进行中在前，已完成的变灰在后。
class TagTasksPage extends ConsumerWidget {
  const TagTasksPage({super.key, required this.tagId, required this.tagName});

  final String tagId;
  final String tagName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(allTaskTagsProvider).value ?? <TaskTag>[];
    final tasks = ref.watch(allActiveTasksProvider).value ?? <Task>[];
    final scheme = Theme.of(context).colorScheme;

    final tagged = tasksWithTag(tasks, links, tagId);
    final open = tagged.where((t) => t.status == 0).toList();
    final done = tagged.where((t) => t.status == 1).toList();
    final repo = ref.read(taskRepositoryProvider);

    Widget tile(Task t) => TaskTile(
      task: t,
      onToggle: () => repo.setDone(t.id, t.status != 1),
      onOpen: () => openTaskDetail(context, t.id),
      onDelete: () => repo.softDelete(t.id),
      onArchive: () => repo.archiveTask(t.id),
    );

    return Scaffold(
      appBar: AppBar(title: Text(trf('标签：{}', [tagName]))),
      body: tagged.isEmpty
          ? Center(
              child: Text(
                tr('这个标签下还没有任务'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
              children: [
                if (open.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(
                      trf('进行中 · {}', [open.length]),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final t in open) tile(t),
                ],
                if (done.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
                    child: Text(
                      trf('已完成 · {}', [done.length]),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final t in done) tile(t),
                ],
              ],
            ),
    );
  }
}
