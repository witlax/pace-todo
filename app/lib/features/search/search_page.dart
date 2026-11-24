import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../memos/memo_edit_page.dart';
import '../tags/tags_page.dart';
import '../tasks/task_detail_page.dart';
import '../tasks/task_repository.dart';
import '../../core/i18n/i18n.dart';

/// 全屏搜索。查任务标题/备注与备忘录正文，结果分组展示。
/// 数据量小时用 LIKE 足够；接 FTS5 时只换这里，不动界面。
final _taskSearchProvider = FutureProvider.family<List<Task>, String>((
  ref,
  q,
) async {
  final keyword = q.trim();
  if (keyword.isEmpty) return const [];
  final db = ref.watch(databaseProvider);
  final pattern = '%$keyword%';
  final query = db.select(db.tasks)
    ..where(
      (t) =>
          t.deletedAt.isNull() &
          (t.title.like(pattern) | t.notes.like(pattern)),
    )
    ..orderBy([
      (t) => OrderingTerm(expression: t.status),
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
    ])
    ..limit(50);
  return query.get();
});

final _noteSearchProvider = FutureProvider.family<List<Note>, String>((
  ref,
  q,
) async {
  final keyword = q.trim();
  if (keyword.isEmpty) return const [];
  final db = ref.watch(databaseProvider);
  final pattern = '%$keyword%';
  final query = db.select(db.notes)
    ..where(
      (n) =>
          n.deletedAt.isNull() &
          (n.title.like(pattern) | n.bodyMd.like(pattern)),
    )
    ..orderBy([
      (n) => OrderingTerm(expression: n.updatedAt, mode: OrderingMode.desc),
    ])
    ..limit(20);
  return query.get();
});

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _query = value);
    });
  }

  /// 支持的语法：`!高/!中/!低` 只看对应重要性；`#标签` 按标签名过滤。
  int? get _importanceFilter {
    final q = _query.trim();
    if (!q.startsWith('!')) return null;
    return switch (q.substring(1, q.length >= 2 ? 2 : 1)) {
      '高' || 'high' => 3,
      '中' || 'medium' => 2,
      '低' || 'low' => 1,
      _ => null,
    };
  }

  String get _keyword {
    var q = _query.trim();
    if (q.startsWith('!') && q.length >= 2) q = q.substring(2).trim();
    if (q.startsWith('#')) q = q.substring(1).trim();
    return q;
  }

  /// 命中词高亮：只标第一处，避免长文本满屏黄色。
  Widget _mark(String text, {TextStyle? style}) {
    final kw = _keyword;
    if (kw.isEmpty) return Text(text, style: style);
    final i = text.toLowerCase().indexOf(kw.toLowerCase());
    if (i < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, i)),
          TextSpan(
            text: text.substring(i, i + kw.length),
            style: TextStyle(
              backgroundColor: Color(0xFFFDF0C9),
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: text.substring(i + kw.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rawTasks = _query.trim().isEmpty
        ? <Task>[]
        : ref.watch(_taskSearchProvider(_keyword)).value ?? <Task>[];
    final impFilter = _importanceFilter;
    final tasks = impFilter == null
        ? rawTasks
        : rawTasks.where((t) => t.importance == impFilter).toList();
    final tags = _query.trim().isEmpty
        ? <Tag>[]
        : (ref.watch(tagsProvider).value ?? <Tag>[])
              .where((t) => t.name.contains(_keyword))
              .toList();
    final notes = _query.trim().isEmpty
        ? <Note>[]
        : ref.watch(_noteSearchProvider(_query)).value ?? <Note>[];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            hintText: tr('搜索任务、备忘录'),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              tooltip: tr('清空'),
              icon: Icon(Icons.close, size: 20),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: _query.trim().isEmpty
          ? _EmptyTips(
              onPick: (word) {
                _controller.text = word;
                setState(() => _query = word);
              },
            )
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (tasks.isEmpty && notes.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(
                      child: Text(
                        trf('没有匹配「{}」的内容', [_query]),
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                if (tasks.isNotEmpty) ...[
                  _header(context, tr('任务'), tasks.length),
                  for (final t in tasks)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        t.status == 1
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                        size: 18,
                        color: scheme.outline,
                      ),
                      title: _mark(t.title),
                      subtitle: Text(
                        [
                          if (t.dueAt != null)
                            dfMonthDayTimeFmt().format(t.dueAt!),
                          if (t.status == 1) tr('已完成'),
                        ].join(' · '),
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                      onTap: () => openTaskDetail(context, t.id),
                    ),
                ],
                if (notes.isNotEmpty) ...[
                  _header(context, tr('备忘录'), notes.length),
                  for (final n in notes)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.sticky_note_2_outlined,
                        size: 18,
                        color: scheme.outline,
                      ),
                      title: _mark(
                        n.title?.isNotEmpty == true ? n.title! : tr('无标题'),
                      ),
                      subtitle: Text(
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
                    ),
                ],
                if (tags.isNotEmpty) ...[
                  _header(context, tr('标签'), tags.length),
                  for (final t in tags)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.tag, size: 18, color: scheme.outline),
                      title: _mark('#${t.name}'),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: scheme.outline,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TagTasksPage(tagId: t.id, tagName: t.name),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _header(BuildContext context, String label, int count) => Padding(
    padding: EdgeInsets.fromLTRB(4, 14, 4, 4),
    child: Text(
      '$label · $count',
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class _EmptyTips extends StatelessWidget {
  const _EmptyTips({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tips = [tr('周报'), tr('会议'), tr('买菜'), tr('需求'), tr('复盘')];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('搜索范围：任务标题与备注、备忘录正文。多个词用空格分隔时按「同时包含」匹配。'),
            style: TextStyle(fontSize: 12, height: 1.6, color: scheme.outline),
          ),
          SizedBox(height: 18),
          Text(
            tr('试试这些'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in tips)
                ActionChip(label: Text(t), onPressed: () => onPick(t)),
            ],
          ),
        ],
      ),
    );
  }
}
