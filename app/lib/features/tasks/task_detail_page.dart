import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../../core/ui/confirm.dart';
import '../../core/ui/schedule_sheet.dart';
import '../focus/focus_page.dart';
import '../memos/memo_edit_page.dart';
import '../memos/memo_page.dart' show notesProvider;
import '../settings/settings.dart';
import 'recurrence.dart';
import 'task_repository.dart';
import '../../core/i18n/i18n.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  const TaskDetailPage({super.key, required this.taskId});

  final String taskId;

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  Timer? _debounce;
  bool _initialized = false;
  int _importance = 0;
  DateTime? _dueAt;
  String _listId = 'inbox';
  String? _repeatRule;
  bool _pinned = false;
  DateTime? _remindAt;
  final _summaryController = TextEditingController();
  final _subtaskController = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _notesController.dispose();
    _subtaskController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _hydrate(Task task) {
    if (_initialized) return;
    _initialized = true;
    _titleController.text = task.title;
    _notesController.text = task.notes ?? '';
    _importance = task.importance;
    _dueAt = task.dueAt;
    _listId = task.listId;
    _repeatRule = task.repeatRule;
    _pinned = task.pinned;
    _remindAt = task.remindAt;
    _summaryController.text = task.completedSummary ?? '';
  }

  void _scheduleTextSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ref
          .read(taskRepositoryProvider)
          .updateTask(
            widget.taskId,
            title: _titleController.text,
            notes: _notesController.text,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(taskByIdProvider(widget.taskId));
    final palette = ref.watch(paletteProvider);
    final lists = ref.watch(listsProvider).value ?? const <TaskList>[];
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: async.value == null
          ? null
          : _DetailActionBar(task: async.value!, onReschedule: _pickDate),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: tr('删除'),
            icon: Icon(Icons.delete_outline),
            onPressed: () async {
              final task = ref.read(taskByIdProvider(widget.taskId)).value;
              final ok = await confirmDanger(
                context,
                title: trf('删除「{}」？', [task?.title ?? tr('这个任务')]),
                message: tr('任务会移到回收站，保留 30 天，期间可以恢复。'),
              );
              if (!ok || !context.mounted) return;
              await ref.read(taskRepositoryProvider).softDelete(widget.taskId);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (task) {
          if (task == null) {
            return Center(child: Text(tr('任务不存在')));
          }
          _hydrate(task);
          final listName = lists
              .where((l) => l.id == _listId)
              .map((l) => l.name)
              .firstOrNull;

          return ListView(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () async {
                      await ref
                          .read(taskRepositoryProvider)
                          .setDone(widget.taskId, true);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Container(
                      margin: EdgeInsets.only(top: 6, right: 12),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _importance == 0
                              ? scheme.outline
                              : palette.of(Emphasis.fromValue(_importance)),
                          width: 1.8,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      onChanged: (_) => _scheduleTextSave(),
                      maxLines: null,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        hintText: tr('任务标题'),
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
              if (task.status == 1) ...[
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: scheme.primary),
                      SizedBox(width: 8),
                      Text(
                        task.completedAt == null
                            ? tr('已完成')
                            : trf('完成于 {}', [dfMonthDayTimeFmt().format(task.completedAt!)]),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () async {
                          await ref
                              .read(taskRepositoryProvider)
                              .setDone(widget.taskId, false);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Text(
                          tr('撤销完成'),
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  tr('完成总结'),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 4),
                TextField(
                  controller: _summaryController,
                  minLines: 2,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: tr('这次做成了什么？卡在哪里？下次怎么更快？'),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(fontSize: 13.5, height: 1.6),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(Duration(milliseconds: 500), () {
                      ref
                          .read(taskRepositoryProvider)
                          .setCompletedSummary(widget.taskId, v);
                    });
                  },
                ),
              ],
              SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    icon: Icons.folder_outlined,
                    label: listName ?? tr('收件箱'),
                    onTap: () => _pickList(lists),
                  ),
                  _Chip(
                    icon: Icons.event_outlined,
                    label: _dueAt == null
                        ? tr('无日期')
                        : dfMonthDayTimeFmt().format(_dueAt!),
                    onTap: _pickDate,
                  ),
                  _Chip(
                    icon: Icons.notifications_none,
                    label: _remindAt == null
                        ? tr('不提醒')
                        : dfMonthDayTimeFmt().format(_remindAt!),
                    accent: _remindAt == null ? null : scheme.primary,
                    onTap: _pickRemind,
                  ),
                  _Chip(
                    icon: Icons.flag_outlined,
                    label: trf('重要性 {}', [Emphasis.fromValue(_importance).label]),
                    accent: _importance == 0
                        ? null
                        : palette.of(Emphasis.fromValue(_importance)),
                  ),
                  _Chip(
                    icon: Icons.repeat,
                    label: RecurrenceService.labelOf(_repeatRule),
                    accent: _repeatRule == null ? null : scheme.primary,
                    onTap: _pickRepeat,
                  ),
                  _Chip(
                    icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: _pinned ? tr('已置顶') : tr('置顶'),
                    accent: _pinned ? scheme.primary : null,
                    onTap: () async {
                      setState(() => _pinned = !_pinned);
                      await ref
                          .read(taskRepositoryProvider)
                          .setPinned(widget.taskId, _pinned);
                    },
                  ),
                ],
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
                        onTap: () {
                          setState(() => _importance = e.value);
                          ref
                              .read(taskRepositoryProvider)
                              .updateTask(widget.taskId, importance: e.value);
                        },
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
                  Text(
                    Emphasis.fromValue(_importance).label,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 22),
              _subtasksSection(context, ref, scheme),
              SizedBox(height: 18),
              _tagsSection(context, ref, scheme),
              SizedBox(height: 18),
              _notesSection(context, ref, scheme),
              SizedBox(height: 18),
              Text(
                tr('备注'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              SizedBox(height: 6),
              TextField(
                controller: _notesController,
                onChanged: (_) => _scheduleTextSave(),
                minLines: 4,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(hintText: tr('补充说明、链接或要点…')),
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
              SizedBox(height: 20),
              Text(
                trf('创建于 {}', [dfFullDateTimeFmt().format(task.createdAt)]),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _subtasksSection(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    final subs =
        ref.watch(subtasksProvider(widget.taskId)).value ?? <Task>[];
    final repo = ref.read(taskRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              tr('子任务'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            SizedBox(width: 6),
            Text(
              '${subs.where((s) => s.status == 1).length}/${subs.length}',
              style: TextStyle(fontSize: 11, color: scheme.outline),
            ),
          ],
        ),
        SizedBox(height: 4),
        for (final sub in subs)
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  sub.status == 1
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: sub.status == 1 ? scheme.primary : scheme.outline,
                ),
                onPressed: () => repo.setDone(sub.id, sub.status != 1),
              ),
              Expanded(
                child: Text(
                  sub.title,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: sub.status == 1 ? scheme.outline : scheme.onSurface,
                    decoration: sub.status == 1
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('删除子任务'),
                icon: Icon(Icons.close, size: 16, color: scheme.outline),
                onPressed: () async {
                  final ok = await confirmDanger(
                    context,
                    title: trf('删除子任务「{}」？', [sub.title]),
                    message: tr('删除后进回收站，30 天内可以恢复。'),
                  );
                  if (ok) await repo.softDelete(sub.id);
                },
              ),
            ],
          ),
        Row(
          children: [
            Icon(Icons.add, size: 16, color: scheme.outline),
            SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _subtaskController,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) async {
                  final text = v.trim();
                  if (text.isEmpty) return;
                  await repo.createSubtask(
                    widget.taskId,
                    text,
                    listId: _listId,
                  );
                  _subtaskController.clear();
                },
                decoration: InputDecoration(
                  hintText: tr('添加子任务，回车保存'),
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tagsSection(BuildContext context, WidgetRef ref, ColorScheme scheme) {
    final tags = ref.watch(tagsProvider).value ?? <Tag>[];
    final selected =
        ref.watch(taskTagIdsProvider(widget.taskId)).value ?? <String>[];
    final repo = ref.read(taskRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('标签'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              FilterChip(
                label: Text(tag.name, style: TextStyle(fontSize: 12)),
                selected: selected.contains(tag.id),
                visualDensity: VisualDensity.compact,
                onSelected: (on) {
                  final next = [...selected];
                  on ? next.add(tag.id) : next.remove(tag.id);
                  repo.setTaskTags(widget.taskId, next);
                },
                onDeleted: () => repo.deleteTag(tag.id),
              ),
            ActionChip(
              avatar: Icon(Icons.add, size: 14),
              label: Text(tr('新建标签'), style: TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final name = await _promptTagName(context);
                if (name == null) return;
                final tag = await repo.createTag(name);
                await repo.setTaskTags(widget.taskId, [...selected, tag.id]);
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<String?> _promptTagName(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('新建标签')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('标签名')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              Navigator.of(ctx).pop(v.isEmpty ? null : v);
            },
            child: Text(tr('创建')),
          ),
        ],
      ),
    );
  }

  Widget _notesSection(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    final linked =
        ref.watch(linkedNotesProvider(widget.taskId)).value ?? <Note>[];
    final all = ref.watch(notesProvider).value ?? <Note>[];
    final repo = ref.read(taskRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              tr('关联备忘录'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.symmetric(horizontal: 6),
              ),
              icon: Icon(Icons.add, size: 15),
              label: Text(tr('选择'), style: TextStyle(fontSize: 12)),
              onPressed: () async {
                final candidates = all.where(
                  (n) => !linked.any((l) => l.id == n.id),
                );
                if (candidates.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('没有可选的备忘录，先到备忘录里新建'))),
                  );
                  return;
                }
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => SafeArea(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: Text(
                            tr('选择备忘录（引用方式，改一处同步）'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final n in candidates)
                          ListTile(
                            dense: true,
                            title: Text(
                              n.title?.isNotEmpty == true ? n.title! : tr('无标题'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.of(ctx).pop(n.id),
                          ),
                      ],
                    ),
                  ),
                );
                if (picked != null) await repo.linkNote(widget.taskId, picked);
              },
            ),
          ],
        ),
        if (linked.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              tr('还没有关联。备忘录是独立实体，同一份资料可被多个任务引用。'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: scheme.outline,
              ),
            ),
          )
        else
          for (final n in linked)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.sticky_note_2_outlined,
                size: 18,
                color: scheme.outline,
              ),
              title: Text(
                n.title?.isNotEmpty == true ? n.title! : tr('无标题'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5),
              ),
              subtitle: (n.bodyMd ?? '').isEmpty
                  ? null
                  : Text(
                      (n.bodyMd ?? '').replaceAll('\n', ' '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MemoEditPage(noteId: n.id),
                ),
              ),
              trailing: IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.link_off, size: 16, color: scheme.outline),
                onPressed: () => repo.unlinkNote(widget.taskId, n.id),
              ),
            ),
      ],
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
            Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Center(
                child: Text(
                  tr('重复'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
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
              trailing: _repeatRule == null
                  ? Icon(Icons.check, size: 18)
                  : null,
              onTap: () => Navigator.of(ctx).pop(''),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final rule = picked.isEmpty ? null : picked;
    setState(() => _repeatRule = rule);
    await ref.read(taskRepositoryProvider).setRepeat(widget.taskId, rule);
  }

  /// 日期与提醒统一走排期面板；提醒按「相对日期的偏移」跟随平移。
  Future<void> _pickDate() async {
    final offset = (_dueAt != null && _remindAt != null)
        ? _dueAt!.difference(_remindAt!).inMinutes
        : null;
    final res = await ScheduleSheet.show(
      context,
      initialDue: _dueAt,
      initialRemindOffset: offset == null || offset < 0 ? 0 : offset,
    );
    if (res == null || !mounted) return;

    final repo = ref.read(taskRepositoryProvider);
    if (res.dueAt == null) {
      setState(() {
        _dueAt = null;
        _remindAt = null;
      });
      await repo.updateTask(widget.taskId, clearDue: true);
      await repo.setRemindAt(widget.taskId, null);
      return;
    }

    setState(() {
      _dueAt = res.dueAt;
      _remindAt = res.remindOffset == null
          ? null
          : res.dueAt!.subtract(Duration(minutes: res.remindOffset!));
    });
    await repo.updateTask(widget.taskId, dueAt: res.dueAt);
    await repo.setRemindAt(widget.taskId, _remindAt);
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
            ListTile(
              dense: true,
              title: Text(tr('不提醒')),
              onTap: () => Navigator.of(ctx).pop('none'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'none') {
      setState(() => _remindAt = null);
      await ref.read(taskRepositoryProvider).setRemindAt(widget.taskId, null);
      return;
    }

    DateTime value;
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
      value = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    } else {
      final due = _dueAt;
      if (due == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr('先设置日期，才能按「准时/提前」计算提醒'))));
        return;
      }
      value = choice == 'exact'
          ? due
          : due.subtract(Duration(minutes: int.parse(choice)));
    }

    setState(() => _remindAt = value);
    await ref.read(taskRepositoryProvider).setRemindAt(widget.taskId, value);
  }

  Future<void> _pickList(List<TaskList> lists) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                tr('移动到清单'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            for (final l in lists)
              ListTile(
                dense: true,
                title: Text(l.name),
                trailing: l.id == _listId
                    ? Icon(Icons.check, size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(l.id),
              ),
            ListTile(
              dense: true,
              leading: Icon(Icons.add, size: 18),
              title: Text(tr('新建清单')),
              onTap: () async {
                final name = await _promptListName(ctx);
                if (name != null && ctx.mounted) Navigator.of(ctx).pop(name);
              },
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;

    if (selected.startsWith('__new__:')) {
      final created = await ref
          .read(taskRepositoryProvider)
          .createList(selected.substring(8));
      setState(() => _listId = created.id);
      await ref
          .read(taskRepositoryProvider)
          .updateTask(widget.taskId, listId: created.id);
    } else {
      setState(() => _listId = selected);
      await ref
          .read(taskRepositoryProvider)
          .updateTask(widget.taskId, listId: selected);
    }
  }

  Future<String?> _promptListName(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('新建清单')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('清单名称')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.of(ctx).pop(name.isEmpty ? null : '__new__:$name');
            },
            child: Text(tr('创建')),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

/// 详情页底部固定操作条：完成 / 专注 / 改期 / 归档。
/// 长任务滚到多深都不用滑回顶部；完成后第一项变「撤销完成」。
class _DetailActionBar extends ConsumerWidget {
  const _DetailActionBar({required this.task, required this.onReschedule});

  final Task task;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final done = task.status == 1;

    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool primary = false,
    }) {
      final color = primary ? scheme.primary : scheme.onSurfaceVariant;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: color),
                SizedBox(height: 3),
                Text(label, style: TextStyle(fontSize: 10, color: color)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        // 宽屏右栏里 padding.bottom 可能为 0，会让文字贴着系统导航条被裁；
        // 用 minimum 兜底，手机上也不会多出明显留白。
        minimum: EdgeInsets.only(bottom: 4),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              item(
                done ? Icons.undo : Icons.check_circle_outline,
                done ? tr('撤销完成') : tr('完成'),
                () async {
                  await ref
                      .read(taskRepositoryProvider)
                      .setDone(task.id, !done);
                },
                primary: true,
              ),
              item(Icons.timer_outlined, tr('专注'), () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FocusPage(
                      initialTaskId: task.id,
                      initialTaskTitle: task.title,
                    ),
                  ),
                );
              }),
              item(Icons.event_outlined, tr('改期'), onReschedule),
              item(Icons.archive_outlined, tr('归档'), () async {
                await ref.read(taskRepositoryProvider).archiveTask(task.id);
                if (context.mounted) Navigator.of(context).pop();
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// 打开任务详情的统一入口。
///
/// 手机：整页 push。
/// 宽屏（≥980dp）：右侧 480dp 面板覆盖，左侧列表保持可见——这才是「三栏」的右栏，
/// 点遮罩或按 Esc 关闭。详情页本身不需要改造，换的只是路由的呈现方式。
Future<void> openTaskDetail(BuildContext context, String taskId) {
  final wide = MediaQuery.sizeOf(context).width >= 980;
  if (!wide) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => TaskDetailPage(taskId: taskId)),
    );
  }
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.10),
      transitionDuration: Duration(milliseconds: 200),
      pageBuilder: (ctx, _, _) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 480,
          child: Material(elevation: 12, child: TaskDetailPage(taskId: taskId)),
        ),
      ),
      transitionsBuilder: (ctx, anim, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}
