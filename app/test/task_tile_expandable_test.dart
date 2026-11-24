import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tasks/core/db/database.dart';
import 'package:tasks/features/settings/settings.dart';
import 'package:tasks/features/tasks/task_repository.dart';
import 'package:tasks/features/tasks/widgets/task_tile_expandable.dart';

/// 只验证「展开箭头能展开子任务」这一条交互，不引入数据库。
/// 涉及落库的行为在 feature_test.dart 里用仓储层验证，避免 widget 测试
/// 与 Drift 流的生命周期互相牵制。
void main() {
  final parent = Task(
    id: 'p1',
    listId: 'inbox',
    title: '发布 0.6.0',
    status: 0,
    importance: 0,
    allDay: false,
    spentMin: 0,
    repeatMode: 0,
    pinned: false,
    sortOrder: 0,
    createdAt: DateTime(2026, 11, 20),
    updatedAt: DateTime(2026, 11, 20),
    rev: 1,
  );

  testWidgets('有子任务时显示展开箭头，点开后列出子任务', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          subtasksProvider.overrideWith(
            (ref, id) => Stream.value([
              Task(
                id: 's1',
                listId: 'inbox',
                parentId: id,
                title: '改文档',
                status: 0,
                importance: 0,
                allDay: false,
                spentMin: 0,
                repeatMode: 0,
                pinned: false,
                sortOrder: 0,
                createdAt: DateTime(2026, 11, 20),
                updatedAt: DateTime(2026, 11, 20),
                rev: 1,
              ),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TaskTileExpandable(
              task: parent,
              onToggle: () {},
              onOpen: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('发布 0.6.0'), findsOneWidget);
    expect(find.text('改文档'), findsNothing);

    await tester.tap(find.byTooltip('展开子任务'));
    await tester.pumpAndSettle();

    expect(find.text('改文档'), findsOneWidget);
  });
}
