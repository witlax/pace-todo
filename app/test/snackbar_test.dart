import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter 新版默认带 action 常驻（记录框架行为）', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    ScaffoldMessenger.of(captured).showSnackBar(
      SnackBar(
        content: const Text('TEST-SNACKBAR'),
        duration: const Duration(seconds: 1),
        action: SnackBarAction(label: '撤销', onPressed: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // 记录框架行为：不设 persist 时带 action 的 SnackBar 常驻。
    // 若未来框架改回自动消失，这条测试会失败，届时可删掉 persist:false 的补丁。
    expect(find.text('TEST-SNACKBAR'), findsOneWidget);
  });

  testWidgets('带 action 且 persist:false 的 SnackBar 按 duration 自动消失', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    ScaffoldMessenger.of(captured).showSnackBar(
      SnackBar(
        persist: false,
        content: const Text('TEST-SNACKBAR'),
        duration: const Duration(seconds: 1),
        action: SnackBarAction(label: '撤销', onPressed: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TEST-SNACKBAR'), findsOneWidget);

    // 1 秒后应开始退场
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    await tester.pumpAndSettle();
    expect(
      find.text('TEST-SNACKBAR'),
      findsNothing,
      reason: '设置了 duration 的 SnackBar 必须自动消失',
    );
  });
}
