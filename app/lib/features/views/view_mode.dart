import 'package:flutter/material.dart';
import '../../core/i18n/i18n.dart';

/// 视图页的五个视图。
///
/// 放在独立文件里，是因为「设置页决定显示哪几个」也需要它；
/// 若留在 `views_page.dart` 会和设置形成循环引用。
///
/// 四象限是必选项：它是任务的另一种组织方式，不是装饰性视图。
enum ViewMode {
  dashboard('工作台', Icons.dashboard_outlined, optional: true),
  calendar('日历', Icons.calendar_month_outlined, optional: true),
  board('看板', Icons.view_kanban_outlined, optional: true),
  card('卡片', Icons.grid_view_outlined, optional: true),
  quadrant('四象限', Icons.grid_on_outlined, optional: false);

  const ViewMode(this._label, this.icon, {required this.optional});
  final String _label;
  final IconData icon;

  String get label => tr(_label);

  /// 是否可以关闭显示（四象限固定显示）。
  final bool optional;

  static const defaults = <ViewMode>{
    ViewMode.dashboard,
    ViewMode.calendar,
    ViewMode.board,
    ViewMode.card,
  };
}
