import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/ui/bottom_sheet_inset.dart';
import '../../core/ui/confirm.dart';
import '../memos/note_repository.dart';
import '../settings/settings.dart';
import 'habit_repository.dart';
import '../../core/i18n/i18n.dart';

/// 打卡与写心得的共用动作。
///
/// 之前在 `habit_page.dart` 里是私有方法，首页也要打卡就只能复制一遍；
/// 复制出来的那份把「已打卡 → 写心得」写成了「已打卡 → 撤销」，
/// 正是 1.0.0 的那个 bug。现在只有这一份实现。

/// 单击打卡：未完成则 +1，已完成则撤销（撤销可按设置要求二次确认）。
Future<void> habitQuickCheckIn(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
  Set<String> days,
  int todayCount,
) async {
  final repo = ref.read(habitRepositoryProvider);
  final target = habit.targetCount;
  final done = todayCount >= target;
  final needConfirm = ref.read(settingsProvider).confirmCheckIn;
  final name = habitDisplayName(habit.name);
  final todayLabel = dfMonthDayFmt().format(DateTime.now());

  Future<bool> confirm({
    required String title,
    required String message,
    required String okLabel,
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Text(message, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  if (done) {
    if (needConfirm) {
      final ok = await confirm(
        title: trf('撤销「{}」今天的打卡？', [name]),
        message: target > 1
            ? trf('{} 已记 {}/{} 次，撤销会清掉今天全部记录。', [todayLabel, todayCount, target])
            : trf('{} 的这条记录会被删掉，可随时重新打卡。', [todayLabel]),
        okLabel: tr('撤销'),
        danger: true,
      );
      if (!ok || !context.mounted) return;
    }
    for (var i = 0; i < (todayCount == 0 ? 1 : todayCount); i++) {
      await repo.undo(habit.id);
    }
    if (!context.mounted) return;
    showHabitBar(
      context,
      trf('已撤销「{}」', [name]),
      actionLabel: tr('恢复'),
      onAction: () => repo.checkIn(habit.id),
    );
    return;
  }

  if (needConfirm) {
    final ok = await confirm(
      title: trf('打卡「{}」', [name]),
      message: target > 1
          ? trf('记录 {} 的第 {}/{} 次。', [todayLabel, todayCount + 1, target])
          : trf('记录 {} 的这一次。可在设置里关掉确认。', [todayLabel]),
      okLabel: tr('打卡'),
    );
    if (!ok || !context.mounted) return;
  }

  final next = await repo.checkIn(habit.id);
  if (!context.mounted) return;
  final reached = next >= target;

  // 一次型习惯达成后直接弹「写一句」——这是 pinch 的操作逻辑：
  // 打卡和记录感受是一件事，不该让人再去找入口。
  // 多次习惯（喝水 8 杯）不自动弹，否则每点一次都被打断。
  if (reached && target == 1 && habit.promptJournal) {
    await habitPromptNote(context, ref, habit);
    if (!context.mounted) return;
  }

  showHabitBar(
    context,
    reached
        ? trf('已打卡「{}」· {}', [name, DateFormat('HH:mm').format(DateTime.now())])
        : trf('「{}」{}/{} 次', [name, next, target]),
    actionLabel: tr('撤销'),
    onAction: () => repo.undo(habit.id),
    secondLabel: tr('写心得'),
    onSecond: () => habitOpenJournal(context, ref, habit),
  );
}

/// 打卡成功后的「写一句」：可以跳过，不做阻断。
Future<void> habitPromptNote(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
) async {
  final controller = TextEditingController();
  final name = habitDisplayName(habit.name);

  final saved = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, sheetBottomInset(ctx)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            trf('已打卡 · {}', [name]),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4),
          Text(
            tr('记一句今天的状态，下次回看时有据可循'),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(ctx).colorScheme.outline,
            ),
          ),
          SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(hintText: tr('例如：今天状态一般，但坚持下来了')),
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tr('跳过')),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(controller.text),
                  child: Text(tr('保存')),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  final note = (saved ?? '').trim();
  if (note.isEmpty || !context.mounted) return;
  await ref.read(habitRepositoryProvider).setTodayNote(habit.id, note);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        persist: false,
        duration: Duration(seconds: 2),
        content: Text(tr('心得已记下'), style: TextStyle(fontSize: 12.5)),
      ),
    );
}

/// 打卡 / 写心得弹层。
///
/// - 未打卡：填一句（可空）→ 完成打卡；想留档就存成备忘录。
/// - 已打卡：编辑这一天这条记录的心得。撤销是旁边那个明确的按钮，且要二次确认。
Future<void> habitOpenJournal(
  BuildContext context,
  WidgetRef ref,
  Habit habit,
) async {
  final repo = ref.read(habitRepositoryProvider);
  final today = dayKey(DateTime.now());
  final log = (ref.read(habitLogsProvider).value ?? <HabitLog>[])
      .where((l) => l.habitId == habit.id && l.date == today)
      .firstOrNull;
  final doneToday = log != null;
  final name = habitDisplayName(habit.name);
  final target = habit.targetCount;
  final doneCount = log?.count ?? 0;
  final controller = TextEditingController(text: log?.note ?? '');
  final scheme = Theme.of(context).colorScheme;

  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, sheetBottomInset(ctx)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  doneToday ? trf('今天已打卡 · {}', [name]) : trf('打卡：{}', [name]),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (doneToday)
                Text(
                  trf('{}/{} 次', [doneCount, target]),
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            decoration: InputDecoration(
              hintText: doneToday ? tr('给这次打卡补一句（可留空）') : tr('今天感觉如何？（可留空）'),
            ),
            style: TextStyle(fontSize: 14, height: 1.6),
          ),
          SizedBox(height: 14),
          if (doneToday)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop('undo'),
                    child: Text(
                      tr('撤销打卡'),
                      style: TextStyle(fontSize: 13, color: scheme.error),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop('saveNote'),
                    child: Text(tr('保存心得')),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop('note'),
                    child: Text(tr('存为备忘录')),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop('check'),
                    child: Text(tr('完成打卡')),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;
  final note = controller.text.trim();

  if (action == 'saveNote') {
    await repo.setTodayNote(habit.id, note.isEmpty ? null : note);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          persist: false,
          duration: Duration(seconds: 2),
          content: Text(
            note.isEmpty ? tr('已清空这条打卡的心得') : tr('心得已保存'),
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      );
    return;
  }

  if (action == 'undo') {
    final ok = await confirmDanger(
      context,
      title: trf('撤销「{}」今天的打卡？', [name]),
      message: target > 1
          ? trf('今天已记 {}/{} 次，撤销会清掉今天全部记录。', [doneCount, target])
          : tr('这条记录会被删掉，可随时重新打卡。'),
      confirmLabel: tr('撤销'),
    );
    if (!ok || !context.mounted) return;
    final times = doneCount == 0 ? 1 : doneCount;
    for (var i = 0; i < times; i++) {
      await repo.undo(habit.id);
    }
    if (!context.mounted) return;
    showHabitBar(
      context,
      trf('已撤销「{}」', [name]),
      actionLabel: tr('恢复'),
      onAction: () => repo.checkIn(habit.id),
    );
    return;
  }

  await repo.checkIn(habit.id, note: note.isEmpty ? null : note);
  if (action == 'note' && note.isNotEmpty) {
    await ref
        .read(noteRepositoryProvider)
        .createNote(title: trf('{} · 打卡心得', [name]), body: note);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        persist: false,
        content: Text(
          action == 'note' ? tr('已打卡，心得已存为备忘录') : trf('已打卡：{}', [name]),
          style: TextStyle(fontSize: 12.5),
        ),
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: tr('撤销'),
          onPressed: () => repo.undo(habit.id),
        ),
      ),
    );
}

/// 带两个动作的提示条（撤销 + 写心得）。
void showHabitBar(
  BuildContext context,
  String message, {
  required String actionLabel,
  required VoidCallback onAction,
  String? secondLabel,
  VoidCallback? onSecond,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        // 带 action 的 SnackBar 在 Flutter 新版会常驻，必须显式关掉。
        persist: false,
        duration: Duration(seconds: 6),
        content: Row(
          children: [
            Expanded(
              child: Text(message, style: TextStyle(fontSize: 12.5)),
            ),
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: Theme.of(context).colorScheme.primary,
                padding: EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size(0, 32),
              ),
              onPressed: onAction,
              child: Text(
                actionLabel,
                style: TextStyle(fontSize: 12.5),
              ),
            ),
            if (secondLabel != null)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size(0, 32),
                ),
                onPressed: onSecond,
                child: Text(
                  secondLabel,
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
    );
}
