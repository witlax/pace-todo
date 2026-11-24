import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../focus/focus_repository.dart';
import '../habits/habit_repository.dart';
import '../tasks/task_repository.dart';
import '../../core/i18n/i18n.dart';

/// 成长值：把「今天做了什么」折成碎片、等级和金币。
///
/// 规则只有三条，界面上也写得出来，不需要教程：
/// - 1 碎片 = 完成 1 个任务，或达标打卡 1 天，或专注 10 分钟
/// - 每 40 碎片升 1 级（等级内的进度就是「还差多少碎片」）
/// - 每 10 碎片累计 1 枚金币（只记数，不设商店——不做消耗就没人会为了刷币而刷）
///
/// 数值只从真实记录推导，不单独存一份「经验值」：存了就会和任务/打卡表对不上。
class GrowthTotals {
  const GrowthTotals({
    this.doneTasks = 0,
    this.doneHabits = 0,
    this.focusMinutes = 0,
  });

  final int doneTasks;
  final int doneHabits;
  final int focusMinutes;

  int get shards => doneTasks + doneHabits + focusMinutes ~/ 10;
}

class GrowthView {
  const GrowthView({
    required this.total,
    required this.todayShards,
    required this.tasksToday,
    required this.habitsToday,
    required this.focusMinutesToday,
  });

  final int total;
  final int todayShards;
  final int tasksToday;
  final int habitsToday;
  final int focusMinutesToday;

  static const int span = 40;

  int get level => total ~/ span + 1;
  int get intoLevel => total % span;
  int get coins => total ~/ 10;

  /// 等级内的进度（0–1），用于顶部细进度条。
  double get levelProgress => (intoLevel / span).clamp(0.0, 1.0);

  String get levelLabel => 'Lv.$level';
  String get shardLabel => trf('{}/{} 碎片', [intoLevel, span]);
}

class GrowthRepository {
  GrowthRepository(this._db);

  final AppDatabase _db;

  Future<GrowthTotals> totals() async {
    final taskCount = _db.tasks.id.count();
    final taskRow = await (_db.selectOnly(_db.tasks)
          ..addColumns([taskCount])
          ..where(_db.tasks.status.equals(1) & _db.tasks.deletedAt.isNull()))
        .getSingle();
    final doneTasks = taskRow.read(taskCount) ?? 0;

    // 达标打卡：count 达到习惯目标才算一天，8 杯水点 3 次不计数。
    // 日志量在千级，直接取回来在内存里配对比拼 SQL 更不容易写错。
    final rows =
        await (_db.select(_db.habitLogs).join([
              innerJoin(
                _db.habits,
                _db.habits.id.equalsExp(_db.habitLogs.habitId),
              ),
            ])..where(
              _db.habitLogs.deletedAt.isNull() & _db.habits.deletedAt.isNull(),
            ))
            .get();
    var doneHabits = 0;
    for (final row in rows) {
      final log = row.readTable(_db.habitLogs);
      final habit = row.readTable(_db.habits);
      if (log.count >= habit.targetCount) doneHabits++;
    }

    final secSum = _db.focusSessions.actualSec.sum();
    final focusRow = await (_db.selectOnly(_db.focusSessions)
          ..addColumns([secSum]))
        .getSingle();
    final focusMinutes = (focusRow.read(secSum) ?? 0) ~/ 60;

    return GrowthTotals(
      doneTasks: doneTasks,
      doneHabits: doneHabits,
      focusMinutes: focusMinutes,
    );
  }
}

final growthRepositoryProvider = Provider<GrowthRepository>(
  (ref) => GrowthRepository(ref.watch(databaseProvider)),
);

/// 累计值：任务完成 / 打卡 / 专注任一处变化都会重算。
final growthTotalsProvider = FutureProvider<GrowthTotals>((ref) async {
  ref.watch(completedTasksProvider);
  ref.watch(habitLogsProvider);
  ref.watch(focusTodayMinutesProvider);
  return ref.watch(growthRepositoryProvider).totals();
});

/// 顶部展示用：累计 + 今日。
final growthViewProvider = Provider<GrowthView>((ref) {
  final totals =
      ref.watch(growthTotalsProvider).value ?? const GrowthTotals();
  final tasksToday = ref.watch(doneTodayProvider).value ?? 0;
  final focusMinutesToday = ref.watch(focusTodayMinutesProvider).value ?? 0;
  final logs = ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
  final habits = ref.watch(habitsProvider).value ?? const <Habit>[];

  final today = dayKey(DateTime.now());
  final byId = {for (final h in habits) h.id: h};
  var habitsToday = 0;
  for (final log in logs) {
    if (log.date != today) continue;
    final habit = byId[log.habitId];
    if (habit == null) continue;
    if (log.count >= habit.targetCount) habitsToday++;
  }

  // 今日碎片与累计口径一致：任务 + 达标打卡 + 专注每 10 分钟 1 片
  final todayShards =
      tasksToday + habitsToday + focusMinutesToday ~/ 10;

  return GrowthView(
    total: totals.shards,
    todayShards: todayShards,
    tasksToday: tasksToday,
    habitsToday: habitsToday,
    focusMinutesToday: focusMinutesToday,
  );
});
