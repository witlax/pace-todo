import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/settings/settings.dart';
import 'package:tasks/features/tasks/task_detail_page.dart';
import 'package:tasks/features/tasks/task_repository.dart';
import 'package:tasks/features/tasks/trash_page.dart';

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

Widget _wrap(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  testWidgets('详情页改标题后写入数据库', (tester) async {
    final (container, db) = await _bootstrap();
    final repo = container.read(taskRepositoryProvider);
    await repo.create(title: '原标题');
    final task = (await db.select(db.tasks).get()).single;

    await tester.pumpWidget(_wrap(container, TaskDetailPage(taskId: task.id)));
    await tester.pumpAndSettle();

    expect(find.text('原标题'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '改后的标题');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    final updated = (await db.select(db.tasks).get()).single;
    expect(updated.title, '改后的标题');

    await db.close();
    container.dispose();
  });

  testWidgets('回收站可恢复软删任务', (tester) async {
    final (container, db) = await _bootstrap();
    final repo = container.read(taskRepositoryProvider);
    await repo.create(title: '要删的任务');
    final task = (await db.select(db.tasks).get()).single;
    await repo.softDelete(task.id);

    await tester.pumpWidget(_wrap(container, const TrashPage()));
    await tester.pumpAndSettle();

    expect(find.text('要删的任务'), findsOneWidget);
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    final restored = (await db.select(db.tasks).get()).single;
    expect(restored.deletedAt, isNull);

    await db.close();
    container.dispose();
  });

  testWidgets('彻底删除后数据库不再有该任务', (tester) async {
    final (container, db) = await _bootstrap();
    final repo = container.read(taskRepositoryProvider);
    await repo.create(title: '永久删除');
    final task = (await db.select(db.tasks).get()).single;
    await repo.softDelete(task.id);

    await repo.purge(task.id);
    final rows = await db.select(db.tasks).get();
    expect(rows, isEmpty);

    await db.close();
    container.dispose();
  });
}
