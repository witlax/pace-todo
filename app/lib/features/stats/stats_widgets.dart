import 'package:flutter/material.dart';
import '../../core/i18n/i18n.dart';

/// 统计用的小组件集合。
///
/// 刻意保持「只读、无状态」：数据由页面算好传进来，组件只管画。
/// 这样同一套组件能出现在今日概况、工作台、习惯页三处而不走样。
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.value,
    required this.label,
    this.hint,
    this.accent,
  });

  final String value;
  final String label;
  final String? hint;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: accent ?? scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: TextStyle(fontSize: 10, color: scheme.outline)),
          ],
        ],
      ),
    );
  }
}

/// 最近 7 天完成柱状图。柱高按当周最大值归一，空数据时显示基线。
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.counts});

  /// key: 日期（当天 0 点），value: 完成数
  final Map<DateTime, int> counts;

  static List<String> get _labels => weekdayInitials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final maxCount = days
        .map((d) => counts[d] ?? 0)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${counts[day] ?? 0}',
                    style: TextStyle(fontSize: 9.5, color: scheme.outline),
                  ),
                  SizedBox(height: 3),
                  Container(
                    height: 8 + 44 * ((counts[day] ?? 0) / maxCount),
                    margin: EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: (counts[day] ?? 0) == 0
                          ? scheme.surfaceContainerHighest
                          : scheme.primary.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(3),
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _labels[day.weekday - 1],
                    style: TextStyle(fontSize: 9.5, color: scheme.outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 打卡热力：近 26 周（半年），周一为列起点。
class HeatmapGrid extends StatelessWidget {
  const HeatmapGrid({super.key, required this.days, this.weeks = 26});

  /// 打卡日期集合，格式 yyyy-MM-dd
  final Set<String> days;
  final int weeks;

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentMonday = today.subtract(
      Duration(days: (today.weekday + 6) % 7),
    );
    final start = currentMonday.subtract(Duration(days: 7 * (weeks - 1)));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            for (final label in [
              '',
              weekdayShort(2),
              '',
              weekdayShort(4),
              '',
              weekdayShort(6),
              '',
            ])
              SizedBox(
                height: 13,
                child: Text(
                  label,
                  style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        SizedBox(width: 3),
        Expanded(
          child: Row(
            children: [
              for (var w = 0; w < weeks; w++)
                Expanded(
                  child: Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Builder(
                          builder: (context) {
                            final day = start.add(Duration(days: w * 7 + d));
                            final hit = days.contains(_key(day));
                            final future = day.isAfter(today);
                            return AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                margin: EdgeInsets.all(1.2),
                                decoration: BoxDecoration(
                                  color: future
                                      ? Colors.transparent
                                      : hit
                                      ? scheme.primary.withValues(alpha: 0.8)
                                      : scheme.surfaceContainerHighest
                                            .withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(2.5),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class FocusSlice {
  FocusSlice(this.label, this.minutes);

  final String label;
  final int minutes;
}

/// 本周专注分布：按任务聚合，取前 4，其余归入「其他」。
class FocusDistribution extends StatelessWidget {
  const FocusDistribution({
    super.key,
    required this.slices,
    required this.total,
  });

  final List<FocusSlice> slices;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (total == 0) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text(
          tr('本周还没有专注记录'),
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
      );
    }
    return Column(
      children: [
        for (final s in slices)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Text(
                      '${_fmt(s.minutes)}  ${(s.minutes / total * 100).round()}%',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: s.minutes / total,
                    minHeight: 5,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _fmt(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m}m';
  }
}
