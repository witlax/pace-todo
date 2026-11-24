import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasks/core/i18n/en.dart';
import 'package:tasks/core/i18n/i18n.dart';
import 'package:tasks/features/settings/settings.dart';

/// 中英切换最容易出的问题不是「翻得不好」，而是「漏了一句」：
/// 漏掉的那句在英文界面里突兀地显示中文，或者干脆是空的。
/// 这几条测试就是拦这个的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('英文词表', () {
    test('没有空值', () {
      for (final entry in en.entries) {
        expect(
          entry.value.trim(),
          isNotEmpty,
          reason: '「${entry.key}」没有译文',
        );
      }
    });

    test('没有原样照抄的中文（说明漏翻）', () {
      for (final entry in en.entries) {
        expect(
          entry.value,
          isNot(equals(entry.key)),
          reason: '「${entry.key}」看起来没翻',
        );
      }
    });

    test('模板都保留了占位符', () {
      for (final entry in enTemplates.entries) {
        if (!entry.key.contains('{')) continue;
        // 少数句子英文里不需要那个数字（比如「记录这一天的这一次」），
        // 所以只要求「用到的占位符不超过原文」。
        expect(
          '{'.allMatches(entry.value).length,
          lessThanOrEqualTo('{'.allMatches(entry.key).length),
          reason: '「${entry.key}」占位符比原文多',
        );
      }
    });
  });

  group('翻译函数', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
    });

    test('默认中文，原样返回', () {
      expect(tr('今天'), '今天');
      expect(trf('{} 项', [3]), '3 项');
    });

    test('切到英文后返回译文', () {
      container.read(langProvider.notifier).set(AppLang.en);
      expect(tr('今天'), 'Today');
      expect(trf('{} 项', [3]), '3');
      expect(tr('没收录的句子'), '没收录的句子', reason: '缺失时回退原文，不是返回 key');
    });

    test('切回中文能恢复', () {
      container.read(langProvider.notifier).set(AppLang.en);
      container.read(langProvider.notifier).set(AppLang.zh);
      expect(tr('今天'), '今天');
    });

    test('占位符按下标替换（英文语序用）', () {
      container.read(langProvider.notifier).set(AppLang.en);
      // 年月：英文写成「11/2026」，中文是「2026 年 11 月」
      expect(trf('{} 年 {} 月', [2026, 11]), '11/2026');
    });

    test('语言写进 prefs，重开仍是英文', () {
      container.read(langProvider.notifier).set(AppLang.en);
      final prefs = container.read(prefsProvider);
      expect(prefs.getString(kLangPrefKey), 'en');
      expect(AppLang.parse(prefs.getString(kLangPrefKey)), AppLang.en);
    });
  });
}
