# ADR-0009 V1 不实现同步，但预留可替换数据源与局域网服务端接口

- 状态：已接受
- 日期：2026-11-19
- 关系：细化 ADR-0004（不推翻"V1 不做自动同步"的结论）

## 背景

V1 明确为单机、免登录、离线优先。但后续有两种可预见的形态：

1. **WebDAV / S3 文件同步**：把数据库快照或增量变更同步到网盘，用于多设备。
2. **手机作为局域网后端**：Android 端常驻一个本地 HTTP 服务，桌面端（或另一台设备）通过浏览器/网页版访问同一份数据。

第二种不是"同步"，而是**数据源的替换**：同一个界面层，既能读写本地 SQLite，也能读写远端 HTTP API。若 V1 把 SQL、dart:io、Drift 类型漏进 UI 或领域层，后续要改的就是整个应用。

## 决策

V1 仍不实现任何网络同步，但必须遵守以下**不可回退的架构约束**：

| 约束 | 具体要求 | 违反后果 |
| --- | --- | --- |
| 分层隔离 | `domain` 与 `application` **禁止** import `dart:io`、`package:drift`、任何 Flutter 库 | 无法编译到 Web，无法替换数据源 |
| 仓储接口 | 数据访问只能经 `domain` 中的仓储接口；实现放 `data`（`DriftXxxRepository`，未来 `HttpXxxRepository`） | UI 与 SQL 耦合，替换需重写界面 |
| 可序列化 | 所有实体提供 `toJson/fromJson`，与备份格式、API 结构共用同一套 | 需要维护两套映射，易漂移 |
| 同步字段 | 所有业务表带 `updated_at`、`deleted_at`、`rev`、`device_id` | 上线同步时必须做全表迁移 |
| ID 生成 | 主键用 UUIDv7（时间有序），客户端生成，不依赖数据库自增 | 多端/服务端合并时冲突 |
| 时间语义 | 存 UTC 毫秒 + 独立时区字段，禁止存本地时间字符串 | 跨时区与新设备解析错误 |
| 单机假设 | 不写"全局单例即真相"的逻辑；状态一律经 Provider 注入 | 切换数据源时状态错乱 |

### 预留的接口形态（V1 只定义，不实现）

```
domain/
  task/
    task.dart              // 实体 + toJson/fromJson
    task_repository.dart   // 抽象：watchAll(filter), upsert(task), softDelete(id)
data/
  local/drift_task_repository.dart
  remote/http_task_repository.dart   // V2：指向手机端 HTTP 服务
  sync/sync_adapter.dart             // V2：WebDAV/S3 增量同步
```

`SyncAdapter` 只负责"传输与合并"，不关心业务；`Repository` 只负责"读写"，不关心传输。两者组合出三种部署形态：纯本地、文件同步、局域网服务端。

### 局域网服务端的约束（V2 设计前置）

- 手机端服务用 `shelf` 起 HTTP，暴露 `/api/v1/*`，与 `toJson` 结构一致。
- 认证用局域网 token（扫码或配对码），不做账号体系。
- 桌面"网页打开"意味着**必须有一个可编译到 Web 的构建目标**，因此 `domain`/`application` 与 UI 不能触碰 `dart:io`。
- Android 端需处理息屏/后台导致服务中断的问题（前台服务 + 常驻通知），这与番茄钟的前台服务可共用一套实现。
- 冲突策略沿用字段级 LWW + 墓碑，与 WebDAV 方案一致，不引入第二套规则。

## 备选方案

| 方案 | 未采用原因 |
| --- | --- |
| V1 直接做同步/服务端 | 工期翻倍，且未验证核心体验前不值得投入 |
| V1 不做任何预留，之后再重构 | 重构成本远高于现在约束分层；Web 目标尤其难补 |
| 用 GraphQL 统一接口 | 单人项目过度设计，REST + JSON 足够 |

## 后果

正向：

- V1 保持 60 人日量级交付，同时不锁死未来三种部署形态。
- 分层约束本身提升可测试性：domain 可纯 Dart 单测，无需 Flutter 环境。
- 备份格式与 API 格式统一，减少两套序列化。

负向：

- 每个实体都要写 `toJson/fromJson`，比直接暴露 Drift 行对象多一层代码。
- 不能图省事在 Widget 里直接查库，初期开发略慢。
- Web 兼容性约束会限制部分便捷 API（如 `File`、`Platform`）的使用范围。

## 重新评估条件

1. 明确放弃"网页访问"形态 → 可放宽 Web 兼容约束；
2. 同步方案确定后，若与上述接口形态冲突，需新增 ADR 说明偏离原因；
3. 数据量或并发要求超出单机 SQLite 能力。
