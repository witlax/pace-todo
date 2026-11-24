import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../../core/ui/schedule_sheet.dart';
import '../memos/memo_page.dart' show notesProvider;
import '../settings/settings.dart';
import 'recurrence.dart';
import 'task_repository.dart';
import '../../core/i18n/i18n.dart';

/// 完整新建页。
///
/// 快速添加只解决「先记下来」，真正排期需要日期到分钟、提醒、清单、重复、
/// 重要性和备注一次配齐——这些放在底部弹层里会被键盘挤成两屏，所以单独给一页。
/// 入口：快速添加弹层右上角的「高级模式」（对齐 Pinch 的同名入口）。
class TaskCreatePage extends ConsumerStatefulWidget {
  const TaskCreatePage({
    super.key,
    this.initialDue,
    this.initialListId,
    this.initialTitle,
  });

  final DateTime? initialDue;
  final String? initialListId;
  final String? initialTitle;

  @override
  ConsumerState<TaskCreatePage> createState() => _TaskCreatePageState();
}

class _TaskCreatePageState extends ConsumerState<TaskCreatePage> {
  final _title = TextEditingController();
  final _notes = TextEditingController();
  int _importance = 0;
  DateTime? _dueAt;
  DateTime? _remindAt;
  int? _remindOffset;
  String _listId = 'inbox';
  String? _repeatRule;
  bool _saving = false;
  final Set<String> _tagIds = {};
  final Set<String> _noteIds = {};

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _dueAt = widget.initialDue;
    _listId = widget.initialListId ?? settings.defaultListId;
    if (widget.initialTitle != null) _title.text = widget.initialTitle!;
    // 默认提醒按「相对日期的偏移」落到已有的日期上。
    if (_dueAt != null && settings.defaultRemindOffset != null) {
      _remindOffset = settings.defaultRemindOffset;
      _remindAt = _dueAt!.subtract(Duration(minutes: _remindOffset!));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteProvider);
    final scheme = Theme.of(context).colorScheme;
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('新建任务')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(tr('保存')),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: tr('要做什么？'),
              border: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SizedBox(height: 6),
          Divider(color: scheme.outlineVariant.withValues(alpha: 0.6)),
          SizedBox(height: 6),

          _row(
            context,
            icon: Icons.folder_outlined,
            label: tr('清单'),
            value:
                lists
                    .where((l) => l.id == _listId)
                    .map((l) => l.name)
                    .firstOrNull ??
                tr('收件箱'),
            onTap: () => _pickList(lists),
          ),
          _row(
            context,
            icon: Icons.event_outlined,
            label: tr('日期'),
            value: _dueAt == null
                ? tr('无日期')
                : DateFormat('yyyy-MM-dd HH:mm').format(_dueAt!),
            onTap: _pickDue,
            onClear: _dueAt == null
                ? null
                : () => setState(() {
                    _dueAt = null;
                    _remindAt = null;
                    _remindOffset = null;
                  }),
          ),
          _row(
            context,
            icon: Icons.notifications_none,
            label: tr('提醒'),
            value: _remindAt == null
                ? tr('不提醒')
                : DateFormat('yyyy-MM-dd HH:mm').format(_remindAt!),
            onTap: _pickRemind,
            onClear: _remindAt == null
                ? null
                : () => setState(() => _remindAt = null),
          ),
          _row(
            context,
            icon: Icons.repeat,
            label: tr('重复'),
            value: RecurrenceService.labelOf(_repeatRule),
            onTap: _pickRepeat,
            onClear: _repeatRule == null
                ? null
                : () => setState(() => _repeatRule = null),
          ),

          _row(
            context,
            icon: Icons.local_offer_outlined,
            label: tr('标签'),
            value: _tagIds.isEmpty ? tr('未选择') : trf('已选 {} 个', [_tagIds.length]),
            onTap: () => _pickTags(),
            onClear: _tagIds.isEmpty
                ? null
                : () => setState(() => _tagIds.clear()),
          ),
          _row(
            context,
            icon: Icons.sticky_note_2_outlined,
            label: tr('关联备忘录'),
            value: _noteIds.isEmpty ? tr('无') : trf('已关联 {} 条', [_noteIds.length]),
            onTap: () => _pickNotes(),
            onClear: _noteIds.isEmpty
                ? null
                : () => setState(() => _noteIds.clear()),
          ),

          SizedBox(height: 18),
          Text(
            tr('重要性'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              for (final e in Emphasis.values)
                Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _importance = e.value),
                    child: Container(
                      width: 26,
                      height: 26,
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
                                color: scheme.onSurface.withValues(alpha: 0.35),
                                width: 2,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              Text(
                Emphasis.fromValue(_importance).label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),

          SizedBox(height: 20),
          Text(
            tr('备注'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 6),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(hintText: tr('补充说明、链接或要点…')),
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 14)),
            Spacer(),
            Text(
              value,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (onClear != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 15, color: scheme.outline),
                onPressed: onClear,
              )
            else
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }

  Future<void> _pickList(List<TaskList> lists) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 16),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in lists)
              ListTile(
                dense: true,
                title: Text(l.name),
                trailing: l.id == _listId
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(l.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _listId = picked);
  }

  /// 日期与提醒统一走排期面板（替代系统两步弹窗）。
  Future<void> _pickDue() async {
    final res = await ScheduleSheet.show(
      context,
      initialDue: _dueAt,
      initialRemindOffset: _remindOffset ?? (_remindAt == null ? 0 : null),
    );
    if (res == null || !mounted) return;
    setState(() {
      _dueAt = res.dueAt;
      if (res.dueAt == null) {
        _remindAt = null;
        _remindOffset = null;
      } else if (res.remindOffset == null) {
        _remindAt = null;
        _remindOffset = null;
      } else {
        _remindOffset = res.remindOffset;
        _remindAt = res.dueAt!.subtract(Duration(minutes: res.remindOffset!));
      }
    });
  }

  Future<void> _pickRemind() async {
    final scheme = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 16),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                tr('提醒时间'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            ListTile(
              dense: true,
              title: Text(tr('准时提醒（与日期相同）')),
              onTap: () => Navigator.of(ctx).pop('exact'),
            ),
            ListTile(
              dense: true,
              title: Text(tr('提前 10 分钟')),
              onTap: () => Navigator.of(ctx).pop('10'),
            ),
            ListTile(
              dense: true,
              title: Text(tr('提前 1 小时')),
              onTap: () => Navigator.of(ctx).pop('60'),
            ),
            ListTile(
              dense: true,
              title: Text(tr('自定义时间…')),
              onTap: () => Navigator.of(ctx).pop('custom'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'custom') {
      final now = DateTime.now();
      final base = _remindAt ?? _dueAt ?? now;
      final date = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 5),
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );
      if (time == null || !mounted) return;
      setState(() {
        _remindAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        _remindOffset = null; // 自定义绝对时间，不随日期平移
      });
      return;
    }

    final due = _dueAt;
    if (!mounted) return;
    if (due == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('先设置日期，才能按「准时/提前」计算提醒'))));
      return;
    }
    setState(() {
      _remindOffset = choice == 'exact' ? 0 : int.parse(choice);
      _remindAt = choice == 'exact'
          ? due
          : due.subtract(Duration(minutes: int.parse(choice)));
    });
  }

  Future<void> _pickTags() async {
    final tags = ref.read(tagsProvider).value ?? <Tag>[];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('标签'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
                if (tags.isEmpty)
                  Text(tr('还没有标签，先在任务详情里新建'), style: TextStyle(fontSize: 12)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tags)
                      FilterChip(
                        label: Text(
                          t.name,
                          style: TextStyle(fontSize: 12),
                        ),
                        selected: _tagIds.contains(t.id),
                        onSelected: (on) {
                          setSheet(() {
                            on ? _tagIds.add(t.id) : _tagIds.remove(t.id);
                          });
                          setState(() {});
                        },
                      ),
                  ],
                ),
                SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(tr('完成')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickNotes() async {
    final notes = ref.read(notesProvider).value ?? <Note>[];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: 16),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            children: [
              Text(
                tr('关联备忘录（引用方式，改一处同步）'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              if (notes.isEmpty)
                Text(tr('还没有备忘录'), style: TextStyle(fontSize: 12)),
              for (final n in notes)
                CheckboxListTile(
                  value: _noteIds.contains(n.id),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    n.title?.isNotEmpty == true ? n.title! : tr('无标题'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5),
                  ),
                  onChanged: (on) {
                    setSheet(() {
                      on == true ? _noteIds.add(n.id) : _noteIds.remove(n.id);
                    });
                    setState(() {});
                  },
                ),
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tr('完成')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickRepeat() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 20),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in RecurrenceService.presets.entries)
              ListTile(
                dense: true,
                title: Text(e.key),
                trailing: e.value == _repeatRule
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.value),
              ),
            ListTile(
              dense: true,
              title: Text(tr('不重复')),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _repeatRule = picked.isEmpty ? null : picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('先写个标题'))));
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(taskRepositoryProvider);
    final id = await repo.create(
      title: title,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      importance: _importance,
      dueAt: _dueAt,
      remindAt: _remindAt,
      listId: _listId,
      repeatRule: _repeatRule,
    );
    if (_tagIds.isNotEmpty) {
      await repo.setTaskTags(id, _tagIds.toList());
    }
    for (final noteId in _noteIds) {
      await repo.linkNote(id, noteId);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }
}
