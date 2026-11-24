import '../../core/i18n/i18n.dart';

/// 一句话录入的解析结果。
class QuickParse {
  const QuickParse({
    required this.title,
    this.dueAt,
    this.importance,
    this.tags = const [],
    this.labels = const [],
  });

  /// 去掉已识别片段后的标题。
  final String title;

  /// 识别出的日期时间；只有日期时默认 18:00。
  final DateTime? dueAt;

  /// 0 无 / 1 低 / 2 中 / 3 高；未写则为 null。
  final int? importance;

  /// `#标签` 识别结果。
  final List<String> tags;

  /// 给界面展示的识别项（日期 / 重要性 / 标签）。
  final List<String> labels;

  bool get isEmpty => dueAt == null && importance == null && tags.isEmpty;
}

/// 规则解析，不接模型：可预测、离线、错了也能改。
///
/// 支持：
/// - 日期：今天/明天/后天/大后天、周三/下周三、11月20日、11-20、11/20
/// - 时间：15:30、15点、下午3点半、晚上8点
/// - 重要性：!高 / !中 / !低 / !无
/// - 标签：#工作
QuickParse parseQuickAdd(String raw, {DateTime? now}) {
  final base = now ?? DateTime.now();
  final today = DateTime(base.year, base.month, base.day);
  final ranges = <List<int>>[];
  final tags = <String>[];
  final labels = <String>[];

  var text = raw;
  int? importance;
  DateTime? date;
  int? hour;
  int? minute;

  void take(RegExpMatch m, void Function(String v) apply) {
    ranges.add([m.start, m.end]);
    apply(m.group(0)!.trim());
  }

  // 1. 重要性
  final impRe = RegExp(r'[!！]\s*(高|中|低|无)');
  final impMatch = impRe.firstMatch(text);
  if (impMatch != null) {
    take(impMatch, (_) {
      importance = switch (impMatch.group(1)) {
        '高' => 3,
        '中' => 2,
        '低' => 1,
        _ => 0,
      };
    });
    labels.add(trf('重要性 {}', [tr(impMatch.group(1) ?? '')]));
  }

  // 2. 标签
  final tagRe = RegExp(r'#([^\s#，,。、]+)');
  for (final m in tagRe.allMatches(text)) {
    tags.add(m.group(1)!);
    ranges.add([m.start, m.end]);
  }
  if (tags.isNotEmpty) labels.add(tags.map((t) => '#$t').join(' '));

  // 3. 相对日期（含下周）
  final relRe = RegExp(
    r'(大后天|后天|明天|明日|今天|今日|下(?:周|星期)[一二三四五六日天]|(?:周|星期)[一二三四五六日天])',
  );
  final relMatch = relRe.firstMatch(text);
  if (relMatch != null) {
    final token = relMatch.group(1)!;
    var delta = 0;
    if (token == '明天' || token == '明日') {
      delta = 1;
    } else if (token == '后天') {
      delta = 2;
    } else if (token == '大后天') {
      delta = 3;
    } else if (token.startsWith('下')) {
      final target = _weekdayOf(token.substring(2));
      delta = (target - today.weekday + 7) % 7;
      if (delta == 0) delta = 7;
    } else if (token.startsWith('周') || token.startsWith('星期')) {
      final target = _weekdayOf(
        token.startsWith('周') ? token.substring(1) : token.substring(2),
      );
      delta = (target - today.weekday + 7) % 7;
    }
    date = today.add(Duration(days: delta));
    ranges.add([relMatch.start, relMatch.end]);
  }

  // 4. 绝对日期（11月20日 / 11-20 / 11/20）
  if (date == null) {
    final mdRe = RegExp(r'(\d{1,2})\s*[月/-]\s*(\d{1,2})\s*[日号]?');
    final mdMatch = mdRe.firstMatch(text);
    if (mdMatch != null) {
      final month = int.parse(mdMatch.group(1)!);
      final day = int.parse(mdMatch.group(2)!);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        var d = DateTime(today.year, month, day);
        // 已经过去的日子按明年算，避免设成半年前的日期。
        if (d.isBefore(today)) d = DateTime(today.year + 1, month, day);
        date = d;
        ranges.add([mdMatch.start, mdMatch.end]);
      }
    }
  }

  // 5. 时间：15:30 / 下午3点半 / 晚上8点
  final hmRe = RegExp(r'(上午|下午|晚上|中午)?\s*(\d{1,2})\s*[:：]\s*(\d{2})');
  final hmMatch = hmRe.firstMatch(text);
  if (hmMatch != null) {
    hour = int.parse(hmMatch.group(2)!);
    minute = int.parse(hmMatch.group(3)!);
    hour = _adjustHour(hour, hmMatch.group(1));
    ranges.add([hmMatch.start, hmMatch.end]);
  } else {
    final hRe = RegExp(r'(上午|下午|晚上|中午)?\s*(\d{1,2})\s*[点時时](半|\d{1,2}\s*分?)?');
    final hMatch = hRe.firstMatch(text);
    if (hMatch != null) {
      hour = _adjustHour(int.parse(hMatch.group(2)!), hMatch.group(1));
      final tail = hMatch.group(3);
      if (tail == '半') {
        minute = 30;
      } else if (tail != null && tail.isNotEmpty) {
        minute = int.tryParse(tail.replaceAll('分', '').trim()) ?? 0;
      } else {
        minute = 0;
      }
      ranges.add([hMatch.start, hMatch.end]);
    }
  }

  if (hour != null && (hour < 0 || hour > 23 || (minute ?? 0) > 59)) {
    hour = null;
    minute = null;
  }

  DateTime? dueAt;
  if (date != null || hour != null) {
    final d = date ?? today;
    dueAt = DateTime(d.year, d.month, d.day, hour ?? 18, minute ?? 0);
    final hasTime = hour != null;
    final stamp = '${dueAt.month}-${dueAt.day} ${_weekCn(dueAt.weekday)}';
    labels.insert(
      0,
      hasTime
          ? '$stamp ${dueAt.hour.toString().padLeft(2, '0')}:${dueAt.minute.toString().padLeft(2, '0')}'
          : '$stamp 18:00',
    );
  }

  // 6. 拼回标题
  ranges.sort((a, b) => b[0].compareTo(a[0]));
  for (final r in ranges) {
    text = text.replaceRange(r[0], r[1], ' ');
  }
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = text.replaceAll(RegExp(r'^[，,。、\s]+|[，,。、\s]+$'), '');

  return QuickParse(
    title: text,
    dueAt: dueAt,
    importance: importance,
    tags: tags,
    labels: labels,
  );
}

int _weekdayOf(String cn) => switch (cn) {
  '一' => 1,
  '二' => 2,
  '三' => 3,
  '四' => 4,
  '五' => 5,
  '六' => 6,
  _ => 7,
};

String _weekCn(int weekday) =>
    const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];

int _adjustHour(int hour, String? period) {
  if (period == null) return hour;
  if ((period == '下午' || period == '晚上') && hour < 12) return hour + 12;
  if (period == '中午' && hour < 11) return hour + 12;
  return hour;
}
