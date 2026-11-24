import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/habits/habit_repository.dart';

/// 打卡之后「写心得」不能变成「撤销打卡」。
///
/// 1.0.0 的 bug：已打卡时点开心得入口，弹的是撤销确认——入口和语义错位。
/// 这里锁住正确行为：补写 / 修改 / 清空心得都不动次数。
void main() {
  late AppDatabase db;
  late HabitRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = HabitRepository(db);
  });

  tearDown(() async => db.close());

  test('已打卡后补写心得：次数不变，备注写入', () async {
    final id = await repo.create('冥想', targetCount: 1);
    await repo.checkIn(id);

    await repo.setTodayNote(id, '今天很平静');
    final logs = await repo.watchLogsOf(id).first;
    expect(logs.single.count, 1);
    expect(logs.single.note, '今天很平静');
  });

  test('多次习惯补写心得不会把次数清掉', () async {
    final id = await repo.create('喝水', targetCount: 8);
    for (var i = 0; i < 3; i++) {
      await repo.checkIn(id);
    }
    await repo.setTodayNote(id, '下午喝得少');
    final log = (await repo.watchLogsOf(id).first).single;
    expect(log.count, 3);
    expect(log.note, '下午喝得少');
  });

  test('清空心得：只清备注，记录仍在', () async {
    final id = await repo.create('阅读');
    await repo.checkIn(id, note: '读了 20 页');
    await repo.setTodayNote(id, null);
    final log = (await repo.watchLogsOf(id).first).single;
    expect(log.count, 1);
    expect(log.note, isNull);
  });

  test('没打卡时写心得是空操作（不凭空造记录）', () async {
    final id = await repo.create('跑步');
    await repo.setTodayNote(id, '还没打卡');
    expect(await repo.watchLogsOf(id).first, isEmpty);
  });
}
