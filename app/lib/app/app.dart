import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../core/i18n/i18n.dart';
import '../features/memos/memo_page.dart';
import '../features/settings/settings.dart';
import '../features/shell/app_shell.dart';
import 'theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class TasksApp extends ConsumerWidget {
  const TasksApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final lang = ref.watch(langProvider);
    final palette = ref.watch(paletteSchemeProvider);
    ref.watch(notesProvider); // 预热备忘录列表，切换 Tab 时不闪烁

    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(palette),
      darkTheme: AppTheme.dark(palette),
      themeMode: settings.themeMode,
      locale: lang.locale,
      supportedLocales: [for (final l in AppLang.values) l.locale],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorKey: navigatorKey,
      // 翻译是同步函数、不依赖 context，所以切语言时用 key 让整棵树重建一次：
      // 这比让每个页面都 watch 一个 provider 简单，也不会漏掉某个角落。
      home: KeyedSubtree(
        key: ValueKey(lang),
        child: const AppShell(),
      ),
    );
  }
}
