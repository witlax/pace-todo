import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../../platform/notification_service.dart';
import 'recurrence.dart';

/// 任务读写。UI 不直接碰 Drift，一律经这里（ADR-0009）。
class TaskRepository {
  TaskRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  // ---------------------------------------------------------------- 读

  /// 未完成的主任务。子任务只在父任务详情里出现，不混进今日清单。
  Stream<List<Task>> watchOpen() {
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.archivedAt.isNull() &
            t.status.equals(0) &
            t.parentId.isNull(),
      );
    return query.watch();
  }

  Stream<int> watchDoneToday() {
    final start = DateTime.now();
    final dayStart = DateTime(start.year, start.month, start.day);
    final query = _db.selectOnly(_db.tasks)
      ..addColumns([_db.tasks.id.count()])
      ..where(
        _db.tasks.status.equals(1) &
            _db.tasks.completedAt.isBiggerOrEqualValue(dayStart) &
            _db.tasks.deletedAt.isNull(),
      );
    return query.watchSingle().map(
      (row) => row.read(_db.tasks.id.count()) ?? 0,
    );
  }

  /// 今天完成的任务：仍显示在列表里（变灰），不直接从视野消失。
  Stream<List<Task>> watchDoneTodayTasks() {
    final start = DateTime.now();
    final dayStart = DateTime(start.year, start.month, start.day);
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.archivedAt.isNull() &
            t.status.equals(1) &
            t.parentId.isNull() &
            t.completedAt.isBiggerOrEqualValue(dayStart),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 已归档。按归档时间倒序。
  Stream<List<Task>> watchArchived() {
    final query = _db.select(_db.tasks)
      ..where((t) => t.deletedAt.isNull() & t.archivedAt.isNotNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.archivedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  /// 已完成。按完成时间倒序，供「已完成」页回看与撤销。
  Stream<List<Task>> watchCompleted({int limit = 300}) {
    final query = _db.select(_db.tasks)
      ..where(
        (t) => t.deletedAt.isNull() & t.status.equals(1) & t.parentId.isNull(),
      )
      ..orderBy([
        (t) => OrderingTerm(expression: t.completedAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch();
  }

  Stream<List<Task>> watchSubtasks(String parentId) {
    final query = _db.select(_db.tasks)
      ..where((t) => t.parentId.equals(parentId) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);
    return query.watch();
  }

  Stream<List<TaskList>> watchLists() {
    final query = _db.select(_db.lists)
      ..where((l) => l.deletedAt.isNull())
      ..orderBy([(l) => OrderingTerm(expression: l.sortOrder)]);
    return query.watch();
  }

  Future<Task?> findById(String id) =>
      (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Task?> watchTask(String id) => (_db.select(
    _db.tasks,
  )..where((t) => t.id.equals(id))).watchSingleOrNull();

  // ---------------------------------------------------------------- 写

  Future<String> create({
    required String title,
    String? notes,
    int importance = 0,
    DateTime? dueAt,
    DateTime? remindAt,
    String listId = 'inbox',
    String? repeatRule,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            listId: listId,
            title: title.trim(),
            notes: Value(notes),
            importance: Value(importance),
            dueAt: Value(dueAt),
            remindAt: Value(remindAt),
            repeatRule: Value(repeatRule),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncReminder(id);
    return id;
  }

  Future<String> createSubtask(
    String parentId,
    String title, {
    String listId = 'inbox',
  }) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            listId: listId,
            parentId: Value(parentId),
            title: title.trim(),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 完成/取消完成。完成重复任务时，顺带生成下一次实例。
  Future<void> setDone(String id, bool done) async {
    final before = await findById(id);
    final now = DateTime.now();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        status: Value(done ? 1 : 0),
        completedAt: Value(done ? now : null),
        updatedAt: Value(now),
        rev: Value(await _nextRev(id)),
      ),
    );
    await _syncReminder(id);

    final rule = before?.repeatRule;
    if (done && rule != null && rule.isNotEmpty) {
      await _spawnNextOccurrence(before!, rule);
    }
    // 勾完子任务**不**自动把父任务标成完成：
    // 父任务是「这件事本身」，只有一个步骤时自动关闭会让人误以为整件事做完了。
    // 需要完成父任务就点它自己的圆圈（1.2.0 用户反馈）。
  }

  Future<void> setImportance(String id, int importance) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        importance: Value(importance),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> setDue(String id, DateTime? dueAt) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(dueAt: Value(dueAt), updatedAt: Value(DateTime.now())),
    );
    await _syncReminder(id);
  }

  Future<void> setPinned(String id, bool pinned) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(pinned: Value(pinned), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setRepeat(String id, String? rule) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(repeatRule: Value(rule), updatedAt: Value(DateTime.now())),
    );
  }

  /// 软删除，进回收站（保留 30 天）。子任务随之进入回收站。
  Future<void> softDelete(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(deletedAt: Value(now)),
    );
    await (_db.update(_db.tasks)..where((t) => t.parentId.equals(id))).write(
      TasksCompanion(deletedAt: Value(now)),
    );
    await NotificationService.cancel(id);
  }

  /// 详情页的整体保存：一次写入，避免多次刷新。
  Future<void> updateTask(
    String id, {
    String? title,
    String? notes,
    int? importance,
    DateTime? dueAt,
    bool clearDue = false,
    String? listId,
  }) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: title == null ? const Value.absent() : Value(title.trim()),
        notes: notes == null ? const Value.absent() : Value(notes),
        importance: importance == null
            ? const Value.absent()
            : Value(importance),
        dueAt: clearDue
            ? const Value(null)
            : (dueAt == null ? const Value.absent() : Value(dueAt)),
        listId: listId == null ? const Value.absent() : Value(listId),
        updatedAt: Value(DateTime.now()),
        rev: Value(await _nextRev(id)),
      ),
    );
    await _syncReminder(id);
  }

  // ---------------------------------------------------------------- 归档与完成总结

  Future<void> archiveTask(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(archivedAt: Value(now), updatedAt: Value(now)),
    );
    await NotificationService.cancel(id);
  }

  Future<void> unarchiveTask(String id) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        archivedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _syncReminder(id);
  }

  /// 完成总结：完成之后补一段「这次做成了什么」，是复盘的最小单位。
  Future<void> setCompletedSummary(String id, String summary) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        completedSummary: Value(summary),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 独立提醒时间。传 null 表示回到「按到期时间提醒」。
  Future<void> setRemindAt(String id, DateTime? remindAt) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        remindAt: Value(remindAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _syncReminder(id);
  }

  /// 全量标签-任务关联与全量主任务，供标签统计页聚合。
  Stream<List<TaskTag>> watchAllTaskTags() => _db.select(_db.taskTags).watch();

  Stream<List<Task>> watchAllActiveMainTasks() {
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() & t.archivedAt.isNull() & t.parentId.isNull(),
      );
    return query.watch();
  }

  /// 完成热力图的数据源：所有已完成主任务，不限条数。
  Stream<List<Task>> watchCompletedForHeatmap() {
    final query = _db.select(_db.tasks)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.status.equals(1) &
            t.parentId.isNull() &
            t.completedAt.isNotNull(),
      );
    return query.watch();
  }

  // ---------------------------------------------------------------- 回收站

  Stream<List<Task>> watchDeleted() {
    final query = _db.select(_db.tasks)
      ..where((t) => t.deletedAt.isNotNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.deletedAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  Future<void> restore(String id) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _syncReminder(id);
  }

  Future<void> purge(String id) async {
    await NotificationService.cancel(id);
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> purgeAll() async {
    await (_db.delete(_db.tasks)..where((t) => t.deletedAt.isNotNull())).go();
  }

  // ---------------------------------------------------------------- 清单

  Future<TaskList> createList(String name) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    final maxOrder =
        await (_db.selectOnly(_db.lists)
              ..addColumns([_db.lists.sortOrder.max()]))
            .map((r) => r.read(_db.lists.sortOrder.max()))
            .getSingle();
    await _db
        .into(_db.lists)
        .insert(
          ListsCompanion.insert(
            id: id,
            name: name.trim(),
            sortOrder: Value((maxOrder ?? 0) + 1),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return TaskList(
      id: id,
      name: name.trim(),
      color: null,
      isInbox: false,
      sortOrder: (maxOrder ?? 0) + 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      rev: 1,
      deviceId: null,
    );
  }

  Future<void> renameList(String id, String name) async {
    await (_db.update(_db.lists)..where((l) => l.id.equals(id))).write(
      ListsCompanion(
        name: Value(name.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 归档清单：清单本体软删，里面的任务落到收件箱，不连带删除。
  Future<void> archiveList(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.tasks)..where((t) => t.listId.equals(id))).write(
      TasksCompanion(listId: const Value('inbox'), updatedAt: Value(now)),
    );
    await (_db.update(_db.lists)..where((l) => l.id.equals(id))).write(
      ListsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  /// 手动排序：按传入顺序写 sortOrder（步长 10，便于以后插队）。
  Future<void> reorderTasks(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (_db.update(_db.tasks)..where((t) => t.id.equals(orderedIds[i])))
          .write(TasksCompanion(sortOrder: Value(i * 10)));
    }
  }

  Future<void> reorderLists(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await (_db.update(_db.lists)..where((l) => l.id.equals(orderedIds[i])))
          .write(ListsCompanion(sortOrder: Value(i)));
    }
  }

  // ---------------------------------------------------------------- 标签

  Stream<List<Tag>> watchTags() {
    final query = _db.select(_db.tags)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.watch();
  }

  Stream<List<String>> watchTaskTagIds(String taskId) {
    final query = _db.select(_db.taskTags)
      ..where((tt) => tt.taskId.equals(taskId));
    return query.watch().map((rows) => rows.map((r) => r.tagId).toList());
  }

  Future<Tag> createTag(String name) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.tags)
        .insert(
          TagsCompanion.insert(id: id, name: name.trim(), createdAt: now),
        );
    return Tag(
      id: id,
      name: name.trim(),
      color: null,
      createdAt: now,
      deletedAt: null,
    );
  }

  Future<void> setTaskTags(String taskId, List<String> tagIds) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.taskTags,
      )..where((tt) => tt.taskId.equals(taskId))).go();
      for (final tagId in tagIds) {
        await _db
            .into(_db.taskTags)
            .insert(TaskTagsCompanion.insert(taskId: taskId, tagId: tagId));
      }
    });
  }

  Future<void> deleteTag(String id) async {
    final now = DateTime.now();
    await (_db.delete(_db.taskTags)..where((tt) => tt.tagId.equals(id))).go();
    await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
      TagsCompanion(deletedAt: Value(now)),
    );
  }

  // ---------------------------------------------------------------- 备忘录关联

  Stream<List<Note>> watchLinkedNotes(String taskId) {
    final query =
        _db.select(_db.notes).join([
          innerJoin(
            _db.taskNoteLinks,
            _db.taskNoteLinks.noteId.equalsExp(_db.notes.id),
          ),
        ])..where(
          _db.taskNoteLinks.taskId.equals(taskId) &
              _db.notes.deletedAt.isNull(),
        );
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_db.notes)).toList(),
    );
  }

  /// 默认按「引用」关联：改一处，所有引用它的任务同步。
  Future<void> linkNote(String taskId, String noteId) async {
    await _db
        .into(_db.taskNoteLinks)
        .insertOnConflictUpdate(
          TaskNoteLinksCompanion.insert(
            taskId: taskId,
            noteId: noteId,
            createdAt: DateTime.now(),
          ),
        );
  }

  Future<void> unlinkNote(String taskId, String noteId) async {
    await (_db.delete(
      _db.taskNoteLinks,
    )..where((l) => l.taskId.equals(taskId) & l.noteId.equals(noteId))).go();
  }

  // ---------------------------------------------------------------- 内部

  /// 完成重复任务后生成下一次：复制字段、按规则推进到期时间、重新排提醒。
  Future<void> _spawnNextOccurrence(Task task, String rule) async {
    final base = task.dueAt ?? DateTime.now();
    final next = RecurrenceService.nextAfter(rule, base);
    if (next == null) return;

    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            listId: task.listId,
            title: task.title,
            notes: Value(task.notes),
            importance: Value(task.importance),
            dueAt: Value(next),
            allDay: Value(task.allDay),
            estimateMin: Value(task.estimateMin),
            repeatRule: Value(task.repeatRule),
            repeatMode: Value(task.repeatMode),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _syncReminder(id);
  }

  /// 任何字段变化后，按最新状态重排或取消提醒。
  Future<void> _syncReminder(String id) async {
    final task = await findById(id);
    if (task == null ||
        task.deletedAt != null ||
        task.archivedAt != null ||
        task.status != 0) {
      await NotificationService.cancel(id);
      return;
    }
    final when = task.remindAt ?? task.dueAt;
    if (when == null) {
      await NotificationService.cancel(id);
      return;
    }
    await NotificationService.scheduleTask(
      id: task.id,
      title: task.title,
      dueAt: when,
    );
  }

  Future<int> _nextRev(String id) async {
    final row = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return (row?.rev ?? 0) + 1;
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(databaseProvider)),
);

/// 未完成任务流。排序在 UI 层按 逾期/今天/无日期 分组后处理。
final openTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchOpen(),
);

final doneTodayProvider = StreamProvider<int>(
  (ref) => ref.watch(taskRepositoryProvider).watchDoneToday(),
);

final completedTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchCompleted(),
);

final doneTodayTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchDoneTodayTasks(),
);

final archivedTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchArchived(),
);

final deletedTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchDeleted(),
);

final listsProvider = StreamProvider<List<TaskList>>(
  (ref) => ref.watch(taskRepositoryProvider).watchLists(),
);

final tagsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(taskRepositoryProvider).watchTags(),
);

final taskByIdProvider = StreamProvider.family<Task?, String>(
  (ref, id) => ref.watch(taskRepositoryProvider).watchTask(id),
);

final subtasksProvider = StreamProvider.family<List<Task>, String>(
  (ref, parentId) => ref.watch(taskRepositoryProvider).watchSubtasks(parentId),
);

final taskTagIdsProvider = StreamProvider.family<List<String>, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).watchTaskTagIds(taskId),
);

final linkedNotesProvider = StreamProvider.family<List<Note>, String>(
  (ref, taskId) => ref.watch(taskRepositoryProvider).watchLinkedNotes(taskId),
);

final allTaskTagsProvider = StreamProvider<List<TaskTag>>(
  (ref) => ref.watch(taskRepositoryProvider).watchAllTaskTags(),
);

final allActiveTasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchAllActiveMainTasks(),
);

final completionHeatmapProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchCompletedForHeatmap(),
);

/// 单个标签的统计。
class TagStat {
  const TagStat(this.tag, this.openCount, this.doneCount);

  final Tag tag;
  final int openCount;
  final int doneCount;
}

/// 标签统计：派生 Provider，任一数据源变化即重算。
final tagStatsProvider = Provider<AsyncValue<List<TagStat>>>((ref) {
  final tags = ref.watch(tagsProvider).value;
  final links = ref.watch(allTaskTagsProvider).value;
  final tasks = ref.watch(allActiveTasksProvider).value;
  if (tags == null || links == null || tasks == null) {
    return const AsyncLoading();
  }
  final byTask = <String, Set<String>>{};
  for (final link in links) {
    byTask.putIfAbsent(link.taskId, () => {}).add(link.tagId);
  }
  final stats = [
    for (final tag in tags)
      TagStat(
        tag,
        tasks
            .where(
              (t) => t.status == 0 && byTask[t.id]?.contains(tag.id) == true,
            )
            .length,
        tasks
            .where(
              (t) => t.status == 1 && byTask[t.id]?.contains(tag.id) == true,
            )
            .length,
      ),
  ];
  return AsyncData(stats);
});

/// 某个标签下的主任务（未完成在前）。
List<Task> tasksWithTag(List<Task> tasks, List<TaskTag> links, String tagId) {
  final ids = links.where((l) => l.tagId == tagId).map((l) => l.taskId).toSet();
  return tasks.where((t) => ids.contains(t.id)).toList()..sort((a, b) {
    final s = a.status.compareTo(b.status);
    if (s != 0) return s;
    final ad = a.completedAt ?? a.updatedAt;
    final bd = b.completedAt ?? b.updatedAt;
    return bd.compareTo(ad);
  });
}

/// 搜索词。列表页的过滤仍走内存；全屏搜索页有独立查询状态。
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;

  void clear() => state = '';
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

enum TaskViewMode { list, quadrant }

class ViewModeNotifier extends Notifier<TaskViewMode> {
  @override
  TaskViewMode build() => TaskViewMode.list;

  void set(TaskViewMode mode) => state = mode;
}

final viewModeProvider = NotifierProvider<ViewModeNotifier, TaskViewMode>(
  ViewModeNotifier.new,
);
