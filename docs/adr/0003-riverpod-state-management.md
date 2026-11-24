# ADR-0003 使用 Riverpod 3 管理状态

- 状态：已接受
- 日期：2026-11-18

## 决策

采用 **Riverpod 3.5.0**（`flutter_riverpod`），不引入 `riverpod_generator`：

- 全局依赖（数据库、时钟、仓储、通知调度）用 `Provider` 覆盖注入，测试中可替换为假实现。
- 页面状态用 `Notifier` / `AsyncNotifier`；列表与筛选结果用 `StreamProvider` 直接消费 Drift 查询。
- 派生状态（今日任务数、逾期数、当前 streak）用 `Provider` 组合，不重复查询数据库。

## 备选方案

| 方案 | 放弃原因 |
| --- | --- |
| Provider + ChangeNotifier | 依赖关系隐式，跨页面共享与测试替身麻烦 |
| BLoC | 样板代码多，单人项目收益不足 |
| GetX | 全局可变状态难以约束，长期可维护性差 |
| 原生 setState | 无法承载跨页面共享与派生查询 |

## 后果

正向：

- 编译期捕获依赖错误；Provider 可被 `overrideWith` 精确替换，纯逻辑测试不需要 Flutter 环境。
- 与 Drift 的 `Stream` 天然契合，省掉手写刷新逻辑。
- 不引入 build_runner 生成，减少一条 codegen 链路。

负向：

- 需要团队理解 Provider 生命周期与 `autoDispose` 语义，否则易出现重复订阅。
- 3.x 的 API 与 2.x 有差异，检索到的旧示例不能直接照搬。

## 重新评估条件

1. 出现大量需要跨页面事务编排的场景，Notifier 职责膨胀；
2. Riverpod 主版本出现破坏性变更且迁移成本高于收益。
