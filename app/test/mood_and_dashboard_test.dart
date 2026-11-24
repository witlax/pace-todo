import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/mood/mood_repository.dart';
import 'package:tasks/features/settings/settings.dart';
import 'package:tasks/features/stats/dashboard_cards.dart';
import 'package:tasks/features/tasks/task_repository.dart';

Future<(ProviderContainer, AppDatabase)> _bootstrap() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ],
  );
  return (container, db);
}

void main() {
  group('心情打卡', () {
    test('同一天保存两次是更新，不是新增', () async {
      final (container, db) = await _bootstrap();
      final repo = container.read(moodRepositoryProvider);
      final day = DateTime(2026, 11, 23);

      await repo.save(day: day, mood: 2, note: '有点累');
      await repo.save(day: day, mood: 4, note: '下午缓过来了');

      final all = await db.select(db.moodEntries).get();
      expect(all.length, 1);
      expect(all.single.mood, 4);
      expect(all.single.note, '下午缓过来了');

      await db.close();
      container.dispose();
    });

    test('不同日期各一条，byDate 能精确取回', () async {
      final (container, db) = await _bootstrap();
      final repo = container.read(moodRepositoryProvider);

      await repo.save(day: DateTime(2026, 11, 22), mood: 3);
      await repo.save(day: DateTime(2026, 11, 23), mood: 5);

      final all = await db.select(db.moodEntries).get();
      expect(all.length, 2);
      expect((await repo.byDate(DateTime(2026, 11, 23)))?.mood, 5);

      await db.close();
      container.dispose();
    });

    test('删除后 watchAll 不再包含该天', () async {
      final (container, db) = await _bootstrap();
      final repo = container.read(moodRepositoryProvider);
      final day = DateTime(2026, 11, 23);

      await repo.save(day: day, mood: 1);
      await repo.remove(day);

      final all = await repo.watchAll().first;
      expect(all, isEmpty);
      expect(await repo.byDate(day), isNull);

      await db.close();
      container.dispose();
    });
  });

  group('工作台卡片配置', () {
    test('默认显示全部，顺序为定义顺序', () async {
      final (container, db) = await _bootstrap();
      final cards = container.read(dashboardCardsProvider);
      expect(cards, DashboardCard.values);

      await db.close();
      container.dispose();
    });

    test('隐藏后从列表移除，恢复后加到末尾', () async {
      final (container, db) = await _bootstrap();
      final notifier = container.read(dashboardCardsProvider.notifier);

      notifier.toggle(DashboardCard.heatmap);
      expect(
        container.read(dashboardCardsProvider).contains(DashboardCard.heatmap),
        isFalse,
      );

      notifier.toggle(DashboardCard.heatmap);
      expect(
        container.read(dashboardCardsProvider).last,
        DashboardCard.heatmap,
      );

      await db.close();
      container.dispose();
    });

    test('上下移动生效并持久化到 prefs', () async {
      final (container, db) = await _bootstrap();
      final before = container.read(dashboardCardsProvider).first;
      final notifier = container.read(dashboardCardsProvider.notifier);

      notifier.moveDown(before);
      expect(container.read(dashboardCardsProvider)[1], before);

      await db.close();
      container.dispose();
    });
  });
}
