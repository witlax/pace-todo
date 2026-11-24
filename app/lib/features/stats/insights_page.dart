import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../focus/focus_repository.dart';
import '../habits/habit_repository.dart';
import '../tasks/task_repository.dart';
import 'dashboard_cards.dart';
import 'stats_widgets.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 今日概况。入口在今日页右上角，也是「工作台」视图的主体。
///
/// 只保留三个指标 + 三条趋势：统计一旦要翻二级页面就不看了，
/// 全部铺在一屏里反而会天天扫一眼。
class TodayInsightsPage extends StatelessWidget {
  const TodayInsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(tr('今日概览'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            trf('{} · 第 {} 周', [dfMonthDayWeekFmt().format(now), _weekOfYear(now)]),
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 12),
          InsightsBody(),
        ],
      ),
    );
  }

  /// 手算周次：DateFormat 的模式 'ww' 在 zh_CN 下会原样返回 "ww"，
  /// 之前 int.parse 直接抛 FormatException，整页白屏。
  static int _weekOfYear(DateTime d) {
    final first = DateTime(d.year, 1, 1);
    final offset = first.weekday - 1; // 周一为 0
    return ((d.difference(first).inDays + offset) / 7).floor() + 1;
  }
}

/// 概览主体：可嵌入在今日概况页与工作台视图里。
class InsightsBody extends ConsumerWidget {
  const InsightsBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final doneToday = ref.watch(doneTodayProvider).value ?? 0;
    final focusMin = ref.watch(focusTodayMinutesProvider).value ?? 0;

    final habits = ref.watch(habitsProvider).value ?? <Habit>[];
    final habitLogs = ref.watch(habitLogsProvider).value ?? <HabitLog>[];
    final todayKey = dayKey(DateTime.now());
    // 多次习惯要打满目标才算完成，只数「有没有记录」会把 1/8 杯算成完成。
    final todayCount = <String, int>{};
    for (final l in habitLogs.where((l) => l.date == todayKey)) {
      todayCount[l.habitId] = l.count;
    }
    final habitsDone = habits
        .where((h) => (todayCount[h.id] ?? 0) >= h.targetCount)
        .length;

    final completed =
        ref.watch(completionHeatmapProvider).value ?? <Task>[];
    final byDay = <DateTime, int>{};
    for (final t in completed) {
      final at = t.completedAt;
      if (at == null) continue;
      final day = DateTime(at.year, at.month, at.day);
      byDay[day] = (byDay[day] ?? 0) + 1;
    }

    final habitDays = habitLogs.map((l) => l.date).toSet();

    // 给指标卡配一句对照：孤立的数字看不出好坏。
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final yesterday = today0.subtract(Duration(days: 1));
    final weekStart = today0.subtract(Duration(days: now.weekday - 1));
    var yDone = 0, wDone = 0;
    for (final t in completed) {
      final at = t.completedAt;
      if (at == null) continue;
      final d = DateTime(at.year, at.month, at.day);
      if (d == yesterday) yDone++;
      if (!d.isBefore(weekStart)) wDone++;
    }

    // 本周专注分布：按任务聚合，未关联任务归为「未关联」。
    final sessions =
        ref.watch(focusThisWeekProvider).value ?? <FocusSession>[];
    final tasks = ref.watch(allActiveTasksProvider).value ?? <Task>[];
    final titleOf = {for (final t in tasks) t.id: t.title};
    final byTask = <String, int>{};
    for (final s in sessions) {
      final key = s.taskId == null ? tr('未关联任务') : (titleOf[s.taskId] ?? tr('已删除任务'));
      byTask[key] = (byTask[key] ?? 0) + ((s.actualSec ?? 0) ~/ 60);
    }
    final weekTotal = byTask.values.fold<int>(0, (a, b) => a + b);
    final weekFocus = sessions.fold<int>(
      0,
      (a, s) => a + ((s.actualSec ?? 0) ~/ 60),
    );
    final slices =
        byTask.entries.map((e) => FocusSlice(e.key, e.value)).toList()
          ..sort((a, b) => b.minutes.compareTo(a.minutes));
    final topSlices = slices.length <= 4
        ? slices
        : [
            ...slices.take(4),
            FocusSlice(
              trf('其他 {} 项', [slices.length - 4]),
              slices.skip(4).fold<int>(0, (a, b) => a + b.minutes),
            ),
          ];

    // 卡片可配置：只渲染用户保留的卡片，按用户排的顺序。
    final cards = ref.watch(dashboardCardsProvider);
    final blocks = <Widget>[];
    void add(Widget w) {
      if (blocks.isNotEmpty) blocks.add(SizedBox(height: 22));
      blocks.add(w);
    }

    for (final card in cards) {
      switch (card) {
        case DashboardCard.metrics:
          add(
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    value: '$doneToday',
                    label: tr('完成任务'),
                    hint: trf('昨日 {} · 本周 {}', [yDone, wDone]),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    value: focusMin >= 60
                        ? '${focusMin ~/ 60}h${focusMin % 60 == 0 ? '' : focusMin % 60}m'
                        : '${focusMin}m',
                    label: tr('专注时长'),
                    hint: trf('本周 {}m', [weekFocus]),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: MetricCard(
                    value: '$habitsDone/${habits.length}',
                    label: tr('习惯打卡'),
                    hint: trf('共 {} 个习惯', [habits.length]),
                    accent: habits.isNotEmpty && habitsDone == habits.length
                        ? context.appColors.done
                        : null,
                  ),
                ),
              ],
            ),
          );
        case DashboardCard.weekBars:
          add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(tr('最近 7 天完成'), scheme),
                SizedBox(height: 6),
                WeekBars(counts: byDay),
              ],
            ),
          );
        case DashboardCard.heatmap:
          add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(
                  tr('本年打卡热力'),
                  scheme,
                  trailing: trf('{} 天', [habitDays.length]),
                ),
                SizedBox(height: 8),
                HeatmapGrid(days: habitDays),
              ],
            ),
          );
        case DashboardCard.focus:
          add(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(
                  tr('本周专注分布'),
                  scheme,
                  trailing: weekTotal == 0 ? null : trf('共 {}m', [weekTotal]),
                ),
                SizedBox(height: 4),
                FocusDistribution(slices: topSlices, total: weekTotal),
              ],
            ),
          );
      }
    }

    if (blocks.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 44),
        child: Column(
          children: [
            Icon(
              Icons.dashboard_customize_outlined,
              size: 32,
              color: scheme.outline,
            ),
            SizedBox(height: 8),
            Text(
              tr('工作台的卡片都收起来了'),
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
            TextButton(
              onPressed: ref.read(dashboardCardsProvider.notifier).reset,
              child: Text(tr('恢复默认')),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks,
    );
  }

  Widget _sectionTitle(String text, ColorScheme scheme, {String? trailing}) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        Spacer(),
        if (trailing != null)
          Text(trailing, style: TextStyle(fontSize: 11, color: scheme.outline)),
      ],
    );
  }
}
