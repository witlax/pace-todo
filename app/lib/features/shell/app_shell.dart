import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../focus/focus_controller.dart';
import '../focus/focus_page.dart';
import '../goals/goal_page.dart';
import '../home/home_page.dart';
import '../log/daily_log_page.dart';
import '../habits/habit_edit_page.dart';
import '../habits/habit_page.dart';
import '../habits/habit_stats_page.dart';
import '../memos/memo_page.dart';
import '../mood/mood_page.dart';
import '../search/search_page.dart';
import '../settings/settings.dart';
import '../settings/settings_page.dart';
import '../settings/settings_pages.dart';
import '../stats/insights_page.dart';
import '../tasks/completed_page.dart';
import '../tasks/today_page.dart';
import '../tasks/trash_page.dart';
import '../views/views_page.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 应用外壳。
///
/// 手机：底部 5 个 Tab（中间项可在设置里开关）。
/// 桌面（≥980dp）：左侧常驻导航 + 中间内容，不再出现底部导航；
/// 同时接管几个全局快捷键，让「一直开着」真的能只用键盘。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// 切语言会整树重建，用文件级变量记住当前页，避免打回首页。
  static TabId _last = TabId.home;

  TabId _selected = _last;

  void _select(TabId tab) {
    _last = tab;
    setState(() => _selected = tab);
  }

  void _openQuickAdd() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 专注结束时无论用户在哪个 Tab，都先给一条明确提示；
    // 系统通知负责锁屏场景，这一条负责「正在看屏幕」的场景。
    ref.listen(focusControllerProvider.select((s) => s.finished), (prev, next) {
      if (!next || prev == true) return;
      final s = ref.read(focusControllerProvider);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            persist: false,
            duration: const Duration(seconds: 8),
            content: Text(
              trf('专注完成 · {} 分钟', [(s.actualSec / 60).round()]),
              style: const TextStyle(fontSize: 12.5),
            ),
            action: SnackBarAction(
              label: tr('查看结算'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => FocusPage()),
              ),
            ),
          ),
        );
    });

    // 微休息：专注满 50 分钟时提醒一次，不暂停计时。
    ref.listen(focusControllerProvider.select((s) => s.breakCount), (
      prev,
      next,
    ) {
      if (next <= (prev ?? 0)) return;
      final s = ref.read(focusControllerProvider);
      final minutes = s.countUp
          ? s.elapsedSec ~/ 60
          : (s.plannedSec - s.remainingSec) ~/ 60;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            persist: false,
            duration: Duration(seconds: 8),
            content: Text(
              trf('已专注 {} 分钟，起来走两步 · 计时继续', [minutes]),
              style: TextStyle(fontSize: 12.5),
            ),
            action: SnackBarAction(
              label: tr('知道了'),
              onPressed: () {},
            ),
          ),
        );
    });

    final tabs = ref.watch(settingsProvider).tabs;
    final index = tabs.contains(_selected) ? tabs.indexOf(_selected) : 0;
    final wide = MediaQuery.sizeOf(context).width >= 980;

    final content = IndexedStack(
      index: index,
      children: [for (final tab in tabs) _pageFor(tab)],
    );

    final pill = ref.watch(focusPillProvider);
    final showPill = pill != null && _selected != TabId.focus;

    if (!wide) {
      return Scaffold(
        body: Stack(
          children: [
            content,
            if (showPill)
              // 抬高到悬浮按钮之上，避免两颗球叠在一起。
              Positioned(
                right: 14,
                bottom: 78,
                child: _MiniBottle(onTap: _openFocus),
              ),
          ],
        ),
        // 自绘底部栏：Material 的 NavigationBar 会吞掉长按，
        // 而「长按 Tab 进次级入口」是滴答那套里很省事的一条。
        bottomNavigationBar: _tabsBar(tabs, index),
      );
    }

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _openQuickAdd,
        SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => SearchPage()));
        },
        SingleActivator(LogicalKeyboardKey.space): () {
          ref.read(focusControllerProvider.notifier).toggle();
        },
        SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              _SideNav(
                tabs: tabs,
                selected: index,
                onSelect: (i) => _select(tabs[i]),
                onQuickAdd: _openQuickAdd,
              ),
              VerticalDivider(width: 1),
              Expanded(
                child: Stack(
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 1000),
                        child: content,
                      ),
                    ),
                    if (showPill)
                      Positioned(
                        right: 18,
                        bottom: 18,
                        child: _MiniBottle(onTap: _openFocus),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabsBar(List<TabId> tabs, int index) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => _select(tabs[i]),
                    onLongPress: () => _showTabActions(context, tabs[i]),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: Duration(milliseconds: 150),
                          padding: EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: i == index
                                ? scheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            i == index ? tabs[i].selectedIcon : tabs[i].icon,
                            size: 20,
                            color: i == index
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          tabs[i].label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: i == index
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: i == index
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTabActions(BuildContext context, TabId tab) {
    final entries = <(String, IconData, Widget Function())>[];
    switch (tab) {
      case TabId.home:
        entries.addAll([
          (tr('搜索任务'), Icons.search, () => SearchPage()),
          (tr('已完成'), Icons.check_circle_outline, () => CompletedPage()),
          (tr('回收站'), Icons.delete_outline, () => TrashPage()),
        ]);
      case TabId.view:
        entries.addAll([
          (tr('今日概览'), Icons.bar_chart, () => TodayInsightsPage()),
          (tr('备忘录'), Icons.sticky_note_2_outlined, () => MemoPage()),
          (tr('习惯管理'), Icons.check_circle_outline, () => HabitPage()),
        ]);
      case TabId.focus:
        entries.addAll([
          (tr('今日概览'), Icons.bar_chart, () => TodayInsightsPage()),
          (tr('习惯统计'), Icons.insights, () => HabitStatsPage()),
        ]);
      case TabId.log:
        entries.addAll([
          (tr('心情打卡'), Icons.mood, () => MoodPage()),
          (tr('备忘录'), Icons.sticky_note_2_outlined, () => MemoPage()),
        ]);
      case TabId.goal:
        entries.addAll([
          (tr('目标管理'), Icons.flag_outlined, () => GoalsPage()),
          (tr('已完成目标'), Icons.task_alt, () => ArchivedGoalsPage()),
        ]);
      case TabId.habits:
        entries.addAll([
          (tr('习惯统计'), Icons.insights, () => HabitStatsPage()),
          (tr('心情打卡'), Icons.mood, () => MoodPage()),
          (tr('新建习惯'), Icons.add, () => HabitEditPage()),
        ]);
      case TabId.memos:
        entries.addAll([(tr('搜索备忘录'), Icons.search, () => SearchPage())]);
      case TabId.settings:
        entries.addAll([
          (tr('备份与恢复'), Icons.backup_outlined, () => BackupPage()),
          (tr('外观与配色'), Icons.palette_outlined, () => AppearancePage()),
          (tr('运行日志'), Icons.receipt_long, () => LogsPage()),
        ]);
    }
    if (entries.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Divider(height: 1),
            for (final e in entries)
              ListTile(
                dense: true,
                leading: Icon(e.$2, size: 19),
                title: Text(e.$1, style: TextStyle(fontSize: 13.5)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => e.$3()));
                },
              ),
            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 迷你瓶：点一下回到专注页；专注 tab 被隐藏时改用路由。
  void _openFocus() {
    final tabs = ref.read(settingsProvider).tabs;
    if (tabs.contains(TabId.focus)) {
      _select(TabId.focus);
    } else {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => FocusPage()));
    }
  }

  Widget _pageFor(TabId tab) => switch (tab) {
    TabId.home => HomePage(),
    TabId.view => ViewsPage(),
    TabId.focus => FocusPage(),
    TabId.log => DailyLogPage(),
    TabId.habits => HabitPage(),
    TabId.memos => MemoPage(),
    TabId.goal => GoalsPage(),
    TabId.settings => SettingsPage(),
  };
}

/// 桌面左栏：定位用，不承担操作。
class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    required this.onQuickAdd,
  });

  final List<TabId> tabs;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 208,
      color: scheme.surfaceContainerLowest,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      tr('待'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    tr('任务待办'),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < tabs.length; i++)
              _navItem(context, tabs[i].icon, tabs[i].label, i == selected, () {
                onSelect(i);
              }),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Text(
                tr('快捷'),
                style: TextStyle(fontSize: 10.5, color: Color(0xFF9AA0A8)),
              ),
            ),
            _navItem(
              context,
              Icons.add_circle_outline,
              tr('新建任务'),
              false,
              onQuickAdd,
              trailing: 'Ctrl N',
            ),
            _navItem(
              context,
              Icons.search,
              tr('搜索'),
              false,
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => SearchPage()),
              ),
              trailing: 'Ctrl F',
            ),
            Spacer(),
            Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Text(
                tr('本地数据 · 不收集任何信息'),
                style: TextStyle(fontSize: 9.5, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    IconData icon,
    String label,
    bool active,
    VoidCallback onTap, {
    String? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: active ? scheme.primaryContainer.withValues(alpha: 0.55) : null,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: TextStyle(
                      fontSize: 9,
                      color: scheme.outline,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 迷你瓶：专注进行中时浮在右下角，显示剩余时间，点一下回专注页。
///
/// 这是引脚版的 pinch 悬浮胶囊——不做系统级悬浮窗（要 overlay 权限，
/// 且大部分时间用户就在应用里，应用内足够）。
class _MiniBottle extends ConsumerWidget {
  const _MiniBottle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(focusPillProvider);
    if (s == null) return SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final accent = s.inBreak ? context.appColors.done : scheme.primary;

    return Material(
      color: accent,
      elevation: 5,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 13, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                s.inBreak
                    ? Icons.local_cafe_outlined
                    : (s.running ? Icons.timer : Icons.pause_circle_outline),
                size: 15,
                color: scheme.onPrimary,
              ),
              SizedBox(width: 7),
              Text(
                s.displayText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (s.inBreak) ...[
                SizedBox(width: 4),
                Text(
                  tr('短休'),
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
