import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../tasks/task_repository.dart';

final _dateFmt = DateFormat('yyyy-MM-dd');

String dayKey(DateTime date) => _dateFmt.format(date);

/// 连续天数：从今天（或昨天）往回数，遇到断档即停。
/// 习惯名在创建时被拼成「🌱 阅读」。
/// 显示、弹窗、再次编辑前都先剥掉前缀，否则每编辑一次就会多一个 emoji。
String habitDisplayName(String name) {
  var rest = name;
  while (true) {
    final m = RegExp(r'^(\S+)\s+').firstMatch(rest);
    if (m == null || m.group(1)!.runes.length > 3) break;
    rest = rest.substring(m.end);
  }
  return rest;
}

/// 取名字里的 emoji 前缀（只取第一个图标；历史数据可能存成了「🌱🌱 阅读」）。
String? habitIconOf(String name) {
  final m = RegExp(r'^(\S+)\s+').firstMatch(name);
  if (m == null) return null;
  final group = m.group(1)!;
  if (group.runes.length > 3) return null;
  final rs = group.runes.toList();
  // 组合 emoji（✍️ / 👨‍💻）保留变体选择符或 ZWJ 后的第二个码位。
  if (rs.length >= 2 && (rs[1] == 0xFE0F || rs[1] == 0x200D)) {
    return String.fromCharCodes(rs.take(2));
  }
  return String.fromCharCode(rs.first);
}

/// 列表/标题里显示的名字：一个图标 + 去掉所有重复前缀后的正文。
String habitDisplayTitle(String name) {
  final icon = habitIconOf(name);
  var rest = name;
  while (true) {
    final m = RegExp(r'^(\S+)\s+').firstMatch(rest);
    if (m == null || m.group(1)!.runes.length > 3) break;
    rest = rest.substring(m.end);
  }
  final text = rest.trim();
  if (icon == null) return name;
  return text.isEmpty ? icon : '$icon $text';
}

int calcStreak(Set<String> days, {DateTime? now}) {
  if (days.isEmpty) return 0;
  final today = now ?? DateTime.now();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(dayKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
    if (!days.contains(dayKey(cursor))) return 0;
  }
  var streak = 0;
  while (days.contains(dayKey(cursor))) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// 最长连续天数：把天数集合按日期排序后扫描，取最长的一段。
int calcLongestStreak(Set<String> days) {
  if (days.isEmpty) return 0;
  final sorted = days.toList()..sort();
  var best = 1;
  var cur = 1;
  for (var i = 1; i < sorted.length; i++) {
    final prev = DateTime.parse(sorted[i - 1]);
    final now = DateTime.parse(sorted[i]);
    if (now.difference(prev).inDays == 1) {
      cur++;
      if (cur > best) best = cur;
    } else {
      cur = 1;
    }
  }
  return best;
}

class HabitRepository {
  HabitRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<Habit>> watchHabits() {
    final query = _db.select(_db.habits)
      ..where((h) => h.deletedAt.isNull() & h.archived.equals(false))
      ..orderBy([(h) => OrderingTerm(expression: h.sortOrder)]);
    return query.watch();
  }

  Stream<List<HabitLog>> watchRecentLogs() {
    final since = dayKey(DateTime.now().subtract(const Duration(days: 400)));
    final query = _db.select(_db.habitLogs)
      ..where((l) => l.deletedAt.isNull() & l.date.isBiggerOrEqualValue(since));
    return query.watch();
  }

  Future<String> create(
    String name, {
    int targetCount = 1,
    String freqType = 'daily',
    String? remindTime,
    bool promptJournal = true,
    DateTime? startDate,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.habits)
        .insert(
          HabitsCompanion.insert(
            id: id,
            name: name.trim(),
            targetCount: Value(targetCount),
            freqConfig: Value(freqType),
            remindTime: Value(remindTime),
            promptJournal: Value(promptJournal),
            startDate: Value(dayKey(startDate ?? now)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateHabit(
    String id, {
    String? name,
    int? targetCount,
    String? freqType,
    String? remindTime,
    bool clearRemind = false,
    bool? promptJournal,
  }) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        name: name == null ? const Value.absent() : Value(name.trim()),
        targetCount: targetCount == null
            ? const Value.absent()
            : Value(targetCount),
        freqConfig: freqType == null ? const Value.absent() : Value(freqType),
        remindTime: clearRemind
            ? const Value(null)
            : (remindTime == null ? const Value.absent() : Value(remindTime)),
        promptJournal: promptJournal == null
            ? const Value.absent()
            : Value(promptJournal),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 归档习惯：不删记录，只是从列表移出（保留历史）。
  Future<void> archiveHabit(String id) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        archived: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 删除习惯：连带全部打卡记录。
  /// 不可恢复，调用前必须走 confirmDanger 二次确认。
  Future<void> deleteHabit(String id) async {
    await (_db.delete(_db.habitLogs)..where((l) => l.habitId.equals(id))).go();
    await (_db.delete(_db.habits)..where((h) => h.id.equals(id))).go();
  }

  Stream<List<HabitLog>> watchLogsOf(String habitId) {
    final query = _db.select(_db.habitLogs)
      ..where((l) => l.habitId.equals(habitId) & l.deletedAt.isNull())
      ..orderBy([
        (l) => OrderingTerm(expression: l.date, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 今天已打卡则取消，否则补一次。
  Future<bool> toggleToday(String habitId) async {
    final today = dayKey(DateTime.now());
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) =>
                  l.habitId.equals(habitId) &
                  l.date.equals(today) &
                  l.deletedAt.isNull(),
            ))
            .getSingleOrNull();

    if (existing != null) {
      await (_db.delete(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).go();
      return false;
    }
    await _db
        .into(_db.habitLogs)
        .insert(
          HabitLogsCompanion.insert(
            id: _uuid.v7(),
            habitId: habitId,
            date: today,
            createdAt: DateTime.now(),
          ),
        );
    return true;
  }

  /// 打卡（带心得）。同一天已经打过时，按次累加（喝水 8 杯这类习惯），
  /// 只有单次习惯才把重复点击当作「更新心得」。
  Future<int> checkIn(String habitId, {String? note, DateTime? day}) async {
    final key = dayKey(day ?? DateTime.now());
    final habit = await (_db.select(
      _db.habits,
    )..where((h) => h.id.equals(habitId))).getSingleOrNull();
    final target = habit?.targetCount ?? 1;

    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) =>
                  l.habitId.equals(habitId) &
                  l.date.equals(key) &
                  l.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) {
      final next = existing.count + 1;
      await (_db.update(
        _db.habitLogs,
      )..where((l) => l.id.equals(existing.id))).write(
        HabitLogsCompanion(
          count: Value(target > 1 ? next : existing.count),
          note: note == null ? const Value.absent() : Value(note),
          deletedAt: const Value(null),
        ),
      );
      return target > 1 ? next : existing.count;
    }
    await _db
        .into(_db.habitLogs)
        .insert(
          HabitLogsCompanion.insert(
            id: _uuid.v7(),
            habitId: habitId,
            date: key,
            count: const Value(1),
            note: Value(note),
            createdAt: DateTime.now(),
          ),
        );
    return 1;
  }

  /// 撤销一次：多次习惯减 1，减到 0 才删记录。
  Future<void> undo(String habitId, {DateTime? day}) async {
    final key = dayKey(day ?? DateTime.now());
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) =>
                  l.habitId.equals(habitId) &
                  l.date.equals(key) &
                  l.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing == null) return;
    if (existing.count > 1) {
      await (_db.update(_db.habitLogs)..where((l) => l.id.equals(existing.id)))
          .write(HabitLogsCompanion(count: Value(existing.count - 1)));
      return;
    }
    await (_db.delete(
      _db.habitLogs,
    )..where((l) => l.id.equals(existing.id))).go();
  }

  /// 补写 / 修改当天这条打卡的心得。
  ///
  /// 打卡之后再点圆圈，语义是「给这次打卡补一句话」，不是撤销——
  /// 之前这里走成撤销确认，是入口写错了（见 1.0.1 修复）。
  Future<void> setTodayNote(String habitId, String? note, {DateTime? day}) async {
    final key = dayKey(day ?? DateTime.now());
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) =>
                  l.habitId.equals(habitId) &
                  l.date.equals(key) &
                  l.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing == null) return;
    await (_db.update(_db.habitLogs)..where((l) => l.id.equals(existing.id)))
        .write(
          HabitLogsCompanion(
            note: Value(note == null || note.isEmpty ? null : note),
          ),
        );
  }

  /// 跳过今天：写一条 count=0 的记录，streak 计算时视为「已处理但不计分」。
  Future<void> skipToday(String habitId) async {
    final key = dayKey(DateTime.now());
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) =>
                  l.habitId.equals(habitId) &
                  l.date.equals(key) &
                  l.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) {
      await (_db.update(_db.habitLogs)..where((l) => l.id.equals(existing.id)))
          .write(const HabitLogsCompanion(count: Value(0)));
      return;
    }
    await _db
        .into(_db.habitLogs)
        .insert(
          HabitLogsCompanion.insert(
            id: _uuid.v7(),
            habitId: habitId,
            date: key,
            count: const Value(0),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// 习惯排序：把手常驻，松手即写 sortOrder。
  Future<void> reorderHabits(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (_db.update(_db.habits)..where((h) => h.id.equals(orderedIds[i])))
          .write(HabitsCompanion(sortOrder: Value(i * 10)));
    }
  }

  /// 长按补卡：给指定日期补一条。
  Future<void> backfill(String habitId, DateTime day) async {
    final key = dayKey(day);
    final existing =
        await (_db.select(_db.habitLogs)..where(
              (l) =>
                  l.habitId.equals(habitId) &
                  l.date.equals(key) &
                  l.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return;
    await _db
        .into(_db.habitLogs)
        .insert(
          HabitLogsCompanion.insert(
            id: _uuid.v7(),
            habitId: habitId,
            date: key,
            createdAt: DateTime.now(),
          ),
        );
  }
}

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => HabitRepository(ref.watch(databaseProvider)),
);

final habitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchHabits(),
);

final habitLogsProvider = StreamProvider<List<HabitLog>>(
  (ref) => ref.watch(habitRepositoryProvider).watchRecentLogs(),
);
