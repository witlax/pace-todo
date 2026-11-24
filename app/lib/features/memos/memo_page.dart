import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../../core/ui/bottom_sheet_inset.dart';
import '../../core/ui/confirm.dart';
import '../settings/settings.dart';
import '../tasks/task_repository.dart';
import 'memo_edit_page.dart';
import 'note_repository.dart';
import '../../core/i18n/i18n.dart';

final notesProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.notes)
    ..where((n) => n.deletedAt.isNull() & n.archived.equals(false));
  return query.watch();
});

/// 备忘录的三种呈现：单列卡片（信息全）、双列卡片（扫得快，信息仍分层）、列表（密度最高）。
enum MemoView { card, grid, list }

enum MemoSort {
  updated('最近修改'),
  created('创建时间'),
  title('按标题');

  const MemoSort(this._label);
  final String _label;

  String get label => tr(_label);
}

class MemoViewNotifier extends Notifier<MemoView> {
  static const _key = 'memo.view';

  @override
  MemoView build() {
    final raw = ref.read(prefsProvider).getString(_key);
    return MemoView.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MemoView.card,
    );
  }

  void set(MemoView value) {
    state = value;
    ref.read(prefsProvider).setString(_key, value.name);
  }
}

final memoViewProvider = NotifierProvider<MemoViewNotifier, MemoView>(
  MemoViewNotifier.new,
);

class MemoSortNotifier extends Notifier<MemoSort> {
  static const _key = 'memo.sort';

  @override
  MemoSort build() {
    final raw = ref.read(prefsProvider).getString(_key);
    return MemoSort.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MemoSort.updated,
    );
  }

  void set(MemoSort value) {
    state = value;
    ref.read(prefsProvider).setString(_key, value.name);
  }
}

final memoSortProvider = NotifierProvider<MemoSortNotifier, MemoSort>(
  MemoSortNotifier.new,
);

class MemoPage extends ConsumerWidget {
  const MemoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesProvider);
    final palette = ref.watch(paletteProvider);
    final view = ref.watch(memoViewProvider);
    final sort = ref.watch(memoSortProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAdd(context, ref),
        child: Icon(Icons.edit_outlined),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                children: [
                  Text(
                    tr('备忘录'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Spacer(),
                  Text(
                    trf('{} 条', [notesAsync.value?.length ?? 0]),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(width: 4),
                  IconButton(
                    tooltip: switch (view) {
                      MemoView.card => tr('切换为双列'),
                      MemoView.grid => tr('切换为列表'),
                      MemoView.list => tr('切换为单列卡片'),
                    },
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        ref.read(memoViewProvider.notifier).set(switch (view) {
                          MemoView.card => MemoView.grid,
                          MemoView.grid => MemoView.list,
                          MemoView.list => MemoView.card,
                        }),
                    icon: Icon(switch (view) {
                      MemoView.card => Icons.grid_view_outlined,
                      MemoView.grid => Icons.view_list_outlined,
                      MemoView.list => Icons.view_agenda_outlined,
                    }, size: 20),
                  ),
                  PopupMenuButton<MemoSort>(
                    tooltip: tr('排序'),
                    initialValue: sort,
                    onSelected: ref.read(memoSortProvider.notifier).set,
                    icon: Icon(Icons.sort, size: 20),
                    itemBuilder: (_) => [
                      for (final s in MemoSort.values)
                        PopupMenuItem(
                          value: s,
                          child: Row(
                            children: [
                              Icon(
                                s == sort ? Icons.check : Icons.remove,
                                size: 15,
                                color: s == sort
                                    ? scheme.primary
                                    : Colors.transparent,
                              ),
                              SizedBox(width: 6),
                              Text(
                                s.label,
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: notesAsync.when(
                loading: () => Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
                data: (notes) {
                  if (notes.isEmpty) return _EmptyMemos();
                  final ordered = _sorted(notes, sort);
                  if (view == MemoView.grid) {
                    return GridView.builder(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
                      itemCount: ordered.length,
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 142,
                          ),
                      itemBuilder: (_, i) => GestureDetector(
                        onLongPress: () =>
                            _showActions(context, ref, ordered[i]),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _open(context, ordered[i]),
                          child: _NoteGridCard(
                            note: ordered[i],
                            palette: palette,
                          ),
                        ),
                      ),
                    );
                  }
                  if (view == MemoView.list) {
                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(20, 2, 20, 96),
                      itemCount: ordered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                      itemBuilder: (_, i) => _NoteRow(
                        note: ordered[i],
                        palette: palette,
                        onTap: () => _open(context, ordered[i]),
                        onLongPress: () =>
                            _showActions(context, ref, ordered[i]),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 96),
                    itemCount: ordered.length,
                    separatorBuilder: (_, _) => SizedBox(height: 10),
                    itemBuilder: (_, i) => GestureDetector(
                      onLongPress: () => _showActions(context, ref, ordered[i]),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _open(context, ordered[i]),
                        child: _NoteCard(note: ordered[i], palette: palette),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 置顶永远在最前，其余按选择的维度排序。
  List<Note> _sorted(List<Note> notes, MemoSort sort) {
    final list = [...notes];
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return switch (sort) {
        MemoSort.updated => b.updatedAt.compareTo(a.updatedAt),
        MemoSort.created => b.createdAt.compareTo(a.createdAt),
        MemoSort.title => (a.title ?? '').compareTo(b.title ?? ''),
      };
    });
    return list;
  }

  void _open(BuildContext context, Note note) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MemoEditPage(noteId: note.id)),
    );
  }

  /// 长按菜单：置顶 / 复制 / 归档 / 删除。归档与删除都先确认。
  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    Note note,
  ) async {
    final pinned = note.pinned;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        Widget row(IconData icon, String label, String value, {Color? color}) {
          return ListTile(
            dense: true,
            leading: Icon(
              icon,
              size: 19,
              color: color ?? scheme.onSurfaceVariant,
            ),
            title: Text(label, style: TextStyle(fontSize: 13.5, color: color)),
            onTap: () => Navigator.of(ctx).pop(value),
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    note.title?.isNotEmpty == true ? note.title! : tr('无标题'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Divider(height: 1),
              row(
                pinned ? Icons.push_pin : Icons.push_pin_outlined,
                pinned ? tr('取消置顶') : tr('置顶'),
                'pin',
              ),
              row(Icons.copy_all_outlined, tr('复制一份'), 'copy'),
              row(Icons.archive_outlined, tr('归档'), 'archive'),
              row(
                Icons.delete_outline,
                tr('删除'),
                'delete',
                color: Theme.of(ctx).colorScheme.error,
              ),
              SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null || !context.mounted) return;

    final db = ref.read(databaseProvider);
    switch (action) {
      case 'pin':
        await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
          NotesCompanion(pinned: Value(!pinned)),
        );
        if (!context.mounted) return;
        _toast(context, pinned ? tr('已取消置顶') : tr('已置顶'));
      case 'copy':
        await ref
            .read(noteRepositoryProvider)
            .createNote(
              title: trf('{}（副本）', [note.title ?? tr('无标题')]),
              body: note.bodyMd,
              tags: note.tags,
            );
        if (!context.mounted) return;
        _toast(context, tr('已复制一条副本'));
      case 'archive':
        final ok = await confirmAction(
          context,
          title: tr('归档这条备忘录？'),
          message: tr('归档后不在列表显示；任务引用与附件都保留。'),
          confirmLabel: tr('归档'),
        );
        if (!ok || !context.mounted) return;
        await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
          NotesCompanion(archived: Value(true)),
        );
        if (!context.mounted) return;
        _toast(context, tr('已归档'));
      case 'delete':
        final ok = await confirmDanger(
          context,
          title: tr('删除这条备忘录？'),
          message: tr('会移到回收站，附件仍保留在本机，30 天内可以恢复。'),
        );
        if (!ok || !context.mounted) return;
        await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
          NotesCompanion(deletedAt: Value(DateTime.now())),
        );
        if (!context.mounted) return;
        _toast(context, tr('已移到回收站'));
    }
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 2),
          content: Text(text, style: TextStyle(fontSize: 12.5)),
        ),
      );
  }

  void _showAdd(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, sheetBottomInset(sheetContext)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('新建备忘录'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(hintText: tr('随手记点什么…')),
            ),
            SizedBox(height: 14),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                final id = await ref
                    .read(noteRepositoryProvider)
                    .createNote(title: text.split('\n').first, body: text);
                if (!sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                Navigator.of(sheetContext).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MemoEditPage(noteId: id),
                  ),
                );
              },
              child: Text(tr('保存')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMemos extends StatelessWidget {
  const _EmptyMemos();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 40, color: scheme.outline),
          SizedBox(height: 10),
          Text(tr('还没有备忘录'), style: TextStyle(color: scheme.onSurfaceVariant)),
          SizedBox(height: 4),
          Text(
            tr('先收集，再整理'),
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.palette});

  final Note note;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final emphasis = Emphasis.fromValue(note.importance);
    final scheme = Theme.of(context).colorScheme;
    final body = (note.bodyMd ?? '').replaceAll('\n', ' ');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 36,
            margin: EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: emphasis == Emphasis.none
                  ? Colors.transparent
                  : palette.of(emphasis),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (note.pinned) ...[
                      Icon(Icons.push_pin, size: 12, color: scheme.primary),
                      SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        note.title?.isNotEmpty == true ? note.title! : tr('无标题'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  SizedBox(height: 3),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if ((note.tags ?? '').trim().isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(
                    note.tags!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: scheme.primary),
                  ),
                ],
                SizedBox(height: 6),
                Text(
                  dfMonthDayTimeFmt().format(note.updatedAt),
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表视图：一行一条，左侧色条仍表示重要性，右侧给日期。
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.note,
    required this.palette,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final Palette palette;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emphasis = Emphasis.fromValue(note.importance);
    final body = (note.bodyMd ?? '').replaceAll('\n', ' ').trim();

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 2.5,
              height: 26,
              margin: EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: emphasis == Emphasis.none
                    ? scheme.outlineVariant.withValues(alpha: 0.4)
                    : palette.of(emphasis),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (note.pinned)
              Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.push_pin, size: 12, color: scheme.primary),
              ),
            Expanded(
              child: Text(
                note.title?.isNotEmpty == true ? note.title! : tr('无标题'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (body.isNotEmpty) ...[
              SizedBox(width: 10),
              Flexible(
                flex: 2,
                child: Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            SizedBox(width: 8),
            Text(
              DateFormat('M-d').format(note.updatedAt),
              style: TextStyle(fontSize: 10, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 双列卡片：宽度只有单列的一半，所以把「色条 + 标题 + 两行摘要 + 时间」
/// 竖着堆，标签让位给摘要——两列里放三个标签会挤成马赛克。
class _NoteGridCard extends StatelessWidget {
  const _NoteGridCard({required this.note, required this.palette});

  final Note note;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emphasis = Emphasis.fromValue(note.importance);
    final body = (note.bodyMd ?? '').replaceAll('\n', ' ').trim();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            color: emphasis == Emphasis.none
                ? scheme.outlineVariant.withValues(alpha: 0.4)
                : palette.of(emphasis),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          note.title?.isNotEmpty == true ? note.title! : tr('无标题'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (note.pinned)
                        Padding(
                          padding: EdgeInsets.only(left: 3, top: 1),
                          child: Icon(
                            Icons.push_pin,
                            size: 11,
                            color: scheme.primary,
                          ),
                        ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    SizedBox(height: 4),
                    Expanded(
                      child: Text(
                        body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ] else
                    Spacer(),
                  SizedBox(height: 4),
                  Text(
                    DateFormat('M-d HH:mm').format(note.updatedAt),
                    style: TextStyle(fontSize: 9, color: scheme.outline),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
