import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../features/settings/settings.dart';
import 'en.dart';

/// 应用语言。
///
/// 只有中文与英文两档：够用，且不用维护一堆空翻译。
enum AppLang {
  zh('中文', Locale('zh', 'CN')),
  en('English', Locale('en', 'US'));

  const AppLang(this.title, this.locale);

  /// 语言自身的名字，永远用该语言写（中文叫「中文」，英文叫 English）。
  final String title;
  final Locale locale;

  static AppLang parse(String? value) =>
      value == 'en' ? AppLang.en : AppLang.zh;
}

/// 当前语言。
///
/// 为什么用进程内变量而不是 InheritedWidget：翻译会出现在仓储、通知、
/// 控制器这些没有 `BuildContext` 的地方（比如「已排提醒」的日志、
/// 通知的频道名）。全局变量让 `tr()` 在任何地方都能用，
/// 代价是切语言时要整棵树重建一次——这个由 `App` 里的 key 负责。
AppLang _lang = AppLang.zh;

AppLang get appLang => _lang;

bool get isEnglish => _lang == AppLang.en;

/// 翻译静态文案。key 就是中文原文。
///
/// 找不到译文时返回原文：宁可看到一句中文，也不要看到 `missing.key`。
String tr(String zh) {
  if (_lang == AppLang.zh) return zh;
  return en[zh] ?? zh;
}

/// 翻译带插值的文案。
///
/// 模板里用 `{}` 按顺序占位，或用 `{0}` `{1}` 指定位置（英文语序常要换位）。
/// 中文直接用模板原文，只做占位替换。
String trf(String template, List<Object?> args) {
  final raw = _lang == AppLang.zh ? template : (enTemplates[template] ?? template);
  if (args.isEmpty || !raw.contains('{')) return raw;

  final buffer = StringBuffer();
  var i = 0;
  var next = 0;
  while (i < raw.length) {
    final open = raw.indexOf('{', i);
    if (open < 0) {
      buffer.write(raw.substring(i));
      break;
    }
    final close = raw.indexOf('}', open);
    if (close < 0) {
      buffer.write(raw.substring(i));
      break;
    }
    final key = raw.substring(open + 1, close);
    final index = key.isEmpty ? next : int.tryParse(key) ?? -1;
    if (index < 0 || index >= args.length) {
      // 不是占位符（比如正文里本来就有花括号），原样输出。
      buffer.write(raw.substring(i, close + 1));
    } else {
      buffer.write(raw.substring(i, open));
      buffer.write('${args[index]}');
      if (key.isEmpty) next++;
    }
    i = close + 1;
  }
  return buffer.toString();
}

/// 数量短语：中文「3 个清单」，英文「3 lists」（自动单复数）。
///
/// 中文没有复数，英文有；单靠 `'{} 个'` 这种模板会出现「1 lists」。
String trCount(num n, String zhUnit, String enOne, String enMany) {
  if (_lang == AppLang.zh) return '$n $zhUnit';
  return '$n ${n == 1 ? enOne : enMany}';
}

/// 多个候选里按语言挑一个：`pick('中文', 'English')`。
String pick(String zh, String enText) => _lang == AppLang.zh ? zh : enText;

// ---------------------------------------------------------------------------
// 日期格式：英文用 `MMM d` 这类，中文用 `M月d日`。
//
// 不把格式化串放进翻译表，是因为它们不是「文案」而是「格式」：
// 混在一起会让翻译的人以为要翻 `M月d日`。
// ---------------------------------------------------------------------------

/// 月日：11月24日 / Nov 24
String get dfMonthDay => pick('M月d日', 'MMM d');

/// 月日 + 星期：11月24日 星期一 / Mon, Nov 24
String get dfMonthDayWeek => pick('M月d日 EEEE', 'EEE, MMM d');

/// 月日 + 时分：11月24日 18:00 / Nov 24, 18:00
String get dfMonthDayTime => pick('M月d日 HH:mm', 'MMM d, HH:mm');

/// 年月日：2026年11月24日 / Nov 24, 2026
String get dfFullDate => pick('yyyy年M月d日', 'MMM d, yyyy');

/// 年月日 + 星期：2026年11月24日 星期一 / Mon, Nov 24, 2026
String get dfFullDateWeek => pick('yyyy年M月d日 EEEE', 'EEE, MMM d, yyyy');

/// 年月：2026 年 11 月 / November 2026
String get dfYearMonth => pick('yyyy 年 M 月', 'MMMM yyyy');

/// 年月日 + 时分：2026年11月24日 18:00 / Nov 24, 2026 18:00
String get dfFullDateTime => pick('yyyy年M月d日 HH:mm', 'MMM d, yyyy HH:mm');

/// 只到月：11月 / Nov
String get dfMonthOnly => pick('M月', 'MMM');

/// 年月（紧凑）：2026年11月 / Nov 2026
String get dfYearMonthShort => pick('yyyy年M月', 'MMM yyyy');

/// 月日时分秒用的格式器（跟着语言走，不再传死 'zh_CN'）。
DateFormat dfMonthDayFmt() => DateFormat(dfMonthDay, appLang.locale.toLanguageTag());

DateFormat dfMonthDayWeekFmt() =>
    DateFormat(dfMonthDayWeek, appLang.locale.toLanguageTag());

DateFormat dfMonthDayTimeFmt() => DateFormat(dfMonthDayTime);

DateFormat dfFullDateFmt() => DateFormat(dfFullDate);

DateFormat dfFullDateWeekFmt() => DateFormat(dfFullDateWeek);

DateFormat dfYearMonthFmt() => DateFormat(dfYearMonth);

DateFormat dfYearMonthShortFmt() => DateFormat(dfYearMonthShort);

DateFormat dfFullDateTimeFmt() => DateFormat(dfFullDateTime);

DateFormat dfMonthOnlyFmt() => DateFormat(dfMonthOnly);

/// 星期的单字：一 二 三 四 五 六 日 / M T W T F S S
String weekdayInitial(int weekday) {
  if (_lang == AppLang.zh) {
    return const ['一', '二', '三', '四', '五', '六', '日'][weekday - 1];
  }
  return const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][weekday - 1];
}

/// 一周七天的单字列表，给日期条表头用。
List<String> get weekdayInitials =>
    [for (var day = 1; day <= 7; day++) weekdayInitial(day)];

/// 星期的短名：二 / Tue（热力图那种极窄位置用）。
String weekdayShort(int weekday) {
  if (_lang == AppLang.zh) return weekdayInitial(weekday);
  return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
}

/// 「周一 / Mon」
String weekdayLong(int weekday) {
  if (_lang == AppLang.zh) return '周${weekdayInitial(weekday)}';
  return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];
}

// ---------------------------------------------------------------------------
// 语言状态
// ---------------------------------------------------------------------------

const String kLangPrefKey = 'app.lang';

/// 语言控制器：写 prefs，同时更新全局变量。
final langProvider = NotifierProvider<LangController, AppLang>(
  LangController.new,
);

class LangController extends Notifier<AppLang> {
  @override
  AppLang build() {
    final stored = ref.watch(prefsProvider).getString(kLangPrefKey);
    final lang = AppLang.parse(stored);
    _lang = lang;
    return lang;
  }

  void set(AppLang lang) {
    _lang = lang;
    state = lang;
    ref.read(prefsProvider).setString(kLangPrefKey, lang.name);
  }

  void toggle() => set(state == AppLang.zh ? AppLang.en : AppLang.zh);
}
