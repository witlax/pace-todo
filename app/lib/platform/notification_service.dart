import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/log/app_log.dart';
import '../core/i18n/i18n.dart';

/// 提醒调度。Android 走 AlarmManager（精确→降级），通知点击回到任务详情。
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// 由 app 层注入：点击通知时打开对应任务。
  static void Function(String taskId)? onOpenTask;

  /// 通知上的动作：`complete` 完成 / `snooze` 稍后 10 分钟。
  /// 动作按钮被点后 Android 会把应用拉到前台，所以回调里能直接写库；
  /// 若某些 ROM 不给这个能力，用户点通知进应用仍可正常操作（见 docs/11）。
  static void Function(String action, String taskId)? onTaskAction;

  /// 习惯提醒的动作：`done` 打卡 / `skip` 跳过今天。
  static void Function(String action, String habitId)? onHabitAction;

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      // 取不到系统时区时退化为东八区，避免整体失败
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      debugPrint(trf('时区获取失败，回退 Asia/Shanghai: {}', [e]));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) {
        handlePayload(response.payload ?? '', response.actionId ?? '');
      },
    );
    _ready = true;
  }

  /// 通知点击与动作的统一入口：热启动由 `initialize` 回调，
  /// 冷启动由 `launchPayload()` + 首帧后手动调用。
  static void handlePayload(String payload, String action) {
    if (payload.isEmpty) return;
    if (payload.startsWith('habit:')) {
      final id = payload.substring(6);
      if (action.isEmpty) {
        onOpenTask?.call('HABIT_OPEN:$id');
      } else {
        onHabitAction?.call(action, id);
      }
      return;
    }
    final taskId = payload.startsWith('task:') ? payload.substring(5) : payload;
    if (action.isEmpty) {
      onOpenTask?.call(taskId);
    } else {
      onTaskAction?.call(action, taskId);
    }
  }

  /// 应用是被通知「冷启动」时，取回那条通知的 payload。
  static Future<String?> launchPayload() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details?.notificationResponse?.payload;
    } catch (_) {
      return null;
    }
  }

  /// Android 13+ 通知权限。首启只申请这一项，避免跳到系统设置页。
  static Future<bool> requestNotificationPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? true;
  }

  /// 精确闹钟权限：会跳系统页面，只在设置里按需触发。
  static Future<void> requestExactAlarmPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    try {
      await android?.requestExactAlarmsPermission();
    } catch (_) {
      // 部分 ROM 不支持该入口，忽略：调度时自动降级为非精确
    }
  }

  static int _idFor(String taskId) => taskId.hashCode & 0x7fffffff;

  static Future<void> scheduleTask({
    required String id,
    required String title,
    required DateTime dueAt,
  }) async {
    if (!_ready) return;
    final now = DateTime.now();
    if (!dueAt.isAfter(now)) {
      await cancel(id);
      AppLog.i(tr('到期时间已过，不排提醒'));
      return;
    }

    final when = tz.TZDateTime.from(dueAt, tz.local);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'task_reminders',
        tr('任务提醒'),
        channelDescription: tr('任务到期提醒'),
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        actions: [
          AndroidNotificationAction('complete', tr('完成')),
          AndroidNotificationAction('snooze', tr('稍后 10 分钟')),
        ],
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id: _idFor(id),
        title: title,
        body: tr('到时间了'),
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'task:$id',
      );
    } catch (e) {
      // 精确闹钟被拒时降级为非精确，仍保证能提醒
      AppLog.w(trf('精确提醒失败，降级为非精确：{}', [e]));
      await _plugin.zonedSchedule(
        id: _idFor(id),
        title: title,
        body: tr('到时间了'),
        scheduledDate: when,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: 'task:$id',
      );
      AppLog.i(trf('已排提醒 {}:{}', [when.hour, when.minute.toString().padLeft(2, '0')]));
    }
  }

  static Future<void> cancel(String taskId) async {
    if (!_ready) return;
    await _plugin.cancel(id: _idFor(taskId));
    AppLog.i(tr('已取消提醒'));
  }

  /// 专注结束提醒：前台服务通知只负责「还剩多久」，
  /// 这一个是「已经结束」，需要清掉常驻通知后单独弹一条。
  static Future<void> showFocusDone({
    required String title,
    required int minutes,
  }) async {
    if (!_ready) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'focus_done',
        tr('专注结束'),
        channelDescription: tr('专注倒计时结束时提醒'),
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        playSound: true,
        enableVibration: true,
      ),
    );
    await _plugin.show(
      id: 4202,
      title: trf('专注结束 · {} 分钟', [minutes]),
      body: title.isEmpty ? tr('点开看看这一轮的记录') : trf('「{}」这一轮完成', [title]),
      notificationDetails: details,
    );
    AppLog.i(tr('已发送专注结束提醒'));
  }

  /// 微休息：专注满 50 分钟提示起身，不打断本轮计时。
  static Future<void> showMicroBreak({required int minutes}) async {
    if (!_ready) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'focus_break',
        tr('微休息提醒'),
        channelDescription: tr('连续专注较久时提示起身活动'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    await _plugin.show(
      id: 4203,
      title: trf('已经专注 {} 分钟', [minutes]),
      body: tr('起身走两步、看看远处。计时不会中断。'),
      notificationDetails: details,
    );
    AppLog.i(tr('已发送微休息提醒'));
  }

  /// 习惯每日提醒：每个习惯一个固定 id，改时间时先取消再排。
  static Future<void> scheduleHabit({
    required String habitId,
    required String name,
    required String hhmm,
  }) async {
    if (!_ready) return;
    final parts = hhmm.split(':');
    if (parts.length != 2) return;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return;

    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(Duration(days: 1));
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'habit_reminders',
        tr('习惯提醒'),
        channelDescription: tr('每天固定时间提醒打卡'),
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.reminder,
        actions: [
          AndroidNotificationAction('done', tr('打卡')),
          AndroidNotificationAction('skip', tr('跳过今天')),
        ],
      ),
    );
    try {
      await _plugin.zonedSchedule(
        id: _habitIdFor(habitId),
        title: name,
        body: tr('今天的打卡还没记，花 3 秒点一下'),
        scheduledDate: tz.TZDateTime.from(next, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'habit:$habitId',
      );
      AppLog.i(trf('已排习惯提醒 {} @ {}', [name, hhmm]));
    } catch (e) {
      AppLog.w(trf('习惯提醒排程失败：{}', [e]));
    }
  }

  static Future<void> cancelHabit(String habitId) async {
    if (!_ready) return;
    await _plugin.cancel(id: _habitIdFor(habitId));
  }

  static int _habitIdFor(String habitId) =>
      0x40000000 | (habitId.hashCode & 0x0fffffff);
}
