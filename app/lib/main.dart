import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'features/habits/habit_page.dart';
import 'features/habits/habit_repository.dart';
import 'features/settings/settings.dart';
import 'features/tasks/task_detail_page.dart';
import 'features/tasks/task_repository.dart';
import 'platform/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  final prefs = await SharedPreferences.getInstance();
  await NotificationService.init();

  // 用一个显式容器，让通知动作（完成 / 稍后 / 打卡）能在没有 Widget 的地方写库。
  final container = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs)],
  );

  NotificationService.onOpenTask = (taskId) {
    // 习惯提醒没有「详情页路由」，直接进习惯页即可。
    if (taskId.startsWith('HABIT_OPEN:')) {
      navigatorKey.currentState?.push(
        MaterialPageRoute<void>(builder: (_) => const HabitPage()),
      );
      return;
    }
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => TaskDetailPage(taskId: taskId)),
    );
  };

  NotificationService.onTaskAction = (action, taskId) async {
    final repo = container.read(taskRepositoryProvider);
    switch (action) {
      case 'complete':
        await repo.setDone(taskId, true);
      case 'snooze':
        // 稍后 10 分钟：只改提醒时间，不动任务本身的到期日。
        await repo.setRemindAt(
          taskId,
          DateTime.now().add(const Duration(minutes: 10)),
        );
    }
  };

  NotificationService.onHabitAction = (action, habitId) async {
    final repo = container.read(habitRepositoryProvider);
    if (action == 'done') {
      await repo.checkIn(habitId);
    } else if (action == 'skip') {
      await repo.skipToday(habitId);
    }
  };

  runApp(
    UncontrolledProviderScope(container: container, child: const TasksApp()),
  );

  // 首启只申请通知权限；精确闹钟在设置里按需开启。
  await NotificationService.requestNotificationPermission();

  // 冷启动：用户是从通知（或通知上的按钮）进来的，等首帧后再处理。
  final launchPayload = await NotificationService.launchPayload();
  if (launchPayload != null && launchPayload.isNotEmpty) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        NotificationService.handlePayload(launchPayload, '');
      }),
    );
  }
}
