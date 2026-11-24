import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/settings/settings.dart';
import 'package:tasks/features/shell/app_shell.dart';
import 'package:tasks/features/tasks/task_repository.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  testWidgets('整壳渲染无异常（含所有 Tab）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = TaskRepository(db);
    await repo.create(title: '一条任务');
    await repo.create(
      title: '带日期的任务',
      dueAt: DateTime.now().add(const Duration(hours: 2)),
      importance: 3,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          databaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // 逐个切 Tab，确保每个页面都能渲染
    for (final label in ['视图', '专注', '日志', '目标', '设置', '首页']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label 渲染异常');
    }

    await db.close();
  });
}
