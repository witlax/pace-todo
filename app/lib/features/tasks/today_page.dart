import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../../core/ui/bottom_sheet_inset.dart';
import '../../core/ui/schedule_sheet.dart';
import '../focus/focus_controller.dart';
import '../focus/focus_fullscreen_page.dart';
import '../focus/focus_page.dart';
import '../settings/settings.dart';
import '../search/search_page.dart';
import 'task_create_page.dart';
import 'task_detail_page.dart';
import 'quick_parse.dart';
import 'task_repository.dart';
import 'widgets/task_tile.dart';
import 'widgets/task_tile_expandable.dart';
import '../../core/i18n/i18n.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  late final PageController _page = PageController(
    initialPage: ref.read(viewModeProvider).index,
  );

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final mode = ref.watch(viewModeProvider);
    // 点分段时翻页；翻页时由 onPageChanged 回写模式，避免两处状态打架。
    ref.listen(viewModeProvider, (prev, next) {
      if (!_page.hasClients) return;
      final current = (_page.page ?? next.index.toDouble()).round();
      if (current != next.index) {
        _page.animateToPage(
          next.index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
    final tasksAsync = ref.watch(openTasksProvider);
    final query = ref.watch(searchQueryProvider);
    final done = ref.watch(doneTodayProvider).value ?? 0;
    final keepDone = ref.watch(
      settingsProvider.select((s) => s.keepDoneInList),
    );
    final doneTasks = keepDone
        ? (ref.watch(doneTodayTasksProvider).value ?? const <Task>[])
        : const <Task>[];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showQuickAdd(context),
        child: const Icon(Icons.add, size: 26),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FocusPill(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tr('今天'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 10),
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(
                      dfMonthDayWeekFmt().format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    tooltip: tr('专注'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FocusPage(),
                      ),
                    ),
                    icon: Icon(Icons.timer_outlined, size: 22),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    trf('{} 项待办 · 今日完成 {}', [tasksAsync.value?.length ?? 0, done]),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<TaskViewMode>(
                segments: [
                  ButtonSegment(
                    value: TaskViewMode.list,
                    label: Text(tr('清单')),
                    icon: Icon(Icons.format_list_bulleted, size: 16),
                  ),
                  ButtonSegment(
                    value: TaskViewMode.quadrant,
                    label: Text(tr('四象限')),
                    icon: Icon(Icons.grid_view, size: 16),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) =>
                    ref.read(viewModeProvider.notifier).set(s.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStateProperty.all(
                    TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) {
                  final next = TaskViewMode.values[i];
                  if (ref.read(viewModeProvider) != next) {
                    ref.read(viewModeProvider.notifier).set(next);
                  }
                },
                children: [
                  _listPage(context, ref, tasksAsync, query, doneTasks, scheme),
                  _quadrantPage(context, ref, tasksAsync, query, doneTasks),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listPage(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Task>> tasksAsync,
    String query,
    List<Task> doneTasks,
    ColorScheme scheme,
  ) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => SearchPage())),
            child: Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: scheme.onSurfaceVariant),
                  SizedBox(width: 8),
                  Text(
                    tr('搜索任务、备忘录'),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 2),
        Expanded(
          child: tasksAsync.when(
            loading: () => Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
            data: (tasks) {
              final filtered = _filter(tasks, query);
              if (filtered.isEmpty && doneTasks.isEmpty) {
                return _EmptyState(hasQuery: query.isNotEmpty);
              }
              return _TaskList(tasks: filtered, doneTasks: doneTasks);
            },
          ),
        ),
      ],
    );
  }

  Widget _quadrantPage(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Task>> tasksAsync,
    String query,
    List<Task> doneTasks,
  ) {
    return tasksAsync.when(
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
      data: (tasks) {
        final filtered = _filter(tasks, query);
        if (filtered.isEmpty) {
          return _EmptyState(hasQuery: query.isNotEmpty);
        }
        return QuadrantView(tasks: filtered);
      },
    );
  }

  List<Task> _filter(List<Task> tasks, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return tasks;
    return tasks.where((t) => t.title.toLowerCase().contains(q)).toList();
  }

  void _showQuickAdd(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddSheet(),
    );
  }
}

class _TaskList extends ConsumerWidget {
  const _TaskList({required this.tasks, this.doneTasks = const []});

  final List<Task> tasks;
  final List<Task> doneTasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = _group(tasks);
    final items = <Widget>[];
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      items.add(_sectionHeader(context, entry.key.label, entry.value.length));
      for (final t in entry.value) {
        items.add(
          TaskTileExpandable(
            task: t,
            onToggle: () => _complete(context, ref, t),
            onOpen: () => openTaskDetail(context, t.id),
            onDelete: () => _delete(context, ref, t),
            onArchive: () => _archive(context, ref, t),
          ),
        );
      }
    }
    if (doneTasks.isNotEmpty) {
      items.add(_sectionHeader(context, tr('今日完成'), doneTasks.length));
      for (final t in doneTasks) {
        items.add(
          TaskTile(
            task: t,
            onToggle: () => _complete(context, ref, t, undoIfDone: true),
            onOpen: () => openTaskDetail(context, t.id),
            onDelete: () => _delete(context, ref, t),
            onArchive: () => _archive(context, ref, t),
          ),
        );
      }
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
      children: items,
    );
  }

  Widget _sectionHeader(BuildContext context, String label, int count) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        '$label · $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Map<_Bucket, List<Task>> _group(List<Task> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(Duration(days: 1));
    final map = {for (final b in _Bucket.values) b: <Task>[]};
    for (final t in tasks) {
      final due = t.dueAt;
      if (due == null) {
        map[_Bucket.none]!.add(t);
      } else if (due.isBefore(today)) {
        map[_Bucket.overdue]!.add(t);
      } else if (due.isBefore(tomorrow)) {
        map[_Bucket.today]!.add(t);
      } else {
        map[_Bucket.later]!.add(t);
      }
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final imp = b.importance.compareTo(a.importance);
        if (imp != 0) return imp;
        final ad = a.dueAt, bd = b.dueAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    }
    return map;
  }

  Future<void> _complete(
    BuildContext context,
    WidgetRef ref,
    Task task, {
    bool undoIfDone = false,
  }) async {
    final repo = ref.read(taskRepositoryProvider);
    if (undoIfDone && task.status == 1) {
      await repo.setDone(task.id, false);
      return;
    }
    await repo.setDone(task.id, true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Flutter 新版默认：带 action 的 SnackBar 常驻（persist=action!=null），
          // 必须显式关掉，否则 duration 失效。
          persist: false,
          content: Text(trf('已完成「{}」', [task.title])),
          action: SnackBarAction(
            label: tr('撤销'),
            onPressed: () => repo.setDone(task.id, false),
          ),
          duration: Duration(seconds: 3),
        ),
      );
  }

  Future<void> _archive(BuildContext context, WidgetRef ref, Task task) async {
    final repo = ref.read(taskRepositoryProvider);
    await repo.archiveTask(task.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          content: Text(trf('已归档：{}', [task.title])),
          duration: Duration(seconds: 4),
          action: SnackBarAction(
            label: tr('撤销'),
            onPressed: () => repo.unarchiveTask(task.id),
          ),
        ),
      );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Task task) async {
    final repo = ref.read(taskRepositoryProvider);
    await repo.softDelete(task.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(trf('已移到回收站：{}', [task.title])),
          duration: Duration(seconds: 4),
        ),
      );
  }
}

enum _Bucket {
  overdue('逾期'),
  today('今天'),
  later('之后'),
  none('未排期');

  const _Bucket(this._label);
  final String _label;

  String get label => tr(_label);
}

class QuadrantView extends ConsumerWidget {
  const QuadrantView({super.key, required this.tasks});

  final List<Task> tasks;

  /// 拖到某一格 = 同时定「重要性」与「日期」：
  /// q1 高/今天，q2 中/五天后，q3 低/今天，q4 无/无日期。
  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    Task task,
    _Q to,
  ) async {
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    final today18 = DateTime(now.year, now.month, now.day, 18);
    // 「紧急」的判定是 3 天内，所以「计划做」必须推到 4 天后，
    // 否则拖过去下一帧又被算回紧急象限。
    final later = today18.add(Duration(days: 4));

    final (importance, due) = switch (to) {
      _Q.q1 => (3, today18),
      _Q.q2 => (2, later),
      _Q.q3 => (1, today18),
      // 「有空再说」只降重要性，不动用户已经设好的日期。
      _Q.q4 => (0, task.dueAt),
    };

    final beforeImp = task.importance;
    final beforeDue = task.dueAt;
    await repo.updateTask(task.id, importance: importance, dueAt: due);
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 4),
          content: Text(trf('已移到「{}」', [to.label])),
          action: SnackBarAction(
            label: tr('撤销'),
            onPressed: () => beforeDue == null
                ? repo.updateTask(
                    task.id,
                    importance: beforeImp,
                    clearDue: true,
                  )
                : repo.updateTask(
                    task.id,
                    importance: beforeImp,
                    dueAt: beforeDue,
                  ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    final now = DateTime.now();
    final urgentBefore = now.add(Duration(days: 3));

    List<Task> bucket({required bool important, required bool urgent}) =>
        tasks.where((t) {
          // 已完成的不进矩阵：它已经不是「待安排的事」了。
          if (t.status != 0) return false;
          final isImportant = t.importance >= 2;
          final isUrgent = t.dueAt != null && !t.dueAt!.isAfter(urgentBefore);
          return isImportant == important && isUrgent == urgent;
        }).toList()..sort((a, b) => b.importance.compareTo(a.importance));

    Widget cell(_Q q, Color color, List<Task> items) => _Quadrant(
      quadrant: q,
      color: color,
      tasks: items,
      rule: switch (q) {
        _Q.q1 => tr('重要 · 3 天内'),
        _Q.q2 => tr('重要 · 以后'),
        _Q.q3 => tr('不重要 · 3 天内'),
        _Q.q4 => tr('不重要 · 以后'),
      },
      onDrop: (t) => _move(context, ref, t, q),
    );

    // 两行两列；高度由同一行里内容多的那一格决定，格内不滚动。
    Widget row(Widget left, Widget right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          SizedBox(width: 8),
          Expanded(child: right),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 96),
      child: Column(
        children: [
          row(
            cell(_Q.q1, palette.high, bucket(important: true, urgent: true)),
            cell(_Q.q2, palette.medium, bucket(important: true, urgent: false)),
          ),
          SizedBox(height: 8),
          row(
            cell(_Q.q3, palette.low, bucket(important: false, urgent: true)),
            cell(_Q.q4, palette.none, bucket(important: false, urgent: false)),
          ),
        ],
      ),
    );
  }
}

enum _Q {
  q1('马上做'),
  q2('计划做'),
  q3('尽快脱手'),
  q4('有空再说');

  const _Q(this._label);
  final String _label;

  String get label => tr(_label);
}

class _Quadrant extends StatelessWidget {
  const _Quadrant({
    required this.quadrant,
    required this.color,
    required this.tasks,
    required this.rule,
    required this.onDrop,
  });

  final _Q quadrant;
  final Color color;
  final List<Task> tasks;

  /// 这一格的判定规则，写在标题下——四象限最容易被问「凭什么在这里」。
  final String rule;
  final void Function(Task) onDrop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: color.withValues(alpha: hovering ? 0.16 : 0.07),
            borderRadius: BorderRadius.circular(AppTokens.radiusCard),
            border: hovering
                ? Border.all(color: color.withValues(alpha: 0.55), width: 1.4)
                : null,
          ),
          padding: EdgeInsets.fromLTRB(10, 9, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    quadrant.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '${tasks.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 1),
              Text(
                rule,
                style: TextStyle(
                  fontSize: 8.5,
                  color: color.withValues(alpha: 0.55),
                ),
              ),
              // 空象限只留标题：不写「拖到这里」，那行字在四宫格里最像噪音。
              if (tasks.isNotEmpty) ...[
                SizedBox(height: 6),
                for (var i = 0; i < tasks.length; i++) ...[
                  if (i > 0) SizedBox(height: 5),
                  _card(context, scheme, tasks[i]),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _card(BuildContext context, ColorScheme scheme, Task t) {
    final card = Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      padding: EdgeInsets.fromLTRB(9, 7, 8, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, height: 1.35),
          ),
          if (t.dueAt != null) ...[
            SizedBox(height: 2),
            Text(
              DateFormat('M-d HH:mm').format(t.dueAt!),
              style: TextStyle(fontSize: 8.5, color: Color(0xFF9AA0A8)),
            ),
          ],
        ],
      ),
    );
    return LongPressDraggable<Task>(
      data: t,
      delay: Duration(milliseconds: 220),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 150,
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 12,
              ),
            ],
          ),
          child: Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.hasQuery});

  final bool hasQuery;

  /// 三条示例覆盖「有日期 / 无日期 / 高重要性」三种形态，
  /// 让第一次打开的人知道这应用能记什么，而不是只看到一句空话。
  Future<void> _seed(WidgetRef ref) async {
    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 18);
    await repo.create(
      title: tr('交周报'),
      importance: 3,
      dueAt: today,
      notes: tr('示例任务：周五 18:00 的固定动作'),
    );
    await repo.create(
      title: tr('读 20 页书'),
      importance: 1,
      notes: tr('示例任务：没有日期也能先记下来'),
    );
    await repo.create(
      title: tr('回顾这周做完的事'),
      importance: 2,
      dueAt: today.add(Duration(days: 2)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.task_alt,
            size: 40,
            color: scheme.outline,
          ),
          SizedBox(height: 10),
          Text(
            hasQuery ? tr('没有匹配的任务') : tr('今天没有安排'),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (!hasQuery) ...[
            SizedBox(height: 4),
            Text(
              tr('点右下角 + 记一条，或先用示例上手'),
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            SizedBox(height: 16),
            Container(
              width: 260,
              padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('三条示例'),
                    style: TextStyle(fontSize: 10, color: scheme.outline),
                  ),
                  SizedBox(height: 6),
                  for (final line in [
                    tr('今天 18:00 交周报（高）'),
                    tr('读 20 页书（无日期）'),
                    tr('两天后 回顾这周'),
                  ])
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Icon(Icons.add, size: 12, color: scheme.primary),
                          SizedBox(width: 6),
                          Text(line, style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _seed(ref),
                      child: Text(
                        tr('添加示例并体验'),
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.initialDue, this.initialListId});

  final DateTime? initialDue;
  final String? initialListId;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _controller = TextEditingController();
  int _importance = 0;
  DateTime? _dueAt;
  QuickParse _parsed = QuickParse(title: '');
  bool _dateManual = false;
  late final String _listId;

  @override
  void initState() {
    super.initState();
    _dueAt = widget.initialDue;
    _listId = widget.initialListId ?? ref.read(settingsProvider).defaultListId;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final parsed = parseQuickAdd(_controller.text);
    setState(() {
      _parsed = parsed;
      if (parsed.importance != null) _importance = parsed.importance!;
      if (!_dateManual && parsed.dueAt != null) _dueAt = parsed.dueAt;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteProvider);
    final scheme = Theme.of(context).colorScheme;
    final bottom = sheetBottomInset(context) - 16;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      hintText: tr('写点什么…'),
                      border: InputBorder.none,
                      filled: false,
                    ),
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    final title = _parsed.title.isEmpty
                        ? _controller.text.trim()
                        : _parsed.title;
                    final due = _dueAt;
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TaskCreatePage(
                          initialTitle: title.isEmpty ? null : title,
                          initialDue: due,
                        ),
                      ),
                    );
                  },
                  child: Text(tr('高级模式'), style: TextStyle(fontSize: 12.5)),
                ),
                SizedBox(width: 2),
                FilledButton(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: Size(0, 34),
                  ),
                  onPressed: _save,
                  child: Text(tr('保存'), style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
            if (!_parsed.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 4, bottom: 2),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (_dueAt != null)
                      _parseChip(
                        context,
                        Icons.event_outlined,
                        _dateChipLabel(_dueAt!),
                        onClear: () => setState(() {
                          _dateManual = true;
                          _dueAt = null;
                        }),
                      ),
                    if (_parsed.importance != null)
                      _parseChip(
                        context,
                        Icons.flag_outlined,
                        Emphasis.fromValue(_parsed.importance!).label,
                        onClear: () => setState(() => _importance = 0),
                      ),
                    for (final t in _parsed.tags)
                      _parseChip(context, Icons.tag, '#$t', onClear: null),
                  ],
                ),
              ),
            Divider(height: 20),
            Row(
              children: [
                Text(
                  tr('重要性'),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: 10),
                for (final e in Emphasis.values)
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _importance = e.value),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: e == Emphasis.none
                              ? Colors.transparent
                              : palette.of(e),
                          border: Border.all(
                            color: e == Emphasis.none
                                ? scheme.outline
                                : palette.of(e),
                            width: 1.5,
                          ),
                        ),
                        foregroundDecoration: _importance == e.value
                            ? BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.35,
                                  ),
                                  width: 2,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                SizedBox(width: 4),
                Text(
                  Emphasis.fromValue(_importance).label,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(tr('今天')),
                  selected: _sameDay(_dueAt, DateTime.now()),
                  onSelected: (_) => setState(() {
                    _dateManual = true;
                    _dueAt = DateTime.now().copyWith(hour: 18, minute: 0);
                  }),
                ),
                ChoiceChip(
                  label: Text(tr('明天')),
                  selected: _sameDay(
                    _dueAt,
                    DateTime.now().add(Duration(days: 1)),
                  ),
                  onSelected: (_) => setState(() {
                    _dateManual = true;
                    _dueAt = DateTime.now().add(Duration(days: 1));
                  }),
                ),
                ChoiceChip(
                  label: Text(tr('无日期')),
                  selected: _dueAt == null,
                  onSelected: (_) => setState(() {
                    _dateManual = true;
                    _dueAt = null;
                  }),
                ),
                ActionChip(
                  label: Text(tr('自定义…')),
                  onPressed: () async {
                    final res = await ScheduleSheet.show(
                      context,
                      initialDue: _dueAt,
                    );
                    if (res == null || !mounted) return;
                    setState(() {
                      _dateManual = true;
                      _dueAt = res.dueAt;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateChipLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    final prefix = switch (diff) {
      0 => tr('今天'),
      1 => tr('明天'),
      2 => tr('后天'),
      _ =>
        trf('{}-{} 周{}', [d.month, d.day, weekdayInitial(d.weekday)]),
    };
    return '$prefix ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _parseChip(
    BuildContext context,
    IconData icon,
    String label, {
    VoidCallback? onClear,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 5, 6, 5),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: scheme.primary),
          SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10.5, color: scheme.primary)),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.fromLTRB(3, 1, 1, 1),
                child: Icon(
                  Icons.close,
                  size: 11,
                  color: scheme.primary.withValues(alpha: 0.8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _parsed.title.isEmpty
        ? _controller.text.trim()
        : _parsed.title;
    if (title.isEmpty) return;
    final repo = ref.read(taskRepositoryProvider);
    final id = await repo.create(
      title: title,
      importance: _importance,
      dueAt: _dueAt,
      listId: _listId,
    );

    if (_parsed.tags.isNotEmpty) {
      final existing = ref.read(tagsProvider).value ?? <Tag>[];
      final ids = <String>[];
      for (final name in _parsed.tags) {
        final hit = existing.where((t) => t.name == name).firstOrNull;
        ids.add(hit?.id ?? (await repo.createTag(name)).id);
      }
      await repo.setTaskTags(id, ids);
    }

    if (mounted) Navigator.of(context).pop();
  }
}

/// 首页常驻的专注胶囊：有进行中的会话才出现。
/// 点一下回专注页，右两枚按钮分别是暂停/继续与全屏。
class _FocusPill extends ConsumerWidget {
  const _FocusPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(focusControllerProvider);
    // 结束时保留一条绿色「已完成」，否则胶囊一消失，用户根本不知道计时结束了。
    if (!s.active && !s.finished) return SizedBox.shrink();
    final done = s.finished;
    final taskLabel = (s.taskTitle?.isNotEmpty ?? false)
        ? s.taskTitle!
        : tr('自由专注');

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Material(
        color: done ? context.appColors.done : Color(0xFF1F2328),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => FocusPage())),
          child: SizedBox(
            height: 38,
            child: Row(
              children: [
                SizedBox(width: 11),
                Icon(
                  done ? Icons.check_circle_outline : Icons.timer_outlined,
                  size: 15,
                  color: Colors.white,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    done
                        ? trf('专注完成 · {} 分钟 · 点击查看', [(s.actualSec / 60).round()])
                        : s.running
                        ? trf('专注中 · {}', [taskLabel])
                        : trf('已暂停 · {}', [taskLabel]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: done ? Colors.white : Color(0xFFB8BEC6),
                    ),
                  ),
                ),
                if (!done) ...[
                  Text(
                    s.remainingText,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(width: 2),
                  _pillButton(
                    s.running ? Icons.pause : Icons.play_arrow,
                    () => ref.read(focusControllerProvider.notifier).toggle(),
                  ),
                  _pillButton(
                    Icons.open_in_full,
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FocusFullscreenPage(),
                      ),
                    ),
                  ),
                ],
                SizedBox(width: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pillButton(IconData icon, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: EdgeInsets.all(7),
        child: Icon(icon, size: 15, color: Colors.white),
      ),
    );
  }
}
