import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../tasks/task_repository.dart';

class FocusRepository {
  FocusRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<void> saveSession({
    String? taskId,
    required int plannedSec,
    required int actualSec,
    int mode = 0,
  }) async {
    final now = DateTime.now();
    final start = now.subtract(Duration(seconds: actualSec));
    await _db
        .into(_db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: _uuid.v7(),
            taskId: Value(taskId),
            mode: Value(mode),
            startedAt: start,
            endedAt: Value(now),
            plannedSec: Value(plannedSec),
            actualSec: Value(actualSec),
            createdAt: now,
          ),
        );
    if (taskId != null && actualSec >= 60) {
      final task = await (_db.select(
        _db.tasks,
      )..where((t) => t.id.equals(taskId))).getSingleOrNull();
      if (task != null) {
        await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
          TasksCompanion(
            spentMin: Value(task.spentMin + (actualSec ~/ 60)),
            updatedAt: Value(now),
          ),
        );
      }
    }
  }

  /// 修正最近一轮的时长：`deltaSec` 为补记（可为负），`absoluteSec` 为直接覆盖。
  /// 关联任务的累计分钟同步差额，避免「专注改了、任务还是旧数」。
  Future<int?> adjustLatest({int deltaSec = 0, int? absoluteSec}) async {
    final row =
        await (_db.select(_db.focusSessions)
              ..orderBy([
                (f) => OrderingTerm(
                  expression: f.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    final old = row.actualSec ?? 0;
    final next = (absoluteSec ?? old + deltaSec).clamp(0, 12 * 3600);
    if (next == old) return next;

    await (_db.update(
      _db.focusSessions,
    )..where((f) => f.id.equals(row.id))).write(
      FocusSessionsCompanion(
        actualSec: Value(next),
        endedAt: Value(row.startedAt.add(Duration(seconds: next))),
      ),
    );

    final taskId = row.taskId;
    if (taskId != null) {
      final task = await (_db.select(
        _db.tasks,
      )..where((t) => t.id.equals(taskId))).getSingleOrNull();
      if (task != null) {
        final diffMin = (next - old) ~/ 60;
        await (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(
          TasksCompanion(
            spentMin: Value((task.spentMin + diffMin).clamp(0, 999999)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    }
    return next;
  }

  /// 指定时间之后的专注记录，用于周分布与单日回顾。
  Stream<List<FocusSession>> watchSince(DateTime since) {
    final query = _db.select(_db.focusSessions)
      ..where((f) => f.startedAt.isBiggerOrEqualValue(since))
      ..orderBy([(f) => OrderingTerm(expression: f.startedAt)]);
    return query.watch();
  }

  /// 今日专注总时长（分钟）。
  Stream<int> watchTodayMinutes() {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final query = _db.selectOnly(_db.focusSessions)
      ..addColumns([_db.focusSessions.actualSec.sum()])
      ..where(_db.focusSessions.startedAt.isBiggerOrEqualValue(dayStart));
    return query.watchSingle().map((row) {
      final seconds = row.read(_db.focusSessions.actualSec.sum()) ?? 0;
      return seconds ~/ 60;
    });
  }
}

final focusRepositoryProvider = Provider<FocusRepository>(
  (ref) => FocusRepository(ref.watch(databaseProvider)),
);

final focusTodayMinutesProvider = StreamProvider<int>(
  (ref) => ref.watch(focusRepositoryProvider).watchTodayMinutes(),
);

/// 本周专注记录（周一 00:00 起）。
final focusThisWeekProvider = StreamProvider<List<FocusSession>>((ref) {
  final now = DateTime.now();
  final monday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: (now.weekday + 6) % 7));
  return ref.watch(focusRepositoryProvider).watchSince(monday);
});
