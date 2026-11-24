import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/focus/focus_repository.dart';
import 'package:tasks/features/goals/goal_repository.dart';
import 'package:tasks/features/habits/habit_repository.dart';
import 'package:tasks/features/settings/settings.dart';
import 'package:tasks/features/tasks/task_repository.dart';

Future<(ProviderContainer, AppDatabase)> _bootstrap() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ],
  );
  return (container, db);
}

void main() {
  group('目标进度', () {
    test('任务模式：按已完成 / 关联总数计算', () async {
      final (container, _) = await _bootstrap();
      final tasks = container.read(taskRepositoryProvider);
      final goals = container.read(goalRepositoryProvider);

      final a = await tasks.create(title: '写提纲');
      final b = await tasks.create(title: '写正文');
      final goalId = await goals.create(title: '写完一篇文章', mode: GoalMode.tasks);
      await goals.addLink(goalId, 0, a);
      await goals.addLink(goalId, 0, b);
      await tasks.setDone(a, true);

      var all = await goals.computeAll();
      expect(all, hasLength(1));
      expect(all.first.current, 1);
      expect(all.first.target, 2);
      expect(all.first.ratio, 0.5);
      expect(all.first.achieved, isFalse);

      await tasks.setDone(b, true);
      all = await goals.computeAll();
      expect(all.first.current, 2);
      expect(all.first.achieved, isTrue);
    });

    test('习惯模式：分母是计划次数，非计划日不拉低进度', () async {
      final (container, _) = await _bootstrap();
      final habits = container.read(habitRepositoryProvider);
      final goals = container.read(goalRepositoryProvider);

      final habitId = await habits.create('喝水', targetCount: 1);
      final goalId = await goals.create(title: '坚持喝水', mode: GoalMode.habits);
      await goals.addLink(goalId, 1, habitId);
      await habits.checkIn(habitId);

      final all = await goals.computeAll();
      final p = all.first;
      // 习惯是今天创建的，计划 1 次，今天打了 1 次。
      expect(p.current, 1);
      expect(p.target, greaterThanOrEqualTo(1));
      expect(p.mode, GoalMode.habits);
    });

    test('专注模式：累计分钟数与目标分钟数', () async {
      final (container, _) = await _bootstrap();
      final focus = container.read(focusRepositoryProvider);
      final goals = container.read(goalRepositoryProvider);

      // 进度从目标创建那一刻开始累计，所以先建目标再记专注。
      final goalId = await goals.create(
        title: '本周专注 10 小时',
        mode: GoalMode.focus,
        target: 600,
      );
      await focus.saveSession(plannedSec: 1500, actualSec: 1500);
      await focus.saveSession(plannedSec: 1500, actualSec: 1500);

      final all = await goals.computeAll();
      final p = all.firstWhere((e) => e.goal.id == goalId);
      expect(p.current, 50);
      expect(p.target, 600);
    });

    test('手动模式：拖进度条直接写 current', () async {
      final (container, _) = await _bootstrap();
      final goals = container.read(goalRepositoryProvider);
      final id = await goals.create(
        title: '把书读完',
        mode: GoalMode.manual,
        target: 100,
      );
      await goals.setManualCurrent(id, 42);

      final all = await goals.computeAll();
      expect(all.first.current, 42);
      expect(all.first.label, '42 / 100 %');
    });

    test('归档后从进行中列表消失，但仍可恢复', () async {
      final (container, _) = await _bootstrap();
      final goals = container.read(goalRepositoryProvider);
      final id = await goals.create(title: '阶段性目标');
      await goals.archive(id);

      expect(await goals.computeAll(), isEmpty);
      final archived = await goals.watchArchived().first;
      expect(archived.map((g) => g.id), contains(id));
      await goals.setStatus(id, 0);
      expect(await goals.computeAll(), hasLength(1));
    });

    test('删除目标不会动任务本身', () async {
      final (container, db) = await _bootstrap();
      final tasks = container.read(taskRepositoryProvider);
      final goals = container.read(goalRepositoryProvider);
      final taskId = await tasks.create(title: '保留我');
      final goalId = await goals.create(title: '临时目标');
      await goals.addLink(goalId, 0, taskId);

      await goals.remove(goalId);
      final row = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(taskId))).getSingleOrNull();
      expect(row, isNotNull);
      expect(await goals.computeAll(), isEmpty);
      final links = await db.select(db.goalLinks).get();
      expect(links, isEmpty);
    });
  });

  group('智能清单显示策略', () {
    test('默认：今天常显，另外两个有内容才显示', () async {
      final (container, _) = await _bootstrap();
      final settings = container.read(settingsProvider.notifier);

      expect(
        container.read(settingsProvider).visibilityOf(SmartListKind.today),
        SmartVisibility.always,
      );
      expect(
        container.read(settingsProvider).visibilityOf(SmartListKind.week),
        SmartVisibility.auto,
      );
      settings.setSmartVisibility(
        SmartListKind.overdue,
        SmartVisibility.hidden,
      );
      expect(
        container.read(settingsProvider).visibilityOf(SmartListKind.overdue),
        SmartVisibility.hidden,
      );
    });
  });
}
