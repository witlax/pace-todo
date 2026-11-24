import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../core/app_info.dart';
import '../../core/db/database.dart';
import '../../core/log/app_log.dart';
import '../../platform/notification_service.dart';
import '../goals/goal_page.dart';
import '../habits/habit_page.dart';
import '../goals/goal_repository.dart';
import '../lists/lists_page.dart';
import '../memos/memo_page.dart';
import '../tasks/archive_page.dart';
import '../tasks/completed_page.dart';
import '../tasks/task_repository.dart';
import '../tags/tags_page.dart';
import '../views/view_mode.dart';
import '../tasks/trash_page.dart';
import 'settings.dart';
import 'settings_pages.dart';
import '../../core/i18n/i18n.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final notesCount = ref.watch(notesProvider).value?.length ?? 0;
    final listsCount = ref.watch(listsProvider).value?.length ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Text(
              tr('设置'),
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 4),
            Text(
              tr('本地数据 · 未登录'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),

            _section(context, tr('我的内容')),
            _card(context, [
              _row(
                context,
                Icons.flag_outlined,
                tr('目标'),
                trailing: switch (ref.watch(goalCountsProvider).value) {
                  (final a, final b, final c) => trf('进行 {} · 完成 {} · 暂停 {}', [a, b, c]),
                  null => tr('统计中…'),
                },
                onTap: () => _push(context, GoalsPage()),
              ),
              _row(
                context,
                Icons.folder_outlined,
                tr('清单'),
                trailing: trCount(listsCount, '个清单', 'list', 'lists'),
                onTap: () => _push(context, ListsPage()),
              ),
              _row(
                context,
                Icons.check_circle_outline,
                tr('习惯'),
                trailing: tr('排序 / 归档 / 新建'),
                onTap: () => _push(context, HabitPage()),
              ),
              _row(
                context,
                Icons.local_offer_outlined,
                tr('标签'),
                trailing: tr('按标签统计与查看'),
                onTap: () => _push(context, TagsPage()),
              ),
              _row(
                context,
                Icons.sticky_note_2_outlined,
                tr('备忘录'),
                trailing: trCount(notesCount, '条备忘录', 'note', 'notes'),
                onTap: () => _push(context, MemoPage()),
              ),
              _row(
                context,
                Icons.check_circle_outline,
                tr('已完成'),
                trailing: tr('按日期回看'),
                onTap: () => _push(context, CompletedPage()),
              ),
              _row(
                context,
                Icons.archive_outlined,
                tr('归档'),
                trailing: tr('不删除，移出列表'),
                onTap: () => _push(context, ArchivePage()),
              ),
              _row(
                context,
                Icons.delete_outline,
                tr('回收站'),
                trailing: tr('保留 30 天'),
                onTap: () => _push(context, TrashPage()),
              ),
            ]),

            _section(context, tr('底部导航')),
            _card(context, [
              for (final tab in kOptionalTabs)
                SwitchListTile(
                  value: settings.visibleTabs.contains(tab),
                  onChanged: (_) => notifier.toggleTab(tab),
                  secondary: Icon(tab.icon, size: 20),
                  title: Text(tab.label, style: TextStyle(fontSize: 14)),
                  subtitle: Text(switch (tab) {
                    TabId.view => tr('工作台 / 日历 / 看板 / 卡片 / 四象限'),
                    TabId.focus => tr('计时、白噪音与专注记录'),
                    TabId.log => tr('每日记录与心情'),
                    TabId.goal => tr('目标进度'),
                    TabId.habits => tr('习惯列表、排序与统计'),
                    _ => tr('备忘录列表'),
                  }, style: TextStyle(fontSize: 11)),
                  dense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12),
                ),
            ]),
            Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                tr('首页与设置固定显示；其余按需开关，最多 8 项（底部栏会自动均分宽度）'),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),

            _section(context, tr('视图显示')),
            _card(context, [
              for (final mode in ViewMode.values)
                if (mode.optional)
                  SwitchListTile(
                    value: settings.visibleViews.contains(mode),
                    onChanged: (_) => notifier.toggleView(mode),
                    secondary: Icon(mode.icon, size: 20),
                    title: Text(
                      mode.label,
                      style: TextStyle(fontSize: 14),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  )
                else
                  ListTile(
                    leading: Icon(mode.icon, size: 20),
                    title: Text(
                      mode.label,
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      tr('固定显示（任务的另一种组织方式）'),
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: Text(
                      tr('固定'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
            ]),
            Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                tr('视图页右上角可随时切换；关掉的视图不会出现在列表里'),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),

            _section(context, tr('任务默认值')),
            _card(context, [
              _row(
                context,
                Icons.inbox_outlined,
                tr('默认清单'),
                trailing:
                    (ref.watch(listsProvider).value ?? [])
                        .where((l) => l.id == settings.defaultListId)
                        .map((l) => l.name)
                        .firstOrNull ??
                    tr('收件箱'),
                onTap: () => _pickDefaultList(context, ref, notifier),
              ),
              _row(
                context,
                Icons.notifications_none,
                tr('默认提醒'),
                trailing: switch (settings.defaultRemindOffset) {
                  null => tr('不提醒'),
                  0 => tr('准时'),
                  final v => trf('提前 {} 分钟', [v]),
                },
                onTap: () => _pickDefaultRemind(
                  context,
                  notifier,
                  settings.defaultRemindOffset,
                ),
              ),
              SwitchListTile(
                value: settings.keepDoneInList,
                onChanged: notifier.setKeepDoneInList,
                secondary: Icon(Icons.check_circle_outline, size: 20),
                title: Text(tr('完成后留在列表'), style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  tr('关掉后完成即从今天页消失，只留在「已完成」'),
                  style: TextStyle(fontSize: 11),
                ),
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              _row(
                context,
                Icons.swipe_left_outlined,
                tr('任务左滑'),
                trailing: switch (settings.leftSwipeAction) {
                  'complete' => tr('完成'),
                  'delete' => tr('删除'),
                  _ => tr('归档 / 删除'),
                },
                onTap: () =>
                    _pickLeftSwipe(context, notifier, settings.leftSwipeAction),
              ),
              SwitchListTile(
                value: settings.confirmCheckIn,
                onChanged: notifier.setConfirmCheckIn,
                secondary: Icon(Icons.touch_app_outlined, size: 20),
                title: Text(tr('打卡需二次确认'), style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  tr('默认关：单击圆圈直接打卡，误触用 4 秒撤销'),
                  style: TextStyle(fontSize: 11),
                ),
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
            ]),

            _section(context, tr('智能清单')),
            _card(context, [
              for (final kind in SmartListKind.values)
                _row(
                  context,
                  switch (kind) {
                    SmartListKind.today => Icons.today_outlined,
                    SmartListKind.week => Icons.date_range_outlined,
                    SmartListKind.overdue => Icons.error_outline,
                  },
                  kind.label,
                  trailing: settings.visibilityOf(kind).label,
                  onTap: () => _pickSmart(
                    context,
                    notifier,
                    kind,
                    settings.visibilityOf(kind),
                  ),
                ),
            ]),
            Padding(
              padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(
                tr('「有内容时显示」让清单页保持干净：没事的时候不占位置'),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),

            _section(context, tr('专注')),
            _card(context, [
              SwitchListTile(
                value: settings.microBreak,
                onChanged: notifier.setMicroBreak,
                secondary: Icon(Icons.airline_seat_recline_normal, size: 20),
                title: Text(tr('微休息提醒'), style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  tr('连续专注满 50 分钟时提示起身活动，不打断本轮计时'),
                  style: TextStyle(fontSize: 11),
                ),
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
            ]),

            _section(context, tr('提醒')),
            _card(context, [
              _row(
                context,
                Icons.notifications_active_outlined,
                tr('通知与精确闹钟'),
                trailing: tr('去授权'),
                onTap: () async {
                  await NotificationService.requestNotificationPermission();
                  await NotificationService.requestExactAlarmPermission();
                },
              ),
              _row(context, Icons.alarm_outlined, tr('重复任务'), trailing: tr('完成即生成下一次')),
            ]),

            _section(context, tr('外观与数据')),
            _card(context, [
              _row(
                context,
                Icons.translate,
                tr('语言'),
                trailing: ref.watch(langProvider).title,
                onTap: () => _pickLanguage(context, ref),
              ),
              _row(
                context,
                Icons.palette_outlined,
                tr('主题与配色'),
                trailing: trf('{} · {}', [
                  settings.paletteName.label,
                  switch (settings.themeMode) {
                    ThemeMode.light => tr('浅色'),
                    ThemeMode.dark => tr('深色'),
                    ThemeMode.system => tr('跟随系统'),
                  },
                ]),
                onTap: () => _push(context, AppearancePage()),
              ),
              _row(
                context,
                Icons.backup_outlined,
                tr('备份与恢复'),
                trailing: 'JSON / zip',
                onTap: () => _push(context, BackupPage()),
              ),
            ]),

            _section(context, tr('开发者')),
            _card(context, [
              _row(
                context,
                Icons.receipt_long_outlined,
                tr('日志'),
                trailing: trf('{} 条', [AppLog.entries.length]),
                onTap: () => _push(context, LogsPage()),
              ),
            ]),

            _section(context, tr('关于')),
            _card(context, [
              _row(
                context,
                Icons.info_outline,
                tr('版本与许可'),
                trailing: kAppVersion,
                onTap: () => _push(context, AboutPage()),
              ),
            ]),
            SizedBox(height: 20),
            Center(
              child: Text(
                tr('数据保存在本机 · 不收集任何个人信息'),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 语言选择：两个选项就够，不做下拉——语言是低频设置，看得到全貌更重要。
  Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
    final current = ref.read(langProvider);
    final picked = await showModalBottomSheet<AppLang>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr('语言'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            for (final lang in AppLang.values)
              ListTile(
                dense: true,
                leading: Icon(
                  lang == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: lang == current
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.outline,
                ),
                title: Text(
                  lang.title,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  lang == AppLang.zh ? '简体中文' : 'English (US)',
                  style: const TextStyle(fontSize: 10.5),
                ),
                onTap: () => Navigator.of(ctx).pop(lang),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                tr('切换只影响界面文案，数据不受影响'),
                style: TextStyle(
                  fontSize: 10.5,
                  color: Theme.of(ctx).colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    ref.read(langProvider.notifier).set(picked);
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _pickDefaultList(
    BuildContext context,
    WidgetRef ref,
    SettingsNotifier notifier,
  ) async {
    final lists = ref.read(listsProvider).value ?? <TaskList>[];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in lists)
              ListTile(
                dense: true,
                title: Text(l.name),
                trailing: l.id == ref.read(settingsProvider).defaultListId
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(l.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) notifier.setDefaultList(picked);
  }

  Future<void> _pickLeftSwipe(
    BuildContext context,
    SettingsNotifier notifier,
    String current,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in [
              ('archive', tr('归档 / 删除面板'), tr('滑动后还要再选一次，最安全')),
              ('complete', tr('直接完成'), tr('滑一下即完成，可撤销')),
              ('delete', tr('直接删除'), tr('会先二次确认')),
            ])
              ListTile(
                dense: true,
                title: Text(e.$2),
                subtitle: Text(e.$3, style: TextStyle(fontSize: 10.5)),
                trailing: e.$1 == current
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.$1),
              ),
          ],
        ),
      ),
    );
    if (picked != null) notifier.setLeftSwipeAction(picked);
  }

  Future<void> _pickSmart(
    BuildContext context,
    SettingsNotifier notifier,
    SmartListKind kind,
    SmartVisibility current,
  ) async {
    final picked = await showModalBottomSheet<SmartVisibility>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  kind.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            for (final v in SmartVisibility.values)
              ListTile(
                dense: true,
                title: Text(v.label, style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  switch (v) {
                    SmartVisibility.always => tr('一直显示，哪怕没有任务'),
                    SmartVisibility.auto => tr('有任务时才出现'),
                    SmartVisibility.hidden => tr('完全不在清单页出现'),
                  },
                  style: TextStyle(fontSize: 10.5),
                ),
                trailing: v == current
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(v),
              ),
          ],
        ),
      ),
    );
    if (picked != null) notifier.setSmartVisibility(kind, picked);
  }

  Future<void> _pickDefaultRemind(
    BuildContext context,
    SettingsNotifier notifier,
    int? current,
  ) async {
    final picked = await showModalBottomSheet<int?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in [
              (tr('不提醒'), null),
              (tr('准时提醒'), 0),
              (tr('提前 10 分钟'), 10),
              (tr('提前 1 小时'), 60),
            ])
              ListTile(
                dense: true,
                title: Text(e.$1),
                trailing: current == e.$2
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.$2),
              ),
          ],
        ),
      ),
    );
    notifier.setDefaultRemind(picked);
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _card(BuildContext context, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(children: children),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String title, {
    String? trailing,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap ?? () {},
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 20),
          SizedBox(width: 14),
          // 标题占剩余宽度、右侧取值最多 190，英文长句子不会把标题挤成竖排。
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14),
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 156),
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          SizedBox(width: 2),
          Icon(Icons.chevron_right, size: 18),
        ],
      ),
    ),
  );
}
