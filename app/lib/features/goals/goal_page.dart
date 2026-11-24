import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../../core/ui/confirm.dart';
import '../habits/habit_repository.dart';
import '../tasks/task_repository.dart';
import 'goal_repository.dart';
import '../../core/i18n/i18n.dart';

/// 目标页：把任务、习惯、专注聚成一条进度。
///
/// 这里刻意不做「子目标树」和「自动打卡」——目标是复盘时的坐标系，
/// 不是第二套项目管理工具。
class GoalsPage extends ConsumerStatefulWidget {
  const GoalsPage({super.key});

  @override
  ConsumerState<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends ConsumerState<GoalsPage> {
  int _status = 0; // 0 进行中 / 1 已完成 / 2 已暂停

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progressAsync = ref.watch(goalProgressProvider);
    final done = ref.watch(completedGoalsProvider).value ?? const <Goal>[];
    final paused = ref.watch(pausedGoalsProvider).value ?? const <Goal>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('目标')),
        actions: [
          IconButton(
            tooltip: tr('目标管理'),
            icon: Icon(Icons.tune, size: 20),
            onPressed: () => _showStatusHelp(context),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showGoalEditor(context),
        child: Icon(Icons.add),
      ),
      body: Column(
        children: [
          _segments(
            active: progressAsync.value?.length ?? 0,
            done: done.length,
            paused: paused.length,
          ),
          Expanded(
            child: switch (_status) {
              0 => _activeList(progressAsync),
              1 => _statusList(
                done,
                emptyTitle: tr('还没有完成的目标'),
                emptyHint: tr('在目标详情点「完成目标」后，会出现在这里——不会被删掉。'),
                tag: tr('已完成'),
                tagColor: context.appColors.done,
              ),
              _ => _statusList(
                paused,
                emptyTitle: tr('没有暂停的目标'),
                emptyHint: tr('长按目标选「暂停」，它会留在这里，随时可以继续。'),
                tag: tr('已暂停'),
                tagColor: scheme.outline,
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _segments({
    required int active,
    required int done,
    required int paused,
  }) {
    final scheme = Theme.of(context).colorScheme;
    Widget seg(int value, String label, int count) {
      final on = _status == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _status = value),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 3),
            padding: EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: on
                  ? Border.all(color: scheme.outlineVariant, width: 1)
                  : null,
            ),
            child: Text(
              '$label $count',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(17, 6, 17, 8),
      child: Row(
        children: [
          seg(0, tr('进行中'), active),
          seg(1, tr('已完成'), done),
          seg(2, tr('已暂停'), paused),
        ],
      ),
    );
  }

  Widget _activeList(AsyncValue<List<GoalProgress>> async) {
    final scheme = Theme.of(context).colorScheme;
    return async.when(
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.flag_outlined, size: 40, color: scheme.outline),
                  SizedBox(height: 12),
                  Text(
                    tr('还没有进行中的目标'),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  SizedBox(height: 6),
                  Text(
                    tr('目标可以是「本月读完 3 本书」「每天喝水 60 次」，\n关联任务或习惯后进度会自动长出来。'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.outline,
                    ),
                  ),
                  SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => showGoalEditor(context),
                    child: Text(tr('新建第一个目标')),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                tr('进度自动来自关联的任务 / 习惯 / 专注记录；长按可编辑、完成或暂停'),
                style: TextStyle(fontSize: 10.5, color: scheme.outline),
              ),
            ),
            for (final p in items)
              _GoalCard(
                progress: p,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GoalDetailPage(goalId: p.goal.id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _statusList(
    List<Goal> goals, {
    required String emptyTitle,
    required String emptyHint,
    required String tag,
    required Color tagColor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    if (goals.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 36, color: scheme.outline),
              SizedBox(height: 10),
              Text(
                emptyTitle,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              SizedBox(height: 6),
              Text(
                emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: scheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        for (final g in goals)
          Card(
            elevation: 0,
            margin: EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusCard),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.fromLTRB(14, 4, 8, 4),
              title: Text(
                g.title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  decoration: _status == 1 ? TextDecoration.lineThrough : null,
                  color: _status == 1 ? scheme.outline : null,
                ),
              ),
              subtitle: Text(
                trf('{} · 关联 {} · {}', [
                  tag,
                  _modeLabel(g.mode),
                  dfMonthDayFmt().format(g.updatedAt),
                ]),
                style: TextStyle(fontSize: 10.5),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => ref
                        .read(goalRepositoryProvider)
                        .setStatus(g.id, 0),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(tr('恢复'), style: TextStyle(fontSize: 12)),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('删除'),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 17,
                      color: scheme.error,
                    ),
                    onPressed: () => _delete(g),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _modeLabel(int mode) => GoalMode.fromValue(mode).label;

  Future<void> _delete(Goal goal) async {
    final ok = await confirmDanger(
      context,
      title: trf('删除「{}」？', [goal.title]),
      message: tr('只删目标本身，关联的任务和习惯不受影响。'),
    );
    if (!ok) return;
    await ref.read(goalRepositoryProvider).remove(goal.id);
  }

  void _showStatusHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('目标去哪里了'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                tr('「完成目标」不会删除目标，它只是从「进行中」挪到「已完成」，') + tr('进度与关联关系都保留，点「恢复」可以退回来。\n\n') + tr('「暂停」用于暂时不做的事（比如换季的习惯），同样不删除。\n\n') + tr('真正的删除只在已结束状态下点垃圾桶，会二次确认。'),
                style: TextStyle(fontSize: 12.5, height: 1.7),
              ),
              SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.progress, required this.onTap});

  final GoalProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final goal = progress.goal;
    final accent = progress.achieved
        ? context.appColors.done
        : scheme.primary;
    final due = goal.dueAt;

    return Card(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        onTap: onTap,
        onLongPress: () => _menu(context, ref),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(progress.mode.icon, size: 15, color: accent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (progress.achieved)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        tr('已达成'),
                        style: TextStyle(fontSize: 9.5, color: accent),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 5,
                  backgroundColor: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.7,
                  ),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
              SizedBox(height: 7),
              Row(
                children: [
                  Text(
                    progress.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      progress.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                  ),
                  if (due != null)
                    Text(
                      due.isBefore(DateTime.now())
                          ? tr('已过期')
                          : trf('到 {}', [DateFormat('M-d').format(due)]),
                      style: TextStyle(
                        fontSize: 10,
                        color: due.isBefore(DateTime.now())
                            ? context.appColors.warn
                            : scheme.outline,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(goalRepositoryProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              dense: true,
              leading: Icon(Icons.edit_outlined, size: 19),
              title: Text(tr('编辑'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.check_circle_outline, size: 19),
              title: Text(tr('标记完成'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('done'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.pause_circle_outline, size: 19),
              title: Text(tr('暂停'), style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                tr('不删除，挪到「已暂停」，随时可以继续'),
                style: TextStyle(fontSize: 10.5),
              ),
              onTap: () => Navigator.of(ctx).pop('archive'),
            ),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.delete_outline,
                size: 19,
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
      case 'edit':
        await showGoalEditor(context, goal: progress.goal);
      case 'done':
        await repo.setStatus(progress.goal.id, 1);
      case 'archive':
        await repo.archive(progress.goal.id);
      case 'delete':
        final ok = await confirmDanger(
          context,
          title: trf('删除「{}」？', [progress.goal.title]),
          message: tr('只删目标本身，关联的任务和习惯不受影响。'),
        );
        if (ok) await repo.remove(progress.goal.id);
    }
  }
}

class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(goalProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('目标')),
        actions: [
          IconButton(
            tooltip: tr('编辑'),
            icon: Icon(Icons.edit_outlined, size: 20),
            onPressed: () {
              final p = async.value?.where((e) => e.goal.id == goalId).firstOrNull;
              if (p != null) showGoalEditor(context, goal: p.goal);
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (items) {
          final p = items.where((e) => e.goal.id == goalId).firstOrNull;
          if (p == null) {
            return Center(child: Text(tr('这个目标已经归档或删除')));
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _ProgressHead(progress: p),
              if ((p.goal.note ?? '').isNotEmpty) ...[
                SizedBox(height: 14),
                Text(
                  p.goal.note!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.6,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: 20),
              if (p.mode == GoalMode.manual) _manualEditor(context, ref, p),
              if (p.mode == GoalMode.tasks) _taskLinks(context, ref, p),
              if (p.mode == GoalMode.habits) _habitLinks(context, ref, p),
              if (p.mode == GoalMode.focus)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tr('专注进度从目标创建那一刻开始累计，改目标分钟数即可调整分母。'),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await ref.read(goalRepositoryProvider).archive(goalId);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: Icon(Icons.archive_outlined, size: 17),
                      label: Text(tr('归档')),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await ref
                            .read(goalRepositoryProvider)
                            .setStatus(goalId, 1);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: Icon(Icons.check, size: 17),
                      label: Text(tr('完成目标')),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _manualEditor(BuildContext context, WidgetRef ref, GoalProgress p) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('当前进度'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: () => ref
                    .read(goalRepositoryProvider)
                    .setManualCurrent(p.goal.id, p.current - 10),
                child: Text('-10'),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: p.current.toDouble().clamp(0, 100),
                  max: 100,
                  divisions: 20,
                  label: '${p.current}%',
                  onChanged: (v) => ref
                      .read(goalRepositoryProvider)
                      .setManualCurrent(p.goal.id, v.round()),
                ),
              ),
              SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => ref
                    .read(goalRepositoryProvider)
                    .setManualCurrent(p.goal.id, p.current + 10),
                child: Text('+10'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _taskLinks(BuildContext context, WidgetRef ref, GoalProgress p) {
    final links = ref.watch(goalLinksProvider).value ?? <GoalLink>[];
    final tasks = ref.watch(allActiveTasksProvider).value ?? <Task>[];
    final mine = links
        .where((l) => l.goalId == p.goal.id && l.refType == 0)
        .map((l) => tasks.where((t) => t.id == l.refId).firstOrNull)
        .whereType<Task>()
        .toList();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, trf('关联任务 {}', [mine.length])),
        if (mine.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              tr('还没有关联任务。关联后，勾完任务进度自动往前走。'),
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
          ),
        for (final t in mine)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              t.status == 1
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 18,
              color: t.status == 1 ? context.appColors.done : scheme.outline,
            ),
            title: Text(
              t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                decoration: t.status == 1 ? TextDecoration.lineThrough : null,
                color: t.status == 1 ? scheme.outline : null,
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.close, size: 16),
              onPressed: () => ref
                  .read(goalRepositoryProvider)
                  .removeLink(p.goal.id, 0, t.id),
            ),
          ),
        TextButton.icon(
          onPressed: () => _pickTasks(context, ref, p.goal.id),
          icon: Icon(Icons.add, size: 16),
          label: Text(tr('关联任务'), style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _habitLinks(BuildContext context, WidgetRef ref, GoalProgress p) {
    final links = ref.watch(goalLinksProvider).value ?? <GoalLink>[];
    final habits = ref.watch(habitsProvider).value ?? <Habit>[];
    final mine = links
        .where((l) => l.goalId == p.goal.id && l.refType == 1)
        .map((l) => habits.where((h) => h.id == l.refId).firstOrNull)
        .whereType<Habit>()
        .toList();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, trf('关联习惯 {}', [mine.length])),
        if (mine.isEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              tr('还没有关联习惯。关联后按「计划次数」自动算分母。'),
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
          ),
        for (final h in mine)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.repeat, size: 18),
            title: Text(h.name, style: TextStyle(fontSize: 13)),
            trailing: IconButton(
              icon: Icon(Icons.close, size: 16),
              onPressed: () => ref
                  .read(goalRepositoryProvider)
                  .removeLink(p.goal.id, 1, h.id),
            ),
          ),
        TextButton.icon(
          onPressed: () => _pickHabits(context, ref, p.goal.id),
          icon: Icon(Icons.add, size: 16),
          label: Text(tr('关联习惯'), style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
    padding: EdgeInsets.only(top: 6, bottom: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Future<void> _pickTasks(
    BuildContext context,
    WidgetRef ref,
    String goalId,
  ) async {
    final tasks = ref.read(allActiveTasksProvider).value ?? <Task>[];
    final links = ref.read(goalLinksProvider).value ?? <GoalLink>[];
    final selected = links
        .where((l) => l.goalId == goalId && l.refType == 0)
        .map((l) => l.refId)
        .toSet();

    final result = await _multiPick(
      context,
      title: tr('关联任务'),
      items: [
        for (final t in tasks)
          (t.id, t.title, trf('{} · {} 分钟', [t.status == 1 ? tr('已完成') : tr('待办'), t.spentMin])),
      ],
      selected: selected,
    );
    if (result == null) return;
    final repo = ref.read(goalRepositoryProvider);
    for (final id in result.difference(selected)) {
      await repo.addLink(goalId, 0, id);
    }
    for (final id in selected.difference(result)) {
      await repo.removeLink(goalId, 0, id);
    }
  }

  Future<void> _pickHabits(
    BuildContext context,
    WidgetRef ref,
    String goalId,
  ) async {
    final habits = ref.read(habitsProvider).value ?? <Habit>[];
    final links = ref.read(goalLinksProvider).value ?? <GoalLink>[];
    final selected = links
        .where((l) => l.goalId == goalId && l.refType == 1)
        .map((l) => l.refId)
        .toSet();

    final result = await _multiPick(
      context,
      title: tr('关联习惯'),
      items: [for (final h in habits) (h.id, h.name, trf('每天 {} 次', [h.targetCount]))],
      selected: selected,
    );
    if (result == null) return;
    final repo = ref.read(goalRepositoryProvider);
    for (final id in result.difference(selected)) {
      await repo.addLink(goalId, 1, id);
    }
    for (final id in selected.difference(result)) {
      await repo.removeLink(goalId, 1, id);
    }
  }

  Future<Set<String>?> _multiPick(
    BuildContext context, {
    required String title,
    required List<(String, String, String)> items,
    required Set<String> selected,
  }) {
    final chosen = {...selected};
    return showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(chosen),
                        child: Text(tr('保存')),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1),
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            tr('没有可关联的内容'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final item = items[i];
                            final on = chosen.contains(item.$1);
                            return CheckboxListTile(
                              dense: true,
                              value: on,
                              title: Text(
                                item.$2,
                                style: TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                item.$3,
                                style: TextStyle(fontSize: 10.5),
                              ),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  chosen.add(item.$1);
                                } else {
                                  chosen.remove(item.$1);
                                }
                              }),
                            );
                          },
                        ),
                ),
                SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressHead extends StatelessWidget {
  const _ProgressHead({required this.progress});

  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = progress.achieved
        ? context.appColors.done
        : scheme.primary;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.goal.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(progress.mode.icon, size: 11, color: accent),
                    SizedBox(width: 3),
                    Text(
                      progress.mode.label,
                      style: TextStyle(fontSize: 9.5, color: accent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                progress.label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: accent,
                  height: 1,
                ),
              ),
              SizedBox(width: 8),
              Padding(
                padding: EdgeInsets.only(bottom: 2),
                child: Text(
                  '${(progress.ratio * 100).round()}%',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.ratio,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          SizedBox(height: 10),
          Text(
            progress.detail,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          if (progress.goal.dueAt != null) ...[
            SizedBox(height: 4),
            Text(
              trf('截止 {}', [dfFullDateFmt().format(progress.goal.dueAt!)]),
              style: TextStyle(fontSize: 10.5, color: scheme.outline),
            ),
          ],
        ],
      ),
    );
  }
}

class ArchivedGoalsPage extends ConsumerWidget {
  const ArchivedGoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(archivedGoalsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('已归档的目标'))),
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (goals) => goals.isEmpty
            ? Center(
                child: Text(
                  tr('没有归档的目标'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            : ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  for (final g in goals)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        GoalMode.fromValue(g.mode).icon,
                        size: 18,
                        color: scheme.outline,
                      ),
                      title: Text(
                        g.title,
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        g.status == 1 ? tr('已完成') : tr('已归档'),
                        style: TextStyle(fontSize: 10.5),
                      ),
                      trailing: TextButton(
                        onPressed: () => ref
                            .read(goalRepositoryProvider)
                            .setStatus(g.id, 0),
                        child: Text(
                          tr('恢复'),
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 新建 / 编辑目标的底部面板。
Future<void> showGoalEditor(BuildContext context, {Goal? goal}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GoalEditorSheet(goal: goal),
  );
}

class _GoalEditorSheet extends ConsumerStatefulWidget {
  const _GoalEditorSheet({this.goal});

  final Goal? goal;

  @override
  ConsumerState<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<_GoalEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _target;
  late GoalMode _mode;
  DateTime? _due;

  bool get _editing => widget.goal != null;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _title = TextEditingController(text: g?.title ?? '');
    _note = TextEditingController(text: g?.note ?? '');
    _mode = GoalMode.fromValue(g?.mode ?? 0);
    _target = TextEditingController(
      text: g == null ? '' : '${_mode == GoalMode.manual ? 100 : g.target}',
    );
    _due = g?.dueAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing ? tr('编辑目标') : tr('新建目标'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 14),
              TextField(
                controller: _title,
                autofocus: !_editing,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: tr('目标'),
                  hintText: tr('例：本月读完 3 本书'),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 2,
                minLines: 1,
                decoration: InputDecoration(
                  labelText: tr('说明（可选）'),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              SizedBox(height: 16),
              Text(
                tr('进度来自'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in GoalMode.values)
                    ChoiceChip(
                      selected: _mode == m,
                      onSelected: (_) => setState(() {
                        _mode = m;
                        if (m == GoalMode.manual && _target.text.isEmpty) {
                          _target.text = '100';
                        }
                      }),
                      avatar: Icon(m.icon, size: 14),
                      label: Text(m.label, style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                _mode.hint,
                style: TextStyle(fontSize: 10.5, color: scheme.outline),
              ),
              SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _target,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: switch (_mode) {
                          GoalMode.manual => tr('目标百分比'),
                          GoalMode.focus => tr('目标分钟数'),
                          _ => tr('目标值'),
                        },
                        helperText: switch (_mode) {
                          GoalMode.manual => null,
                          GoalMode.focus => null,
                          _ => tr('未关联时按此值作分母'),
                        },
                        helperStyle: TextStyle(fontSize: 9.5),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDue,
                      icon: Icon(Icons.event_outlined, size: 16),
                      label: Text(
                        _due == null
                            ? tr('截止日期')
                            : dfMonthDayFmt().format(_due!),
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(_editing ? tr('保存') : tr('创建目标')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(Duration(days: 7)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: tr('选择截止日期'),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('先给目标起个名字'))));
      return;
    }
    final repo = ref.read(goalRepositoryProvider);
    final target = (int.tryParse(_target.text.trim()) ?? 1).clamp(1, 100000);
    final note = _note.text.trim();

    if (_editing) {
      await repo.updateGoal(
        widget.goal!.id,
        title: title,
        note: note,
        mode: _mode,
        target: target,
        dueAt: _due,
        clearDue: _due == null,
      );
    } else {
      await repo.create(
        title: title,
        note: note.isEmpty ? null : note,
        mode: _mode,
        target: target,
        dueAt: _due,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }
}
