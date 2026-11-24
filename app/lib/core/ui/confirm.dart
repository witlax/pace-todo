import 'package:flutter/material.dart';
import '../i18n/i18n.dart';

/// 危险操作的统一二次确认。
///
/// 删除任务、子任务、习惯、备忘录、附件这类动作都会走这里：
/// 标题说清对象，正文说清后果与能否恢复，确认按钮用错误色。
/// 目的只有一个——把「手滑一下」的成本从「数据没了」降到「多点一下」。
Future<bool> confirmDanger(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: TextStyle(fontSize: 17)),
      content: Text(
        message,
        style: TextStyle(fontSize: 13.5, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel ?? tr('取消')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel ?? tr('删除')),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 非危险但需要说明后果的确认（归档清单、覆盖恢复等）。
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: TextStyle(fontSize: 17)),
      content: Text(
        message,
        style: TextStyle(fontSize: 13.5, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel ?? tr('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel ?? tr('继续')),
        ),
      ],
    ),
  );
  return ok ?? false;
}
