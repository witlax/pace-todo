import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/tokens.dart';
import '../../core/app_info.dart';
import '../../core/backup/backup_service.dart';
import '../../core/log/app_log.dart';
import '../tasks/task_repository.dart';
import 'settings.dart';
import '../../core/i18n/i18n.dart';

// ---------------------------------------------------------------- 外观

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('外观'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            tr('主题'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(value: ThemeMode.system, label: Text(tr('跟随系统'))),
              ButtonSegment(value: ThemeMode.light, label: Text(tr('浅色'))),
              ButtonSegment(value: ThemeMode.dark, label: Text(tr('深色'))),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => notifier.setThemeMode(s.first),
            showSelectedIcon: false,
          ),
          SizedBox(height: 24),
          Text(
            tr('配色方案'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          SizedBox(height: 8),
          for (final name in AppPaletteName.values)
            _PaletteTile(
              name: name,
              selected: settings.paletteName == name,
              onTap: () => notifier.setPalette(name),
            ),
          SizedBox(height: 10),
          Text(
            tr('配色取自 PaletteMaker 的思路：低饱和主色 + 中性底 + 一个暖色强调。') + tr('中性色承担大部分面积，主色只出现在可点的东西上，暖色只标「今天 / 进行中」。') + tr('切换方案会同时换掉重要性四色的色相，避免「主色蓝又被当成低优先级蓝」。'),
            style: TextStyle(
              fontSize: 11,
              height: 1.7,
              color: scheme.outline,
            ),
          ),
          SizedBox(height: 18),
          SwitchListTile(
            value: settings.colorBlindPalette,
            onChanged: notifier.setColorBlindPalette,
            contentPadding: EdgeInsets.zero,
            title: Text(tr('色觉友好配色'), style: TextStyle(fontSize: 14)),
            subtitle: Text(
              tr('高=品红、低=青，替代任何方案里的红与蓝'),
              style: TextStyle(fontSize: 11.5),
            ),
          ),
          SizedBox(height: 8),
          Text(
            tr('重要性只有一套四色语义：红=必做、琥珀=该做、蓝=有空做、灰=未评估。') + tr('色条宽度固定 3 dp，不做整行染色，避免界面花掉（ADR-0012）。'),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.7,
              color: scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 日志

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String _level = 'ALL';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: AppLog.revision,
      builder: (context, _, _) {
        final all = AppLog.entries.reversed.toList();
        final items = _level == 'ALL'
            ? all
            : all.where((e) => e.level == _level).toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('日志')),
            actions: [
              IconButton(
                tooltip: tr('复制全部'),
                icon: Icon(Icons.copy_all_outlined, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: AppLog.export()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(tr('已复制到剪贴板'))));
                  }
                },
              ),
              IconButton(
                tooltip: tr('清空'),
                icon: Icon(Icons.delete_sweep_outlined, size: 20),
                onPressed: AppLog.clear,
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Row(
                  children: [
                    for (final l in ['ALL', 'INFO', 'WARN', 'ERROR'])
                      Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(l, style: TextStyle(fontSize: 11)),
                          selected: _level == l,
                          onSelected: (_) => setState(() => _level = l),
                        ),
                      ),
                    Spacer(),
                    Text(
                      '${items.length}',
                      style: TextStyle(fontSize: 11, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(
                          tr('暂无日志'),
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final e = items[i];
                          final color = switch (e.level) {
                            'ERROR' => scheme.error,
                            'WARN' => Colors.orange.shade700,
                            _ => scheme.onSurfaceVariant,
                          };
                          return Padding(
                            padding: EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('HH:mm:ss').format(e.at),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: scheme.outline,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  e.level,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.message,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 关于

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('关于'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              // 与桌面图标同款：主色圆角底 + 白色对勾。
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.check, size: 30, color: scheme.onPrimary),
              ),
              SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kAppName,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '$kAppSubtitle · $kAppVersion (build $kAppBuild)',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            kAppTagline,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 18),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.description_outlined, size: 20),
            title: Text(tr('开源许可'), style: TextStyle(fontSize: 14)),
            trailing: Icon(Icons.chevron_right, size: 18),
            onTap: () => showLicensePage(
              context: context,
              applicationName: kAppName,
              applicationVersion: '0.2.0',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.privacy_tip_outlined, size: 20),
            title: Text(tr('隐私说明'), style: TextStyle(fontSize: 14)),
            trailing: Icon(Icons.chevron_right, size: 18),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(tr('隐私说明')),
                scrollable: true,
                content: Text(
                    kPrivacyText,
                    style: TextStyle(fontSize: 12.5, height: 1.75),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(tr('知道了')),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 24),
          Text(
            tr('本地优先 · 无账号 · 无网络请求'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 备份

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _lastPath;

  BackupService get _service => BackupService(ref.read(databaseProvider));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr('备份与恢复'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            tr('V1 不做自动同步，备份是唯一的外部副本。') + tr('推荐「完整备份包」：一个 zip 含数据库与全部附件；') + tr('JSON 只含文本记录。导入均为覆盖式（会清空现有数据）。'),
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _exportZip,
            icon: Icon(Icons.inventory_2_outlined, size: 18),
            label: Text(tr('导出完整备份包（含附件）')),
          ),
          SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importZip,
            icon: Icon(Icons.unarchive_outlined, size: 18),
            label: Text(tr('从完整备份包恢复')),
          ),
          SizedBox(height: 22),
          Text(
            tr('仅文本（JSON）'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _export,
            icon: Icon(Icons.save_alt, size: 18),
            label: Text(tr('导出到文件')),
          ),
          SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final json = await _service.exportJson();
                    await Clipboard.setData(ClipboardData(text: json));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('JSON 已复制到剪贴板'))),
                      );
                    }
                  },
            icon: Icon(Icons.copy_all_outlined, size: 18),
            label: Text(tr('复制 JSON')),
          ),
          SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importFromClipboard,
            icon: Icon(Icons.restore, size: 18),
            label: Text(tr('从剪贴板恢复')),
          ),
          SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importFromLatestFile,
            icon: Icon(Icons.folder_open, size: 18),
            label: Text(tr('从最近的备份文件恢复')),
          ),
          if (_lastPath != null) ...[
            SizedBox(height: 20),
            Text(
              trf('最近导出：{}', [_lastPath]),
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: scheme.outline,
              ),
            ),
          ],
          SizedBox(height: 28),
          Text(
            tr('导入前会二次确认。恢复完成后需要重启应用，让提醒重新排程。'),
            style: TextStyle(fontSize: 11, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _exportZip() async {
    setState(() => _busy = true);
    try {
      final bytes = await _service.exportZipBytes();
      final now = DateTime.now();
      final stamp =
          '${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final uri = await FilePicker.saveFile(
        fileName: 'tasks-backup-$stamp.zip',
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/zip',
        dialogTitle: tr('保存完整备份包'),
      );
      AppLog.i(trf('完整备份包已导出：{}', [uri]));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uri == null
                ? tr('已取消保存')
                : trf('备份包已保存（{} KB）', [(bytes.length / 1024).round()]),
          ),
        ),
      );
    } catch (e) {
      AppLog.e(trf('备份包导出失败：{}', [e]));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('导出失败：{}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importZip() async {
    final picked = await FilePicker.pickFiles();
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('用备份包覆盖当前数据？')),
        content: Text(tr('会先清空任务、备忘录、打卡与专注记录，再写入备份内容，且无法撤销。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('导入')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final (rows, assets) = await _service.importZipBytes(bytes);
      AppLog.i(trf('备份包已导入：{} 条记录，{} 个附件', [rows, assets]));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(trf('已恢复 {} 条记录、{} 个附件，建议重启应用', [rows, assets]))),
      );
    } catch (e) {
      AppLog.e(trf('备份包导入失败：{}', [e]));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('导入失败：{}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await _service.exportToFile();
      AppLog.i(tr('备份已导出'));
      if (!mounted) return;
      setState(() => _lastPath = path);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('已导出：{}', [path]))));
    } catch (e) {
      AppLog.e(trf('备份导出失败：{}', [e]));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('导出失败：{}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final json = data?.text;
    if (json == null || json.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('剪贴板里没有 JSON'))));
      return;
    }
    await _doImport(json);
  }

  Future<void> _importFromLatestFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('tasks-backup-'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('还没有备份文件'))));
      return;
    }
    await _doImport(await files.first.readAsString());
  }

  Future<void> _doImport(String json) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('覆盖当前数据？')),
        content: Text(tr('导入会清空现有任务、备忘录、打卡与专注记录，且无法撤销。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('导入')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final count = await _service.importJson(json);
      AppLog.i(trf('备份已导入，共 {} 条', [count]));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('已恢复 {} 条记录，建议重启应用', [count]))));
    } catch (e) {
      AppLog.e(trf('备份导入失败：{}', [e]));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(trf('导入失败：{}', [e]))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// 一个配色方案的色卡：背景 / 主色 / 强调 / 完成 四格预览。
class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final AppPaletteName name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = name.scheme;
    final swatches = [p.bgLight, p.seed, p.accent, p.done];

    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in swatches)
                      Container(
                        width: 16,
                        height: 30,
                        color: c,
                        child: c == p.bgLight
                            ? Center(
                                child: Container(
                                  width: 16,
                                  height: 1,
                                  color: scheme.outlineVariant,
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      name.hint,
                      style: TextStyle(fontSize: 10.5, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
