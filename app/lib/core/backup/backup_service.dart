import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../i18n/i18n.dart';

/// 全量 JSON 备份。V1 不做同步，备份就是唯一的外部副本（ADR-0004）。
/// 格式：`{ "schema": 1, "exportedAt": "...", "tables": { "tasks": [...] } }`
/// 各表用 Drift 数据类的 toJson/fromJson，字段改名时两边同时受编译期保护。
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const schema = 1;

  Future<String> exportJson() async {
    final tables = <String, dynamic>{
      'lists': (await _db.select(_db.lists).get())
          .map((e) => e.toJson())
          .toList(),
      'tasks': (await _db.select(_db.tasks).get())
          .map((e) => e.toJson())
          .toList(),
      'tags': (await _db.select(_db.tags).get())
          .map((e) => e.toJson())
          .toList(),
      'task_tags': (await _db.select(_db.taskTags).get())
          .map((e) => e.toJson())
          .toList(),
      'notes': (await _db.select(_db.notes).get())
          .map((e) => e.toJson())
          .toList(),
      'note_assets': (await _db.select(_db.noteAssets).get())
          .map((e) => e.toJson())
          .toList(),
      'task_note_links': (await _db.select(_db.taskNoteLinks).get())
          .map((e) => e.toJson())
          .toList(),
      'habits': (await _db.select(_db.habits).get())
          .map((e) => e.toJson())
          .toList(),
      'habit_logs': (await _db.select(_db.habitLogs).get())
          .map((e) => e.toJson())
          .toList(),
      'focus_sessions': (await _db.select(_db.focusSessions).get())
          .map((e) => e.toJson())
          .toList(),
      'mood_entries': (await _db.select(_db.moodEntries).get())
          .map((e) => e.toJson())
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert({
      'schema': schema,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': tables,
    });
  }

  /// 写到应用文档目录，返回文件路径。
  Future<String> exportToFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}-'
        '${_two(now.hour)}${_two(now.minute)}';
    final file = File('${dir.path}/pace-backup-$stamp.json');
    await file.writeAsString(await exportJson());
    return file.path;
  }

  /// 覆盖式导入：先清空再写入，返回恢复的记录数。
  /// 覆盖而非合并，是因为合并需要冲突解决，而 V1 没有 rev 比较逻辑。
  Future<int> importJson(String json) async {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final tables = (decoded['tables'] as Map).cast<String, dynamic>();
    var count = 0;

    await _db.transaction(() async {
      // 先删子表再删主表，避免外键顺序问题。
      for (final wipe in <Future<void> Function()>[
        () => _db.delete(_db.taskNoteLinks).go(),
        () => _db.delete(_db.noteAssets).go(),
        () => _db.delete(_db.taskTags).go(),
        () => _db.delete(_db.focusSessions).go(),
        () => _db.delete(_db.habitLogs).go(),
        () => _db.delete(_db.moodEntries).go(),
        () => _db.delete(_db.tasks).go(),
        () => _db.delete(_db.notes).go(),
        () => _db.delete(_db.tags).go(),
        () => _db.delete(_db.habits).go(),
        () => _db.delete(_db.lists).go(),
      ]) {
        await wipe();
      }

      List<Map<String, dynamic>> rows(String key) =>
          ((tables[key] as List?) ?? const [])
              .map((e) => (e as Map).cast<String, dynamic>())
              .toList();

      for (final m in rows('lists')) {
        await _db.into(_db.lists).insert(TaskList.fromJson(m));
        count++;
      }
      for (final m in rows('tasks')) {
        await _db.into(_db.tasks).insert(Task.fromJson(m));
        count++;
      }
      for (final m in rows('tags')) {
        await _db.into(_db.tags).insert(Tag.fromJson(m));
        count++;
      }
      for (final m in rows('task_tags')) {
        await _db.into(_db.taskTags).insert(TaskTag.fromJson(m));
        count++;
      }
      for (final m in rows('notes')) {
        await _db.into(_db.notes).insert(Note.fromJson(m));
        count++;
      }
      for (final m in rows('note_assets')) {
        await _db.into(_db.noteAssets).insert(NoteAsset.fromJson(m));
        count++;
      }
      for (final m in rows('task_note_links')) {
        await _db.into(_db.taskNoteLinks).insert(TaskNoteLink.fromJson(m));
        count++;
      }
      for (final m in rows('habits')) {
        await _db.into(_db.habits).insert(Habit.fromJson(m));
        count++;
      }
      for (final m in rows('habit_logs')) {
        await _db.into(_db.habitLogs).insert(HabitLog.fromJson(m));
        count++;
      }
      for (final m in rows('focus_sessions')) {
        await _db.into(_db.focusSessions).insert(FocusSession.fromJson(m));
        count++;
      }
      for (final m in rows('mood_entries')) {
        await _db.into(_db.moodEntries).insert(MoodEntry.fromJson(m));
        count++;
      }
    });
    return count;
  }

  /// 完整备份包：backup.json + note-assets/ + note-files/。
  /// 换机时只带一个 zip，附件不会丢——JSON 备份解决不了这个问题。
  Future<List<int>> exportZipBytes() async {
    final dir = await getApplicationDocumentsDirectory();
    final json = await exportJson();
    final archive = Archive();

    final jsonBytes = utf8.encode(json);
    archive.addFile(ArchiveFile('backup.json', jsonBytes.length, jsonBytes));

    for (final sub in const ['note-assets', 'note-files']) {
      final folder = Directory('${dir.path}/$sub');
      if (!await folder.exists()) continue;
      await for (final entity in folder.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = entity.path
            .substring(dir.path.length + 1)
            .replaceAll(r'\', '/');
        final bytes = await entity.readAsBytes();
        archive.addFile(ArchiveFile(rel, bytes.length, bytes));
      }
    }
    return ZipEncoder().encode(archive);
  }

  /// 从 zip 恢复：先解出附件到文档目录，再覆盖式导入数据库。
  /// 返回 (记录数, 附件数)。
  Future<(int, int)> importZipBytes(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final dir = await getApplicationDocumentsDirectory();
    String? json;
    var assets = 0;

    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll(r'\', '/');
      if (name == 'backup.json') {
        json = utf8.decode(file.content);
        continue;
      }
      final isAsset =
          name.startsWith('note-assets/') || name.startsWith('note-files/');
      if (!isAsset) continue;
      final target = File('${dir.path}/$name');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(file.content, flush: true);
      assets++;
    }
    if (json == null) {
      throw FormatException(tr('备份包里没有 backup.json'));
    }
    final rows = await importJson(json);
    return (rows, assets);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
