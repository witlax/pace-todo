import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/tasks/task_repository.dart';

/// 性能基准：不做严格断言，只把「明显退化」挡在门外。
///
/// 目标是 V1 发布前有一条可重复的数字，而不是凭感觉说「还行」。
/// 阈值给得宽（约为实测的 4–6 倍），因为它要拦的是数量级问题，
/// 不是 CI 机器抖动。
void main() {
  test('1000 条任务：写入与首屏查询耗时', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    addTearDown(db.close);

    final now = DateTime.now();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 1000; i++) {
      await repo.create(
        title: '基准任务 $i',
        importance: i % 4,
        dueAt: now.add(Duration(hours: i % 48)),
      );
    }
    sw.stop();
    final insertMs = sw.elapsedMilliseconds;

    final read = Stopwatch()..start();
    final all = await repo.watchAllActiveMainTasks().first;
    read.stop();
    final readMs = read.elapsedMilliseconds;

    // ignore: avoid_print
    print('[perf] 插入 1000 条：${insertMs}ms · 全量读取 ${all.length} 条：${readMs}ms');

    expect(all.length, 1000);
    expect(insertMs, lessThan(30000), reason: '写入明显退化');
    expect(readMs, lessThan(3000), reason: '列表读取明显退化');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('schema 从 v5 升级：补出目标表，旧数据不动', () async {
    final dir = await Directory.systemTemp.createTemp('tasks-migrate');
    final file = File('${dir.path}/migrate.sqlite');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    // 造一个「v5 且只有一张无关表」的库：v6 迁移只做建表，不依赖旧表结构，
    // 这样既验证了 onUpgrade 分支，又不用把 v5 的建表语句抄一遍。
    var db = AppDatabase.forTesting(NativeDatabase(file));
    await db.customStatement('CREATE TABLE legacy_probe (x INTEGER)');
    await db.customStatement('INSERT INTO legacy_probe VALUES (7)');
    await db.customStatement('PRAGMA user_version = 5');
    await db.close();

    db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
        .get();
    final names = tables.map((r) => r.read<String>('name')).toSet();
    expect(names, containsAll(['goals', 'goal_links', 'legacy_probe']));

    final probe = await db.customSelect('SELECT x FROM legacy_probe').get();
    expect(probe.single.read<int>('x'), 7);

    // 新表可写可读
    await db
        .into(db.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'g1',
            title: '迁移后的第一个目标',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
    expect((await db.select(db.goals).get()).single.title, '迁移后的第一个目标');
  });
}
