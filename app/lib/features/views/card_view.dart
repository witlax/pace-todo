import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../settings/settings.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/task_repository.dart';
import '../../core/i18n/i18n.dart';

/// 卡片视图：两列磁贴，扫标题为主，时间和清单为辅。
/// 与看板的区别：看板按状态分组回答「卡在哪」，卡片按时间回答「有什么」。
class CardView extends ConsumerWidget {
  const CardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(openTasksProvider).value ?? const <Task>[];
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];
    final palette = ref.watch(paletteProvider);
    final scheme = Theme.of(context).colorScheme;
    final listName = {for (final l in lists) l.id: l.name};

    final ordered = [...tasks]
      ..sort((a, b) {
        final ad = a.dueAt;
        final bd = b.dueAt;
        if (ad == null && bd == null) return a.title.compareTo(b.title);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    if (ordered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dashboard_customize_outlined,
              size: 36,
              color: scheme.outline,
            ),
            const SizedBox(height: 10),
            Text(
              tr('还没有未完成的任务'),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 96),
      itemCount: ordered.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 118,
      ),
      itemBuilder: (_, i) {
        final t = ordered[i];
        final emphasis = Emphasis.fromValue(t.importance);
        final accent = palette.of(emphasis);
        final due = t.dueAt;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => openTaskDetail(context, t.id),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  color: emphasis == Emphasis.none
                      ? scheme.outlineVariant.withValues(alpha: 0.4)
                      : accent,
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(10, 9, 10, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Spacer(),
                        Row(
                          children: [
                            Icon(
                              due == null
                                  ? Icons.inbox_outlined
                                  : Icons.event_outlined,
                              size: 11,
                              color: due != null && due.isBefore(DateTime.now())
                                  ? context.appColors.warn
                                  : scheme.outline,
                            ),
                            SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                _dueLabel(due),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color:
                                      due != null &&
                                          due.isBefore(DateTime.now())
                                      ? context.appColors.warn
                                      : scheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 3),
                        Text(
                          listName[t.listId] ?? tr('收件箱'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            color: scheme.outlineVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _dueLabel(DateTime? due) {
    if (due == null) return tr('未排期');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(due.year, due.month, due.day);
    final diff = day.difference(today).inDays;
    if (diff < 0) return trf('逾期 {} 天', [-diff]);
    if (diff == 0) return trf('今天 {}', [DateFormat('HH:mm').format(due)]);
    if (diff == 1) return trf('明天 {}', [DateFormat('HH:mm').format(due)]);
    return DateFormat('M-d HH:mm').format(due);
  }
}
