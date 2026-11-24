import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../habits/habit_repository.dart';
import '../habits/habit_schedule.dart';
import '../tasks/task_repository.dart';
import '../../core/i18n/i18n.dart';

/// 目标的进度来源。四种就够：任务看完成比例、习惯看打卡次数、
/// 专注看累计分钟、手动自己写——再多的模式都会变成负担。
enum GoalMode {
  tasks('任务', '项'),
  habits('习惯', '次'),
  focus('专注', '分钟'),
  manual('手动', '%');

  const GoalMode(this._label, this._unit);
  final String _label;
  final String _unit;

  String get label => tr(_label);
  String get unit => tr(_unit);

  static GoalMode fromValue(int v) =>
      v >= 0 && v < GoalMode.values.length ? GoalMode.values[v] : GoalMode.tasks;

  String get hint => switch (this) {
    GoalMode.tasks => tr('关联若干任务，按已完成 / 总数计算'),
    GoalMode.habits => tr('关联若干习惯，按已完成打卡 / 计划次数计算'),
    GoalMode.focus => tr('从目标创建以来的专注时长累计'),
    GoalMode.manual => tr('自己填当前进度，适合没有数据源的事'),
  };

  IconData get icon => switch (this) {
    GoalMode.tasks => Icons.checklist_rtl,
    GoalMode.habits => Icons.repeat,
    GoalMode.focus => Icons.timer_outlined,
    GoalMode.manual => Icons.tune,
  };
}

/// 一条目标的实时进度。
class GoalProgress {
  GoalProgress({
    required this.goal,
    required this.current,
    required this.target,
    required this.mode,
    this.detail = '',
    this.linked = 0,
  });

  final Goal goal;
  final int current;
  final int target;
  final GoalMode mode;

  /// 一行说明，例如「8 次 / 12 次计划」。
  final String detail;

  /// 关联了多少条任务 / 习惯，用于提示「还没关联」。
  final int linked;

  double get ratio =>
      target <= 0 ? 0 : (current / target).clamp(0.0, 1.0).toDouble();

  bool get achieved => target > 0 && current >= target;

  /// 任务 / 习惯模式还没挂任何对象时，进度条没有意义，直接说「待关联」。
  bool get needsLink =>
      (mode == GoalMode.tasks || mode == GoalMode.habits) && linked == 0;

  String get label {
    if (needsLink) return tr('待关联');
    final unit = mode == GoalMode.manual ? '%' : mode.unit;
    return '$current / $target $unit';
  }
}

class GoalRepository {
  GoalRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Goal>> watchGoals() {
    final query = _db.select(_db.goals)
      ..where((g) => g.deletedAt.isNull() & g.status.equals(0))
      ..orderBy([
        (g) => OrderingTerm(expression: g.sortOrder),
        (g) => OrderingTerm(expression: g.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 按状态取目标：0 进行中 / 1 已完成 / 2 已暂停。
  Stream<List<Goal>> watchByStatus(int status) {
    final query = _db.select(_db.goals)
      ..where((g) => g.deletedAt.isNull() & g.status.equals(status))
      ..orderBy([
        (g) => OrderingTerm(expression: g.sortOrder),
        (g) => OrderingTerm(expression: g.updatedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 三个状态的计数，设置页用来一行说清「目标都去哪了」。
  Future<(int active, int done, int paused)> statusCounts() async {
    final rows = await (_db.select(
      _db.goals,
    )..where((g) => g.deletedAt.isNull())).get();
    var active = 0, done = 0, paused = 0;
    for (final g in rows) {
      switch (g.status) {
        case 1:
          done++;
        case 2:
          paused++;
        default:
          active++;
      }
    }
    return (active, done, paused);
  }

  Stream<List<Goal>> watchArchived() {
    final query = _db.select(_db.goals)
      ..where((g) => g.deletedAt.isNull() & g.status.equals(2))
      ..orderBy([
        (g) => OrderingTerm(expression: g.updatedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  Stream<List<GoalLink>> watchLinks() => _db.select(_db.goalLinks).watch();

  Future<String> create({
    required String title,
    String? note,
    GoalMode mode = GoalMode.tasks,
    int target = 1,
    DateTime? dueAt,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.goals)
        .insert(
          GoalsCompanion.insert(
            id: id,
            title: title,
            note: Value(note),
            mode: Value(mode.index),
            target: Value(target),
            dueAt: Value(dueAt),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateGoal(
    String id, {
    String? title,
    String? note,
    GoalMode? mode,
    int? target,
    int? current,
    DateTime? dueAt,
    bool clearDue = false,
    int? status,
  }) async {
    await (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
      GoalsCompanion(
        title: title == null ? Value.absent() : Value(title),
        note: note == null ? Value.absent() : Value(note),
        mode: mode == null ? Value.absent() : Value(mode.index),
        target: target == null ? Value.absent() : Value(target),
        current: current == null ? Value.absent() : Value(current),
        dueAt: clearDue
            ? Value(null)
            : (dueAt == null ? Value.absent() : Value(dueAt)),
        status: status == null ? Value.absent() : Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setManualCurrent(String id, int current) =>
      updateGoal(id, current: current.clamp(0, 100000));

  Future<void> setStatus(String id, int status) => updateGoal(id, status: status);

  Future<void> archive(String id) => setStatus(id, 2);

  Future<void> remove(String id) async {
    final now = DateTime.now();
    await (_db.delete(_db.goalLinks)..where((l) => l.goalId.equals(id))).go();
    await (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
      GoalsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Future<void> reorder(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (_db.update(_db.goals)..where((g) => g.id.equals(orderedIds[i])))
          .write(GoalsCompanion(sortOrder: Value(i)));
    }
  }

  Future<void> addLink(String goalId, int refType, String refId) async {
    await _db
        .into(_db.goalLinks)
        .insert(
          GoalLinksCompanion.insert(
            goalId: goalId,
            refType: refType,
            refId: refId,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> removeLink(String goalId, int refType, String refId) async {
    await (_db.delete(_db.goalLinks)..where(
          (l) =>
              l.goalId.equals(goalId) &
              l.refType.equals(refType) &
              l.refId.equals(refId),
        ))
        .go();
  }

  /// 一次性算全部目标的进度。
  ///
  /// 之所以集中在仓储里算，是因为「进度」一旦分散到各页面，就会出现
  /// 目标和统计页显示不同数字的老问题。
  Future<List<GoalProgress>> computeAll() async {
    final goals =
        await (_db.select(_db.goals)..where(
              (g) => g.deletedAt.isNull() & g.status.equals(0),
            ))
            .get();
    if (goals.isEmpty) return [];

    final links = await _db.select(_db.goalLinks).get();
    final tasks =
        await (_db.select(_db.tasks)..where((t) => t.deletedAt.isNull())).get();
    final habits =
        await (_db.select(_db.habits)..where((h) => h.deletedAt.isNull())).get();
    final logs =
        await (_db.select(_db.habitLogs)..where((l) => l.deletedAt.isNull()))
            .get();
    final sessions = await _db.select(_db.focusSessions).get();

    final taskById = {for (final t in tasks) t.id: t};
    final habitById = {for (final h in habits) h.id: h};
    final now = habitDateOnly(DateTime.now());

    final result = <GoalProgress>[];
    for (final goal in goals) {
      final mode = GoalMode.fromValue(goal.mode);
      final mine = links.where((l) => l.goalId == goal.id).toList();
      switch (mode) {
        case GoalMode.tasks:
          final linked = mine
              .where((l) => l.refType == 0)
              .map((l) => taskById[l.refId])
              .whereType<Task>()
              .toList();
          final done = linked.where((t) => t.status == 1).length;
          result.add(
            GoalProgress(
              goal: goal,
              mode: mode,
              current: done,
              target: linked.isEmpty ? goal.target : linked.length,
              linked: linked.length,
              detail: linked.isEmpty
                  ? tr('还没关联任务')
                  : trf('已完成 {} / {} 项任务', [done, linked.length]),
            ),
          );
        case GoalMode.habits:
          final linked = mine
              .where((l) => l.refType == 1)
              .map((l) => habitById[l.refId])
              .whereType<Habit>()
              .toList();
          var planned = 0;
          var doneDays = 0;
          for (final habit in linked) {
            final schedule = HabitSchedule.of(habit);
            final habitStart = habit.startDate != null
                ? habitDateOnly(DateTime.parse(habit.startDate!))
                : habitDateOnly(habit.createdAt);
            final from = habitStart.isAfter(habitDateOnly(goal.createdAt))
                ? habitStart
                : habitDateOnly(goal.createdAt);
            if (from.isAfter(now)) continue;
            planned += schedule.plannedBetween(from, now);
            final days = <String>{};
            for (final log in logs) {
              if (log.habitId != habit.id) continue;
              if (log.count < habit.targetCount) continue;
              final day = DateTime.tryParse(log.date);
              if (day == null) continue;
              final d = habitDateOnly(day);
              if (d.isBefore(from) || d.isAfter(now)) continue;
              days.add(log.date);
            }
            doneDays += days.length;
          }
          result.add(
            GoalProgress(
              goal: goal,
              mode: mode,
              current: doneDays,
              target: planned > 0 ? planned : goal.target,
              linked: linked.length,
              detail: linked.isEmpty
                  ? tr('还没关联习惯')
                  : trf('打卡 {} 次 / 计划 {} 次', [doneDays, planned]),
            ),
          );
        case GoalMode.focus:
          var seconds = 0;
          for (final s in sessions) {
            // 用「结束时间」判断：一轮专注可能跨过目标创建的时刻，
            // 只要它是建目标之后结束的，就算这一轮。
            final ended = s.endedAt ?? s.startedAt;
            if (ended.isBefore(goal.createdAt)) continue;
            seconds += s.actualSec ?? 0;
          }
          final minutes = seconds ~/ 60;
          result.add(
            GoalProgress(
              goal: goal,
              mode: mode,
              current: minutes,
              target: goal.target,
              detail: trf('累计专注 {} 分钟', [minutes]),
            ),
          );
        case GoalMode.manual:
          result.add(
            GoalProgress(
              goal: goal,
              mode: mode,
              current: goal.current,
              target: goal.target,
              detail: goal.current >= goal.target ? tr('已完成') : tr('手动记录'),
            ),
          );
      }
    }
    return result;
  }
}

final goalRepositoryProvider = Provider<GoalRepository>(
  (ref) => GoalRepository(ref.watch(databaseProvider)),
);

final goalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchGoals(),
);

final archivedGoalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchByStatus(2),
);

final completedGoalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchByStatus(1),
);

final pausedGoalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(goalRepositoryProvider).watchByStatus(2),
);

/// 设置页用：进行中 / 已完成 / 已暂停的数量。
final goalCountsProvider = FutureProvider<(int, int, int)>((ref) {
  ref.watch(goalsProvider);
  ref.watch(completedGoalsProvider);
  ref.watch(pausedGoalsProvider);
  return ref.watch(goalRepositoryProvider).statusCounts();
});

final goalLinksProvider = StreamProvider<List<GoalLink>>(
  (ref) => ref.watch(goalRepositoryProvider).watchLinks(),
);

/// 目标进度：任务完成、习惯打卡都会让它重算，页面不需要自己拼数据。
final goalProgressProvider = FutureProvider<List<GoalProgress>>((ref) async {
  ref.watch(goalsProvider);
  ref.watch(goalLinksProvider);
  ref.watch(allActiveTasksProvider);
  ref.watch(habitLogsProvider);
  return ref.watch(goalRepositoryProvider).computeAll();
});
