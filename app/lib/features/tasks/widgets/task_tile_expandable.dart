import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../task_repository.dart';
import 'task_tile.dart';
import '../../../core/i18n/i18n.dart';

/// 带子任务展开的任务行。
///
/// 右侧箭头点开后在原地插入子任务，不打开展示详情——子任务是「同一条任务
/// 里的步骤」，跳到另一个页面去勾掉会让上下文断掉。
class TaskTileExpandable extends ConsumerStatefulWidget {
  const TaskTileExpandable({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onOpen,
    required this.onDelete,
    this.onArchive,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback? onArchive;

  @override
  ConsumerState<TaskTileExpandable> createState() => _TaskTileExpandableState();
}

class _TaskTileExpandableState extends ConsumerState<TaskTileExpandable> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final subs =
        ref.watch(subtasksProvider(widget.task.id)).value ?? const <Task>[];
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TaskTile(
          task: widget.task,
          onToggle: widget.onToggle,
          onOpen: widget.onOpen,
          onDelete: widget.onDelete,
          onArchive: widget.onArchive,
          trailing: subs.isEmpty
              ? null
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _expanded ? tr('收起子任务') : tr('展开子任务'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: scheme.outline,
                  ),
                ),
        ),
        if (_expanded && subs.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: 46, bottom: 6, right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final sub in subs)
                  InkWell(
                    onTap: () => ref
                        .read(taskRepositoryProvider)
                        .setDone(sub.id, sub.status != 1),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Icon(
                            sub.status == 1
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 15,
                            color: sub.status == 1
                                ? scheme.primary
                                : scheme.outline,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sub.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: sub.status == 1
                                    ? scheme.outline
                                    : scheme.onSurface,
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
}
