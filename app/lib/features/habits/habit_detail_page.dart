import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/ui/confirm.dart';
import '../tasks/task_repository.dart';
import 'habit_schedule.dart';
import '../focus/focus_page.dart';
import 'habit_edit_page.dart';
import 'habit_repository.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 习惯详情：整月热力图 + 关键指标。
/// 点任意一天可补卡或取消，长按同样可用——补卡是这类工具的高频补救动作。
class HabitDetailPage extends ConsumerStatefulWidget {
  const HabitDetailPage({super.key, required this.habitId});

  final String habitId;

  @override
  ConsumerState<HabitDetailPage> createState() => _HabitDetailPageState();
}

class _HabitDetailPageState extends ConsumerState<HabitDetailPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final logs = ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
    final scheme = Theme.of(context).colorScheme;

    final habit = habits.where((h) => h.id == widget.habitId).firstOrNull;
    if (habit == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr('习惯不存在'))),
      );
    }

    final days = logs
        .where((l) => l.habitId == habit.id)
        .map((l) => l.date)
        .toSet();
    final schedule = HabitSchedule.of(habit);
    final streak = schedule.streak(days);
    // 只算这个月「该打卡」的日子：每周一三五不该按 30 天算分母。
    final monthDays = schedule.plannedDays(
      DateTime(_month.year, _month.month, 1),
      DateTime(_month.year, _month.month + 1, 0),
    );
    final monthDone = monthDays.where((d) => days.contains(dayKey(d))).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(habit.name),
        actions: [
          IconButton(
            tooltip: tr('开始专注'),
            icon: Icon(Icons.timer_outlined, size: 20),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    FocusPage(initialTitle: habitDisplayName(habit.name)),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('编辑习惯'),
            icon: Icon(Icons.edit_outlined, size: 20),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => HabitEditPage(habit: habit),
              ),
            ),
          ),
          IconButton(
            tooltip: tr('上月'),
            icon: Icon(Icons.chevron_left),
            onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1),
            ),
          ),
          IconButton(
            tooltip: tr('下月'),
            icon: Icon(Icons.chevron_right),
            onPressed: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: tr('更多'),
            icon: Icon(Icons.more_vert, size: 20),
            onSelected: (v) async {
              if (v == 'archive') {
                final ok = await confirmAction(
                  context,
                  title: trf('归档习惯「{}」？', [habit.name]),
                  message: tr('归档后不再出现在习惯列表，打卡记录全部保留。'),
                  confirmLabel: tr('归档'),
                );
                if (!ok || !context.mounted) return;
                await ref.read(habitRepositoryProvider).archiveHabit(habit.id);
                if (context.mounted) Navigator.of(context).pop();
                return;
              }
              if (v != 'delete') return;
              final ok = await confirmDanger(
                context,
                title: trf('删除习惯「{}」？', [habit.name]),
                message: trf('全部打卡记录（{} 天）会一起删除，且无法恢复。', [days.length]),
              );
              if (!ok || !context.mounted) return;
              await ref.read(habitRepositoryProvider).deleteHabit(habit.id);
              if (context.mounted) Navigator.of(context).pop();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'archive', child: Text(tr('归档习惯'))),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18),
                    SizedBox(width: 8),
                    Text(tr('删除习惯')),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // 月打卡进度环：计划 / 实际 / 错过 一眼看完
          Container(
            padding: EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(width: 16),
                    Icon(Icons.circle, size: 8, color: scheme.primary),
                    SizedBox(width: 6),
                    Text(
                      trf('打卡进度 · {}', [dfMonthOnlyFmt().format(_month)]),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: monthDays.isEmpty
                              ? 0
                              : monthDone / monthDays.length,
                          strokeWidth: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: scheme.primary,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(monthDone / monthDays.length * 100).round()}%',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            tr('本月'),
                            style: TextStyle(
                              fontSize: 10,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    _Stat(label: tr('计划打卡'), value: trf('{} 天', [monthDays.length])),
                    _Stat(label: tr('实际打卡'), value: trf('{} 天', [monthDone])),
                    _Stat(
                      label: tr('错过'),
                      value: trf('{} 天', [monthDays.length - monthDone]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 14),
          Row(
            children: [
              _Stat(label: tr('连续天数'), value: '$streak'),
              SizedBox(width: 10),
              _Stat(label: tr('最长连续'), value: trf('{} 天', [calcLongestStreak(days)])),
            ],
          ),
          SizedBox(height: 22),
          Text(
            dfYearMonthFmt().format(_month),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              for (final w in [tr('一'), tr('二'), tr('三'), tr('四'), tr('五'), tr('六'), tr('日')])
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 6),
          _MonthHeatmap(
            month: _month,
            days: days,
            onTap: (day) => _toggle(day),
          ),
          SizedBox(height: 20),
          Text(
            tr('点任意一天补卡或取消。补卡按「归属日」记录，跨时区不改写历史（ADR-0012 相关约定）。'),
            style: TextStyle(fontSize: 11, height: 1.7, color: scheme.outline),
          ),
          SizedBox(height: 22),
          Text(
            tr('打卡日志'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8),
          if (logs.where((l) => l.habitId == habit.id).isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                tr('还没有打卡日志'),
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            )
          else
            for (final log in logs.where((l) => l.habitId == habit.id).take(30))
              Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Text(
                        log.date.substring(5),
                        style: TextStyle(fontSize: 11.5, color: scheme.outline),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        (log.note ?? '').isEmpty ? tr('已打卡') : log.note!,
                        style: TextStyle(fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
          SizedBox(height: 18),
          Text(
            tr('打卡总进度'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8),
          _kv(tr('开始日期'), habit.startDate ?? '—'),
          _kv(
            tr('距今天数'),
            habit.startDate == null
                ? '—'
                : trf('{} 天', [DateTime.now().difference(DateTime.parse(habit.startDate!)).inDays + 1]),
          ),
          _kv(tr('打卡总天数'), trf('{} 天', [days.length])),
          _kv(tr('最长连续'), trf('{} 天', [calcLongestStreak(days)])),
        ],
      ),
    );
  }

  Future<void> _toggle(DateTime day) async {
    final repo = ref.read(habitRepositoryProvider);
    final logs = ref.read(habitLogsProvider).value ?? <HabitLog>[];
    final key = dayKey(day);
    final existing = logs.where(
      (l) => l.habitId == widget.habitId && l.date == key,
    );

    if (existing.isNotEmpty) {
      final db = ref.read(databaseProvider);
      await (db.delete(
        db.habitLogs,
      )..where((l) => l.id.equals(existing.first.id))).go();
    } else {
      await repo.backfill(widget.habitId, day);
    }
  }
}

Widget _kv(String k, String v) => Padding(
  padding: EdgeInsets.symmetric(vertical: 5),
  child: Row(
    children: [
      Text(k, style: TextStyle(fontSize: 12.5)),
      Spacer(),
      Text(v, style: TextStyle(fontSize: 12.5)),
    ],
  ),
);

class _MonthHeatmap extends StatelessWidget {
  const _MonthHeatmap({
    required this.month,
    required this.days,
    required this.onTap,
  });

  final DateTime month;
  final Set<String> days;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final leading = (first.weekday + 6) % 7;
    final total = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((leading + total + 6) ~/ 7) * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: cells,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final dayNumber = index - leading + 1;
        if (dayNumber < 1 || dayNumber > total) {
          return SizedBox.shrink();
        }
        final day = DateTime(month.year, month.month, dayNumber);
        final done = days.contains(dayKey(day));
        final isFuture = day.isAfter(DateTime.now());

        return GestureDetector(
          onTap: isFuture ? null : () => onTap(day),
          child: Container(
            decoration: BoxDecoration(
              color: done
                  ? context.appColors.done
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '$dayNumber',
                style: TextStyle(
                  fontSize: 10.5,
                  color: done
                      ? Colors.white
                      : (isFuture
                            ? scheme.outlineVariant
                            : scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
