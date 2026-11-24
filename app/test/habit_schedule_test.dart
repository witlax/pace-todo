import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/features/habits/habit_schedule.dart';

String k(DateTime d) => habitDayKey(d);

void main() {
  group('周期解析与计划日', () {
    test('daily 每天都是计划日', () {
      final s = HabitSchedule.parse('daily');
      expect(s.scheduledOn(DateTime(2026, 11, 23)), isTrue);
      expect(s.label, '每天');
    });

    test('weekly 只命中指定周几', () {
      final s = HabitSchedule.parse('weekly:1,3,5');
      // 2026-11-23 是周一
      expect(s.scheduledOn(DateTime(2026, 11, 23)), isTrue);
      expect(s.scheduledOn(DateTime(2026, 11, 24)), isFalse);
      expect(s.scheduledOn(DateTime(2026, 11, 25)), isTrue);
      expect(s.label, '每周一、三、五');
    });

    test('monthly 命中每月指定日，31 号在短月落到月末', () {
      final s = HabitSchedule.parse('monthly:31');
      expect(s.scheduledOn(DateTime(2026, 2, 28)), isTrue);
      expect(s.scheduledOn(DateTime(2026, 2, 27)), isFalse);
      expect(s.scheduledOn(DateTime(2026, 3, 31)), isTrue);
    });

    test('monthly 15 只命中 15 号', () {
      final s = HabitSchedule.parse('monthly:15');
      expect(s.scheduledOn(DateTime(2026, 11, 15)), isTrue);
      expect(s.scheduledOn(DateTime(2026, 11, 16)), isFalse);
      expect(s.label, '每月 15 日');
    });

    test('interval 从 anchor 起每 N 天', () {
      final s = HabitSchedule.parse(
        'interval:3',
        anchor: DateTime(2026, 11, 20),
      );
      expect(s.scheduledOn(DateTime(2026, 11, 20)), isTrue);
      expect(s.scheduledOn(DateTime(2026, 11, 21)), isFalse);
      expect(s.scheduledOn(DateTime(2026, 11, 23)), isTrue);
      expect(s.scheduledOn(DateTime(2026, 11, 19)), isFalse); // anchor 之前
      expect(s.label, '每 3 天');
    });

    test('未知格式退化为每天，不会算成无计划日', () {
      for (final raw in [null, '', 'weird', 'weekly:', 'monthly:99']) {
        expect(HabitSchedule.parse(raw).scheduledOn(DateTime(2026, 11, 23)), isTrue);
      }
    });
  });

  group('区间计划次数', () {
    test('11 月周一三五共 13 天', () {
      final s = HabitSchedule.parse('weekly:1,3,5');
      final days = s.plannedDays(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
      expect(days.length, 13);
      expect(days.first, DateTime(2026, 11, 2));
      expect(days.last, DateTime(2026, 11, 30));
    });

    test('整月每天 = 当月天数（含闰年 2 月）', () {
      final s = HabitSchedule.parse('daily');
      expect(s.plannedBetween(DateTime(2028, 2, 1), DateTime(2028, 2, 29)), 29);
      expect(s.plannedBetween(DateTime(2026, 2, 1), DateTime(2026, 2, 28)), 28);
    });
  });

  group('连续天数', () {
    test('每天：今天没打不清零，从昨天算', () {
      final s = HabitSchedule.parse('daily');
      final done = {
        k(DateTime(2026, 11, 22)),
        k(DateTime(2026, 11, 21)),
        k(DateTime(2026, 11, 20)),
      };
      expect(s.streak(done, now: DateTime(2026, 11, 23)), 3);
    });

    test('每周一三五：周二不看，周一打了连续就是 1', () {
      final s = HabitSchedule.parse('weekly:1,3,5');
      final done = {k(DateTime(2026, 11, 23))}; // 周一
      expect(s.streak(done, now: DateTime(2026, 11, 24)), 1);
    });

    test('每周一三五：跨过周末继续累加', () {
      final s = HabitSchedule.parse('weekly:1,3,5');
      final done = {
        k(DateTime(2026, 11, 23)), // 一
        k(DateTime(2026, 11, 20)), // 五
        k(DateTime(2026, 11, 18)), // 三
        k(DateTime(2026, 11, 16)), // 一
      };
      expect(s.streak(done, now: DateTime(2026, 11, 24)), 4);
    });

    test('每周一三五：最近计划日没打就断（周二看周一）', () {
      final s = HabitSchedule.parse('weekly:1,3,5');
      final done = {k(DateTime(2026, 11, 20))}; // 上周五
      expect(s.streak(done, now: DateTime(2026, 11, 24)), 0);
    });

    test('隔天习惯：非计划日不打断', () {
      final s = HabitSchedule.parse(
        'interval:2',
        anchor: DateTime(2026, 11, 1),
      );
      final done = {
        k(DateTime(2026, 11, 23)),
        k(DateTime(2026, 11, 21)),
        k(DateTime(2026, 11, 19)),
      };
      expect(s.streak(done, now: DateTime(2026, 11, 23)), 3);
    });

    test('空记录连续为 0', () {
      expect(HabitSchedule.parse('daily').streak({}), 0);
    });
  });
}
