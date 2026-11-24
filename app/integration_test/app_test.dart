import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tasks/main.dart' as app;

/// 端到端冒烟：启动 → 建任务 → 出现在列表 → 切换到四象限 → 设置里开关导航项。
/// 运行：flutter test integration_test/app_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('建任务、切视图、改导航配置', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 启动即在「今天」
    expect(find.text('今天'), findsWidgets);

    // 新建任务
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '集成测试任务');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('集成测试任务'), findsWidgets);

    // 切到四象限
    await tester.tap(find.text('四象限'));
    await tester.pumpAndSettle();
    expect(find.text('马上做'), findsOneWidget);

    // 回到清单
    await tester.tap(find.text('清单'));
    await tester.pumpAndSettle();

    // 设置里开启备忘录 Tab
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.text('导航栏'), findsOneWidget);

    final memoSwitch = find.widgetWithText(SwitchListTile, '备忘录');
    await tester.scrollUntilVisible(memoSwitch, 120);
    await tester.tap(memoSwitch);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 底部出现备忘录入口
    expect(find.widgetWithText(NavigationDestination, '备忘录'), findsWidgets);
  });
}
