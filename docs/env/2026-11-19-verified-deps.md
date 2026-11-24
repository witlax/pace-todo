# 依赖版本基线（实测通过）· 2026-11-19

> 来源：一次性验证工程 `%TEMP%/_stackcheck` 的 `pubspec.lock`（构建通过后导出）。
> 用途：M0 建工程时按此表锁定版本；任何偏离都需在 DEVLOG 说明原因。
> 环境：Flutter 3.47.7 / Dart 3.13.5 / JDK 17.0.20.1 / Android SDK 37.0 + NDK 28.2.13676358 / VS 2022 MSVC 14.43。

## 核心依赖（实际解析版本）

| 包 | 版本 | 说明 |
| --- | --- | --- |
| flutter_riverpod | 3.5.0 | 状态管理 |
| go_router | 18.1.4 | 路由与深链 |
| drift | 2.31.0 | 2.32+ 强制 sqlite3 3.x，会触发 GitHub 下载（ADR-0007） |
| drift_flutter | 0.2.8 | 数据库打开与平台路径 |
| sqlite3 | 2.9.4 | 传递依赖，随 sqlite3_flutter_libs 提供原生库 |
| sqlite3_flutter_libs | 0.5.42 | Android 走 Maven AAR；Windows 从 sqlite.org 编译 |
| flutter_local_notifications | 23.0.3 | 要求 compileSdk 37 + 脱糖 |
| flutter_foreground_task | 11.0.3 | 番茄钟前台服务 |
| home_widget | 0.10.0 | Android 小组件 |
| fl_chart | 1.3.1 | 图表 |
| audioplayers | 6.8.1 | 白噪音与音效 |
| window_manager | 0.5.2 | 0.6+ 依赖 nativeapi（ADR-0008） |
| tray_manager | 0.5.3 | 约束 `^0.5.1`，实际解析 0.5.3 |
| hotkey_manager | 0.2.3 | 0.3+ 依赖 nativeapi |
| launch_at_startup | 0.5.1 | 开机自启 |
| rrule | 0.2.18 | 重复规则（RFC5545） |
| timezone / flutter_timezone | 0.11.2 / 5.1.1 | 时区数据与设备时区 |
| shared_preferences | 2.5.6 | 轻量设置 |
| path_provider | 2.1.6 | 应用目录 |
| msix | 3.18.0 | Windows 打包（dev） |
| uuid / intl / logging | 4.6.0 / 0.20.3 / 1.3.0 | 工具 |

## 构建证据

| 目标 | 命令 | 结果 |
| --- | --- | --- |
| Android | `flutter build apk --debug` | √ 165 MB / 178.1 s（首次 752 s） |
| Windows | `flutter build windows --debug` | √ 42.3 s |
| 运行时 | `flutter test` | 3/3 通过（SQLite + FTS5 + RRULE + 时区） |

## 已知传递依赖风险

| 包 | 风险 |
| --- | --- |
| `jni` / `cnativeapi` | 由 `shared_preferences_android 2.5.x`、`path_provider_android 2.3.x` 引入，会触发原生资产编译（需 NDK；Windows 需 reg.exe）。当前可正常构建 Android，Windows 侧已通过去掉 nativeapi 系插件规避 |
| `home_widget` | 使用旧式 Kotlin Gradle Plugin，Flutter 未来版本会拒绝构建，升级时需跟进 |
