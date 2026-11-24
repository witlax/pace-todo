import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../platform/notification_service.dart';
import 'habit_repository.dart';
import '../../core/i18n/i18n.dart';

/// 习惯创建/编辑。
///
/// 对齐「朝暮计划」的创建页形态：名称与图标、周期（固定/按周/按月/每隔几天）、
/// 目标（一次/多次）、提醒时间、开始日期、打卡后是否弹心得。
/// 频率存成 `daily` / `weekly:1,3,5` / `monthly:15` / `interval:2` 这样的字符串，
/// 解析集中在本文件，避免各页面各写一套。
class HabitEditPage extends ConsumerStatefulWidget {
  const HabitEditPage({super.key, this.habit});

  final Habit? habit;

  bool get isEdit => habit != null;

  @override
  ConsumerState<HabitEditPage> createState() => _HabitEditPageState();
}

class _HabitEditPageState extends ConsumerState<HabitEditPage> {
  static const _icons = ['🌱', '📚', '🏃', '💧', '🧘', '🌙', '✍️', '🍎'];

  final _name = TextEditingController();
  String _icon = '🌱';
  String _freqType = 'daily'; // daily | weekly | monthly | interval
  final Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  int _monthDay = 1;
  int _intervalDays = 2;
  int _targetCount = 1;
  String? _remindTime;
  bool _promptJournal = true;
  late DateTime _startDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    if (h != null) {
      _name.text = habitDisplayName(h.name);
      final icon = habitIconOf(h.name);
      if (icon != null) _icon = icon;
      _targetCount = h.targetCount;
      _remindTime = h.remindTime;
      _promptJournal = h.promptJournal;
      final cfg = h.freqConfig ?? 'daily';
      final parts = cfg.split(':');
      _freqType = parts.first;
      if (_freqType == 'weekly' && parts.length > 1) {
        _weekdays
          ..clear()
          ..addAll(parts[1].split(',').map(int.parse));
      } else if (_freqType == 'monthly' && parts.length > 1) {
        _monthDay = int.parse(parts[1]);
      } else if (_freqType == 'interval' && parts.length > 1) {
        _intervalDays = int.parse(parts[1]);
      }
      if (h.startDate != null) {
        _startDate = DateTime.parse(h.startDate!);
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _freqConfig => switch (_freqType) {
    'weekly' => 'weekly:${(_weekdays.toList()..sort()).join(',')}',
    'monthly' => 'monthly:$_monthDay',
    'interval' => 'interval:$_intervalDays',
    _ => 'daily',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? tr('编辑习惯') : tr('创建习惯')),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(widget.isEdit ? tr('保存') : tr('创建')),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // 图标 + 名称
          Row(
            children: [
              PopupMenuButton<String>(
                tooltip: tr('选择图标'),
                onSelected: (v) => setState(() => _icon = v),
                itemBuilder: (_) => [
                  for (final i in _icons)
                    PopupMenuItem(
                      value: i,
                      child: Text(i, style: TextStyle(fontSize: 20)),
                    ),
                ],
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_icon, style: TextStyle(fontSize: 24)),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _name,
                  autofocus: !widget.isEdit,
                  decoration: InputDecoration(hintText: tr('例如：早起、背单词、喝水')),
                ),
              ),
            ],
          ),
          SizedBox(height: 24),

          _label(tr('习惯周期'), scheme),
          Wrap(
            spacing: 8,
            children: [
              _chip(
                tr('固定'),
                _freqType == 'daily',
                () => setState(() => _freqType = 'daily'),
              ),
              _chip(
                tr('按周'),
                _freqType == 'weekly',
                () => setState(() => _freqType = 'weekly'),
              ),
              _chip(
                tr('按月'),
                _freqType == 'monthly',
                () => setState(() => _freqType = 'monthly'),
              ),
              _chip(
                tr('每隔几天'),
                _freqType == 'interval',
                () => setState(() => _freqType = 'interval'),
              ),
            ],
          ),
          SizedBox(height: 10),
          if (_freqType == 'weekly')
            Wrap(
              spacing: 6,
              children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(
                      [tr('一'), tr('二'), tr('三'), tr('四'), tr('五'), tr('六'), tr('日')][i - 1],
                    ),
                    selected: _weekdays.contains(i),
                    visualDensity: VisualDensity.compact,
                    onSelected: (on) => setState(
                      () => on ? _weekdays.add(i) : _weekdays.remove(i),
                    ),
                  ),
              ],
            ),
          if (_freqType == 'monthly')
            Row(
              children: [
                Text(tr('每月'), style: TextStyle(fontSize: 13)),
                SizedBox(width: 8),
                DropdownButton<int>(
                  value: _monthDay,
                  items: [
                    for (var d = 1; d <= 28; d++)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) => setState(() => _monthDay = v ?? 1),
                ),
                Text(tr('日'), style: TextStyle(fontSize: 13)),
              ],
            ),
          if (_freqType == 'interval')
            Row(
              children: [
                Text(tr('每'), style: TextStyle(fontSize: 13)),
                SizedBox(width: 8),
                DropdownButton<int>(
                  value: _intervalDays,
                  items: [
                    for (var d = 2; d <= 15; d++)
                      DropdownMenuItem(value: d, child: Text('$d')),
                  ],
                  onChanged: (v) => setState(() => _intervalDays = v ?? 2),
                ),
                Text(tr(' 天'), style: TextStyle(fontSize: 13)),
              ],
            ),

          SizedBox(height: 22),
          _label(tr('习惯目标'), scheme),
          Wrap(
            spacing: 8,
            children: [
              _chip(
                tr('每天一次'),
                _targetCount == 1,
                () => setState(() => _targetCount = 1),
              ),
              _chip(
                tr('每天多次'),
                _targetCount > 1,
                () => setState(() => _targetCount = 2),
              ),
            ],
          ),
          if (_targetCount > 1)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text(tr('每天次数'), style: TextStyle(fontSize: 13)),
                  SizedBox(width: 8),
                  DropdownButton<int>(
                    value: _targetCount,
                    items: [
                      for (var d = 2; d <= 12; d++)
                        DropdownMenuItem(value: d, child: Text(trf('{} 次', [d]))),
                    ],
                    onChanged: (v) => setState(() => _targetCount = v ?? 2),
                  ),
                ],
              ),
            ),

          SizedBox(height: 22),
          _label(tr('提醒时间'), scheme),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: Icon(Icons.alarm, size: 16),
                label: Text(_remindTime ?? tr('不提醒')),
              ),
              if (_remindTime != null)
                TextButton(
                  onPressed: () => setState(() => _remindTime = null),
                  child: Text(tr('清除')),
                ),
            ],
          ),

          SizedBox(height: 22),
          _label(tr('打卡开始日期'), scheme),
          Row(
            children: [
              Text(
                dfFullDateFmt().format(_startDate),
                style: TextStyle(fontSize: 13),
              ),
              Spacer(),
              TextButton(onPressed: _pickStartDate, child: Text(tr('修改'))),
            ],
          ),

          SizedBox(height: 18),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _promptJournal,
            onChanged: (v) => setState(() => _promptJournal = v),
            title: Text(tr('打卡后弹心得'), style: TextStyle(fontSize: 14)),
            subtitle: Text(
              tr('打卡时顺手记一句，也能写进备忘录'),
              style: TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text, ColorScheme scheme) => Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
    ),
  );

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
    label: Text(label, style: TextStyle(fontSize: 12.5)),
    selected: selected,
    onSelected: (_) => onTap(),
    visualDensity: VisualDensity.compact,
  );

  Future<void> _pickTime() async {
    final base = _remindTime == null
        ? TimeOfDay(hour: 8, minute: 0)
        : TimeOfDay(
            hour: int.parse(_remindTime!.split(':').first),
            minute: int.parse(_remindTime!.split(':').last),
          );
    final picked = await showTimePicker(context: context, initialTime: base);
    if (picked == null) return;
    setState(() {
      _remindTime =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('先写个名字'))));
      return;
    }
    final repo = ref.read(habitRepositoryProvider);
    final displayName = '$_icon ${habitDisplayName(name)}';
    final String habitId;
    if (widget.isEdit) {
      habitId = widget.habit!.id;
      await repo.updateHabit(
        habitId,
        name: displayName,
        targetCount: _targetCount,
        freqType: _freqConfig,
        remindTime: _remindTime,
        clearRemind: _remindTime == null,
        promptJournal: _promptJournal,
      );
    } else {
      habitId = await repo.create(
        displayName,
        targetCount: _targetCount,
        freqType: _freqConfig,
        remindTime: _remindTime,
        promptJournal: _promptJournal,
        startDate: _startDate,
      );
    }

    // 提醒是习惯真正的「存在感」：存完就排，关掉就取消。
    if (_remindTime != null) {
      await NotificationService.scheduleHabit(
        habitId: habitId,
        name: displayName,
        hhmm: _remindTime!,
      );
    } else {
      await NotificationService.cancelHabit(habitId);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
