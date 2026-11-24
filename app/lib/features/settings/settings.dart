import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/tokens.dart';
import '../views/view_mode.dart';
import '../../core/i18n/i18n.dart';

/// 底部导航固定六项，与 pinch 一致：首页 / 视图 / 专注 / 日志 / 目标 / 设置。
///
/// 0.17 之前是可配置的 5 项（中间项能开关）。复刻 pinch 的信息架构后固定为 6 项：
/// 习惯并进首页的折叠区、备忘录进「视图」与设置入口，底部不再为它们留位置。
enum TabId {
  home('首页', Icons.home_outlined, Icons.home),
  view('视图', Icons.dashboard_outlined, Icons.dashboard),
  focus('专注', Icons.favorite_border, Icons.favorite),
  log('日志', Icons.menu_book_outlined, Icons.menu_book),
  goal('目标', Icons.gps_fixed_outlined, Icons.gps_fixed),
  habits('习惯', Icons.check_circle_outline, Icons.check_circle),
  memos('备忘录', Icons.sticky_note_2_outlined, Icons.sticky_note_2),
  settings('设置', Icons.settings_outlined, Icons.settings);

  const TabId(this._label, this.icon, this.selectedIcon);
  final String _label;
  final IconData icon;
  final IconData selectedIcon;

  String get label => tr(_label);

  /// 首页与设置是锚点，不能隐藏——否则没有入口回到主界面。
  bool get isAnchor => this == home || this == settings;
}

/// 可开关的导航项，顺序即底部栏顺序。
const kOptionalTabs = [
  TabId.view,
  TabId.focus,
  TabId.log,
  TabId.goal,
  TabId.habits,
  TabId.memos,
];

/// 默认显示的四项（加上首页与设置共 6 个）。
const kDefaultTabs = <TabId>{TabId.view, TabId.focus, TabId.log, TabId.goal};

/// 旧版本存过 'calendar' / 'today' / 'habits' / 'memos'，读到时映射或忽略。
TabId? tabFromName(String name) {
  final normalized = switch (name) {
    'calendar' => 'view',
    'today' => 'home',
    _ => name,
  };
  for (final t in TabId.values) {
    if (t.name == normalized) return t;
  }
  return null;
}

/// 智能清单：不需要手动建，按规则自动从所有任务里筛。
enum SmartListKind {
  today('今天', '今天到期与已逾期'),
  week('最近 7 天', '未来一周到期'),
  overdue('已逾期', '过了日期还没做');

  const SmartListKind(this._label, this._subtitle);
  final String _label;
  final String _subtitle;

  String get label => tr(_label);
  String get subtitle => tr(_subtitle);

  /// 默认：今天常显（它是每天的入口），另外两个有内容才出现。
  SmartVisibility get defaultVisibility =>
      this == SmartListKind.today ? SmartVisibility.always : SmartVisibility.auto;
}

/// 显示策略三态：常显 / 有内容才显示 / 隐藏。
enum SmartVisibility {
  always('显示'),
  auto('有内容时显示'),
  hidden('隐藏');

  const SmartVisibility(this._label);
  final String _label;

  String get label => tr(_label);

  static SmartVisibility parse(String? raw) => switch (raw) {
    'always' => SmartVisibility.always,
    'hidden' => SmartVisibility.hidden,
    _ => SmartVisibility.auto,
  };
}

class AppSettings {
  AppSettings({
    required this.themeMode,
    required this.colorBlindPalette,
    this.confirmCheckIn = false,
    this.defaultListId = 'inbox',
    this.defaultRemindOffset,
    this.keepDoneInList = true,
    this.leftSwipeAction = 'archive',
    this.smartLists = const {},
    this.microBreak = true,
    this.visibleTabs = kDefaultTabs,
    this.visibleViews = ViewMode.defaults,
    this.focusClock = false,
    this.paletteName = AppPaletteName.teal,
    this.focusBreakMin = 5,
    this.focusCycles = 1,
  });

  final ThemeMode themeMode;
  final bool colorBlindPalette;

  /// 打卡是否要二次确认（默认关：高频动作不该被拦住）。
  final bool confirmCheckIn;

  /// 新建任务默认落到哪个清单。
  final String defaultListId;

  /// 新建任务默认提醒偏移（分钟，0 准时，null 不提醒）。
  final int? defaultRemindOffset;

  /// 完成后是否留在列表（今日完成分组）。
  final bool keepDoneInList;

  /// 左滑动作：archive（归档/删除面板）/ complete（完成）/ delete（删除）。
  final String leftSwipeAction;

  /// 智能清单的显示策略，未设置时用各清单的默认值。
  final Map<SmartListKind, SmartVisibility> smartLists;

  /// 专注满 50 分钟提示起身（微休息）。
  final bool microBreak;

  /// 底部栏显示哪些可选项（首页与设置恒显示）。
  final Set<TabId> visibleTabs;

  /// 视图页显示哪些视图（四象限恒定显示）。
  final Set<ViewMode> visibleViews;

  /// 专注页显示实时时钟（当前时间）。
  final bool focusClock;

  /// 配色方案（青瓷 / 钢蓝 / 陶土）。
  final AppPaletteName paletteName;

  /// 短休时长（分钟）。
  final int focusBreakMin;

  /// 每组专注几轮（1–8）。
  final int focusCycles;

  /// 视图页实际渲染的顺序：四象限永远在最后。
  List<ViewMode> get views => [
    ...ViewMode.values.where(
      (v) => v != ViewMode.quadrant && visibleViews.contains(v),
    ),
    ViewMode.quadrant,
  ];

  SmartVisibility visibilityOf(SmartListKind kind) =>
      smartLists[kind] ?? kind.defaultVisibility;

  List<TabId> get tabs => [
    TabId.home,
    ...kOptionalTabs.where(visibleTabs.contains),
    TabId.settings,
  ];

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? colorBlindPalette,
    bool? confirmCheckIn,
    String? defaultListId,
    int? defaultRemindOffset,
    bool clearDefaultRemind = false,
    bool? keepDoneInList,
    String? leftSwipeAction,
    Map<SmartListKind, SmartVisibility>? smartLists,
    bool? microBreak,
    Set<TabId>? visibleTabs,
    Set<ViewMode>? visibleViews,
    bool? focusClock,
    AppPaletteName? paletteName,
    int? focusBreakMin,
    int? focusCycles,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    colorBlindPalette: colorBlindPalette ?? this.colorBlindPalette,
    confirmCheckIn: confirmCheckIn ?? this.confirmCheckIn,
    defaultListId: defaultListId ?? this.defaultListId,
    defaultRemindOffset: clearDefaultRemind
        ? null
        : (defaultRemindOffset ?? this.defaultRemindOffset),
    keepDoneInList: keepDoneInList ?? this.keepDoneInList,
    leftSwipeAction: leftSwipeAction ?? this.leftSwipeAction,
    smartLists: smartLists ?? this.smartLists,
    microBreak: microBreak ?? this.microBreak,
    visibleTabs: visibleTabs ?? this.visibleTabs,
    visibleViews: visibleViews ?? this.visibleViews,
    focusClock: focusClock ?? this.focusClock,
    paletteName: paletteName ?? this.paletteName,
    focusBreakMin: focusBreakMin ?? this.focusBreakMin,
    focusCycles: focusCycles ?? this.focusCycles,
  );
}

/// 由 main() 注入已初始化的实例，避免异步读取设置。
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(tr('prefsProvider 必须在 ProviderScope 中覆盖')),
);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _kTheme = 'appearance.themeMode';
  static const _kColorBlind = 'appearance.colorBlind';
  static const _kConfirmCheckIn = 'habit.confirmCheckIn';
  static const _kDefaultList = 'task.defaultList';
  static const _kDefaultRemind = 'task.defaultRemind';
  static const _kKeepDone = 'task.keepDoneInList';
  static const _kLeftSwipe = 'task.leftSwipe';
  static const _kSmartLists = 'smart.visibility';
  static const _kMicroBreak = 'focus.microBreak';
  static const _kVisibleTabs = 'nav.visible';
  static const _kVisibleViews = 'view.visible';
  static const _kFocusClock = 'focus.showClock';
  static const _kPalette = 'appearance.palette';
  static const _kFocusBreak = 'focus.breakMin';
  static const _kFocusCycles = 'focus.cycles';

  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(prefsProvider);
    return AppSettings(
      themeMode: switch (prefs.getString(_kTheme)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      colorBlindPalette: prefs.getBool(_kColorBlind) ?? false,
      confirmCheckIn: prefs.getBool(_kConfirmCheckIn) ?? false,
      defaultListId: prefs.getString(_kDefaultList) ?? 'inbox',
      defaultRemindOffset: prefs.getInt(_kDefaultRemind),
      keepDoneInList: prefs.getBool(_kKeepDone) ?? true,
      leftSwipeAction: prefs.getString(_kLeftSwipe) ?? 'archive',
      smartLists: _readSmart(prefs),
      microBreak: prefs.getBool(_kMicroBreak) ?? true,
      visibleTabs: _readTabs(prefs),
      visibleViews: _readViews(prefs),
      focusClock: prefs.getBool(_kFocusClock) ?? false,
      paletteName: AppPaletteName.parse(prefs.getString(_kPalette)),
      focusBreakMin: prefs.getInt(_kFocusBreak) ?? 5,
      focusCycles: (prefs.getInt(_kFocusCycles) ?? 1).clamp(1, 8),
    );
  }

  static Set<ViewMode> _readViews(SharedPreferences prefs) {
    final raw = prefs.getStringList(_kVisibleViews);
    if (raw == null) return ViewMode.defaults;
    final result = <ViewMode>{};
    for (final name in raw) {
      for (final mode in ViewMode.values) {
        if (mode.name == name && mode.optional) result.add(mode);
      }
    }
    return result;
  }

  static Set<TabId> _readTabs(SharedPreferences prefs) {
    final raw = prefs.getStringList(_kVisibleTabs);
    if (raw == null) return kDefaultTabs;
    final result = <TabId>{};
    for (final name in raw) {
      final tab = tabFromName(name);
      if (tab != null && !tab.isAnchor) result.add(tab);
    }
    return result;
  }

  static Map<SmartListKind, SmartVisibility> _readSmart(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getStringList(_kSmartLists) ?? [];
    final map = <SmartListKind, SmartVisibility>{};
    for (final entry in raw) {
      final parts = entry.split('=');
      if (parts.length != 2) continue;
      for (final kind in SmartListKind.values) {
        if (kind.name == parts[0]) {
          map[kind] = SmartVisibility.parse(parts[1]);
        }
      }
    }
    return map;
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs.setString(_kTheme, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  void setColorBlindPalette(bool value) {
    state = state.copyWith(colorBlindPalette: value);
    _prefs.setBool(_kColorBlind, value);
  }

  void setConfirmCheckIn(bool value) {
    state = state.copyWith(confirmCheckIn: value);
    _prefs.setBool(_kConfirmCheckIn, value);
  }

  void setDefaultList(String id) {
    state = state.copyWith(defaultListId: id);
    _prefs.setString(_kDefaultList, id);
  }

  void setDefaultRemind(int? offset) {
    state = state.copyWith(
      defaultRemindOffset: offset,
      clearDefaultRemind: offset == null,
    );
    if (offset == null) {
      _prefs.remove(_kDefaultRemind);
    } else {
      _prefs.setInt(_kDefaultRemind, offset);
    }
  }

  void setKeepDoneInList(bool value) {
    state = state.copyWith(keepDoneInList: value);
    _prefs.setBool(_kKeepDone, value);
  }

  void setLeftSwipeAction(String value) {
    state = state.copyWith(leftSwipeAction: value);
    _prefs.setString(_kLeftSwipe, value);
  }

  void setSmartVisibility(SmartListKind kind, SmartVisibility value) {
    final next = {...state.smartLists, kind: value};
    state = state.copyWith(smartLists: next);
    _prefs.setStringList(_kSmartLists, [
      for (final e in next.entries) '${e.key.name}=${e.value.name}',
    ]);
  }

  void toggleTab(TabId tab) {
    if (tab.isAnchor) return;
    final next = {...state.visibleTabs};
    if (!next.remove(tab)) next.add(tab);
    state = state.copyWith(visibleTabs: next);
    _prefs.setStringList(_kVisibleTabs, next.map((t) => t.name).toList());
  }

  void toggleView(ViewMode mode) {
    if (!mode.optional) return;
    final next = {...state.visibleViews};
    if (!next.remove(mode)) next.add(mode);
    state = state.copyWith(visibleViews: next);
    _prefs.setStringList(_kVisibleViews, next.map((v) => v.name).toList());
  }

  void setPalette(AppPaletteName name) {
    state = state.copyWith(paletteName: name);
    _prefs.setString(_kPalette, name.name);
  }

  void setFocusClock(bool value) {
    state = state.copyWith(focusClock: value);
    _prefs.setBool(_kFocusClock, value);
  }

  void setFocusBreak(int minutes) {
    state = state.copyWith(focusBreakMin: minutes.clamp(1, 60));
    _prefs.setInt(_kFocusBreak, state.focusBreakMin);
  }

  void setFocusCycles(int cycles) {
    state = state.copyWith(focusCycles: cycles.clamp(1, 8));
    _prefs.setInt(_kFocusCycles, state.focusCycles);
  }

  void setMicroBreak(bool value) {
    state = state.copyWith(microBreak: value);
    _prefs.setBool(_kMicroBreak, value);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// 当前配色方案（主色 + 背景 + 语义色）。
final paletteSchemeProvider = Provider<AppPaletteScheme>(
  (ref) => ref.watch(settingsProvider.select((s) => s.paletteName)).scheme,
);

/// 重要性四色：随配色方案与明暗切换；色盲友好开关优先级最高。
final paletteProvider = Provider<Palette>((ref) {
  final settings = ref.watch(settingsProvider);
  if (settings.colorBlindPalette) return Palette.colorBlindSafe;
  final brightness = switch (settings.themeMode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => PlatformDispatcher.instance.platformBrightness,
  };
  return settings.paletteName.scheme.paletteFor(brightness);
});
