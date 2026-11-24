import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/tokens.dart';
import '../../core/db/database.dart';
import '../../core/log/app_log.dart';
import '../../core/ui/confirm.dart';
import '../settings/settings.dart';
import '../tasks/task_repository.dart';
import 'note_repository.dart';
import '../../core/i18n/i18n.dart';

final noteByIdProvider = StreamProvider.family<Note?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.notes,
  )..where((n) => n.id.equals(id))).watchSingleOrNull();
});

/// 备忘录编辑页。
///
/// 三种输入都要：Markdown 正文、图片附件、贴上就认的链接。
/// 编辑/预览一键切换，工具条只做「插入标记」这一件事——不做富文本，
/// 因为富文本会把内容锁进私有格式，导出和全文搜索都会变麻烦。
class MemoEditPage extends ConsumerStatefulWidget {
  const MemoEditPage({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<MemoEditPage> createState() => _MemoEditPageState();
}

class _MemoEditPageState extends ConsumerState<MemoEditPage> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tags = TextEditingController();
  final _bodyFocus = FocusNode();
  Timer? _debounce;
  bool _hydrated = false;
  bool _pinned = false;
  bool _preview = false;
  int _importance = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _hydrate(Note note) {
    if (_hydrated) return;
    _hydrated = true;
    _title.text = note.title ?? '';
    _body.text = note.bodyMd ?? '';
    _tags.text = note.tags ?? '';
    _pinned = note.pinned;
    _importance = note.importance;
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> _persist() async {
    await ref
        .read(noteRepositoryProvider)
        .saveNote(
          widget.noteId,
          title: _title.text.trim(),
          body: _body.text,
          tags: _tags.text.trim(),
          pinned: _pinned,
          importance: _importance,
        );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(noteByIdProvider(widget.noteId));
    final assets =
        ref.watch(noteAssetsProvider(widget.noteId)).value ??
        const <NoteAsset>[];
    final linked =
        ref.watch(noteLinkedTasksProvider(widget.noteId)).value ??
        const <Task>[];
    final palette = ref.watch(paletteProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(tr('编辑'))),
            ButtonSegment(value: true, label: Text(tr('预览'))),
          ],
          selected: {_preview},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _preview = s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            textStyle: WidgetStateProperty.all(TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          IconButton(
            tooltip: _pinned ? tr('取消置顶') : tr('置顶'),
            icon: Icon(_pinned ? Icons.favorite : Icons.favorite_border),
            color: _pinned ? scheme.primary : null,
            onPressed: () async {
              setState(() => _pinned = !_pinned);
              await _persist();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final db = ref.read(databaseProvider);
              switch (v) {
                case 'duplicate':
                  await ref
                      .read(noteRepositoryProvider)
                      .createNote(
                        title: trf('{}（副本）', [_title.text.trim()]),
                        body: _body.text,
                        tags: _tags.text.trim(),
                      );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(tr('已复制一条副本'))));
                  }
                case 'archive':
                  final ok = await confirmAction(
                    context,
                    title: tr('归档这条备忘录？'),
                    message: tr('归档后不在列表显示，任务引用与附件仍保留。'),
                    confirmLabel: tr('归档'),
                  );
                  if (!ok || !context.mounted) return;
                  await (db.update(db.notes)
                        ..where((n) => n.id.equals(widget.noteId)))
                      .write(NotesCompanion(archived: Value(true)));
                  if (context.mounted) Navigator.of(context).pop();
                case 'delete':
                  final ok = await confirmDanger(
                    context,
                    title: tr('删除这条备忘录？'),
                    message: tr('备忘录会移到回收站，附件仍保留在本机，30 天内可以恢复。'),
                  );
                  if (!ok || !context.mounted) return;
                  await (db.update(db.notes)
                        ..where((n) => n.id.equals(widget.noteId)))
                      .write(NotesCompanion(deletedAt: Value(DateTime.now())));
                  if (context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'duplicate', child: Text(tr('复制一份'))),
              PopupMenuItem(value: 'archive', child: Text(tr('归档'))),
              PopupMenuItem(value: 'delete', child: Text(tr('删除'))),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(trf('读取失败：{}', [e]))),
        data: (note) {
          if (note == null) return Center(child: Text(tr('备忘录不存在')));
          _hydrate(note);
          return ListView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              TextField(
                controller: _title,
                onChanged: (_) => _scheduleSave(),
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: tr('标题'),
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              SizedBox(height: 2),
              Text(
                trf('更新于 {}', [dfMonthDayTimeFmt().format(note.updatedAt)]),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
              SizedBox(height: 12),
              if (_preview)
                _MarkdownPreview(data: _body.text)
              else
                TextField(
                  controller: _body,
                  focusNode: _bodyFocus,
                  onChanged: (_) {
                    _scheduleSave();
                    setState(() {});
                  },
                  minLines: 10,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(fontSize: 14, height: 1.75),
                  decoration: InputDecoration(
                    hintText: tr('记点什么…\n\n支持 Markdown：# 标题、**加粗**、- 列表、`代码`、[链接](https://example.com)'),
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),

              SizedBox(height: 16),
              _tagsRow(scheme),
              SizedBox(height: 14),
              _attachments(scheme, assets),

              if (linked.isNotEmpty) ...[
                SizedBox(height: 16),
                Text(
                  trf('被 {} 个任务引用：{}', [
                    linked.length,
                    linked.map((t) => t.title).join(tr('、')),
                  ]),
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.6,
                    color: scheme.outline,
                  ),
                ),
              ],
              SizedBox(height: 20),
              Row(
                children: [
                  Text(
                    tr('重要性'),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(width: 10),
                  for (final e in Emphasis.values)
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () async {
                          setState(() => _importance = e.value);
                          await _persist();
                        },
                        child: Container(
                          width: 22,
                          height: 22,
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
                ],
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _preview
          ? null
          : SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  children: [
                    _tool(Icons.title, tr('标题'), () => _insert('# ', '')),
                    _tool(Icons.format_bold, tr('加粗'), () => _wrap('**', '**')),
                    _tool(Icons.format_italic, tr('斜体'), () => _wrap('*', '*')),
                    _tool(
                      Icons.check_box_outlined,
                      tr('待办'),
                      () => _insert('- [ ] ', ''),
                    ),
                    _tool(
                      Icons.format_list_bulleted,
                      tr('列表'),
                      () => _insert('- ', ''),
                    ),
                    _tool(Icons.format_quote, tr('引用'), () => _insert('> ', '')),
                    _tool(Icons.code, tr('代码'), () => _wrap('`', '`')),
                    _tool(Icons.link, tr('链接'), () => _wrap('[', '](https://)')),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _tool(IconData icon, String tip, VoidCallback onTap) {
    return Expanded(
      child: IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, size: 19),
        onPressed: onTap,
      ),
    );
  }

  void _insert(String text, String trailing) {
    final sel = _body.selection;
    final start = sel.start < 0 ? _body.text.length : sel.start;
    final end = sel.end < 0 ? start : sel.end;
    final selected = _body.text.substring(start, end);
    final next = _body.text.replaceRange(start, end, '$text$selected$trailing');
    _body.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + text.length + selected.length + trailing.length,
      ),
    );
    _bodyFocus.requestFocus();
    _scheduleSave();
    setState(() {});
  }

  void _wrap(String prefix, String suffix) {
    final sel = _body.selection;
    final start = sel.start < 0 ? _body.text.length : sel.start;
    final end = sel.end < 0 ? start : sel.end;
    final selected = _body.text.substring(start, end);
    final next = _body.text.replaceRange(start, end, '$prefix$selected$suffix');
    _body.value = TextEditingValue(
      text: next,
      selection: TextSelection(
        baseOffset: start + prefix.length,
        extentOffset: start + prefix.length + selected.length,
      ),
    );
    _bodyFocus.requestFocus();
    _scheduleSave();
    setState(() {});
  }

  Widget _tagsRow(ColorScheme scheme) {
    return TextField(
      controller: _tags,
      onChanged: (_) => _scheduleSave(),
      style: TextStyle(fontSize: 12.5),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: Icon(
          Icons.local_offer_outlined,
          size: 16,
          color: scheme.outline,
        ),
        prefixIconConstraints: BoxConstraints(minWidth: 32),
        hintText: tr('标签，用逗号分隔'),
        hintStyle: TextStyle(fontSize: 12.5, color: scheme.outline),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _attachments(ColorScheme scheme, List<NoteAsset> assets) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (assets.isEmpty)
            Column(
              children: [
                Icon(Icons.attach_file, size: 22, color: scheme.outline),
                SizedBox(height: 6),
                Text(
                  tr('暂无附件'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  tr('图片、PDF、Word、PPT、txt 等都可添加，复制到应用目录，离线可用'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
              ],
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in assets.where((a) => a.type == 0))
                  GestureDetector(
                    onTap: () => _viewImage(a),
                    onLongPress: () => _removeImage(a),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(a.localPath),
                        width: 92,
                        height: 92,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 92,
                          height: 92,
                          color: scheme.surface,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 20,
                            color: scheme.outline,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 8),
            for (final a in assets.where((a) => a.type != 0))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _fileIcon(a.localPath),
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                title: Text(
                  a.localPath.split(Platform.pathSeparator).last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  _fmtSize(a.size ?? 0),
                  style: TextStyle(fontSize: 10.5, color: scheme.outline),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close, size: 15, color: scheme.outline),
                  onPressed: () => _removeImage(a),
                ),
              ),
          ],
          SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickAttachment,
            icon: Icon(Icons.add, size: 16),
            label: Text(tr('添加附件'), style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAttachment() async {
    final scheme = Theme.of(context).colorScheme;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        minimum: EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.image_outlined, size: 20),
              title: Text(tr('添加图片')),
              onTap: () => Navigator.of(ctx).pop('image'),
            ),
            ListTile(
              leading: Icon(Icons.attach_file, size: 20),
              title: Text(tr('添加文件')),
              subtitle: Text(
                tr('PDF、Word、PPT、txt 等'),
                style: TextStyle(fontSize: 11, color: scheme.outline),
              ),
              onTap: () => Navigator.of(ctx).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (kind == 'image') {
      await _pickImage();
    } else if (kind == 'file') {
      await _pickFile();
    }
  }

  Future<void> _pickFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final picked = files.single;
      final path = picked.path;
      if (path == null) return;
      await ref
          .read(noteRepositoryProvider)
          .addFile(widget.noteId, File(path), picked.name);
      AppLog.i(tr('备忘录添加文件'));
      if (mounted) setState(() {});
    } catch (e) {
      AppLog.e(trf('添加文件失败：{}', [e]));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('添加文件失败：{}', [e]))));
    }
  }

  IconData _fileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'doc' || 'docx' => Icons.description_outlined,
      'ppt' || 'pptx' => Icons.slideshow_outlined,
      'xls' || 'xlsx' => Icons.table_chart_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
      );
      if (picked == null) return;
      final asset = await ref
          .read(noteRepositoryProvider)
          .addImage(widget.noteId, File(picked.path));
      AppLog.i(trf('备忘录添加图片，{} KB', [(asset.size ?? 0) ~/ 1024]));
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      AppLog.e(trf('添加图片失败：{}', [e]));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('添加图片失败：{}', [e]))));
    }
  }

  void _viewImage(NoteAsset asset) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.all(8),
        child: InteractiveViewer(
          maxScale: 4,
          child: Image.file(File(asset.localPath)),
        ),
      ),
    );
  }

  Future<void> _removeImage(NoteAsset asset) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('移除这张图片？')),
        content: Text(tr('只从备忘录移出，不影响相册里的原图。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('移除')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(noteRepositoryProvider).deleteAsset(asset.id);
    if (mounted) setState(() {});
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (data.trim().isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            tr('还没有内容'),
            style: TextStyle(fontSize: 12.5, color: scheme.outline),
          ),
        ),
      );
    }
    return MarkdownBody(
      data: data,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: 14, height: 1.75),
        h1: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        h2: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        h3: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        listBullet: TextStyle(fontSize: 14, height: 1.7),
        blockquoteDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
        ),
        code: TextStyle(
          fontSize: 12.5,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        a: TextStyle(color: scheme.primary),
      ),
      onTapLink: (text, href, title) {
        // 链接只显示地址不跳转：V1 没有 url_launcher，避免「以为能打开」
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(href ?? text)));
      },
    );
  }
}
