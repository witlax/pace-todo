import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/features/habits/habit_repository.dart';

void main() {
  final now = DateTime(2026, 11, 20, 10);

  String d(int offset) {
    final day = now.subtract(Duration(days: offset));
    return dayKey(day);
  }

  group('calcStreak', () {
    test('空记录为 0', () {
      expect(calcStreak({}, now: now), 0);
    });

    test('连续三天（含今天）为 3', () {
      expect(calcStreak({d(0), d(1), d(2)}, now: now), 3);
    });

    test('今天未打卡但昨天连续，按昨天起算', () {
      expect(calcStreak({d(1), d(2), d(3)}, now: now), 3);
    });

    test('中断后只算最近一段', () {
      expect(calcStreak({d(0), d(1), d(3), d(4)}, now: now), 2);
    });

    test('只有今天一次为 1', () {
      expect(calcStreak({d(0)}, now: now), 1);
    });

    test('只有前天（断两天）为 0', () {
      expect(calcStreak({d(2)}, now: now), 0);
    });
  });
}
