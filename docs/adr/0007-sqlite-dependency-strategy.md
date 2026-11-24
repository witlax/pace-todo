# ADR-0007 数据库依赖改用 drift 2.31 + 预编译 SQLite

- 状态：已接受
- 日期：2026-11-19
- 取代：ADR-0002 中的版本部分（架构决策不变）

## 背景

按 ADR-0002 使用 drift 2.35.4 后，`flutter test` 与双端构建全部失败，定位到两层原因：

1. `sqlite3_flutter_libs` 最新版为 `0.6.0+eol`，官方说明"不再使用，请改用 sqlite3 3.x 的原生资产机制"。
2. `sqlite3 3.9.1` 通过 Dart build hooks 在构建期从 **GitHub Releases 下载**平台二进制：
   `https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.9.1/sqlite3.x64.windows.dll`
   本机访问该地址失败（connection closed），构建直接中断。
3. 即使下载成功，hooks 机制还需要 `native_toolchain_c` 编译 C++，而它通过 `reg.exe` 定位 MSVC/Windows SDK；本机安全策略禁用 `reg.exe`，编译报 `windows.h / crtdbg.h not found`。

实测三种绕行方案：

| 方案 | 结果 |
| --- | --- |
| 配置 `url_pattern` 指向 GitHub 代理（ghfast.top） | DLL 可下载（1.73 MB，PE 头正常），但仍卡在 C++ 编译（reg.exe） |
| `source: system` 用系统 SQLite | 可行但 Android 各版本 FTS5 支持不一致，放弃 |
| `source: source` 从源码编译 | 需要各平台 C 工具链与 NDK，构建成本高，放弃 |

## 决策

固定在"无需原生资产、无需 GitHub"的组合：

```yaml
dependencies:
  drift: ^2.31.0          # 2.32+ 强制 sqlite3 3.x
  drift_flutter: ^0.2.8   # 0.3+ 强制 sqlite3 3.x
  sqlite3_flutter_libs: ^0.5.42
```

- **Android**：`sqlite3_flutter_libs 0.5.42` 通过 Maven 依赖 `eu.simonbinder:sqlite3-native-library:3.52.0` 引入预编译 `.so`，随 APK 打包（实测三个 ABI 各 1.5 MB），不依赖系统 SQLite，FTS5 可用。
- **Windows**：插件从 `sqlite.org` 下载 `sqlite-autoconf` 源码，由 CMake + MSVC 编译为 `sqlite3.dll`（实测 64 秒内完成，sqlite.org 本机可达）。
- **测试**：主机侧把构建产物 `sqlite3.dll` 放到工作目录即可运行 `flutter test`，已实测通过。

## 备选方案

| 方案 | 未采用原因 |
| --- | --- |
| sqlite3 3.x + GitHub 代理 | 依赖第三方代理长期可用性；且仍受 reg.exe 限制 |
| `source: system` | Android 系统 SQLite 版本碎片化，FTS5 不保证 |
| 改用 Hive / Isar | 放弃 SQL 与复杂筛选能力，违背 ADR-0002 |
| 自建二进制镜像 | 单人项目无运维必要 |

## 后果

正向：

- 构建不依赖 GitHub，弱网/被墙环境下可复现。
- 无原生资产编译，Android 首次构建从"不可用"变为 178 秒（缓存后）；Windows 42 秒。
- 数据库能力完整保留：事务、索引、FTS5、迁移。

负向：

- drift 落后 4 个小版本（2.31 vs 2.35），部分新 API 不可用。
- Windows 端首次构建需编译 SQLite 源码，依赖 `sqlite.org` 可达。
- 若将来需要 SQLCipher 加密，需重新评估（0.5.x 有独立加密包）。

## 重新评估条件

1. 本机 `reg.exe` 解禁，且 GitHub 可通过代理稳定访问 → 可回到 sqlite3 3.x；
2. drift 2.31 缺少项目必需的 API；
3. 需要数据库加密或自定义 SQLite 编译选项。
