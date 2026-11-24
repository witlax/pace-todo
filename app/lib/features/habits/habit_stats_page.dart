import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import 'habit_repository.dart';
import '../../core/i18n/i18n.dart';

/// 习惯统计：按周 / 月 / 年看每个习惯的打卡次数与完成率。
/// 周期切换放在顶部分段控件，一屏能比完三个尺度。
class HabitStatsPage extends ConsumerStatefulWidget {
  const HabitStatsPage({super.key});

  @override
  ConsumerState<HabitStatsPage> createState() => _HabitStatsPageState();
}

enum _Period {
  week('本周'),
  month('本月'),
  year('本年');

  const _Period(this._label);
  final String _label;

  String get label => tr(_label);
}

class _HabitStatsPageState extends ConsumerState<HabitStatsPage> {
  _Period _period = _Period.week;

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider).value ?? <Habit>[];
    final logs = ref.watch(habitLogsProvider).value ?? <HabitLog>[];
    final scheme = Theme.of(context).colorScheme;

    final now = DateTime.now();
    final start = switch (_period) {
      _Period.week => DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: (now.weekday + 6) % 7)),
      _Period.month => DateTime(now.year, now.month, 1),
      _Period.year => DateTime(now.year, 1, 1),
    };
    final daysInPeriod = switch (_period) {
      _Period.week => 7,
      _Period.month => DateTime(now.year, now.month + 1, 0).day,
      _Period.year => now.difference(DateTime(now.year, 1, 1)).inDays + 1,
    };

    int countOf(String habitId) => logs
        .where(
          (l) =>
              l.habitId == habitId &&
              !DateTime.parse(l.date).isBefore(start) &&
              !DateTime.parse(l.date).isAfter(now),
        )
        .length;

    return Scaffold(
      appBar: AppBar(title: Text(tr('习惯统计'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SegmentedButton<_Period>(
            segments: [
              for (final p in _Period.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_period},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _period = s.first),
          ),
          SizedBox(height: 6),
          Text(
            trf('{} 起 · 共 {} 天', [dfMonthDayFmt().format(start), daysInPeriod]),
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
          SizedBox(height: 16),
          if (habits.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr('还没有习惯'),
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
            )
          else
            for (final h in habits)
              Builder(
                builder: (context) {
                  final count = countOf(h.id);
                  final rate = daysInPeriod == 0
                      ? 0.0
                      : (count / daysInPeriod).clamp(0.0, 1.0);
                  return Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                h.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5),
                              ),
                            ),
                            Text(
                              trf('{}/{} 天 · {}%', [count, daysInPeriod, (rate * 100).round()]),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: rate,
                            minHeight: 6,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}
