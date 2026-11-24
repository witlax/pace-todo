import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../tasks/task_repository.dart' show databaseProvider;

/// 心情的归属日（本地日），与打卡用同一套日期语义。
String moodDayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final moodRepositoryProvider = Provider<MoodRepository>(
  (ref) => MoodRepository(ref.watch(databaseProvider)),
);

/// 全部心情记录（含历史），页面自行按月/按区间取用。
final moodEntriesProvider = StreamProvider<List<MoodEntry>>(
  (ref) => ref.watch(moodRepositoryProvider).watchAll(),
);

class MoodRepository {
  MoodRepository(this._db);

  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<MoodEntry>> watchAll() {
    final q = _db.select(_db.moodEntries)
      ..where((m) => m.deletedAt.isNull())
      ..orderBy([(m) => OrderingTerm(expression: m.date)]);
    return q.watch();
  }

  Future<MoodEntry?> byDate(DateTime day) {
    return (_db.select(_db.moodEntries)
          ..where((m) => m.date.equals(moodDayKey(day)) & m.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// 一天一条：有则改，无则建。
  Future<void> save({
    required DateTime day,
    required int mood,
    String? note,
  }) async {
    final key = moodDayKey(day);
    final now = DateTime.now();
    final existing =
        await (_db.select(_db.moodEntries)
              ..where((m) => m.date.equals(key) & m.deletedAt.isNull()))
            .getSingleOrNull();

    if (existing != null) {
      await (_db.update(
        _db.moodEntries,
      )..where((m) => m.id.equals(existing.id))).write(
        MoodEntriesCompanion(
          mood: Value(mood),
          note: Value(note),
          updatedAt: Value(now),
        ),
      );
      return;
    }
    await _db
        .into(_db.moodEntries)
        .insert(
          MoodEntriesCompanion.insert(
            id: _uuid.v7(),
            date: key,
            mood: mood,
            note: Value(note),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 清掉某天的心情（软删），用于「今天不记了」。
  Future<void> remove(DateTime day) async {
    await (_db.update(_db.moodEntries)
          ..where((m) => m.date.equals(moodDayKey(day)) & m.deletedAt.isNull()))
        .write(MoodEntriesCompanion(deletedAt: Value(DateTime.now())));
  }
}
