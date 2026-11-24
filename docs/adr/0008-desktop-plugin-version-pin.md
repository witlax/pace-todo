# ADR-0008 桌面插件锁定在无 nativeapi 的版本

- 状态：已接受
- 日期：2026-11-19

## 背景

初次依赖解析即失败：`window_manager 0.7.0`、`tray_manager 0.9.0`、`hotkey_manager 0.4.0` 均要求 Dart `^3.14.0` / Flutter `>=3.50.0`，而本机为 Flutter 3.47.7 / Dart 3.13.5。

降到可解析的版本（0.6.0 / 0.8.3 / 0.3.0）后，Android 可构建，但 **Windows 构建失败**：

```
Target build_hooks failed : error : Building native assets failed.
fatal error C1083: 无法打开包括文件: "windows.h"
```

反查依赖树发现：这三个插件的新版本改为依赖 `nativeapi` → `cnativeapi`，走 Dart 原生资产（build hooks）编译 C++。该机制通过 `reg.exe` 定位 MSVC 与 Windows SDK，而本机安全策略禁用 `reg.exe`，导致头文件路径缺失。实测注入 `INCLUDE`/`LIB` 环境变量无效（工具链使用隔离环境）。

验证：这三个插件的旧版本均**不依赖** `nativeapi`：

| 插件 | 旧版本 | 依赖 |
| --- | --- | --- |
| window_manager | 0.5.2 | path, screen_retriever |
| tray_manager | 0.5.1 | menu_base, path, shortid |
| hotkey_manager | 0.2.3 | collection, hotkey_manager_* 平台包 |

## 决策

```yaml
dependencies:
  window_manager: ^0.5.2
  tray_manager: ^0.5.1
  hotkey_manager: ^0.2.3
```

`^0.5.2` 只允许 0.5.x，不会自动升级到 0.6（0.6 起引入 nativeapi）。

## 备选方案

| 方案 | 未采用原因 |
| --- | --- |
| 升级 Flutter 到 3.50.0 | 可行（当前最新稳定版，2026-11-11 发布），但需重新验证全部工具链；且 nativeapi 仍受 reg.exe 限制 |
| 在安全中心放行 `reg.exe` | 属用户安全策略，不应由项目替用户决定；作为备选路径保留 |
| 放弃托盘/快捷键/窗口管理 | 它们是 Windows"好用"的核心，P1 必须保留 |

## 后果

正向：

- Windows 全量构建通过（42.3 秒），含托盘与全局快捷键能力。
- 构建不依赖原生资产机制，环境要求低，换机可复现。
- 旧版 API 与新版本差异很小（窗口控制、托盘菜单、热键注册的签名基本一致）。

负向：

- 无法使用 0.6+ 的新特性（如新版多窗口 API）。
- 依赖版本落后，后续升级 Flutter 时需重新评估并回归。
- 三个插件合计落后约 3～6 个月。

## 重新评估条件

1. Flutter 升级到 3.50+ 且 `reg.exe` 可放行（或改用用户终端构建），一次性升到最新；
2. 项目需要多窗口 / 新托盘能力；
3. 插件作者提供不依赖 nativeapi 的兼容版本。
