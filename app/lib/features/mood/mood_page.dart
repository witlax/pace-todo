import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import 'mood_repository.dart';
import '../../core/i18n/i18n.dart';

List<String> get _moodLabels =>
    [tr('很差'), tr('有点低'), tr('一般'), tr('不错'), tr('很好')];
const _moodColors = [
  Color(0xFF9AA0A8),
  Color(0xFF7FA6C9),
  Color(0xFF6FA8A0),
  Color(0xFF4E9E86),
  Color(0xFF0F6E56),
];

/// 心情打卡：一天一条，点日期可补记；下面是本月色点与近 30 天趋势。
/// 刻意不做情绪分类、不做评分解释——只回答「那几天我什么状态」。
class MoodPage extends ConsumerStatefulWidget {
  const MoodPage({super.key});

  @override
  ConsumerState<MoodPage> createState() => _MoodPageState();
}

class _MoodPageState extends ConsumerState<MoodPage> {
  late DateTime _day = DateTime.now();
  late DateTime _month = DateTime.now();
  final _note = TextEditingController();
  final _noteFocus = FocusNode();

  @override
  void dispose() {
    _noteFocus.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = ref.watch(moodEntriesProvider).value ?? <MoodEntry>[];
    final byDate = {for (final e in entries) e.date: e};
    final current = byDate[moodDayKey(_day)];

    // 备注跟随选中日期；正在输入时不覆盖。
    if (!_noteFocus.hasFocus && _note.text != (current?.note ?? '')) {
      _note.text = current?.note ?? '';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('心情')),
        actions: [
          if (current != null)
            IconButton(
              tooltip: tr('删掉这天的心情'),
              onPressed: () async {
                await ref.read(moodRepositoryProvider).remove(_day);
                if (!mounted) return;
                setState(() => _note.clear());
              },
              icon: Icon(Icons.delete_outline, size: 20),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 84),
        children: [
          Text(
            '${dfMonthDayWeekFmt().format(_day)}'
            '${_sameDay(_day, DateTime.now()) ? ' · 今天' : ''}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _save(i),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: Duration(milliseconds: 160),
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: current?.mood == i
                                  ? _moodColors[i - 1].withValues(alpha: 0.18)
                                  : scheme.surfaceContainerHighest.withValues(
                                      alpha: 0.5,
                                    ),
                              border: Border.all(
                                color: current?.mood == i
                                    ? _moodColors[i - 1]
                                    : Colors.transparent,
                                width: 1.4,
                              ),
                            ),
                            child: Text(
                              ['😞', '😕', '😐', '🙂', '😄'][i - 1],
                              style: TextStyle(fontSize: 18),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _moodLabels[i - 1],
                            style: TextStyle(
                              fontSize: 9.5,
                              color: current?.mood == i
                                  ? _moodColors[i - 1]
                                  : scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          TextField(
            controller: _note,
            focusNode: _noteFocus,
            minLines: 1,
            maxLines: 3,
            style: TextStyle(fontSize: 12.5, height: 1.5),
            decoration: InputDecoration(
              hintText: current == null ? tr('先点一个表情，再补一句') : tr('补一句：为什么是这个心情'),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            onSubmitted: (v) {
              final mood = current?.mood;
              if (mood == null) return;
              _save(mood, note: v);
            },
          ),
          Row(
            children: [
              Text(
                tr('近 30 天'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Spacer(),
              Text(
                trf('记录 {} 天', [_last30(entries).length]),
                style: TextStyle(fontSize: 10.5, color: scheme.outline),
              ),
            ],
          ),
          SizedBox(height: 8),
          _Trend(entries: _last30(entries)),
          SizedBox(height: 22),
          _MonthMood(
            month: _month,
            byDate: byDate,
            selected: _day,
            onPrev: () => setState(
              () => _month = DateTime(_month.year, _month.month - 1),
            ),
            onNext: () => setState(
              () => _month = DateTime(_month.year, _month.month + 1),
            ),
            onPick: (d) => setState(() {
              _day = d;
              _month = DateTime(d.year, d.month);
              _note.text = byDate[moodDayKey(d)]?.note ?? '';
            }),
          ),
        ],
      ),
    );
  }

  List<MoodEntry> _last30(List<MoodEntry> all) {
    final now = DateTime.now();
    final from = moodDayKey(now.subtract(Duration(days: 29)));
    final to = moodDayKey(now);
    return all
        .where((e) => e.date.compareTo(from) >= 0 && e.date.compareTo(to) <= 0)
        .toList();
  }

  Future<void> _save(int mood, {String? note}) async {
    await ref
        .read(moodRepositoryProvider)
        .save(
          day: _day,
          mood: mood,
          note: (note ?? _note.text).trim().isEmpty
              ? null
              : (note ?? _note.text).trim(),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 2),
          content: Text(
            trf('已记录 {} · {}', [dfMonthDayFmt().format(_day), _moodLabels[mood - 1]]),
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MonthMood extends StatelessWidget {
  const _MonthMood({
    required this.month,
    required this.byDate,
    required this.selected,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
  });

  final DateTime month;
  final Map<String, MoodEntry> byDate;
  final DateTime selected;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final leading = (first.weekday + 6) % 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              dfYearMonthFmt().format(month),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onPrev,
              icon: Icon(Icons.chevron_left, size: 20),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: onNext,
              icon: Icon(Icons.chevron_right, size: 20),
            ),
          ],
        ),
        Row(
          children: [
            for (final w in [tr('一'), tr('二'), tr('三'), tr('四'), tr('五'), tr('六'), tr('日')])
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(fontSize: 9.5, color: scheme.outline),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: ((leading + days + 6) ~/ 7) * 7,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 32,
          ),
          itemBuilder: (_, i) {
            final n = i - leading + 1;
            if (n < 1 || n > days) return SizedBox.shrink();
            final day = DateTime(month.year, month.month, n);
            final entry = byDate[moodDayKey(day)];
            final isSelected =
                day.year == selected.year &&
                day.month == selected.month &&
                day.day == selected.day;
            final isToday = _isToday(day);

            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onPick(day),
              child: Container(
                margin: EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.primary.withValues(alpha: 0.10)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  border: isToday && !isSelected
                      ? Border.all(color: scheme.primary, width: 0.8)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    SizedBox(height: 2),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entry == null
                            ? Colors.transparent
                            : _moodColors[(entry.mood - 1).clamp(0, 4)],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

class _Trend extends StatelessWidget {
  const _Trend({required this.entries});

  final List<MoodEntry> entries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final byDate = {for (final e in entries) e.date: e.mood};
    final now = DateTime.now();

    return SizedBox(
      height: 52,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 29; i >= 0; i--)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: Builder(
                  builder: (context) {
                    final day = now.subtract(Duration(days: i));
                    final mood = byDate[moodDayKey(day)];
                    if (mood == null) {
                      return Container(
                        height: 2,
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      );
                    }
                    return Container(
                      height: 10 + mood * 7,
                      decoration: BoxDecoration(
                        color: _moodColors[mood - 1].withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
