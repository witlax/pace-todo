import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/log/app_log.dart';
import '../tasks/task_repository.dart';
import 'focus_controller.dart';
import '../../core/i18n/i18n.dart';

/// 全屏专注（ADR-0015）。
///
/// 三条硬规则：
/// 1. 竖屏单列、横屏双列，旋转不重置计时；
/// 2. 剩余时间每秒走，真实时间每 10 秒走（整分立即刷新）；
/// 3. 本轮开始后新建的任务只以低对比提示条出现，不弹窗、不抢焦点。
class FocusFullscreenPage extends ConsumerStatefulWidget {
  const FocusFullscreenPage({super.key});

  @override
  ConsumerState<FocusFullscreenPage> createState() =>
      _FocusFullscreenPageState();
}

class _FocusFullscreenPageState extends ConsumerState<FocusFullscreenPage> {
  late final DateTime _startedAt = DateTime.now();

  Timer? _clockTicker;
  Timer? _chromeTimer;
  bool _chromeVisible = true;
  bool _bannerDismissed = false;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _clockTicker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _scheduleChromeHide();
    AppLog.i(tr('进入全屏专注'));
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    _chromeTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    _chromeTimer = Timer(Duration(seconds: 3), () {
      if (mounted && ref.read(focusControllerProvider).running) {
        setState(() => _chromeVisible = false);
      }
    });
  }

  void _toggleRun() {
    ref.read(focusControllerProvider.notifier).toggle();
    setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  Future<void> _finish() async {
    await ref.read(focusControllerProvider.notifier).finishEarly();
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  String get _remainingText => ref.read(focusControllerProvider).displayText;

  String get _endAtText {
    final end = _now.add(
      Duration(seconds: ref.read(focusControllerProvider).remainingSec),
    );
    return trf('预计 {} 结束', [DateFormat('HH:mm').format(end)]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    // 只认本轮开始之后新建、且仍未完成的主任务。
    final tasks = ref.watch(openTasksProvider).value ?? <Task>[];
    final fresh = tasks
        .where(
          (t) =>
              t.createdAt.isAfter(_startedAt) &&
              t.status == 0 &&
              t.parentId == null,
        )
        .toList();

    return Scaffold(
      backgroundColor: scheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _chromeVisible = true);
          if (ref.read(focusControllerProvider).running) _scheduleChromeHide();
        },
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: landscape
                    ? _landscapeBody(scheme)
                    : _portraitBody(scheme),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: AnimatedOpacity(
                  opacity: _chromeVisible ? 1 : 0,
                  duration: Duration(milliseconds: 400),
                  child: IconButton(
                    tooltip: tr('退出全屏'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_fullscreen, size: 20),
                  ),
                ),
              ),
              if (fresh.isNotEmpty && !_bannerDismissed)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: landscape ? 12 : 24,
                  child: _NewTasksBanner(
                    tasks: fresh,
                    onOpen: () => _showNewTasks(fresh),
                    onDismiss: () => setState(() => _bannerDismissed = true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _portraitBody(ColorScheme scheme) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                DateFormat('HH:mm').format(_now),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Spacer(),
              Text(
                (ref.read(focusControllerProvider).countUp
                    ? tr('正计时')
                    : trf('共 {} 分钟', [(ref.read(focusControllerProvider).plannedSec / 60).round()])),
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ],
          ),
          Spacer(),
          Center(
            child: Text(
              _remainingText,
              style: TextStyle(
                fontSize: 76,
                fontWeight: FontWeight.w200,
                letterSpacing: -2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(height: 10),
          Center(
            child: Text(
              (ref.watch(focusControllerProvider).taskTitle?.isNotEmpty == true
                  ? ref.watch(focusControllerProvider).taskTitle!
                  : tr('自由专注')),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
            ),
          ),
          SizedBox(height: 6),
          Center(
            child: Text(
              _endAtText,
              style: TextStyle(fontSize: 11.5, color: scheme.outline),
            ),
          ),
          Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 108,
                child: OutlinedButton(
                  onPressed: _toggleRun,
                  child: Text(
                    ref.watch(focusControllerProvider).running ? tr('暂停') : tr('开始'),
                  ),
                ),
              ),
              SizedBox(width: 12),
              SizedBox(
                width: 108,
                child: FilledButton(
                  onPressed: _finish,
                  child: Text(tr('结束')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _landscapeBody(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          flex: 6,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _remainingText,
                style: TextStyle(
                  fontSize: 104,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  (ref.watch(focusControllerProvider).taskTitle?.isNotEmpty ==
                          true
                      ? ref.watch(focusControllerProvider).taskTitle!
                      : tr('自由专注')),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  DateFormat('HH:mm').format(_now),
                  style: TextStyle(
                    fontSize: 22,
                    color: scheme.onSurfaceVariant,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _endAtText,
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
                Spacer(),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _toggleRun,
                      child: Text(
                        ref.watch(focusControllerProvider).running
                            ? tr('暂停')
                            : tr('开始'),
                      ),
                    ),
                    SizedBox(width: 10),
                    FilledButton(onPressed: _finish, child: Text(tr('结束'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showNewTasks(List<Task> tasks) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Text(
                      trf('专注中新加入 {} 个', [tasks.length]),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              for (final t in tasks)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.radio_button_unchecked, size: 18),
                  title: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    ref.read(taskRepositoryProvider).setDone(t.id, true);
                    Navigator.of(ctx).pop();
                  },
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  tr('点击即完成，不离开专注。进详情会离开全屏，计时继续。'),
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewTasksBanner extends StatelessWidget {
  const _NewTasksBanner({
    required this.tasks,
    required this.onOpen,
    required this.onDismiss,
  });

  final List<Task> tasks;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, size: 16, color: scheme.onSurfaceVariant),
          SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Text(
                trf('专注中新加入 {} 个任务', [tasks.length]),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr('忽略'),
            onPressed: onDismiss,
            icon: Icon(Icons.close, size: 16, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}
