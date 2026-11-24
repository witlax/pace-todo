import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/core/backup/backup_service.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/memos/note_repository.dart';
import 'package:tasks/features/tasks/recurrence.dart';
import 'package:tasks/features/tasks/task_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TaskRepository(db);
  });

  tearDown(() async => db.close());

  test('重复规则能给出下一次发生时间', () {
    final start = DateTime(2026, 3, 1, 9);
    expect(
      RecurrenceService.nextAfter('RRULE:FREQ=DAILY;INTERVAL=1', start),
      DateTime(2026, 3, 2, 9),
    );
    expect(
      RecurrenceService.nextAfter('RRULE:FREQ=WEEKLY;INTERVAL=1', start),
      DateTime(2026, 3, 8, 9),
    );
    expect(RecurrenceService.labelOf('RRULE:FREQ=DAILY;INTERVAL=1'), '每天');
    expect(RecurrenceService.labelOf(null), '不重复');
    expect(RecurrenceService.nextAfter('坏规则', start), isNull);
  });

  test('完成重复任务后生成下一次，原任务保留为已完成', () async {
    final due = DateTime.now().add(const Duration(hours: 2));
    await repo.create(
      title: '每日站会',
      dueAt: due,
      repeatRule: 'RRULE:FREQ=DAILY;INTERVAL=1',
    );
    final first = (await db.select(db.tasks).get()).single;

    await repo.setDone(first.id, true);

    final all = await db.select(db.tasks).get();
    expect(all.length, 2);
    final done = all.firstWhere((t) => t.id == first.id);
    final next = all.firstWhere((t) => t.id != first.id);
    expect(done.status, 1);
    expect(next.status, 0);
    expect(next.title, '每日站会');
    expect(next.repeatRule, 'RRULE:FREQ=DAILY;INTERVAL=1');
    expect(next.dueAt!.difference(done.dueAt!).inHours, closeTo(24, 1));
  });

  test('勾子任务不自动关闭父任务（父任务由人决定）', () async {
    await repo.create(title: '发布 1.3.0');
    final parent = (await db.select(db.tasks).get()).single;
    final a = await repo.createSubtask(parent.id, '改文档');
    final b = await repo.createSubtask(parent.id, '打包');

    await repo.setDone(a, true);
    var parentRow = await repo.findById(parent.id);
    expect(parentRow!.status, 0, reason: '还有子任务未完成，父任务不应关闭');

    // 1.3.0 起：即使子任务全勾完，父任务也保持未完成——
    // 只有一个子任务时自动关闭会让人误以为整件事做完了。
    await repo.setDone(b, true);
    parentRow = await repo.findById(parent.id);
    expect(parentRow!.status, 0);
    expect(parentRow.completedAt, isNull);
  });

  test('只有一个子任务时勾完也不关闭父任务', () async {
    await repo.create(title: '写成报告');
    final parent = (await db.select(db.tasks).get()).single;
    final only = await repo.createSubtask(parent.id, '收集数据');

    await repo.setDone(only, true);
    final parentRow = await repo.findById(parent.id);
    expect(parentRow!.status, 0, reason: '这就是 1.2.0 报的那个 bug');
  });

  test('子任务不进入今日清单', () async {
    await repo.create(title: '父任务');
    final parent = (await db.select(db.tasks).get()).single;
    await repo.createSubtask(parent.id, '子任务');

    final open = await repo.watchOpen().first;
    expect(open.length, 1);
    expect(open.single.title, '父任务');
  });

  test('归档清单后任务回到收件箱，任务本身不丢', () async {
    await repo.create(title: '临时任务');
    final task = (await db.select(db.tasks).get()).single;
    final list = await repo.createList('等待归档');

    await repo.updateTask(task.id, listId: list.id);
    expect((await repo.findById(task.id))!.listId, list.id);

    await repo.archiveList(list.id);

    final after = await repo.findById(task.id);
    expect(after, isNotNull);
    expect(after!.listId, 'inbox');
    expect(after.deletedAt, isNull);

    final lists = await repo.watchLists().first;
    expect(lists.any((l) => l.id == list.id), isFalse);
  });

  test('标签可创建、绑定与删除', () async {
    await repo.create(title: '带标签的任务');
    final task = (await db.select(db.tasks).get()).single;
    final tag = await repo.createTag('工作');

    await repo.setTaskTags(task.id, [tag.id]);
    expect(await repo.watchTaskTagIds(task.id).first, [tag.id]);

    await repo.deleteTag(tag.id);
    expect(await repo.watchTaskTagIds(task.id).first, isEmpty);
    expect(await repo.watchTags().first, isEmpty);
  });

  test('归档把任务移出未完成列表，并可取消归档', () async {
    await repo.create(title: '以后再说');
    final t = (await db.select(db.tasks).get()).single;

    await repo.archiveTask(t.id);
    expect(await repo.watchOpen().first, isEmpty);
    expect((await repo.watchArchived().first).single.title, '以后再说');

    await repo.unarchiveTask(t.id);
    expect((await repo.watchOpen().first).single.title, '以后再说');
    expect(await repo.watchArchived().first, isEmpty);
  });

  test('完成总结与今日完成列表', () async {
    await repo.create(
      title: '写周报',
      notes: '先列要点',
      remindAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final t = (await db.select(db.tasks).get()).single;
    expect(t.notes, '先列要点');
    expect(t.remindAt, isNotNull);

    await repo.setDone(t.id, true);
    await repo.setCompletedSummary(t.id, '先列要点再展开，30 分钟写完');

    final doneToday = await repo.watchDoneTodayTasks().first;
    expect(doneToday.single.title, '写周报');
    expect(doneToday.single.completedSummary, '先列要点再展开，30 分钟写完');
    expect(doneToday.single.completedAt, isNotNull);
  });

  test('备忘录标签可保存，正文支持 Markdown 原文', () async {
    final notes = NoteRepository(db);
    final id = await notes.createNote(title: '会议纪要', body: '# 标题\n- 结论一');
    await notes.saveNote(id, tags: '工作,需求', pinned: true);

    final row = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle();
    expect(row.tags, '工作,需求');
    expect(row.pinned, isTrue);
    expect(row.bodyMd, contains('# 标题'));
  });

  test('备忘录能看到被哪些任务引用', () async {
    final notes = NoteRepository(db);
    final noteId = await notes.createNote(title: '资料');
    await repo.create(title: '写方案');
    final task = (await db.select(db.tasks).get()).single;

    await repo.linkNote(task.id, noteId);
    final linked = await notes.watchLinkedTasks(noteId).first;
    expect(linked.single.title, '写方案');

    await repo.unlinkNote(task.id, noteId);
    expect(await notes.watchLinkedTasks(noteId).first, isEmpty);
  });

  test('备份导出后可完整导入', () async {
    await repo.create(title: '任务 A');
    await repo.create(title: '任务 B');
    final list = await repo.createList('项目');
    await repo.createTag('重要');
    final habitId = 'h1';
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(
            id: habitId,
            name: '早起',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

    final service = BackupService(db);
    final json = await service.exportJson();
    expect(json.contains('任务 A'), isTrue);
    expect(json.contains('早起'), isTrue);
    expect(list.name, '项目');

    // 清空后导入
    await db.delete(db.tasks).go();
    await db.delete(db.tags).go();
    await db.delete(db.habits).go();
    expect((await db.select(db.tasks).get()), isEmpty);

    final count = await service.importJson(json);
    expect(count, greaterThanOrEqualTo(5));
    final tasks = await db.select(db.tasks).get();
    expect(tasks.map((t) => t.title).toSet(), {'任务 A', '任务 B'});
    expect((await db.select(db.habits).get()).single.name, '早起');
    expect((await db.select(db.tags).get()).single.name, '重要');
  });
}
