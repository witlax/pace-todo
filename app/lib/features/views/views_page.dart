import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../calendar/calendar_page.dart';
import '../settings/settings.dart';
import '../stats/dashboard_cards.dart';
import '../stats/insights_page.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/task_repository.dart';
import '../tasks/today_page.dart' show QuadrantView;
import 'board_view.dart';
import 'card_view.dart';
import 'view_mode.dart';
import '../../core/i18n/i18n.dart';

/// 视图页：工作台 / 日历 / 看板 / 卡片 / 四象限。
///
/// 切换入口放在右上角（一个「当前视图名 + 箭头」的按钮），
/// 不再用一排放不下的分段控件；显示哪几个视图由设置决定，四象限恒定显示。
class ViewsPage extends ConsumerStatefulWidget {
  const ViewsPage({super.key});

  @override
  ConsumerState<ViewsPage> createState() => _ViewsPageState();
}

class _ViewsPageState extends ConsumerState<ViewsPage> {
  ViewMode _mode = ViewMode.dashboard;
  final PageController _page = PageController();

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _goTo(List<ViewMode> views, ViewMode mode) {
    final index = views.indexOf(mode);
    if (index < 0) return;
    setState(() => _mode = mode);
    if (_page.hasClients) {
      _page.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final views = ref.watch(settingsProvider).views;
    // 用户可能在设置里关掉了当前视图，回退到第一个。
    final current = views.contains(_mode) ? _mode : views.first;

    ref.listen(settingsProvider.select((s) => s.visibleViews), (_, _) {
      if (!mounted) return;
      final next = ref.read(settingsProvider).views;
      if (!next.contains(_mode)) {
        setState(() => _mode = next.first);
        if (_page.hasClients) _page.jumpToPage(0);
      }
    });

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 10, 4),
              child: Row(
                children: [
                  Text(
                    tr('视图'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  if (current == ViewMode.dashboard)
                    IconButton(
                      tooltip: tr('工作台卡片'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DashboardCardsPage(),
                        ),
                      ),
                      icon: Icon(Icons.tune, size: 20),
                    ),
                  // 右上角切换：一个按钮说清「现在在哪、还能去哪」。
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _pickView(views, current),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(12, 7, 8, 7),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(current.icon, size: 15, color: scheme.primary),
                          SizedBox(width: 5),
                          Text(
                            current.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.primary,
                            ),
                          ),
                          Icon(
                            Icons.expand_more,
                            size: 16,
                            color: scheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 2),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: views.length,
                onPageChanged: (i) => setState(() => _mode = views[i]),
                itemBuilder: (_, i) => _KeepAlive(
                  child: _pageOf(views[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageOf(ViewMode mode) => switch (mode) {
    ViewMode.dashboard => _DashboardView(),
    ViewMode.calendar => CalendarPage(embedded: true),
    ViewMode.board => BoardView(),
    ViewMode.card => CardView(),
    ViewMode.quadrant => QuadrantView(
      tasks: ref.watch(allActiveTasksProvider).value ?? <Task>[],
    ),
  };

  Future<void> _pickView(List<ViewMode> views, ViewMode current) async {
    final picked = await showModalBottomSheet<ViewMode>(
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
                  tr('切换视图'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            for (final mode in views)
              ListTile(
                dense: true,
                leading: Icon(mode.icon, size: 19),
                title: Text(
                  mode.label,
                  style: TextStyle(fontSize: 13.5),
                ),
                trailing: mode == current
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(mode),
              ),
            SizedBox(height: 4),
            Text(
              tr('在「设置 → 视图显示」里增减视图（四象限固定显示）'),
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(ctx).colorScheme.outline,
              ),
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (picked != null) _goTo(views, picked);
  }
}

/// PageView 会回收远处页面，日历这种有内部状态的页需要保活。
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// 工作台 = 今日概况 + 今日待办。
class _DashboardView extends ConsumerWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(openTasksProvider).value ?? <Task>[];
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final todays = tasks.where((t) {
      final due = t.dueAt;
      if (due == null) return false;
      return due.year == today.year &&
          due.month == today.month &&
          due.day == today.day;
    }).toList()..sort((a, b) => (a.dueAt ?? now).compareTo(b.dueAt ?? now));

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: [
        InsightsBody(),
        SizedBox(height: 22),
        Row(
          children: [
            Text(
              tr('今日待办'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Spacer(),
            Text(
              trf('{} 项', [todays.length]),
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
        SizedBox(height: 6),
        if (todays.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              tr('今天没有带时间的安排'),
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          )
        else
          for (final t in todays)
            InkWell(
              onTap: () => openTaskDetail(context, t.id),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Text(
                      t.dueAt == null
                          ? ''
                          : '${t.dueAt!.hour.toString().padLeft(2, '0')}:${t.dueAt!.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
