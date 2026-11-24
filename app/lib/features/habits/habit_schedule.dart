import '../../core/db/database.dart';
import '../../core/i18n/i18n.dart';

/// 习惯周期的唯一判定入口。
///
/// 之前 `freqConfig` 只是一个字符串：创建时写进去，详情页却按整月天数算完成率，
/// `calcStreak` 按自然日连续算——「每周一三五」的习惯周二就会被判成断签。
/// 所有「哪天该打卡 / 这段区间该打几次 / 连续多少天」都必须走这里。
DateTime habitDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String habitDayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum HabitFreqKind { daily, weeklyDays, monthlyDay, interval }

class HabitSchedule {
  const HabitSchedule({
    required this.kind,
    this.weekdays = const {},
    this.monthDay,
    this.intervalDays,
    this.anchor,
  });

  final HabitFreqKind kind;
  final Set<int> weekdays; // 1=周一 … 7=周日
  final int? monthDay;
  final int? intervalDays;
  final DateTime? anchor; // interval 的起点

  factory HabitSchedule.of(Habit habit) {
    final anchor = habit.startDate != null
        ? DateTime.tryParse(habit.startDate!)
        : habit.createdAt;
    return HabitSchedule.parse(habit.freqConfig, anchor: anchor);
  }

  /// 支持 `daily`、`weekly:1,3,5`、`monthly:15`、`interval:3`。
  /// 解析失败一律退化为每天——宁可多算，不要算错成「无计划日」。
  factory HabitSchedule.parse(String? raw, {DateTime? anchor}) {
    final text = (raw ?? '').trim();
    if (text.isEmpty || text == 'daily') {
      return HabitSchedule(
        kind: HabitFreqKind.daily,
        anchor: anchor == null ? null : habitDateOnly(anchor),
      );
    }
    final parts = text.split(':');
    final head = parts.first;
    final tail = parts.length > 1 ? parts[1] : '';

    if (head == 'weekly') {
      final days = <int>{};
      for (final piece in tail.split(',')) {
        // 兼容 `weekly:3/count` 这类扩展写法，只取斜杠前的周几。
        final v = int.tryParse(piece.split('/').first.trim());
        if (v != null && v >= 1 && v <= 7) days.add(v);
      }
      if (days.isEmpty) {
        return HabitSchedule(kind: HabitFreqKind.daily, anchor: anchor);
      }
      return HabitSchedule(
        kind: HabitFreqKind.weeklyDays,
        weekdays: days,
        anchor: anchor == null ? null : habitDateOnly(anchor),
      );
    }
    if (head == 'monthly') {
      final v = int.tryParse(tail.trim());
      if (v == null || v < 1 || v > 31) {
        return HabitSchedule(kind: HabitFreqKind.daily, anchor: anchor);
      }
      return HabitSchedule(
        kind: HabitFreqKind.monthlyDay,
        monthDay: v,
        anchor: anchor == null ? null : habitDateOnly(anchor),
      );
    }
    if (head == 'interval') {
      final v = int.tryParse(tail.trim());
      if (v == null || v < 1) {
        return HabitSchedule(kind: HabitFreqKind.daily, anchor: anchor);
      }
      return HabitSchedule(
        kind: HabitFreqKind.interval,
        intervalDays: v,
        anchor: anchor == null ? null : habitDateOnly(anchor),
      );
    }
    return HabitSchedule(kind: HabitFreqKind.daily, anchor: anchor);
  }

  /// 这一天是否计划打卡。
  bool scheduledOn(DateTime day) {
    final d = habitDateOnly(day);
    switch (kind) {
      case HabitFreqKind.daily:
        return true;
      case HabitFreqKind.weeklyDays:
        return weekdays.contains(d.weekday);
      case HabitFreqKind.monthlyDay:
        final target = monthDay!;
        final last = DateTime(d.year, d.month + 1, 0).day;
        // 31 号的目标在 30 天的月份落到月末，而不是直接漏掉。
        return d.day == (target > last ? last : target);
      case HabitFreqKind.interval:
        final start = anchor ?? d;
        final diff = habitDateOnly(d).difference(habitDateOnly(start)).inDays;
        return diff >= 0 && diff % intervalDays! == 0;
    }
  }

  /// 区间内（含首尾）的计划打卡日。
  List<DateTime> plannedDays(DateTime from, DateTime to) {
    final a = habitDateOnly(from);
    final b = habitDateOnly(to);
    if (b.isBefore(a)) return const [];
    final result = <DateTime>[];
    var cursor = a;
    var guard = 0;
    while (!cursor.isAfter(b) && guard < 4000) {
      if (scheduledOn(cursor)) result.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
      guard++;
    }
    return result;
  }

  int plannedBetween(DateTime from, DateTime to) =>
      plannedDays(from, to).length;

  /// 连续打卡：只在计划日推进；非计划日不打断；今天尚未打卡不算断。
  int streak(Set<String> doneDays, {DateTime? now, int maxScan = 730}) {
    if (doneDays.isEmpty) return 0;
    var cursor = habitDateOnly(now ?? DateTime.now());

    // 今天不是计划日：先退到最近一个计划日。
    var guard = 0;
    while (!scheduledOn(cursor) && guard < maxScan) {
      cursor = cursor.subtract(const Duration(days: 1));
      guard++;
    }
    // 最近计划日还没打卡：今天/昨天都没打，连续为 0（若今天本来就是计划日，
    // 今天没打也不该把之前的连续清掉——所以今天这个点单独跳过）。
    final today = habitDateOnly(now ?? DateTime.now());
    if (!doneDays.contains(habitDayKey(cursor)) &&
        cursor == today &&
        scheduledOn(today)) {
      cursor = cursor.subtract(const Duration(days: 1));
      guard = 0;
      while (!scheduledOn(cursor) && guard < maxScan) {
        cursor = cursor.subtract(const Duration(days: 1));
        guard++;
      }
    }

    var count = 0;
    guard = 0;
    while (guard < maxScan) {
      if (scheduledOn(cursor)) {
        if (!doneDays.contains(habitDayKey(cursor))) break;
        count++;
      }
      cursor = cursor.subtract(const Duration(days: 1));
      guard++;
    }
    return count;
  }

  String get label {
    final names = weekdayInitials;
    switch (kind) {
      case HabitFreqKind.daily:
        return tr('每天');
      case HabitFreqKind.weeklyDays:
        final sorted = weekdays.toList()..sort();
        return trf('每周{}', [sorted.map((d) => names[d - 1]).join('、')]);
      case HabitFreqKind.monthlyDay:
        return trf('每月 {} 日', [monthDay]);
      case HabitFreqKind.interval:
        return trf('每 {} 天', [intervalDays]);
    }
  }
}
