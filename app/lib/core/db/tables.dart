import 'package:drift/drift.dart';

/// 清单。收件箱是唯一 `isInbox = true` 的记录，不可删除。
@DataClassName('TaskList')
class Lists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer().nullable()();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get rev => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 任务。子任务通过 `parentId` 关联，V1 只允许一层。
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get listId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  IntColumn get status =>
      integer().withDefault(const Constant(0))(); // 0 待办 1 完成 2 取消
  IntColumn get importance =>
      integer().withDefault(const Constant(0))(); // 0 无 1 低 2 中 3 高
  DateTimeColumn get startAt => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();
  IntColumn get estimateMin => integer().nullable()();
  IntColumn get spentMin => integer().withDefault(const Constant(0))();
  TextColumn get repeatRule => text().nullable()();
  IntColumn get repeatMode => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get completedSummary => text().nullable()(); // 完成总结
  DateTimeColumn get remindAt => dateTime().nullable()(); // 提醒时间，空则按到期提醒
  DateTimeColumn get archivedAt => dateTime().nullable()(); // 归档时间
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get rev => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskTags extends Table {
  TextColumn get taskId => text()();
  TextColumn get tagId => text()();

  @override
  Set<Column> get primaryKey => {taskId, tagId};
}

/// 备忘录：独立实体，可被任务引用（ADR-0011）。
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().nullable()();
  TextColumn get bodyMd => text().nullable()();
  IntColumn get importance => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  TextColumn get tags => text().nullable()(); // 逗号分隔，轻量标签，不建关联表
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  IntColumn get rev => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteAssets extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  IntColumn get type => integer().withDefault(const Constant(0))(); // 0 图片 1 文件
  TextColumn get localPath => text()();
  TextColumn get mime => text().nullable()();
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get size => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class TaskNoteLinks extends Table {
  TextColumn get taskId => text()();
  TextColumn get noteId => text()();
  IntColumn get mode => integer().withDefault(const Constant(0))(); // 0 引用 1 快照
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {taskId, noteId};
}

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get color => integer().nullable()();
  IntColumn get freqType => integer().withDefault(const Constant(0))();
  TextColumn get freqConfig => text().nullable()();
  IntColumn get targetCount => integer().withDefault(const Constant(1))();
  TextColumn get remindTime => text().nullable()(); // HH:mm，空为不提醒
  BoolColumn get promptJournal =>
      boolean().withDefault(const Constant(true))(); // 打卡后弹心得
  TextColumn get startDate => text().nullable()(); // yyyy-MM-dd，统计起点
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 打卡记录。date 为"归属日"（本地日 YYYY-MM-DD），跨时区不改写历史。
class HabitLogs extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text()();
  TextColumn get date => text()();
  IntColumn get count => integer().withDefault(const Constant(1))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class FocusSessions extends Table {
  TextColumn get id => text()();
  TextColumn get taskId => text().nullable()();
  IntColumn get mode =>
      integer().withDefault(const Constant(0))(); // 0 番茄 1 正计时 2 休息
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get plannedSec => integer().nullable()();
  IntColumn get actualSec => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 目标：把散落的动作聚成一条进度。
///
/// `mode` 决定进度从哪来：0 任务（关联任务完成比例）、1 习惯（关联习惯打卡/计划次数）、
/// 2 专注（关联会话分钟/目标分钟）、3 手动（直接写 current）。
/// 不做子目标树——目标的用途是复盘时回答「为什么做」，不是再造一层项目管理。
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  IntColumn get mode => integer().withDefault(const Constant(0))();
  IntColumn get target => integer().withDefault(const Constant(1))();
  IntColumn get current => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueAt => dateTime().nullable()();
  IntColumn get status =>
      integer().withDefault(const Constant(0))(); // 0 进行 1 完成 2 归档
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 目标与任务 / 习惯的关联。refType：0 任务，1 习惯。
class GoalLinks extends Table {
  TextColumn get goalId => text()();
  IntColumn get refType => integer()();
  TextColumn get refId => text()();

  @override
  Set<Column> get primaryKey => {goalId, refType, refId};
}

/// 每日心情：一天一条，mood 1（很差）–5（很好），带一句备注。
/// 轻量记录，不做情绪分类体系，只用于回看时知道自己那几天什么状态。
class MoodEntries extends Table {
  TextColumn get id => text()();
  TextColumn get date => text()(); // yyyy-MM-dd
  IntColumn get mood => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
