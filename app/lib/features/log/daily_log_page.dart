import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../focus/focus_repository.dart';
import '../habits/habit_repository.dart';
import '../habits/habit_schedule.dart';
import '../mood/mood_page.dart';
import '../mood/mood_repository.dart';
import '../settings/settings.dart';
import '../tasks/task_repository.dart';
import '../../app/tokens.dart';
import '../../core/i18n/i18n.dart';

/// 五个心情档位与 pinch 一致，用表情表达，不用分数。
const _moodEmoji = ['😫', '😕', '😐', '🙂', '😄'];
List<String> get _moodNames =>
    [tr('很差'), tr('有点低'), tr('一般'), tr('不错'), tr('很好')];

/// 日志页：一天的三件事（专注 / 任务 / 习惯）+ 心情 + 一句话总结。
///
/// pinch 把它叫「每日记录」。这里先做核心：选中日的心情、三条数字、
/// 当天事件时间线、以及底部的那句总结。总结先存本地偏好，
/// 等记录模型稳定后再进表（现在换表只会让历史总结丢一次）。
class DailyLogPage extends ConsumerStatefulWidget {
  const DailyLogPage({super.key});

  @override
  ConsumerState<DailyLogPage> createState() => _DailyLogPageState();
}

class _DailyLogPageState extends ConsumerState<DailyLogPage> {
  DateTime _day = _dayOnly(DateTime.now());
  late final TextEditingController _note;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String get _key => 'log.note.${habitDayKey(_day)}';

  @override
  void initState() {
    super.initState();
    _note = TextEditingController();
    _noteFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final moods = ref.watch(moodEntriesProvider).value ?? <MoodEntry>[];
    final tasks = ref.watch(allActiveTasksProvider).value ?? <Task>[];
    final habits = ref.watch(habitsProvider).value ?? <Habit>[];
    final logs = ref.watch(habitLogsProvider).value ?? <HabitLog>[];
    final sessions =
        ref.watch(_daySessionsProvider(_day)).value ?? <FocusSession>[];

    final dayEnd = _day.add(Duration(days: 1));
    final doneTasks = tasks
        .where(
          (t) =>
              t.status == 1 &&
              t.completedAt != null &&
              !t.completedAt!.isBefore(_day) &&
              t.completedAt!.isBefore(dayEnd),
        )
        .toList();
    final dayHabits = logs
        .where((l) => l.date == habitDayKey(_day) && l.count > 0)
        .toList();
    final focusMinutes = sessions.fold<int>(
      0,
      (sum, s) => sum + (s.actualSec ?? 0) ~/ 60,
    );

    final mood = moods.where((m) => m.date == habitDayKey(_day)).firstOrNull;
    final saved = ref.read(prefsProvider).getString(_key) ?? '';
    if (!_noteHasFocus && _note.text != saved) {
      _note.text = saved;
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Row(
              children: [
                Text(
                  tr('每日记录'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => MoodPage()),
                  ),
                  child: Text(tr('心情打卡'), style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            SizedBox(height: 8),
            _MoodSummary(moods: moods, mood: mood),
            SizedBox(height: 12),
            _WeekRow(
              selected: _day,
              onSelect: (d) => setState(() => _day = d),
            ),
            SizedBox(height: 12),
            Row(
              children: [
                _StatCard(
                  label: tr('专注时间'),
                  value: '$focusMinutes',
                  unit: tr('分钟'),
                ),
                SizedBox(width: 8),
                _StatCard(
                  label: tr('任务完成'),
                  value: '${doneTasks.length}',
                  unit: tr('项'),
                ),
                SizedBox(width: 8),
                _StatCard(
                  label: tr('习惯完成'),
                  value: '${dayHabits.length}',
                  unit: tr('次'),
                ),
              ],
            ),
            SizedBox(height: 16),
            Text(
              trf('{}的记录', [dfMonthDayFmt().format(_day)]),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 8),
            if (doneTasks.isEmpty && dayHabits.isEmpty && sessions.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: Text(
                    tr('暂无记录'),
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
                ),
              )
            else ...[
              for (final t in doneTasks)
                _TimelineRow(
                  time: t.completedAt!,
                  icon: Icons.check_circle_outline,
                  title: t.title,
                  subtitle: tr('完成任务'),
                ),
              for (final log in dayHabits)
                _TimelineRow(
                  time: log.createdAt,
                  icon: Icons.repeat,
                  title: habits
                          .where((h) => h.id == log.habitId)
                          .map((h) => habitDisplayName(h.name))
                          .firstOrNull ??
                      tr('习惯'),
                  subtitle: log.count > 1 ? trf('打卡 {} 次', [log.count]) : tr('打卡'),
                  note: log.note,
                ),
              for (final s in sessions)
                _TimelineRow(
                  time: s.startedAt,
                  icon: Icons.timer_outlined,
                  title: trf('专注 {} 分钟', [((s.actualSec ?? 0) / 60).round()]),
                  subtitle: s.taskId == null ? tr('自由专注') : tr('关联任务'),
                ),
            ],
            SizedBox(height: 18),
            Container(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _note,
                    minLines: 3,
                    maxLines: 6,
                    focusNode: _noteFocusNode,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: tr('写下这一天发生的事、想法或补充说明'),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 13, height: 1.7),
                  ),
                  TextButton(
                    onPressed: _saveNote,
                    child: Text(tr('保存'), style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  final FocusNode _noteFocusNode = FocusNode();

  bool get _noteHasFocus => _noteFocusNode.hasFocus;

  void _saveNote() {
    ref.read(prefsProvider).setString(_key, _note.text.trim());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 2),
          content: Text(tr('已保存这一天的记录'), style: TextStyle(fontSize: 12.5)),
        ),
      );
  }
}

/// 选中日的专注会话。
final _daySessionsProvider =
    StreamProvider.family<List<FocusSession>, DateTime>((ref, day) {
      final start = DateTime(day.year, day.month, day.day);
      final end = start.add(Duration(days: 1));
      return ref.watch(focusRepositoryProvider).watchSince(start).map(
        (list) => list
            .where(
              (s) => s.startedAt.isBefore(end),
            )
            .toList(),
      );
    });

class _MoodSummary extends StatelessWidget {
  const _MoodSummary({required this.moods, required this.mood});

  final List<MoodEntry> moods;
  final MoodEntry? mood;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = List<int>.filled(5, 0);
    for (final m in moods) {
      if (m.mood >= 1 && m.mood <= 5) counts[m.mood - 1]++;
    }

    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                tr('心情统计'),
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
              ),
              Spacer(),
              if (mood != null)
                Text(
                  trf('这一天：{} {}', [_moodEmoji[mood!.mood - 1], _moodNames[mood!.mood - 1]]),
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _moodEmoji[i],
                        style: TextStyle(
                          fontSize: 18,
                          color: mood?.mood == i + 1
                              ? null
                              : scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '${counts[i]}',
                        style: TextStyle(fontSize: 10, color: scheme.outline),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.selected, required this.onSelect});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final start = selected.subtract(Duration(days: selected.weekday - 1));
    final names = weekdayInitials;

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(
              builder: (context) {
                final day = start.add(Duration(days: i));
                final on = day.year == selected.year &&
                    day.month == selected.month &&
                    day.day == selected.day;
                final isToday = day.year == today.year &&
                    day.month == today.month &&
                    day.day == today.day;
                return GestureDetector(
                  onTap: () => onSelect(day),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 2),
                    padding: EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: on
                          ? context.appColors.accent
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          names[i],
                          style: TextStyle(
                            fontSize: 9.5,
                            color: on ? Colors.white : scheme.outline,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                            color: on
                                ? Colors.white
                                : isToday
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: EdgeInsets.fromLTRB(10, 10, 10, 11),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 2),
                Text(
                  unit,
                  style: TextStyle(fontSize: 9.5, color: scheme.outline),
                ),
              ],
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.time,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.note,
  });

  final DateTime time;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              DateFormat('HH:mm').format(time),
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
          ),
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12.5)),
                if ((note ?? '').isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text(
                      note!,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: scheme.outline),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
