import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../focus/focus_repository.dart';
import '../habits/habit_repository.dart';
import '../mood/mood_repository.dart';
import '../tasks/task_repository.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 某一天的回顾：做完了什么、打了哪些卡、专注了多久。
///
/// 这是日历「按天总结」的落点——日历只负责指到哪一天，
/// 细节都在这一页，避免把月视图塞成一张报表。
class DayReviewPage extends ConsumerStatefulWidget {
  const DayReviewPage({super.key, required this.date});

  final DateTime date;

  @override
  ConsumerState<DayReviewPage> createState() => _DayReviewPageState();
}

class _DayReviewPageState extends ConsumerState<DayReviewPage> {
  final _shotKey = GlobalKey();
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final date = widget.date;
    final scheme = Theme.of(context).colorScheme;
    final completed =
        ref.watch(completionHeatmapProvider).value ?? const <Task>[];
    final habits = ref.watch(habitsProvider).value ?? const <Habit>[];
    final logs = ref.watch(habitLogsProvider).value ?? const <HabitLog>[];
    final sessions =
        ref.watch(focusThisWeekProvider).value ?? const <FocusSession>[];
    final tasks = ref.watch(allActiveTasksProvider).value ?? const <Task>[];

    final key = dayKey(date);
    final dayDone = completed.where((t) {
      final at = t.completedAt;
      return at != null &&
          at.year == date.year &&
          at.month == date.month &&
          at.day == date.day;
    }).toList();

    final dayLogs = logs.where((l) => l.date == key).toList();
    final habitName = {for (final h in habits) h.id: h.name};

    final daySessions = sessions.where((s) {
      final at = s.startedAt;
      return at.year == date.year &&
          at.month == date.month &&
          at.day == date.day;
    }).toList();
    final focusMinutes = daySessions.fold<int>(
      0,
      (a, s) => a + ((s.actualSec ?? 0) ~/ 60),
    );
    final titleOf = {for (final t in tasks) t.id: t.title};

    final moods = ref.watch(moodEntriesProvider).value ?? const <MoodEntry>[];
    final dayMood = moods.where((m) => m.date == moodDayKey(date)).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(dfMonthDayWeekFmt().format(date)),
        actions: [
          IconButton(
            tooltip: tr('导出为图片'),
            onPressed: _exporting ? null : _exportPng,
            icon: _exporting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.ios_share, size: 20),
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _shotKey,
        child: Material(
          color: scheme.surface,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 56),
            children: [
              Row(
                children: [
                  _stat(context, '${dayDone.length}', tr('完成任务')),
                  SizedBox(width: 10),
                  _stat(context, '${dayLogs.length}', tr('习惯打卡')),
                  SizedBox(width: 10),
                  _stat(
                    context,
                    focusMinutes >= 60
                        ? '${focusMinutes ~/ 60}h${focusMinutes % 60 == 0 ? '' : focusMinutes % 60}m'
                        : '${focusMinutes}m',
                    tr('专注时长'),
                  ),
                ],
              ),
              SizedBox(height: 22),
              _section(tr('完成的任务'), scheme),
              if (dayDone.isEmpty)
                _empty(scheme)
              else
                for (final t in dayDone)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.completedAt == null
                              ? ''
                              : DateFormat('HH:mm').format(t.completedAt!),
                          style: TextStyle(fontSize: 11, color: scheme.outline),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                style: TextStyle(fontSize: 13),
                              ),
                              if ((t.completedSummary ?? '').isNotEmpty)
                                Text(
                                  t.completedSummary!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.5,
                                    color: scheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              SizedBox(height: 20),
              _section(tr('习惯打卡'), scheme),
              if (dayLogs.isEmpty)
                _empty(scheme)
              else
                for (final l in dayLogs)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: context.appColors.done,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                habitName[l.habitId] ?? tr('已删除的习惯'),
                                style: TextStyle(fontSize: 13),
                              ),
                              if ((l.note ?? '').isNotEmpty)
                                Text(
                                  l.note!,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.5,
                                    color: scheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              SizedBox(height: 20),
              _section(tr('心情'), scheme),
              if (dayMood == null)
                _empty(scheme)
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ['😞', '😕', '😐', '🙂', '😄'][(dayMood.mood - 1)
                          .clamp(0, 4)],
                      style: TextStyle(fontSize: 18),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              tr('很差'),
                              tr('有点低'),
                              tr('一般'),
                              tr('不错'),
                              tr('很好'),
                            ][(dayMood.mood - 1).clamp(0, 4)],
                            style: TextStyle(fontSize: 13),
                          ),
                          if ((dayMood.note ?? '').isNotEmpty)
                            Text(
                              dayMood.note!,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.5,
                                color: scheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              SizedBox(height: 20),
              _section(tr('专注记录'), scheme),
              if (daySessions.isEmpty)
                _empty(scheme)
              else
                for (final s in daySessions)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Text(
                          DateFormat('HH:mm').format(s.startedAt),
                          style: TextStyle(fontSize: 11, color: scheme.outline),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.taskId == null
                                ? tr('未关联任务')
                                : (titleOf[s.taskId] ?? tr('已删除任务')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          trf('{} 分钟', [(s.actualSec ?? 0) ~/ 60]),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
              SizedBox(height: 28),
              Center(
                child: Text(
                  trf('任务待办 · {}', [dfFullDateWeekFmt().format(date)]),
                  style: TextStyle(fontSize: 9.5, color: scheme.outline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 把这一页（不含 AppBar）渲染成 PNG，交给系统保存对话框。
  Future<void> _exportPng() async {
    setState(() => _exporting = true);
    try {
      final boundary =
          _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError(tr('页面尚未渲染'));
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError(tr('图片编码失败'));
      final stamp = DateFormat('yyyyMMdd').format(widget.date);
      final uri = await FilePicker.saveFile(
        fileName: trf('回顾-{}.png', [stamp]),
        bytes: data.buffer.asUint8List(),
        mimeType: 'image/png',
        dialogTitle: tr('保存回顾图片'),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uri == null ? tr('已取消保存') : tr('回顾图片已保存'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('导出失败：{}', [e]))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _stat(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String text, ColorScheme scheme) => Padding(
    padding: EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _empty(ColorScheme scheme) => Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Text(tr('没有记录'), style: TextStyle(fontSize: 12, color: scheme.outline)),
  );
}
