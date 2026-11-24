import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../memos/note_repository.dart';
import '../settings/settings.dart';
import '../tasks/task_repository.dart';
import 'focus_controller.dart';
import 'focus_fullscreen_page.dart';
import 'focus_repository.dart';
import 'white_noise.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 专注页。
///
/// 计时状态放在全局（[focusControllerProvider]），离开页面不中断，
/// 首页顶部的胶囊能随时回到这里；本轮结束先给结算页，再决定下一轮。
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({
    super.key,
    this.initialTaskId,
    this.initialTaskTitle,
    this.initialTitle,
  });

  final String? initialTaskId;
  final String? initialTaskTitle;

  /// 只带标题（例如从习惯进入），不关联任务。
  final String? initialTitle;

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  static const _presets = [15, 25, 45];
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 从任务详情进来时带上任务；已有进行中的会话则不覆盖。
    final id = widget.initialTaskId;
    final freeTitle = widget.initialTitle;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(focusControllerProvider);
      if (s.started) return;
      final c = ref.read(focusControllerProvider.notifier);
      if (id != null) {
        c.selectTask(id, widget.initialTaskTitle);
      } else if (freeTitle != null && freeTitle.isNotEmpty) {
        c.selectFree(freeTitle);
      }
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  FocusController get _c => ref.read(focusControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(focusControllerProvider);
    final tasks = ref.watch(openTasksProvider).value ?? const <Task>[];
    final todayMinutes = ref.watch(focusTodayMinutesProvider).value ?? 0;
    final minutes = (s.plannedSec / 60).round();
    final noise = ref.watch(whiteNoiseProvider);
    final linked = tasks.where((t) => t.id == s.taskId).firstOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 6, 4),
              child: Row(
                children: [
                  Text(
                    tr('专注'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  Text(
                    trf('今日 {} 分钟', [todayMinutes]),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (s.active)
                    IconButton(
                      tooltip: tr('全屏专注'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FocusFullscreenPage(),
                        ),
                      ),
                      icon: Icon(Icons.fullscreen, size: 21),
                    ),
                  // 设置都收进右上角：关联任务、白噪音、实时时间。
                  IconButton(
                    tooltip: tr('专注设置'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showFocusSettings(context),
                    icon: Icon(Icons.tune, size: 20),
                  ),
                ],
              ),
            ),
            // 关联任务保持「页面上直接选」的方式：比藏进设置面板少一步。
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: DropdownButtonFormField<String?>(
                initialValue: s.taskId,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  hintText: tr('关联任务（可选）'),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  prefixIcon: Icon(
                    linked != null && linked.importance >= 3
                        ? Icons.priority_high
                        : Icons.center_focus_strong_outlined,
                    size: 16,
                    color: linked != null && linked.importance >= 3
                        ? context.appColors.warn
                        : scheme.onSurfaceVariant,
                  ),
                  prefixIconConstraints: BoxConstraints(
                    minWidth: 32,
                    minHeight: 20,
                  ),
                ),
                style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(tr('不关联任务'), style: TextStyle(fontSize: 12.5)),
                  ),
                  for (final t in tasks.take(30))
                    DropdownMenuItem<String?>(
                      value: t.id,
                      child: Text(
                        t.importance >= 3 ? '⚡ ${t.title}' : t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                ],
                onChanged: s.running
                    ? null
                    : (v) {
                        final t = tasks.where((e) => e.id == v).firstOrNull;
                        ref
                            .read(focusControllerProvider.notifier)
                            .selectTask(v, t?.title);
                      },
              ),
            ),
            // 结算页自带 ListView（自己滚），所以两种状态分开：
            // 只有圆环需要「内容超高时可滚 + 默认居中」这层约束。
            Expanded(
              child: s.finished
                  ? _settle(scheme, s, todayMinutes)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: _ring(scheme, s, minutes),
                          ),
                        );
                      },
                    ),
            ),
            // 主操作固定在这里：圆环区域可以滚动，但「开始专注」必须一屏可见。
            if (!s.finished)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: s.inBreak
                            ? _c.skipBreak
                            : (s.running ? _c.pause : _c.start),
                        child: Text(
                          s.inBreak
                              ? tr('跳过休息')
                              : (s.running
                                    ? tr('暂停')
                                    : (s.started ? tr('继续') : tr('开始专注'))),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: s.started ? _c.finishEarly : null,
                        child: Text(tr('结束')),
                      ),
                    ),
                  ],
                ),
              ),
            if (noise.active) _NoiseBar(state: noise),
            if (!s.finished)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  s.active
                      ? tr('计时在后台继续 · 回到首页会显示专注胶囊')
                      : tr('离开本页计时不中断 · 锁屏或切后台时通知栏会显示剩余时间'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ring(ColorScheme scheme, FocusState s, int minutes) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: s.progress.clamp(0, 1)),
                  duration: Duration(milliseconds: 950),
                  curve: Curves.linear,
                  builder: (context, value, _) => SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 7,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: scheme.primary,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.displayText,
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w300,
                        letterSpacing: -1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      s.phaseLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: s.inBreak
                            ? context.appColors.done
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    // 当前时间只在真正开始后出现，做成圆环内的一行小字：
                    // 不额外占高度，也不跟倒计时抢注意力。
                    if (ref.watch(settingsProvider).focusClock &&
                        s.started &&
                        !s.inBreak)
                      Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          DateFormat('HH:mm:ss').format(DateTime.now()),
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 0.8,
                            fontFeatures: [
                              FontFeature.tabularFigures(),
                            ],
                            color: scheme.outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          if (!s.started)
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(tr('倒计时'))),
                ButtonSegment(value: 1, label: Text(tr('正计时'))),
              ],
              selected: {s.mode},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _c.setMode(v.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStateProperty.all(
                  TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!s.countUp)
                for (final p in _presets)
                  ChoiceChip(
                    label: Text(trf('{} 分', [p])),
                    selected: minutes == p,
                    onSelected: s.started ? null : (_) => _c.configure(p),
                  ),
              ChoiceChip(
                avatar: Icon(Icons.edit, size: 14),
                label: Text(_presets.contains(minutes) ? tr('自定义') : trf('{} 分', [minutes])),
                selected: !_presets.contains(minutes),
                onSelected: s.started ? null : (_) => _pickCustom(minutes),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settle(ColorScheme scheme, FocusState s, int todayMinutes) {
    // 多组时「本次」要显示累计，而不是最后一组的时长。
    final minutes =
        ((s.totalActualSec > 0 ? s.totalActualSec : s.actualSec) / 60).round();
    return ListView(
      padding: EdgeInsets.fromLTRB(24, 18, 24, 16),
      children: [
        SizedBox(height: 10),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Color(0xFFE1F5EE),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, size: 26, color: context.appColors.done),
          ),
        ),
        SizedBox(height: 12),
        Center(
          child: Text(
            tr('完成一轮专注'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(height: 5),
        Center(
          child: Text(
            s.taskTitle == null || s.taskTitle!.isEmpty
                ? trf('{} 分钟 · 未关联任务', [minutes])
                : trf('{} 分钟，已记到「{}」', [minutes, s.taskTitle]),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
        SizedBox(height: 18),
        Row(
          children: [
            _stat(trf('{} 分', [minutes]), tr('本次')),
            SizedBox(width: 8),
            _stat(trf('{} 分', [todayMinutes]), tr('今日累计')),
            SizedBox(width: 8),
            _stat(s.running ? tr('进行中') : tr('已结束'), tr('状态')),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _addFiveMinutes,
                icon: Icon(Icons.add, size: 15),
                label: Text(tr('补记 5 分钟'), style: TextStyle(fontSize: 11.5)),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _correctDuration,
                icon: Icon(Icons.edit_outlined, size: 15),
                label: Text(tr('修正时长'), style: TextStyle(fontSize: 11.5)),
              ),
            ),
          ],
        ),
        SizedBox(height: 18),
        Text(
          tr('写了一句话'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 6),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(hintText: tr('这次卡在哪一步？下次怎么更快…')),
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        SizedBox(height: 10),
        Row(
          children: [
            OutlinedButton(
              onPressed: () async {
                final text = _note.text.trim();
                if (text.isEmpty) return;
                await ref
                    .read(noteRepositoryProvider)
                    .createNote(
                      title:
                          trf('专注心得 · {}-{}', [DateTime.now().month, DateTime.now().day]),
                      body: text,
                    );
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(tr('已存为备忘录'))));
              },
              child: Text(tr('存为备忘录')),
            ),
            Spacer(),
            TextButton(
              onPressed: () {
                _c.reset();
                Navigator.of(context).maybePop();
              },
              child: Text(tr('返回')),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _c.reset();
                  Navigator.of(context).maybePop();
                },
                child: Text(tr('休息一下')),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () {
                  _note.clear();
                  _c.again();
                },
                child: Text(tr('再来一轮')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }

  /// 真实使用里经常忘按开始、或多做了十分钟：结算页必须能改。
  Future<void> _addFiveMinutes() async {
    await ref.read(focusRepositoryProvider).adjustLatest(deltaSec: 300);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(persist: false, content: Text(tr('已补记 5 分钟到本轮'))),
      );
  }

  Future<void> _correctDuration() async {
    final controller = TextEditingController(
      text: '${(ref.read(focusControllerProvider).actualSec / 60).round()}',
    );
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('修正本轮时长')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: tr('实际分钟数，1–720'),
            suffixText: tr('分钟'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop((v == null || v < 1 || v > 720) ? null : v);
            },
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
    if (minutes == null) return;
    await ref
        .read(focusRepositoryProvider)
        .adjustLatest(absoluteSec: minutes * 60);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(persist: false, content: Text(trf('已改为 {} 分钟', [minutes]))),
      );
  }

  Future<void> _pickCustom(int current) async {
    final controller = TextEditingController(
      text: _presets.contains(current) ? '' : '$current',
    );
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('自定义专注时长')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: tr('分钟，1–180'),
            suffixText: tr('分钟'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop((v == null || v < 1 || v > 180) ? null : v);
            },
            child: Text(tr('确定')),
          ),
        ],
      ),
    );
    if (value == null) return;
    _c.configure(value);
  }
}

/// 白噪音播放条：播放时始终可见，暂停/继续就在手边。
class _NoiseBar extends ConsumerWidget {
  const _NoiseBar({required this.state});

  final NoiseState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final scene = state.scene;
    if (scene == null) return SizedBox.shrink();
    final controller = ref.read(whiteNoiseProvider.notifier);

    return Container(
      margin: EdgeInsets.fromLTRB(20, 2, 20, 6),
      padding: EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(scene.icon, size: 18, color: scheme.primary),
          SizedBox(width: 7),
          Text(
            scene.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.primary,
            ),
          ),
          if (state.paused) ...[
            SizedBox(width: 6),
            Text(
              tr('已暂停'),
              style: TextStyle(fontSize: 10.5, color: scheme.outline),
            ),
          ],
          Spacer(),
          // 播放/暂停做成实心圆按钮：这是播放时最常按的一个键。
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: controller.togglePlay,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                state.paused ? Icons.play_arrow : Icons.pause,
                size: 18,
                color: scheme.onPrimary,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: tr('关闭白噪音'),
            onPressed: controller.stop,
            icon: Icon(Icons.close, size: 17, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 专注设置：计时关联（含紧急任务）、白噪音、实时时间。
Future<void> showFocusSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FocusSettingsSheet(),
  );
}

class _FocusSettingsSheet extends ConsumerWidget {
  const _FocusSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final breakMin = settings.focusBreakMin;
    final cycleSel = settings.focusCycles;
    final noise = ref.watch(whiteNoiseProvider);
    final controller = ref.read(whiteNoiseProvider.notifier);
    final clock = ref.watch(settingsProvider).focusClock;
    final s = ref.watch(focusControllerProvider);

    Widget label(String text) => Padding(
      padding: EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
          children: [
            Text(
              tr('专注设置'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            label(tr('节奏')),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final m in [1, 3, 5, 10, 15])
                  ChoiceChip(
                    label: Text(trf('短休 {} 分', [m]), style: TextStyle(fontSize: 11)),
                    selected: breakMin == m,
                    onSelected: (_) {
                      ref.read(settingsProvider.notifier).setFocusBreak(m);
                      ref
                          .read(focusControllerProvider.notifier)
                          .setBreakMinutes(m);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Text(
                  tr('组数'),
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
                Expanded(
                  child: Slider(
                    value: cycleSel.toDouble().clamp(1, 8),
                    min: 1,
                    max: 8,
                    divisions: 7,
                    label: trf('{} 组', [cycleSel]),
                    onChanged: (v) {
                      final n = v.round();
                      ref.read(settingsProvider.notifier).setFocusCycles(n);
                      ref.read(focusControllerProvider.notifier).setCycles(n);
                    },
                  ),
                ),
                Text(
                  trf('{} 组', [cycleSel]),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Text(
              tr('每结束一组专注进入短休，短休结束自动开始下一组；') + trf('共 {} 组，合计约 {} 分钟', [cycleSel, (cycleSel * (s.plannedSec ~/ 60))]),
              style: TextStyle(fontSize: 10, color: scheme.outline, height: 1.5),
            ),
            Divider(height: 26),
            label(tr('白噪音')),
            Row(
              children: [
                for (final scene in NoiseScene.values) ...[
                  if (scene != NoiseScene.values.first) SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => controller.toggle(scene),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: noise.scene == scene
                              ? scheme.primaryContainer.withValues(alpha: 0.7)
                              : scheme.surfaceContainerHighest.withValues(
                                  alpha: 0.5,
                                ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              scene.icon,
                              size: 17,
                              color: noise.scene == scene
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            SizedBox(height: 3),
                            Text(
                              scene.label,
                              style: TextStyle(
                                fontSize: 10,
                                color: noise.scene == scene
                                    ? scheme.primary
                                    : scheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                Icon(
                  Icons.volume_down,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Slider(
                    value: noise.volume,
                    onChanged: noise.active ? controller.setVolume : null,
                  ),
                ),
                Icon(Icons.volume_up, size: 15, color: scheme.onSurfaceVariant),
              ],
            ),
            label(tr('显示')),
            SwitchListTile(
              value: clock,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setFocusClock(v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('显示实时时间'), style: TextStyle(fontSize: 13)),
              subtitle: Text(
                tr('在圆环内显示当前时钟（仅专注开始后）'),
                style: TextStyle(fontSize: 10.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
