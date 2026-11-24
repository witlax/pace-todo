import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings.dart';
import '../../core/i18n/i18n.dart';

/// 工作台可配置的统计卡片。
/// 只做「显示/隐藏 + 顺序」，不做自定义指标——指标口径必须全应用一致。
enum DashboardCard {
  metrics('今日指标', Icons.speed_outlined),
  weekBars('近 7 天完成', Icons.bar_chart),
  heatmap('本年打卡热力', Icons.grid_on),
  focus('本周专注分布', Icons.donut_large_outlined);

  const DashboardCard(this._label, this.icon);

  final String _label;
  final IconData icon;

  String get label => tr(_label);
}

class DashboardCardsNotifier extends Notifier<List<DashboardCard>> {
  static const _key = 'dashboard.cards';

  @override
  List<DashboardCard> build() {
    final raw = ref.read(prefsProvider).getString(_key);
    if (raw == null) return DashboardCard.values.toList();
    final list = <DashboardCard>[];
    for (final name in raw.split(',')) {
      final card = DashboardCard.values
          .where((e) => e.name == name)
          .firstOrNull;
      if (card != null && !list.contains(card)) list.add(card);
    }
    return list;
  }

  void _persist(List<DashboardCard> next) {
    state = next;
    ref.read(prefsProvider).setString(_key, next.map((e) => e.name).join(','));
  }

  void toggle(DashboardCard card) {
    final next = [...state];
    if (next.contains(card)) {
      next.remove(card);
    } else {
      next.add(card);
    }
    _persist(next);
  }

  void moveUp(DashboardCard card) {
    final next = [...state];
    final i = next.indexOf(card);
    if (i <= 0) return;
    next.removeAt(i);
    next.insert(i - 1, card);
    _persist(next);
  }

  void moveDown(DashboardCard card) {
    final next = [...state];
    final i = next.indexOf(card);
    if (i < 0 || i >= next.length - 1) return;
    next.removeAt(i);
    next.insert(i + 1, card);
    _persist(next);
  }

  void reset() => _persist(DashboardCard.values.toList());
}

final dashboardCardsProvider =
    NotifierProvider<DashboardCardsNotifier, List<DashboardCard>>(
      DashboardCardsNotifier.new,
    );

/// 卡片配置页：开关 = 显示/隐藏，上下箭头 = 顺序（不用拖拽，避免误操作）。
class DashboardCardsPage extends ConsumerWidget {
  const DashboardCardsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(dashboardCardsProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('工作台卡片')),
        actions: [
          TextButton(
            onPressed: ref.read(dashboardCardsProvider.notifier).reset,
            child: Text(tr('恢复默认')),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          Text(
            tr('关掉的卡片不显示；用箭头调整上下顺序。指标口径全应用一致，不可自定义。'),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.7,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 14),
          for (final card in DashboardCard.values)
            Card(
              elevation: 0,
              margin: EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 4, 4, 4),
                child: Row(
                  children: [
                    Icon(card.icon, size: 19, color: scheme.onSurfaceVariant),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.label,
                            style: TextStyle(fontSize: 13.5),
                          ),
                          Text(
                            enabled.contains(card)
                                ? trf('显示中 · 第 {} 位', [enabled.indexOf(card) + 1])
                                : tr('已隐藏'),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: enabled.contains(card)
                                  ? scheme.primary
                                  : scheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (enabled.contains(card)) ...[
                      IconButton(
                        tooltip: tr('上移'),
                        visualDensity: VisualDensity.compact,
                        onPressed: enabled.first == card
                            ? null
                            : () => ref
                                  .read(dashboardCardsProvider.notifier)
                                  .moveUp(card),
                        icon: Icon(Icons.keyboard_arrow_up, size: 18),
                      ),
                      IconButton(
                        tooltip: tr('下移'),
                        visualDensity: VisualDensity.compact,
                        onPressed: enabled.last == card
                            ? null
                            : () => ref
                                  .read(dashboardCardsProvider.notifier)
                                  .moveDown(card),
                        icon: Icon(Icons.keyboard_arrow_down, size: 18),
                      ),
                    ],
                    Switch(
                      value: enabled.contains(card),
                      onChanged: (_) => ref
                          .read(dashboardCardsProvider.notifier)
                          .toggle(card),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
