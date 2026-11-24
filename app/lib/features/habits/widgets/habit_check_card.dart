import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database.dart';
import '../habit_repository.dart';
import '../habit_schedule.dart';
import '../../../app/tokens.dart';
import '../../../core/i18n/i18n.dart';

/// 习惯打卡卡片（首页与习惯页共用）。
///
/// 之前它是 `habit_page.dart` 里的私有类，首页要展示就只能复制一份；
/// 抽出来之后「打卡 / 长按写心得 / 长按日期补卡」只有一套实现。
class HabitCheckCard extends ConsumerWidget {
  const HabitCheckCard({
    super.key,
    required this.habit,
    required this.days,
    required this.todayCount,
    required this.onCheck,
    required this.onCheckLong,
    required this.onOpen,
    this.compact = false,
  });

  final Habit habit;
  final Set<String> days;
  final int todayCount;
  final VoidCallback onCheck;
  final VoidCallback onCheckLong;
  final VoidCallback onOpen;

  /// 首页折叠区里用紧凑版：不画 7 天小格，只留名字、连续天数和圆圈。
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final schedule = HabitSchedule.of(habit);
    final streak = schedule.streak(days, now: today);
    final todayKey = dayKey(today);
    final doneToday = todayCount >= habit.targetCount;
    final week = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(14, compact ? 10 : 12, 14, compact ? 10 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onOpen,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        habitDisplayTitle(habit.name),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          schedule.label,
                          if (habit.targetCount > 1)
                            trf('今天 {}/{}', [todayCount, habit.targetCount]),
                          if (habit.remindTime != null)
                            trf('提醒 {}', [habit.remindTime]),
                        ].join(' · '),
                        style: TextStyle(fontSize: 10.5, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                streak > 0 ? trf('连续 {} 天', [streak]) : tr('未开始'),
                style: TextStyle(
                  fontSize: 11,
                  color: streak > 0 ? context.appColors.done : scheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 4),
              // 点击区放到 44×44，圆圈仍画 28；长按进心得。
              Semantics(
                button: true,
                label: doneToday ? tr('取消今天的打卡') : trf('打卡 {}', [habit.name]),
                child: InkResponse(
                  onTap: onCheck,
                  onLongPress: onCheckLong,
                  radius: 22,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: doneToday
                              ? context.appColors.done
                              : Colors.transparent,
                          border: Border.all(
                            color: doneToday
                                ? context.appColors.done
                                : scheme.outline,
                            width: 1.6,
                          ),
                        ),
                        child: doneToday
                            ? Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!compact) ...[
            SizedBox(height: 10),
            Row(
              children: [
                for (final day in week)
                  Expanded(
                    child: GestureDetector(
                      onLongPress: () => ref
                          .read(habitRepositoryProvider)
                          .backfill(habit.id, day),
                      child: HabitDayCell(
                        day: day,
                        done: days.contains(dayKey(day)),
                        isToday: dayKey(day) == todayKey,
                        planned: schedule.scheduledOn(day),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 卡片里那 7 个日期小格。长按补卡由外层处理。
class HabitDayCell extends StatelessWidget {
  const HabitDayCell({
    super.key,
    required this.day,
    required this.done,
    required this.isToday,
    this.planned = true,
  });

  final DateTime day;
  final bool done;
  final bool isToday;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 2),
      height: 34,
      decoration: BoxDecoration(
        color: done
            ? context.appColors.done.withValues(alpha: 0.14)
            : planned
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isToday
            ? Border.all(color: context.appColors.done, width: 1)
            : null,
      ),
      child: Center(
        child: done
            ? Icon(Icons.check, size: 14, color: context.appColors.done)
            : Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 11,
                  color: planned
                      ? scheme.onSurfaceVariant
                      : scheme.outlineVariant,
                ),
              ),
      ),
    );
  }
}
