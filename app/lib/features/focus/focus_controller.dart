import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/focus_service.dart';
import '../../platform/notification_service.dart';
import '../settings/settings.dart';
import 'focus_repository.dart';
import '../../core/i18n/i18n.dart';

/// 专注会话状态。
///
/// 支持「专注 → 短休 → 下一组」的循环：`phase` 0 专注 / 1 短休，
/// `cycleIndex` 是当前第几组（1-based），`cycles` 是总组数。
/// 每段专注结束都单独落一条 session，中途退出也不会丢已经专注的时间。
class FocusState {
  const FocusState({
    this.plannedSec = 25 * 60,
    this.remainingSec = 25 * 60,
    this.elapsedSec = 0,
    this.mode = 0, // 0 倒计时 1 正计时
    this.running = false,
    this.taskId,
    this.taskTitle,
    this.finished = false,
    this.breakCount = 0,
    this.cycles = 1,
    this.cycleIndex = 1,
    this.breakSec = 5 * 60,
    this.phase = 0, // 0 专注 1 短休
    this.totalActualSec = 0,
  });

  final int plannedSec;
  final int remainingSec;
  final int elapsedSec;
  final int mode;
  final bool running;
  final String? taskId;
  final String? taskTitle;

  /// 整轮刚结束（用于展示结算页），确认后复位。
  final bool finished;

  /// 微休息提示次数。每次 +1 让界面能弹一次「起身活动」。
  final int breakCount;

  final int cycles;
  final int cycleIndex;
  final int breakSec;
  final int phase;

  /// 本轮累计的专注秒数（跨组累加，不含短休）。
  /// 结算页与结束通知都必须用它，否则多组时只会显示最后一段。
  final int totalActualSec;

  bool get countUp => mode == 1;
  bool get inBreak => phase == 1;
  bool get multiCycle => cycles > 1;

  int get actualSec {
    if (inBreak) return 0;
    return countUp ? elapsedSec : plannedSec - remainingSec;
  }

  double get progress {
    if (inBreak) {
      return breakSec == 0 ? 0 : (1 - remainingSec / breakSec).clamp(0.0, 1.0);
    }
    if (countUp) return (elapsedSec % 60) / 60;
    return plannedSec == 0 ? 0 : (1 - remainingSec / plannedSec).clamp(0.0, 1.0);
  }

  bool get started => inBreak
      ? true
      : (countUp ? elapsedSec > 0 : remainingSec < plannedSec);

  bool get active => started && !finished;

  String get remainingText {
    final m = (remainingSec ~/ 60).toString().padLeft(2, '0');
    final s = (remainingSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get elapsedText {
    final h = elapsedSec ~/ 3600;
    final m = ((elapsedSec % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSec % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// 屏幕上显示的那个数字：休息时一定是倒计时。
  String get displayText =>
      inBreak ? remainingText : (countUp ? elapsedText : remainingText);

  /// 圆环下方那一行状态文案。
  String get phaseLabel {
    if (inBreak) return trf('短休中 · 下一组是第 {}/{} 组', [cycleIndex + 1, cycles]);
    if (countUp) return running ? tr('正计时中') : tr('正计时 · 已停止');
    if (running) return multiCycle ? trf('专注中 · 第 {}/{} 组', [cycleIndex, cycles]) : tr('专注中');
    if (started) return tr('已暂停');
    return multiCycle
        ? trf('共 {} 组 · 每组 {} 分钟', [cycles, plannedSec ~/ 60])
        : trf('共 {} 分钟', [plannedSec ~/ 60]);
  }

  FocusState copyWith({
    int? plannedSec,
    int? remainingSec,
    int? elapsedSec,
    int? mode,
    bool? running,
    String? taskId,
    String? taskTitle,
    bool? finished,
    int? breakCount,
    int? cycles,
    int? cycleIndex,
    int? breakSec,
    int? phase,
    int? totalActualSec,
    bool clearTask = false,
  }) => FocusState(
    plannedSec: plannedSec ?? this.plannedSec,
    remainingSec: remainingSec ?? this.remainingSec,
    elapsedSec: elapsedSec ?? this.elapsedSec,
    mode: mode ?? this.mode,
    running: running ?? this.running,
    taskId: clearTask ? null : (taskId ?? this.taskId),
    taskTitle: clearTask ? null : (taskTitle ?? this.taskTitle),
    finished: finished ?? this.finished,
    breakCount: breakCount ?? this.breakCount,
    cycles: cycles ?? this.cycles,
    cycleIndex: cycleIndex ?? this.cycleIndex,
    breakSec: breakSec ?? this.breakSec,
    phase: phase ?? this.phase,
    totalActualSec: totalActualSec ?? this.totalActualSec,
  );
}

class FocusController extends Notifier<FocusState> {
  Timer? _timer;

  /// 上次微休息提示时的已专注秒数。
  int _breakMark = 0;

  @override
  FocusState build() {
    ref.onDispose(() => _timer?.cancel());
    final settings = ref.read(settingsProvider);
    return FocusState(
      breakSec: settings.focusBreakMin * 60,
      cycles: settings.focusCycles,
    );
  }

  /// 选时长；已开始则忽略，避免中途改总量。
  void configure(int minutes) {
    if (state.running || state.started) return;
    final sec = minutes.clamp(1, 180) * 60;
    state = state.copyWith(
      plannedSec: sec,
      remainingSec: sec,
      finished: false,
      phase: 0,
    );
  }

  void setMode(int mode) {
    if (state.running || state.started) return;
    state = state.copyWith(mode: mode, finished: false);
  }

  /// 短休时长（分钟）。进行中也能改，下一轮生效。
  void setBreakMinutes(int minutes) {
    final sec = minutes.clamp(1, 60) * 60;
    state = state.copyWith(breakSec: sec);
    if (!state.running && state.inBreak) {
      state = state.copyWith(remainingSec: sec);
    }
  }

  /// 组数。只在未开始时真正生效。
  void setCycles(int cycles) {
    final n = cycles.clamp(1, 8);
    state = state.copyWith(cycles: n);
    if (!state.running && !state.started) {
      state = state.copyWith(cycleIndex: 1, finished: false);
    }
  }

  void selectTask(String? id, String? title) {
    if (state.running) return;
    if (id == null) {
      state = state.copyWith(clearTask: true);
    } else {
      state = state.copyWith(taskId: id, taskTitle: title ?? '');
    }
  }

  /// 不带任务、只带一个标题（习惯联动专注时用）。
  void selectFree(String? title) {
    if (state.running) return;
    state = FocusState(
      plannedSec: state.plannedSec,
      remainingSec: state.remainingSec,
      mode: state.mode,
      taskTitle: title,
      cycles: state.cycles,
      breakSec: state.breakSec,
    );
  }

  void start() {
    if (state.running) return;
    if (state.finished) {
      state = state.copyWith(
        remainingSec: state.inBreak ? state.breakSec : state.plannedSec,
        elapsedSec: 0,
        finished: false,
        phase: 0,
        cycleIndex: 1,
      );
    }
    state = state.copyWith(running: true);
    _syncForeground();
    _runTimer();
  }

  void _runTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 1), (_) {
      if (!state.inBreak && state.countUp) {
        state = state.copyWith(elapsedSec: state.elapsedSec + 1);
        _maybeMicroBreak();
        return;
      }
      final left = state.remainingSec - 1;
      if (left <= 0) {
        _timer?.cancel();
        state = state.copyWith(remainingSec: 0, running: false);
        _onPhaseEnd();
      } else {
        state = state.copyWith(remainingSec: left);
        if (!state.inBreak) _maybeMicroBreak();
      }
    });
  }

  /// 一段到点：专注段先落库，再看要不要休息 / 进入下一组 / 收尾。
  Future<void> _onPhaseEnd() async {
    if (state.inBreak) {
      if (state.cycleIndex >= state.cycles) {
        await _finish();
      } else {
        _nextCycle();
      }
      return;
    }
    await _persistSession();
    if (state.cycleIndex >= state.cycles) {
      await _finish();
    } else {
      _enterBreak();
    }
  }

  void _enterBreak() {
    state = state.copyWith(
      phase: 1,
      remainingSec: state.breakSec,
      elapsedSec: 0,
      running: true,
    );
    _syncForeground();
    _runTimer();
  }

  void _nextCycle() {
    state = state.copyWith(
      phase: 0,
      cycleIndex: state.cycleIndex + 1,
      remainingSec: state.plannedSec,
      elapsedSec: 0,
      running: true,
    );
    _syncForeground();
    _runTimer();
  }

  /// 休息中「跳过休息」，直接进下一组。
  void skipBreak() {
    if (!state.inBreak) return;
    _timer?.cancel();
    if (state.cycleIndex >= state.cycles) {
      _finish();
    } else {
      _nextCycle();
    }
  }

  void pause() {
    _timer?.cancel();
    state = state.copyWith(running: false);
    FocusForegroundService.stop();
  }

  void _syncForeground() {
    final s = state;
    final endAt = DateTime.now().add(Duration(seconds: s.remainingSec));
    FocusForegroundService.start(
      title: s.inBreak
          ? trf('短休 {} 分钟', [(s.breakSec / 60).round()])
          : ((s.taskTitle?.isNotEmpty ?? false) ? s.taskTitle! : tr('自由专注')),
      endAt: endAt,
    );
  }

  void toggle() => state.running ? pause() : start();

  /// 提前结束：不足 30 秒视为误触（休息段直接跳过）。
  Future<void> finishEarly() async {
    _timer?.cancel();
    if (!state.inBreak && state.actualSec < 30) {
      reset();
      return;
    }
    state = state.copyWith(running: false);
    if (!state.inBreak) await _persistSession();
    await _finish();
  }

  /// 每段专注单独入库：中途退出也不会丢已经专注的时间。
  Future<void> _persistSession() async {
    final s = state;
    if (s.actualSec < 30) return;
    state = state.copyWith(
      totalActualSec: state.totalActualSec + s.actualSec,
    );
    await ref
        .read(focusRepositoryProvider)
        .saveSession(
          taskId: s.taskId,
          plannedSec: s.countUp ? 0 : s.plannedSec,
          actualSec: s.actualSec,
          mode: s.mode,
        );
  }

  Future<void> _finish() async {
    final s = state;
    state = s.copyWith(finished: true, running: false, phase: 0);
    FocusForegroundService.stop();
    // 用实际累计时长，不用「计划 × 组数」——提前结束时后者会报出没做过的分钟数。
    final actual = state.totalActualSec > 0
        ? state.totalActualSec
        : s.actualSec;
    await NotificationService.showFocusDone(
      title: (s.taskTitle?.isNotEmpty ?? false) ? s.taskTitle! : '',
      minutes: (actual / 60).round(),
    );
  }

  /// 结算完成：清零，保留时长与组数选择。
  void reset() {
    _timer?.cancel();
    _breakMark = 0;
    FocusForegroundService.stop();
    state = FocusState(
      plannedSec: state.plannedSec,
      remainingSec: state.plannedSec,
      mode: state.mode,
      taskId: state.taskId,
      taskTitle: state.taskTitle,
      cycles: state.cycles,
      breakSec: state.breakSec,
    );
  }

  /// 结算页的「再来一轮」。
  void again() {
    reset();
    start();
  }

  /// 连续专注满 50 分钟提示一次起身。做成「不打断」的旁路提示：
  /// 计时继续走，只是提醒你活动一下——打断计时反而会让人不敢用。
  void _maybeMicroBreak() {
    if (!ref.read(settingsProvider).microBreak) return;
    final elapsed = state.countUp
        ? state.elapsedSec
        : state.plannedSec - state.remainingSec;
    const step = 50 * 60;
    if (elapsed < _breakMark + step) return;
    _breakMark = elapsed;
    state = state.copyWith(breakCount: state.breakCount + 1);
    NotificationService.showMicroBreak(minutes: elapsed ~/ 60);
  }
}

final focusControllerProvider = NotifierProvider<FocusController, FocusState>(
  FocusController.new,
);

/// 首页胶囊用：只在有进行中的会话时返回状态。
final focusPillProvider = Provider<FocusState?>((ref) {
  final s = ref.watch(focusControllerProvider);
  return s.active ? s : null;
});
