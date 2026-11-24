import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 应用内日志。
///
/// 只记事件，不记任务标题与备注内容——日志是排障用的，不该成为隐私泄漏点。
/// 内存环形缓冲 2000 条，足够定位「刚才那次提醒为什么没响」。
class AppLog {
  AppLog._();

  static const _max = 2000;
  static final ListQueue<LogEntry> _buffer = ListQueue<LogEntry>();

  /// 供界面监听的版本号，每次写入自增。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<LogEntry> get entries => List.unmodifiable(_buffer);

  static void i(String message) => _add('INFO', message);
  static void w(String message) => _add('WARN', message);
  static void e(String message) => _add('ERROR', message);

  static void _add(String level, String message) {
    _buffer.addLast(LogEntry(DateTime.now(), level, message));
    while (_buffer.length > _max) {
      _buffer.removeFirst();
    }
    revision.value++;
    debugPrint('[${level[0]}] $message');
  }

  static void clear() {
    _buffer.clear();
    revision.value++;
  }

  static String export() => _buffer
      .map((e) => '${e.at.toIso8601String()} ${e.level} ${e.message}')
      .join('\n');
}

class LogEntry {
  const LogEntry(this.at, this.level, this.message);

  final DateTime at;
  final String level;
  final String message;
}
