import 'package:flutter/material.dart';
import '../i18n/i18n.dart';

/// 排期结果：日期 + 提醒偏移（分钟，0 = 准时，null = 不提醒）。
class ScheduleResult {
  const ScheduleResult({this.dueAt, this.remindOffset});

  final DateTime? dueAt;
  final int? remindOffset;
}

/// 统一排期面板。
///
/// 替代系统 `showDatePicker` + `showTimePicker` 的两步弹窗：
/// 快捷行 → 月历 → 时间片 → 提醒片，常用路径 2 次点击完成。
/// 新建任务、任务详情、快速添加、日历改期共用同一个面板，规则自然一致。
class ScheduleSheet extends StatefulWidget {
  const ScheduleSheet({
    super.key,
    this.initialDue,
    this.initialRemindOffset,
    this.allowClear = true,
  });

  final DateTime? initialDue;
  final int? initialRemindOffset;
  final bool allowClear;

  static Future<ScheduleResult?> show(
    BuildContext context, {
    DateTime? initialDue,
    int? initialRemindOffset,
    bool allowClear = true,
  }) {
    return showModalBottomSheet<ScheduleResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => ScheduleSheet(
        initialDue: initialDue,
        initialRemindOffset: initialRemindOffset,
        allowClear: allowClear,
      ),
    );
  }

  @override
  State<ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<ScheduleSheet> {
  late DateTime _month; // 当月 1 日
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 18, minute: 0);
  int? _offset = 0; // 0 准时，10/60，null 不提醒

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final due = widget.initialDue;
    _date = due == null ? null : DateTime(due.year, due.month, due.day);
    if (due != null) _time = TimeOfDay.fromDateTime(due);
    _month = DateTime((due ?? now).year, (due ?? now).month);
    _offset = widget.initialRemindOffset ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  tr('排期'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Spacer(),
                Text(
                  dfYearMonthFmt().format(_month),
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(width: 4),
                _arrow(scheme, Icons.chevron_left, () {
                  setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  );
                }),
                _arrow(scheme, Icons.chevron_right, () {
                  setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  );
                }),
              ],
            ),
            SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _quick(tr('今天'), today),
                _quick(tr('明天'), today.add(Duration(days: 1))),
                _quick(tr('后天'), today.add(Duration(days: 2))),
                _quick(tr('下周一'), _nextMonday(today)),
              ],
            ),
            SizedBox(height: 8),
            _calendar(scheme, today),
            SizedBox(height: 6),
            Divider(
              height: 12,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 34,
                    child: Text(
                      tr('时间'),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _timeChip(TimeOfDay(hour: 9, minute: 0)),
                      _timeChip(TimeOfDay(hour: 14, minute: 0)),
                      _timeChip(TimeOfDay(hour: 18, minute: 0)),
                      ActionChip(
                        label: Text(
                          _isPreset
                              ? tr('自定义…')
                              : '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 11),
                        ),
                        onPressed: _pickTime,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 34,
                    child: Text(
                      tr('提醒'),
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _remindChip(tr('准时'), 0),
                      _remindChip(tr('提前 10 分'), 10),
                      _remindChip(tr('提前 1 小时'), 60),
                      _remindChip(tr('不提醒'), null),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            Row(
              children: [
                if (widget.allowClear)
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop(ScheduleResult()),
                    child: Text(tr('清除')),
                  ),
                Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tr('取消')),
                ),
                SizedBox(width: 4),
                FilledButton(onPressed: _confirm, child: Text(tr('确定'))),
              ],
            ),
            SizedBox(height: 2),
            Text(
              _date == null
                  ? tr('未选择日期 · 任务会落到「未排期」')
                  : '${dfMonthDayWeekFmt().format(_date!)} '
                        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isPreset =>
      (_time.hour == 9 && _time.minute == 0) ||
      (_time.hour == 14 && _time.minute == 0) ||
      (_time.hour == 18 && _time.minute == 0);

  Widget _arrow(ColorScheme scheme, IconData icon, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 16,
      child: Padding(
        padding: EdgeInsets.all(3),
        child: Icon(icon, size: 17, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _quick(String label, DateTime date) {
    final on = _date != null && _sameDay(_date!, date);
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11)),
      selected: on,
      onSelected: (_) => setState(() {
        _date = date;
        _month = DateTime(date.year, date.month);
      }),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
    );
  }

  Widget _timeChip(TimeOfDay t) {
    final on = _time.hour == t.hour && _time.minute == t.minute;
    return ChoiceChip(
      label: Text(
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        style: TextStyle(fontSize: 11),
      ),
      selected: on,
      onSelected: (_) => setState(() => _time = t),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
    );
  }

  Widget _remindChip(String label, int? offset) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11)),
      selected: _offset == offset,
      onSelected: (_) => setState(() => _offset = offset),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
    );
  }

  Widget _calendar(ColorScheme scheme, DateTime today) {
    final first = DateTime(_month.year, _month.month, 1);
    final leading = first.weekday - 1; // 周一开头
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[
      for (final w in [tr('一'), tr('二'), tr('三'), tr('四'), tr('五'), tr('六'), tr('日')])
        Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text(
            w,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.5, color: scheme.outline),
          ),
        ),
      for (var i = 0; i < leading; i++) SizedBox(height: 34),
      for (var d = 1; d <= days; d++)
        _dayCell(DateTime(_month.year, _month.month, d), today, scheme),
    ];
    // 补齐整行，避免最后一行高度塌陷
    while (cells.length % 7 != 0) {
      cells.add(SizedBox(height: 34));
    }

    return GridView(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: 34,
      ),
      children: cells,
    );
  }

  Widget _dayCell(DateTime date, DateTime today, ColorScheme scheme) {
    final isToday = _sameDay(date, today);
    final selected = _date != null && _sameDay(_date!, date);
    return InkResponse(
      onTap: () => setState(() => _date = date),
      radius: 20,
      child: Container(
        margin: EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : null,
          borderRadius: BorderRadius.circular(8),
          border: isToday && !selected
              ? Border.all(color: scheme.primary.withValues(alpha: 0.55))
              : null,
        ),
        child: Center(
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 12,
              color: selected
                  ? scheme.onPrimary
                  : (isToday ? scheme.primary : scheme.onSurface),
              fontWeight: selected || isToday ? FontWeight.w600 : null,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null) return;
    setState(() => _time = picked);
  }

  void _confirm() {
    if (_date == null) {
      Navigator.of(context).pop(ScheduleResult());
      return;
    }
    final due = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time.hour,
      _time.minute,
    );
    Navigator.of(context)
        .pop(ScheduleResult(dueAt: due, remindOffset: _offset));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _nextMonday(DateTime today) {
    final delta = (DateTime.monday - today.weekday + 7) % 7;
    return today.add(Duration(days: delta == 0 ? 7 : delta));
  }
}
