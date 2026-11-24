import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../settings/settings.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/task_repository.dart';
import '../tasks/today_page.dart' show QuickAddSheet;
import '../tasks/widgets/task_tile.dart';
import '../views/day_review_page.dart';
import '../../core/i18n/i18n.dart';

/// 日历的三种视图：月总览、三日时间轴、单周时间轴。
enum CalendarViewScope { month, threeDay, week }

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key, this.embedded = false});

  /// 嵌入「视图」页时为 true：不再自己加顶部安全区。
  final bool embedded;

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _month;
  late DateTime _selected;
  CalendarViewScope _scope = CalendarViewScope.month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
  }

  /// 所在周的周一。
  DateTime get _weekStart {
    final d = _selected;
    return DateTime(
      d.year,
      d.month,
      d.day,
    ).subtract(Duration(days: (d.weekday + 6) % 7));
  }

  int get _stepDays => switch (_scope) {
    CalendarViewScope.month => 0,
    CalendarViewScope.threeDay => 3,
    CalendarViewScope.week => 7,
  };

  void _shift(int direction) {
    setState(() {
      if (_scope == CalendarViewScope.month) {
        _month = DateTime(_month.year, _month.month + direction);
        return;
      }
      final target = _selected.add(Duration(days: _stepDays * direction));
      _selected = target;
      _month = DateTime(target.year, target.month);
    });
  }

  void _prev() => _shift(-1);

  void _next() => _shift(1);

  String get _titleText => switch (_scope) {
    CalendarViewScope.month => dfYearMonthFmt().format(_month),
    CalendarViewScope.threeDay =>
      '${dfMonthDayFmt().format(_selected.subtract(const Duration(days: 1)))}'
          ' – '
          '${dfMonthDayFmt().format(_selected.add(const Duration(days: 1)))}',
    CalendarViewScope.week =>
      '${dfMonthDayFmt().format(_weekStart)} – '
          '${dfMonthDayFmt().format(_weekStart.add(const Duration(days: 6)))}',
  };

  /// 三日视图点空白：直接用那个小时新建。
  void _quickAddAt(DateTime day, int hour) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddSheet(
        initialDue: DateTime(day.year, day.month, day.day, hour),
      ),
    );
  }

  /// 标题 + 视图切换：三日视图要固定表头，所以单独抽出来两处复用。
  Widget _header(BuildContext context, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: _prev,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: _next,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: SegmentedButton<CalendarViewScope>(
            segments: [
              ButtonSegment(value: CalendarViewScope.month, label: Text(tr('月'))),
              ButtonSegment(
                value: CalendarViewScope.threeDay,
                label: Text(tr('三日')),
              ),
              ButtonSegment(value: CalendarViewScope.week, label: Text(tr('周'))),
            ],
            selected: {_scope},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _scope = v.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                TextStyle(fontSize: 11.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(openTasksProvider).value ?? <Task>[];
    final completed =
        ref.watch(completionHeatmapProvider).value ?? <Task>[];
    final byDayDone = <DateTime, int>{};
    for (final t in completed) {
      final at = t.completedAt;
      if (at == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      byDayDone[day] = (byDayDone[day] ?? 0) + 1;
    }
    final scheme = Theme.of(context).colorScheme;

    final byDay = <DateTime, List<Task>>{};
    for (final t in tasks) {
      final due = t.dueAt;
      if (due == null) continue;
      final day = DateTime(due.year, due.month, due.day);
      byDay.putIfAbsent(day, () => []).add(t);
    }
    final monthTotal = byDay.entries
        .where((e) => e.key.year == _month.year && e.key.month == _month.month)
        .fold<int>(0, (a, e) => a + e.value.length);
    var monthDone = 0;
    for (final e in byDayDone.entries) {
      if (e.key.year == _month.year && e.key.month == _month.month) {
        monthDone += e.value;
      }
    }

    final dayTasks = [...(byDay[_selected] ?? <Task>[])];
    dayTasks.sort(
      (a, b) =>
          (a.dueAt ?? DateTime.now()).compareTo(b.dueAt ?? DateTime.now()),
    );

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => QuickAddSheet(
            initialDue: DateTime(
              _selected.year,
              _selected.month,
              _selected.day,
              18,
            ),
          ),
        ),
        child: Icon(Icons.add),
      ),
      body: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: _scope == CalendarViewScope.threeDay
            ? Column(
                children: [
                  _header(context, scheme),
                  Expanded(
                    child: _ThreeDayTimeline(
                      selected: _selected,
                      byDay: byDay,
                      onOpen: (t) => openTaskDetail(context, t.id),
                      onCreate: _quickAddAt,
                    ),
                  ),
                ],
              )
            : ListView(
                padding: EdgeInsets.only(bottom: 96),
                children: [
                  _header(context, scheme),
                  if (_scope == CalendarViewScope.month)
                    Padding(
                      padding: EdgeInsets.fromLTRB(22, 0, 22, 6),
                      child: Row(
                        children: [
                          Text(
                            trf('本月 {} 项 · 完成 {}', [monthTotal, monthDone]),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.outline,
                            ),
                          ),
                          Spacer(),
                          Text(
                            monthTotal == 0 ? '' : tr('底色越深越忙'),
                            style: TextStyle(
                              fontSize: 9.5,
                              color: scheme.outlineVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_scope == CalendarViewScope.week)
                    _WeekStrip(
                      start: _weekStart,
                      selected: _selected,
                      byDay: byDay,
                      onSelect: (day) => setState(() => _selected = day),
                    )
                  else ...[
                    _WeekHeader(scheme: scheme),
                    _MonthGrid(
                      month: _month,
                      selected: _selected,
                      byDay: byDay,
                      byDayDone: byDayDone,
                      onSelect: (day) => setState(() => _selected = day),
                      onDropTask: (task, day) => _moveTo(task, day),
                    ),
                  ],
                  if (_scope != CalendarViewScope.threeDay) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Row(
                        children: [
                          Text(
                            dfMonthDayWeekFmt().format(_selected),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            trf('{} 项', [dayTasks.length]),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Spacer(),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DayReviewPage(date: _selected),
                              ),
                            ),
                            icon: Icon(Icons.insights, size: 15),
                            label: Text(
                              tr('这天'),
                              style: TextStyle(fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                    if (dayTasks.isEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(20, 28, 20, 28),
                        child: Center(
                          child: Text(
                            tr('这一天还没有安排'),
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: [
                            for (final t in dayTasks)
                              LongPressDraggable<Task>(
                                data: t,
                                delay: Duration(milliseconds: 240),
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: Container(
                                    width: 220,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface,
                                      borderRadius: BorderRadius.circular(9),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.16,
                                          ),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      t.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.35,
                                  child: _tile(t),
                                ),
                                child: _tile(t),
                              ),
                            Padding(
                              padding: EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                tr('长按任务拖到上面的日期，即可改期'),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: scheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_scope == CalendarViewScope.week)
                      _WeekTimeline(dayTasks: dayTasks, date: _selected),
                  ],

                  SizedBox(height: 20),
                ],
              ),
      ),
    );
  }

  Widget _tile(Task t) => TaskTile(
    task: t,
    onToggle: () => ref.read(taskRepositoryProvider).setDone(t.id, true),
    onOpen: () => openTaskDetail(context, t.id),
    onDelete: () => ref.read(taskRepositoryProvider).softDelete(t.id),
  );

  /// 拖到某天：保留原来的时分，没有时间就落到 18:00。
  Future<void> _moveTo(Task task, DateTime day) async {
    final old = task.dueAt;
    final target = DateTime(
      day.year,
      day.month,
      day.day,
      old?.hour ?? 18,
      old?.minute ?? 0,
    );
    final repo = ref.read(taskRepositoryProvider);
    await repo.updateTask(task.id, dueAt: target);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 4),
          content: Text(
            trf('「{}」已改到 {}', [task.title, dfMonthDayTimeFmt().format(target)]),
            style: TextStyle(fontSize: 12.5),
          ),
          action: SnackBarAction(
            label: tr('撤销'),
            onPressed: () => old == null
                ? repo.updateTask(task.id, clearDue: true)
                : repo.updateTask(task.id, dueAt: old),
          ),
        ),
      );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.start,
    required this.selected,
    required this.byDay,
    required this.onSelect,
  });

  final DateTime start;
  final DateTime selected;
  final Map<DateTime, List<Task>> byDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = ProviderScope.containerOf(context).read(paletteProvider);
    final scheme = Theme.of(context).colorScheme;
    final labels = weekdayInitials;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final day = DateTime(start.year, start.month, start.day + i);
                  final isSelected =
                      day.year == selected.year &&
                      day.month == selected.month &&
                      day.day == selected.day;
                  final isToday = _same(day, DateTime.now());
                  final tasks = byDay[day] ?? <Task>[];
                  final density = tasks.isEmpty
                      ? 0.0
                      : tasks.length >= 5
                      ? 0.16
                      : tasks.length >= 3
                      ? 0.11
                      : 0.06;
                  return GestureDetector(
                    onTap: () => onSelect(day),
                    child: Container(
                      margin: EdgeInsets.all(2),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? scheme.primary
                            : density == 0
                            ? Colors.transparent
                            : scheme.primary.withValues(alpha: density),
                        borderRadius: BorderRadius.circular(10),
                        border: isToday && !isSelected
                            ? Border.all(color: scheme.primary, width: 1)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isSelected
                                  ? scheme.onPrimary.withValues(alpha: 0.8)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? scheme.onPrimary
                                  : scheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 4),
                          SizedBox(
                            height: 5,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (final t in tasks.take(3))
                                  Container(
                                    width: 4,
                                    height: 4,
                                    margin: EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isSelected
                                          ? scheme.onPrimary
                                          : palette.of(
                                              Emphasis.fromValue(t.importance),
                                            ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final labels = weekdayInitials;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final l in labels)
            Expanded(
              child: Center(
                child: Text(
                  l,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.byDay,
    required this.byDayDone,
    required this.onSelect,
    required this.onDropTask,
  });

  final DateTime month;
  final DateTime selected;
  final Map<DateTime, List<Task>> byDay;
  final Map<DateTime, int> byDayDone;
  final ValueChanged<DateTime> onSelect;
  final void Function(Task task, DateTime day) onDropTask;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = ProviderScope.containerOf(context).read(paletteProvider);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = (first.weekday + 6) % 7; // 周一为一周起点
    final total = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: total,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 1.05,
        ),
        itemBuilder: (_, index) {
          final dayNumber = index - leading + 1;
          if (dayNumber < 1 || dayNumber > daysInMonth) {
            return SizedBox.shrink();
          }
          final day = DateTime(month.year, month.month, dayNumber);
          final tasks = byDay[day] ?? <Task>[];
          final done = byDayDone[day] ?? 0;
          final isSelected = day == selected;
          final isToday = _isSameDay(day, DateTime.now());
          // 密度底：让「哪天忙」一眼看出来，而不是一排同样的数字。
          final density = tasks.isEmpty
              ? 0.0
              : tasks.length >= 5
              ? 0.16
              : tasks.length >= 3
              ? 0.11
              : 0.06;

          return DragTarget<Task>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (d) => onDropTask(d.data, day),
            builder: (context, candidate, _) {
              final hovering = candidate.isNotEmpty;
              return GestureDetector(
                onTap: () => onSelect(day),
                child: Container(
                  margin: EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primary
                        : hovering
                        ? scheme.primaryContainer
                        : density == 0
                        ? Colors.transparent
                        : scheme.primary.withValues(alpha: density),
                    borderRadius: BorderRadius.circular(8),
                    border: isToday && !isSelected
                        ? Border.all(color: scheme.primary, width: 1)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isSelected
                              ? scheme.onPrimary
                              : isToday
                              ? scheme.primary
                              : scheme.onSurface,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      SizedBox(height: 3),
                      SizedBox(
                        height: 5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final t in tasks.take(3))
                              _dot(
                                palette.of(Emphasis.fromValue(t.importance)),
                                selected: isSelected,
                                scheme: scheme,
                              ),
                            if (done > 0)
                              _dot(
                                context.appColors.done,
                                selected: isSelected,
                                scheme: scheme,
                                size: 4.5,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _dot(
    Color color, {
    required bool selected,
    required ColorScheme scheme,
    double size = 4,
  }) {
    return Container(
      width: size,
      height: size,
      margin: EdgeInsets.symmetric(horizontal: 0.8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.onPrimary.withValues(alpha: 0.85) : color,
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 周视图下的单日时间轴：8:00–21:00，按小时行排布当天任务。
/// 周条只回答「这周忙不忙」，时间轴回答「几点做什么」。
class _WeekTimeline extends StatelessWidget {
  const _WeekTimeline({required this.dayTasks, required this.date});

  final List<Task> dayTasks;
  final DateTime date;

  bool _isNowHour(int hour) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day &&
        hour == now.hour;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byHour = <int, List<Task>>{};
    for (final t in dayTasks) {
      final due = t.dueAt;
      if (due == null) continue;
      byHour.putIfAbsent(due.hour, () => []).add(t);
    }
    final untimed = dayTasks.where((t) => t.dueAt == null).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (untimed.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                trf('未排时间：{}', [untimed.map((t) => t.title).join('、')]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),
          for (var hour = 8; hour <= 21; hour++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: TextStyle(fontSize: 9.5, color: scheme.outline),
                  ),
                ),
                Expanded(
                  child: Container(
                    constraints: BoxConstraints(minHeight: 26),
                    padding: EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: _isNowHour(hour)
                              ? context.appColors.warn
                              : scheme.outlineVariant.withValues(alpha: 0.35),
                          width: _isNowHour(hour) ? 1.4 : 1,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isNowHour(hour))
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              trf('现在 {}:{}', [DateTime.now().hour.toString().padLeft(2, '0'), DateTime.now().minute.toString().padLeft(2, '0')]),
                              style: TextStyle(
                                fontSize: 9,
                                color: context.appColors.warn,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        for (final t in byHour[hour] ?? <Task>[])
                          Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${t.dueAt!.minute.toString().padLeft(2, '0')} ${t.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 三日视图：以选中日为中心，左右各一天，三列共用一条时间轴。
///
/// 手机上「周」太细（一列只有 40dp），「月」又看不到具体时间；
/// 三日是「知道这三天怎么排」的最小可用粒度。
class _ThreeDayTimeline extends ConsumerWidget {
  const _ThreeDayTimeline({
    required this.selected,
    required this.byDay,
    required this.onOpen,
    required this.onCreate,
  });

  final DateTime selected;
  final Map<DateTime, List<Task>> byDay;
  final void Function(Task) onOpen;
  final void Function(DateTime day, int hour) onCreate;

  /// 重要性色走统一色板，随配色方案与明暗变化。
  Color _colorOf(WidgetRef ref, Task t) =>
      ref.watch(paletteProvider).of(Emphasis.fromValue(t.importance));

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final days = List.generate(
      3,
      (i) => DateTime(selected.year, selected.month, selected.day + i - 1),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 30),
              for (final day in days)
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final isToday = _isSameDay(day, now);
                      final isSelected = _isSameDay(day, selected);
                      final count = (byDay[day] ?? <Task>[]).length;
                      return Container(
                        margin: EdgeInsets.symmetric(horizontal: 1),
                        padding: EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? scheme.primary.withValues(alpha: 0.08)
                              : null,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Column(
                          children: [
                            Text(
                              [
                                tr('一'),
                                tr('二'),
                                tr('三'),
                                tr('四'),
                                tr('五'),
                                tr('六'),
                                tr('日'),
                              ][day.weekday - 1],
                              style: TextStyle(
                                fontSize: 9,
                                color: isToday
                                    ? scheme.primary
                                    : scheme.outline,
                              ),
                            ),
                            SizedBox(height: 1),
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isSelected || isToday
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isToday ? scheme.primary : null,
                              ),
                            ),
                            Text(
                              count == 0 ? ' ' : trf('{} 项', [count]),
                              style: TextStyle(
                                fontSize: 8,
                                color: scheme.outline,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          SizedBox(height: 2),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: 12),
              children: [
                // 行高 28：一屏能看完 8–21 点，表头固定在外层不随滚动。
                for (var hour = 8; hour <= 21; hour++)
                  SizedBox(
                    height: 28,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 30,
                          child: Text(
                            hour.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontSize: 8,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                        for (final day in days)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => onCreate(day, hour),
                              child: Container(
                                margin: EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: _isSameDay(day, now)
                                      ? scheme.primary.withValues(alpha: 0.02)
                                      : null,
                                  border: Border(
                                    top: BorderSide(
                                      color: scheme.outlineVariant.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    for (final t
                                        in (byDay[day] ?? <Task>[]).where(
                                          (t) =>
                                              t.dueAt != null &&
                                              t.dueAt!.hour == hour,
                                        ))
                                      Positioned(
                                        left: 1,
                                        right: 1,
                                        top: ((t.dueAt!.minute / 60) * 20)
                                            .clamp(0, 16),
                                        child: GestureDetector(
                                          onTap: () => onOpen(t),
                                          child: Container(
                                            height: 20,
                                            alignment: Alignment.centerLeft,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _colorOf(ref, t)
                                                  .withValues(alpha: 0.16),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border(
                                                left: BorderSide(
                                                  color: _colorOf(ref, t),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              t.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 8,
                                                color: _colorOf(ref, t),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
