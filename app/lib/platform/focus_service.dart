import 'dart:io';

import 'package:flutter/services.dart';

/// Android 前台服务：专注期间保活并在通知栏显示剩余时间。
/// 其他平台直接跳过；权限被拒时静默失败，不影响应用内计时。
class FocusForegroundService {
  static const _channel = MethodChannel('com.witlax.tasktodo/focus');

  static Future<void> start({
    required String title,
    required DateTime endAt,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start', {
        'title': title,
        'endAt': endAt.millisecondsSinceEpoch,
      });
    } on PlatformException {
      // 通知权限被拒或系统限制：计时继续，只是没有常驻通知。
    } on MissingPluginException {
      // 桌面端或未注册插件。
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }
}
