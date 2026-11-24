# ADR-0001 采用 Flutter 作为唯一跨端框架

- 状态：已接受
- 日期：2026-11-18
- 相关：`docs/02-技术栈与开发框架.md`、`docs/01-调研与技术评估.md`

## 背景

产品要求 Android 优先、同步支持 Windows。界面以列表、日历、图表、计时器为主，属于高度自绘的交互型 UI，而非内容展示型页面。团队规模为 1 人 + AI 辅助，交付效率优先于"原生控件贴合度"。

## 决策

使用 Flutter 3.47.7 / Dart 3.13.5 单工程，同时产出 `android` 与 `windows` 两个 target。UI、状态、数据层全部共享；仅通知、托盘、小组件等平台能力做适配层。

## 备选方案

| 方案 | 放弃原因 |
| --- | --- |
| React Native + Expo | Expo 不支持 Windows 桌面；RN-Windows 为社区方案，需独立工程与维护成本 |
| Kotlin Multiplatform + Compose | 桌面与移动 UI 需两套实现（或依赖 Compose Desktop 的成熟度），单人交付接近翻倍 |
| Android 原生 + WinUI 双端 | 代码零复用，工期不可接受 |
| Tauri + Web 前端 | 移动端（Android）能力与体验不足，通知/后台计时受限 |

## 后果

正向：

- 一份代码覆盖两个目标平台，MVP 工期约 60 人日可达成。
- 自绘 UI 保证两端视觉与交互一致，减少双端对齐成本。
- 关键能力均有成熟包：`drift`、`flutter_local_notifications`（含 Windows Toast）、`home_widget`、`flutter_foreground_task`。

负向：

- 包体积比原生大（引擎约 +8–15 MB）。
- Windows 通知不支持重复排程，需在排程层降级。
- Dart 生态在少数系统级 API 上仍需写平台通道代码。

## 重新评估条件

1. 必须支持 iOS 且团队已有成熟 Swift 能力，同时 Flutter 在 iOS 上出现阻塞性缺陷；
2. 需要深度系统集成（如系统级日历写入、输入法、无障碍服务）超过 30% 的功能量；
3. 包体积成为硬性约束（如要求 <15 MB）。
