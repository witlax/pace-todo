import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../mood/mood_page.dart';
import 'habit_detail_page.dart';
import 'habit_edit_page.dart';
import 'habit_stats_page.dart';
import 'habit_repository.dart';
import 'habit_actions.dart';
import 'habit_schedule.dart';
import 'widgets/habit_check_card.dart';
import '../../core/i18n/i18n.dart';

class HabitPage extends ConsumerWidget {
  const HabitPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final logs = ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
    final scheme = Theme.of(context).colorScheme;

    final byHabit = <String, Set<String>>{};
    final countByHabit = <String, Map<String, int>>{};
    for (final log in logs) {
      if (log.count > 0) {
        byHabit.putIfAbsent(log.habitId, () => <String>{}).add(log.date);
      }
      countByHabit.putIfAbsent(log.habitId, () => {})[log.date] = log.count;
    }
    final today = dayKey(DateTime.now());
    final now = DateTime.now();

    // 「今日 M/N」只算今天该打卡的习惯；次数习惯达到目标才算完成。
    final plannedToday = habits
        .where((h) => HabitSchedule.of(h).scheduledOn(now))
        .toList();
    final doneToday = plannedToday.where((h) {
      final c = countByHabit[h.id]?[today] ?? 0;
      return c >= h.targetCount;
    }).length;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const HabitEditPage())),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
              child: Row(
                children: [
                  Text(
                    tr('习惯'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  IconButton(
                    tooltip: tr('心情'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => MoodPage()),
                    ),
                    icon: Icon(Icons.mood, size: 20),
                  ),
                  IconButton(
                    tooltip: tr('统计'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HabitStatsPage(),
                      ),
                    ),
                    icon: Icon(Icons.insights, size: 20),
                  ),
                  Text(
                    habits.isEmpty
                        ? ''
                        : trf('今日 {} / {}', [doneToday, plannedToday.length]),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Text(
                tr('单击圆圈打卡 · 长按写心得 · 长按日期格补卡'),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),
            Expanded(
              child: habits.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 40,
                            color: scheme.outline,
                          ),
                          SizedBox(height: 10),
                          Text(
                            tr('还没有习惯'),
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          SizedBox(height: 4),
                          Text(
                            tr('从一件小事开始'),
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
                      itemCount: habits.length,
                      onReorderItem: (from, to) {
                        final ids = habits.map((h) => h.id).toList();
                        final moved = ids.removeAt(from);
                        ids.insert(to.clamp(0, ids.length), moved);
                        ref.read(habitRepositoryProvider).reorderHabits(ids);
                      },
                      itemBuilder: (_, i) {
                        final habit = habits[i];
                        final days = byHabit[habit.id] ?? <String>{};
                        return Padding(
                          key: ValueKey(habit.id),
                          padding: EdgeInsets.only(bottom: 10),
                          child: Stack(
                            children: [
                              HabitCheckCard(
                                habit: habit,
                                days: days,
                                todayCount: countByHabit[habit.id]?[today] ?? 0,
                                onCheck: () => habitQuickCheckIn(
                                  context,
                                  ref,
                                  habit,
                                  days,
                                  countByHabit[habit.id]?[today] ?? 0,
                                ),
                                onCheckLong: () =>
                                    habitOpenJournal(context, ref, habit),
                                onOpen: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        HabitDetailPage(habitId: habit.id),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 2,
                                bottom: 4,
                                child: ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      size: 14,
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
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
      ),
    );
  }
}
