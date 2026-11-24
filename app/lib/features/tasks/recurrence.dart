import 'package:rrule/rrule.dart';
import '../../core/i18n/i18n.dart';

/// 重复规则。只存一条 RRULE 字符串，展示与展开都经这里，避免各处各写一套。
class RecurrenceService {
  const RecurrenceService._();

  /// 界面上的预设。值为标准 RRULE，可直接落库。
  static Map<String, String> get presets => {
    tr('每天'): 'RRULE:FREQ=DAILY;INTERVAL=1',
    tr('工作日'): 'RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
    tr('每周'): 'RRULE:FREQ=WEEKLY;INTERVAL=1',
    tr('每两周'): 'RRULE:FREQ=WEEKLY;INTERVAL=2',
    tr('每月'): 'RRULE:FREQ=MONTHLY;INTERVAL=1',
    tr('每年'): 'RRULE:FREQ=YEARLY;INTERVAL=1',
  };

  /// 规则的中文名。命中预设返回预设名，否则回「自定义」。
  static String labelOf(String? rule) {
    if (rule == null || rule.isEmpty) return tr('不重复');
    for (final e in presets.entries) {
      if (e.value == rule) return e.key;
    }
    return tr('自定义');
  }

  /// 严格晚于 [from] 的下一次发生时间。解析失败或已到末尾返回 null。
  ///
  /// 用当前到期时间作为序列起点，语义是「这条任务自己往后推一步」，
  /// 而不是按创建时间推算——补做历史任务时才不会一次生成一串。
  static DateTime? nextAfter(String rule, DateTime from) {
    try {
      final normalized = rule.startsWith('RRULE:') ? rule : 'RRULE:$rule';
      final parsed = RecurrenceRule.fromString(normalized);
      // rrule 只接受 UTC（isValidRruleDateTime == isUtc），进出各转一次。
      final utc = from.toUtc();
      final it = parsed.getInstances(start: utc, after: utc);
      return it.isEmpty ? null : it.first.toLocal();
    } catch (_) {
      return null;
    }
  }

  /// 生成「接下来 30 天内」的发生时间，用于日历预览。最多 [limit] 条。
  static List<DateTime> upcoming(
    String rule,
    DateTime from, {
    int days = 30,
    int limit = 20,
  }) {
    try {
      final normalized = rule.startsWith('RRULE:') ? rule : 'RRULE:$rule';
      final parsed = RecurrenceRule.fromString(normalized);
      final utc = from.toUtc();
      return parsed
          .getInstances(
            start: utc,
            after: utc,
            before: utc.add(Duration(days: days)),
          )
          .take(limit)
          .map((e) => e.toLocal())
          .toList();
    } catch (_) {
      return [];
    }
  }
}
