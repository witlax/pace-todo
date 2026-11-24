import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../log/app_log.dart';
import 'tables.dart';
import '../i18n/i18n.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Lists,
    Tasks,
    Tags,
    TaskTags,
    Notes,
    NoteAssets,
    TaskNoteLinks,
    Habits,
    HabitLogs,
    FocusSessions,
    MoodEntries,
    Goals,
    GoalLinks,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 测试用：传入内存执行器。
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedInbox();
      AppLog.i(tr('数据库初始化完成（schema v6）'));
    },
    onUpgrade: (m, from, to) async {
      // v2：完成总结、独立提醒时间、归档时间
      if (from < 2) {
        await m.addColumn(tasks, tasks.completedSummary);
        await m.addColumn(tasks, tasks.remindAt);
        await m.addColumn(tasks, tasks.archivedAt);
      }
      // v3：备忘录标签（逗号分隔文本）
      if (from < 3) {
        await m.addColumn(notes, notes.tags);
      }
      // v4：习惯提醒时间、打卡心得开关、开始日期
      if (from < 4) {
        await m.addColumn(habits, habits.remindTime);
        await m.addColumn(habits, habits.promptJournal);
        await m.addColumn(habits, habits.startDate);
      }
      // v5：每日心情（一天一条）
      if (from < 5) {
        await m.createTable(moodEntries);
      }
      // v6：目标与目标关联（任务/习惯）
      if (from < 6) {
        await m.createTable(goals);
        await m.createTable(goalLinks);
      }
      AppLog.i(trf('数据库迁移完成：v{} → v{}', [from, to]));
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _seedInbox() async {
    final now = DateTime.now();
    await into(lists).insert(
      ListsCompanion.insert(
        id: 'inbox',
        name: tr('收件箱'),
        isInbox: Value(true),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  static QueryExecutor _openConnection() => driftDatabase(name: 'tasks');
}
