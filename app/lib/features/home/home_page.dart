import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../growth/growth.dart';
import '../habits/habit_actions.dart';
import '../habits/habit_detail_page.dart';
import '../habits/habit_edit_page.dart';
import '../habits/habit_page.dart';
import '../habits/habit_repository.dart';
import '../habits/habit_stats_page.dart';
import '../habits/widgets/habit_check_card.dart';
import '../lists/list_tasks_page.dart';
import '../search/search_page.dart';
import '../tasks/archive_page.dart';
import '../tasks/completed_page.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/task_repository.dart';
import '../tasks/today_page.dart' show QuickAddSheet;
import '../tasks/trash_page.dart';
import '../tasks/widgets/task_row.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 首页：等级头 + 周日期条 + 习惯打卡 + 任务管理。
///
/// 这是 pinch 的信息架构：习惯和任务都在首页，靠折叠区收起来，
/// 不再各占一个底部 tab。日期格决定「任务区看哪一天」，
/// 习惯区始终是今天（打卡只能打今天，补卡在卡片的 7 天格上长按）。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  DateTime _selected = _dayOnly(DateTime.now());
  DateTime _weekStart = _mondayOf(DateTime.now());
  String? _listFilter;
  int _importanceFilter = 0;
  bool _habitsOpen = true;
  bool _tasksOpen = true;

  /// 滚动时收起悬浮加号，避免它压住任务行右侧的「⋯」。
  bool _fabVisible = true;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _mondayOf(DateTime d) =>
      _dayOnly(d).subtract(Duration(days: d.weekday - 1));

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final logs = ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
    final tasks = ref.watch(allActiveTasksProvider).value ?? const <Task>[];
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];

    final byHabit = <String, Set<String>>{};
    final countByHabit = <String, Map<String, int>>{};
    for (final log in logs) {
      byHabit.putIfAbsent(log.habitId, () => <String>{}).add(log.date);
      countByHabit
          .putIfAbsent(log.habitId, () => <String, int>{})
          .update(log.date, (v) => v + log.count, ifAbsent: () => log.count);
    }
    final today = dayKey(DateTime.now());
    final shown = _filterTasks(tasks);

    return Scaffold(
      // 首页给一个明显的入口：点了先问「加任务还是加习惯」。
      // 分区标题旁的小加号保留给「在当前区里直接加」，两个层级不冲突。
      floatingActionButton: AnimatedScale(
        scale: _fabVisible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: IgnorePointer(
          ignoring: !_fabVisible,
          child: FloatingActionButton(
            onPressed: _quickAdd,
            child: const Icon(Icons.add),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollUpdateNotification) {
              final dy = n.scrollDelta ?? 0;
              if (dy > 6 && _fabVisible) setState(() => _fabVisible = false);
              if (dy < -6 && !_fabVisible) setState(() => _fabVisible = true);
            } else if (n is ScrollEndNotification && !_fabVisible) {
              Future<void>.delayed(const Duration(milliseconds: 1100), () {
                if (mounted) setState(() => _fabVisible = true);
              });
            }
            return false;
          },
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
          children: [
            _GrowthHeader(),
            const SizedBox(height: 14),
            _WeekStrip(
              weekStart: _weekStart,
              selected: _selected,
              onSelect: (d) => setState(() => _selected = d),
              onShiftWeek: (delta) => setState(() {
                _weekStart = _weekStart.add(Duration(days: 7 * delta));
                _selected = _selected.add(Duration(days: 7 * delta));
              }),
              onToday: () => setState(() {
                _selected = _dayOnly(DateTime.now());
                _weekStart = _mondayOf(DateTime.now());
              }),
            ),
            const SizedBox(height: 10),
            _SectionHeader(
              title: tr('习惯打卡'),
              open: _habitsOpen,
              onToggle: () => setState(() => _habitsOpen = !_habitsOpen),
              actions: [
                _HeaderIcon(
                  icon: Icons.more_vert,
                  tooltip: tr('习惯管理'),
                  onTap: () => _push(HabitPage()),
                ),
                _HeaderIcon(
                  icon: Icons.insights,
                  tooltip: tr('习惯统计'),
                  onTap: () => _push(HabitStatsPage()),
                ),
                _HeaderIcon(
                  icon: Icons.add,
                  tooltip: tr('新建习惯'),
                  onTap: () => _push(HabitEditPage()),
                ),
              ],
            ),
            if (_habitsOpen)
              if (habits.isEmpty)
                _EmptyHint(
                  text: tr('暂无习惯，点击上方按钮添加新习惯'),
                  actionLabel: tr('新建习惯'),
                  onAction: () => _push(HabitEditPage()),
                )
              else
                for (final habit in habits)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: HabitCheckCard(
                      habit: habit,
                      days: byHabit[habit.id] ?? <String>{},
                      todayCount: countByHabit[habit.id]?[today] ?? 0,
                      onCheck: () => habitQuickCheckIn(
                        context,
                        ref,
                        habit,
                        byHabit[habit.id] ?? <String>{},
                        countByHabit[habit.id]?[today] ?? 0,
                      ),
                      onCheckLong: () => habitOpenJournal(context, ref, habit),
                      onOpen: () => _push(HabitDetailPage(habitId: habit.id)),
                    ),
                  ),
            SizedBox(height: 6),
            _SectionHeader(
              title: tr('任务管理'),
              open: _tasksOpen,
              onToggle: () => setState(() => _tasksOpen = !_tasksOpen),
              actions: [
                _HeaderIcon(
                  icon: Icons.refresh,
                  tooltip: tr('回到今天'),
                  onTap: () => setState(() {
                    _selected = _dayOnly(DateTime.now());
                    _listFilter = null;
                    _importanceFilter = 0;
                  }),
                ),
                _HeaderIcon(
                  icon: Icons.add,
                  tooltip: tr('新建任务'),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => QuickAddSheet(),
                  ),
                ),
              ],
            ),
            if (_tasksOpen) ...[
              _TaskFilterBar(
                lists: lists,
                listId: _listFilter,
                onList: (id) => setState(() => _listFilter = id),
                onSearch: () => _push(SearchPage()),
                onFilter: () => _pickImportance(),
                onMore: () => _moreMenu(),
                selectedLabel: _selectedLabel(),
              ),
              SizedBox(height: 6),
              if (shown.isEmpty)
                _EmptyHint(
                  text: trf('{}没有任务', [dfMonthDayFmt().format(_selected)]),
                  actionLabel: tr('记一条'),
                  onAction: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => QuickAddSheet(),
                  ),
                )
              else
                for (final task in shown)
                  TaskRow(
                    key: ValueKey(task.id),
                    task: task,
                    onToggle: () => ref
                        .read(taskRepositoryProvider)
                        .setDone(task.id, task.status != 1),
                    onOpen: () => _openTask(task.id),
                    onArchive: () => ref
                        .read(taskRepositoryProvider)
                        .archiveTask(task.id),
                    onDelete: () => ref
                        .read(taskRepositoryProvider)
                        .softDelete(task.id),
                  ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _quickAdd() async {
    final picked = await showModalBottomSheet<String>(
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
              leading: Icon(Icons.checklist_rtl, size: 20),
              title: Text(tr('新建任务'), style: TextStyle(fontSize: 14)),
              subtitle: Text(
                tr('支持「明天下午三点 !高 #标签」一句话解析'),
                style: TextStyle(fontSize: 10.5),
              ),
              onTap: () => Navigator.of(ctx).pop('task'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.repeat, size: 20),
              title: Text(tr('新建习惯'), style: TextStyle(fontSize: 14)),
              subtitle: Text(
                tr('周期、目标次数、提醒时间都可以之后再改'),
                style: TextStyle(fontSize: 10.5),
              ),
              onTap: () => Navigator.of(ctx).pop('habit'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == 'task') {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => QuickAddSheet(),
      );
    } else if (picked == 'habit') {
      _push(HabitEditPage());
    }
  }

  String _selectedLabel() {
    final today = _dayOnly(DateTime.now());
    if (_selected == today) return tr('今天');
    if (_selected == today.add(Duration(days: 1))) return tr('明天');
    return dfMonthDayFmt().format(_selected);
  }

  /// 任务区的筛选口径：选中日之前到期的 + 无日期的 + 选中日完成的。
  /// 无日期的不隐藏——藏起来就等于丢任务，这是待办工具最容易犯的错。
  List<Task> _filterTasks(List<Task> all) {
    final endOfDay = _selected.add(Duration(days: 1));
    final result = all.where((t) {
      if (_listFilter != null && t.listId != _listFilter) return false;
      if (_importanceFilter > 0 && t.importance != _importanceFilter) {
        return false;
      }
      if (t.status == 1) {
        final done = t.completedAt;
        return done != null &&
            !done.isBefore(_selected) &&
            done.isBefore(endOfDay);
      }
      final due = t.dueAt;
      if (due == null) return true;
      return due.isBefore(endOfDay);
    }).toList();

    result.sort((a, b) {
      if (a.status != b.status) return a.status == 1 ? 1 : -1;
      final ad = a.dueAt, bd = b.dueAt;
      if (ad == null && bd == null) return b.importance.compareTo(a.importance);
      if (ad == null) return 1;
      if (bd == null) return -1;
      final c = ad.compareTo(bd);
      if (c != 0) return c;
      return b.importance.compareTo(a.importance);
    });
    return result;
  }

  Future<void> _pickImportance() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in [
              (0, tr('全部重要性')),
              (3, tr('只看高')),
              (2, tr('只看中')),
              (1, tr('只看低')),
            ])
              ListTile(
                dense: true,
                title: Text(e.$2, style: TextStyle(fontSize: 13.5)),
                trailing: _importanceFilter == e.$1
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.$1),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _importanceFilter = picked);
  }

  Future<void> _moreMenu() async {
    final picked = await showModalBottomSheet<String>(
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
              leading: Icon(Icons.check_circle_outline, size: 19),
              title: Text(tr('已完成'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('done'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.archive_outlined, size: 19),
              title: Text(tr('归档'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('archive'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline, size: 19),
              title: Text(tr('回收站'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('trash'),
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.folder_outlined, size: 19),
              title: Text(tr('清单管理'), style: TextStyle(fontSize: 13.5)),
              onTap: () => Navigator.of(ctx).pop('lists'),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    switch (picked) {
      case 'done':
        _push(CompletedPage());
      case 'archive':
        _push(ArchivePage());
      case 'trash':
        _push(TrashPage());
      case 'lists':
        _push(ListTasksPage(listId: _listFilter ?? 'inbox', name: tr('清单')));
    }
  }

  Future<void> _openTask(String id) async {
    await openTaskDetail(context, id);
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

// ------------------------------------------------------------------ 等级头

class _GrowthHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final growth = ref.watch(growthViewProvider);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _explain(context, growth),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFF2A65A), context.appColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.appColors.accent.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${growth.level}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        growth.levelLabel,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        growth.shardLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: growth.levelProgress,
                      minHeight: 4,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        context.appColors.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(0xFFF6C445).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Color(0xFFF6C445).withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.monetization_on,
                    size: 13,
                    color: Color(0xFFD79A00),
                  ),
                  SizedBox(width: 3),
                  Text(
                    '${growth.coins}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9A6B00),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _explain(BuildContext context, GrowthView growth) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('成长值怎么算'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                tr('1 碎片 = 完成 1 个任务，或达标打卡 1 天，或专注 10 分钟。\n') + tr('每 40 碎片升 1 级；每 10 碎片累计 1 枚金币（只记数，不做商店）。\n') + tr('数值全部从真实记录推导，不单独存经验值。'),
                style: TextStyle(fontSize: 12.5, height: 1.7),
              ),
              SizedBox(height: 14),
              Text(
                trf('今天：任务 {} · 习惯 {} · ', [growth.tasksToday, growth.habitsToday]) + trf('专注 {} 分钟 → +{} 碎片', [growth.focusMinutesToday, growth.todayShards]),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 周日期条

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.weekStart,
    required this.selected,
    required this.onSelect,
    required this.onShiftWeek,
    required this.onToday,
  });

  final DateTime weekStart;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onShiftWeek;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onShiftWeek(-1),
              icon: Icon(Icons.chevron_left, size: 20),
            ),
            Expanded(
              child: GestureDetector(
                onTap: onToday,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  dfYearMonthShortFmt().format(weekStart),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => onShiftWeek(1),
              icon: Icon(Icons.chevron_right, size: 20),
            ),
          ],
        ),
        SizedBox(height: 2),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _DayChip(
                  day: weekStart.add(Duration(days: i)),
                  selected: _sameDay(weekStart.add(Duration(days: i)), selected),
                  isToday: _sameDay(weekStart.add(Duration(days: i)), today),
                  onTap: () => onSelect(weekStart.add(Duration(days: i))),
                  scheme: scheme,
                ),
              ),
          ],
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
    required this.scheme,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final names = weekdayInitials;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 2.5),
        padding: EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: selected
              ? Border.all(color: scheme.outlineVariant, width: 1)
              : null,
        ),
        child: Column(
          children: [
            Text(
              names[day.weekday - 1],
              style: TextStyle(
                fontSize: 10,
                color: selected ? scheme.onSurface : scheme.outline,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? scheme.onSurface
                    : isToday
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ 折叠区

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.open,
    required this.onToggle,
    this.actions = const [],
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onToggle,
            child: Padding(
              padding: EdgeInsets.fromLTRB(2, 6, 8, 6),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: open ? 0 : -0.25,
                    duration: Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down, size: 18),
                  ),
                  SizedBox(width: 2),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(7),
        child: Icon(icon, size: 17, color: scheme.onSurfaceVariant),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _TaskFilterBar extends StatelessWidget {
  const _TaskFilterBar({
    required this.lists,
    required this.listId,
    required this.onList,
    required this.onSearch,
    required this.onFilter,
    required this.onMore,
    required this.selectedLabel,
  });

  final List<TaskList> lists;
  final String? listId;
  final ValueChanged<String?> onList;
  final VoidCallback onSearch;
  final VoidCallback onFilter;
  final VoidCallback onMore;
  final String selectedLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = lists.where((l) => l.id == listId).firstOrNull;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.only(left: 10, right: 2),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(9),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: listId,
              isDense: true,
              borderRadius: BorderRadius.circular(10),
              padding: EdgeInsets.only(left: 2, right: 2),
              icon: Icon(Icons.expand_more, size: 16),
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
              hint: Text(tr('全部'), style: TextStyle(fontSize: 12)),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(tr('全部'), style: TextStyle(fontSize: 12)),
                ),
                for (final l in lists)
                  DropdownMenuItem<String?>(
                    value: l.id,
                    child: Text(l.name, style: TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: onList,
            ),
          ),
        ),
        SizedBox(width: 6),
        Text(
          selectedLabel,
          style: TextStyle(fontSize: 10.5, color: scheme.outline),
        ),
        Spacer(),
        _HeaderIcon(icon: Icons.search, onTap: onSearch, tooltip: tr('搜索')),
        _HeaderIcon(icon: Icons.tune, onTap: onFilter, tooltip: tr('筛选')),
        _HeaderIcon(icon: Icons.more_vert, onTap: onMore, tooltip: tr('更多')),
        if (current == null) SizedBox.shrink(),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Text(
            text.isEmpty ? tr('这里还没有内容') : text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              actionLabel,
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
