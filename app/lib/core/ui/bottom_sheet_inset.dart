import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 底部弹层的统一留白。
///
/// 只加 `viewInsets.bottom`（键盘高度）时，键盘一收起就变成 0，
/// 保存按钮会被手势导航条压住——真机上点它是会退回桌面的。
/// 这里取「键盘高度」与「系统导航栏高度」的较大者，再留 16。
double sheetBottomInset(BuildContext context) {
  final mq = MediaQuery.of(context);
  return math.max(mq.viewInsets.bottom, mq.padding.bottom) + 16;
}
