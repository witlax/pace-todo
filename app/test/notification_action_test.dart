import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/habits/habit_repository.dart';
import 'package:tasks/features/tasks/task_repository.dart';
import 'package:tasks/platform/notification_service.dart';

/// 通知动作的「两头」都测：
/// 1. payload + actionId 的解析（task:/habit: 前缀、动作分派）；
/// 2. 动作落到仓储后的结果（完成、稍后、打卡、跳过）。
///
/// 中间那段（SystemUI 把点击交给 PendingIntent）属于系统行为，
/// 只能在真机上验证，见 docs/11 §6.6。
void main() {
  late AppDatabase db;
  late TaskRepository tasks;
  late HabitRepository habits;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tasks = TaskRepository(db);
    habits = HabitRepository(db);
  });

  tearDown(() async {
    NotificationService.onTaskAction = null;
    NotificationService.onHabitAction = null;
    NotificationService.onOpenTask = null;
    await db.close();
  });

  group('payload 解析', () {
    test('task: 前缀 + complete 动作', () {
      String? gotAction;
      String? gotId;
      NotificationService.onTaskAction = (a, i) {
        gotAction = a;
        gotId = i;
      };
      NotificationService.handlePayload('task:abc', 'complete');
      expect(gotAction, 'complete');
      expect(gotId, 'abc');
    });

    test('旧格式（无前缀）的 payload 仍能打开任务', () {
      String? opened;
      NotificationService.onOpenTask = (id) => opened = id;
      NotificationService.handlePayload('legacy-id', '');
      expect(opened, 'legacy-id');
    });

    test('habit: 前缀点击正文走习惯入口，动作走 onHabitAction', () {
      String? opened;
      String? action;
      String? id;
      NotificationService.onOpenTask = (v) => opened = v;
      NotificationService.onHabitAction = (a, i) {
        action = a;
        id = i;
      };

      NotificationService.handlePayload('habit:h1', '');
      expect(opened, 'HABIT_OPEN:h1');

      NotificationService.handlePayload('habit:h1', 'skip');
      expect(action, 'skip');
      expect(id, 'h1');
    });

    test('空 payload 不触发任何回调', () {
      var called = false;
      NotificationService.onTaskAction = (_, _) => called = true;
      NotificationService.onOpenTask = (_) => called = true;
      NotificationService.handlePayload('', 'complete');
      expect(called, isFalse);
    });
  });

  group('动作落库', () {
    test('完成动作：任务变已完成', () async {
      final id = await tasks.create(title: '到期任务');
      await tasks.setDone(id, true);
      final task = await tasks.findById(id);
      expect(task!.status, 1);
      expect(task.completedAt, isNotNull);
    });

    test('稍后动作：只挪提醒时间，不改到期日', () async {
      final due = DateTime.now().add(const Duration(hours: 3));
      final id = await tasks.create(title: '稍后提醒我', dueAt: due);
      final snoozeTo = DateTime.now().add(const Duration(minutes: 10));
      await tasks.setRemindAt(id, snoozeTo);

      final task = await tasks.findById(id);
      expect(task!.dueAt!.hour, due.hour);
      expect(task.remindAt!.difference(snoozeTo).inSeconds.abs(), lessThan(2));
    });

    test('习惯「打卡」动作累加次数并达到目标', () async {
      final id = await habits.create('喝水', targetCount: 2);
      await habits.checkIn(id);
      await habits.checkIn(id);
      final logs = await habits.watchLogsOf(id).first;
      expect(logs.single.count, 2);
    });

    test('习惯「跳过今天」写入 0 次记录，不算断签也不算完成', () async {
      final id = await habits.create('跑步');
      await habits.skipToday(id);
      final logs = await habits.watchLogsOf(id).first;
      expect(logs.single.count, 0);
    });
  });
}
