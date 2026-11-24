import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/features/tasks/quick_parse.dart';

void main() {
  // 2026-11-20 是周五。
  final now = DateTime(2026, 11, 20, 9, 0);

  test('识别日期、时间、重要性与标签', () {
    final p = parseQuickAdd('周五 15:30 交周报 !高 #工作', now: now);
    expect(p.title, '交周报');
    expect(p.dueAt, DateTime(2026, 11, 20, 15, 30));
    expect(p.importance, 3);
    expect(p.tags, ['工作']);
  });

  test('只有日期时默认 18:00', () {
    final p = parseQuickAdd('明天 买猫粮', now: now);
    expect(p.dueAt, DateTime(2026, 11, 21, 18, 0));
    expect(p.title, '买猫粮');
  });

  test('下周 + 下午中文时间', () {
    final p = parseQuickAdd('下周三 下午3点半 复盘', now: now);
    expect(p.dueAt, DateTime(2026, 11, 25, 15, 30));
    expect(p.title, '复盘');
  });

  test('已过去的绝对日期顺延到明年', () {
    final p = parseQuickAdd('11月2日 体检', now: now);
    expect(p.dueAt?.year, 2027);
    expect(p.dueAt?.month, 11);
    expect(p.dueAt?.day, 2);
  });

  test('没有可识别内容时标题原样保留', () {
    final p = parseQuickAdd('整理会议纪要', now: now);
    expect(p.title, '整理会议纪要');
    expect(p.dueAt, isNull);
    expect(p.importance, isNull);
    expect(p.isEmpty, isTrue);
  });

  test('一天内多个片段都能剥掉', () {
    final p = parseQuickAdd('今天 !低 #生活 交房租 20:00', now: now);
    expect(p.title, '交房租');
    expect(p.dueAt, DateTime(2026, 11, 20, 20, 0));
    expect(p.importance, 1);
    expect(p.tags, ['生活']);
  });
}
