import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';
import '../tasks/task_repository.dart';

/// 备忘录读写：正文、标签、附件、与任务的关联。
///
/// 附件落在应用文档目录 `note-assets/`，数据库只存路径。
/// 不做云存储——V1 本地优先，图片跟着备份一起走（备份只导路径，见文档说明）。
class NoteRepository {
  NoteRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<NoteAsset>> watchAssets(String noteId) {
    final query = _db.select(_db.noteAssets)
      ..where((a) => a.noteId.equals(noteId) & a.deletedAt.isNull())
      ..orderBy([(a) => OrderingTerm(expression: a.createdAt)]);
    return query.watch();
  }

  Future<String> createNote({String? title, String? body, String? tags}) async {
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            title: Value(title),
            bodyMd: Value(body),
            tags: Value(tags),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> saveNote(
    String id, {
    String? title,
    String? body,
    String? tags,
    bool? pinned,
    int? importance,
  }) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: title == null ? const Value.absent() : Value(title),
        bodyMd: body == null ? const Value.absent() : Value(body),
        tags: tags == null ? const Value.absent() : Value(tags),
        pinned: pinned == null ? const Value.absent() : Value(pinned),
        importance: importance == null
            ? const Value.absent()
            : Value(importance),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 把选中的图片复制进应用目录，再登记一条附件。
  /// 复制而不是引用原路径，是因为相册临时文件随时可能被系统清掉。
  Future<NoteAsset> addImage(String noteId, File source) async {
    final sourceSize = await source.length();
    final dup = await _findDuplicate(noteId, sourceSize, isImage: true);
    if (dup != null) return dup;

    final dir = await getApplicationDocumentsDirectory();
    final assetsDir = Directory(p.join(dir.path, 'note-assets'));
    if (!assetsDir.existsSync()) {
      assetsDir.createSync(recursive: true);
    }
    final ext = p.extension(source.path).isEmpty
        ? '.jpg'
        : p.extension(source.path);
    final target = File(p.join(assetsDir.path, '${_uuid.v7()}$ext'));
    await source.copy(target.path);

    final size = await target.length();
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.noteAssets)
        .insert(
          NoteAssetsCompanion.insert(
            id: id,
            noteId: noteId,
            localPath: target.path,
            mime: Value(ext.replaceFirst('.', 'image/')),
            size: Value(size),
            createdAt: now,
          ),
        );
    return NoteAsset(
      id: id,
      noteId: noteId,
      type: 0,
      localPath: target.path,
      mime: ext.replaceFirst('.', 'image/'),
      width: null,
      height: null,
      size: size,
      createdAt: now,
      deletedAt: null,
    );
  }

  /// 文件附件：任意格式（pdf/docx/pptx/txt…），同样复制进应用目录。
  /// 同一份文件重复添加时直接复用已有附件，避免附件区出现两条一样的记录。
  Future<NoteAsset?> _findDuplicate(
    String noteId,
    int size, {
    required bool isImage,
  }) {
    return (_db.select(_db.noteAssets)..where(
          (a) =>
              a.noteId.equals(noteId) &
              a.deletedAt.isNull() &
              a.size.equals(size) &
              a.type.equals(isImage ? 0 : 1),
        ))
        .getSingleOrNull();
  }

  Future<NoteAsset> addFile(String noteId, File source, String fileName) async {
    final dup = await _findDuplicate(
      noteId,
      await source.length(),
      isImage: false,
    );
    if (dup != null) return dup;

    final dir = await getApplicationDocumentsDirectory();
    final filesDir = Directory(p.join(dir.path, 'note-files'));
    if (!filesDir.existsSync()) {
      filesDir.createSync(recursive: true);
    }
    final ext = p.extension(fileName).isEmpty ? '' : p.extension(fileName);
    final target = File(p.join(filesDir.path, '${_uuid.v7()}$ext'));
    await source.copy(target.path);
    final size = await target.length();
    final now = DateTime.now();
    final id = _uuid.v7();
    await _db
        .into(_db.noteAssets)
        .insert(
          NoteAssetsCompanion.insert(
            id: id,
            noteId: noteId,
            type: const Value(1),
            localPath: target.path,
            mime: Value(
              ext.isEmpty
                  ? 'application/octet-stream'
                  : ext.replaceFirst('.', 'file/'),
            ),
            size: Value(size),
            createdAt: now,
          ),
        );
    return NoteAsset(
      id: id,
      noteId: noteId,
      type: 1,
      localPath: target.path,
      mime: ext,
      width: null,
      height: null,
      size: size,
      createdAt: now,
      deletedAt: null,
    );
  }

  Future<void> deleteAsset(String id) async {
    final row = await (_db.select(
      _db.noteAssets,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
    await (_db.update(_db.noteAssets)..where((a) => a.id.equals(id))).write(
      NoteAssetsCompanion(deletedAt: Value(DateTime.now())),
    );
    if (row != null) {
      final f = File(row.localPath);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {
          // 文件被占用时忽略：记录已软删，不影响使用
        }
      }
    }
  }

  /// 备忘录被哪些任务引用，用于编辑页底部显示「被 N 个任务引用」。
  Stream<List<Task>> watchLinkedTasks(String noteId) {
    final query =
        _db.select(_db.tasks).join([
          innerJoin(
            _db.taskNoteLinks,
            _db.taskNoteLinks.taskId.equalsExp(_db.tasks.id),
          ),
        ])..where(
          _db.taskNoteLinks.noteId.equals(noteId) &
              _db.tasks.deletedAt.isNull(),
        );
    return query.watch().map(
      (rows) => rows.map((r) => r.readTable(_db.tasks)).toList(),
    );
  }
}

final noteRepositoryProvider = Provider<NoteRepository>(
  (ref) => NoteRepository(ref.watch(databaseProvider)),
);

final noteAssetsProvider = StreamProvider.family<List<NoteAsset>, String>(
  (ref, noteId) => ref.watch(noteRepositoryProvider).watchAssets(noteId),
);

final noteLinkedTasksProvider = StreamProvider.family<List<Task>, String>(
  (ref, noteId) => ref.watch(noteRepositoryProvider).watchLinkedTasks(noteId),
);
