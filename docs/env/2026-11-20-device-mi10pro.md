# 真机基线 · Xiaomi Mi 10 Pro

> 首次接入：2026-11-20。用于开发期验证提醒、前台服务、小组件与全屏专注。
> 后续换机或重置系统，按本文逐项复核；状态变化写入 `DEVLOG.md`。

---

## 1. 设备信息（实测）

| 项 | 值 |
| --- | --- |
| 型号 | Mi 10 Pro（`cmi`） |
| 系统 | HyperOS 1.0，`V816.0.9.0.TJACNXM`，Android 13（SDK 33） |
| 架构 | arm64-v8a |
| 屏幕 | 1080 × 2340，440 dpi（约 393 dp 宽），最高 90 Hz |
| 存储 | /data 226 GB，剩余 119 GB |
| Root | 无（`no-su`） |
| 电池优化模式 | 未开启省电（`low_power=0`） |
| 序列号 | `5b4d88de` |

## 2. 已验证通过（有证据）

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| adb 授权 | 通过 | `adb devices` 显示 `device` 而非 `unauthorized` |
| 开发者选项 | 已开启 | `development_settings_enabled=1` |
| USB 调试 | 已开启 | `adb_enabled=1` |
| 未知来源安装 | 允许 | `install_non_market_apps=1` |
| **APK 安装** | **成功，未被 MIUI 拦截** | `adb install -r` 返回 `Success`（74 MB，arm64） |
| 应用启动与渲染 | 通过 | 临时 Flutter 工程启动后截图正常，无系统弹窗 |
| USB 安装二次确认 | 未触发 | 说明"通过 USB 安装"已放行，无需额外点按 |

> 结论：**基础链路已通，可以直接进入 M0 装机调试。**

## 3. 仍建议手动开启的项

按重要性排序。"设置路径"为 HyperOS 1.0 的菜单名，可能因版本略有差异。

### 3.1 必开（影响提醒可靠性）

| # | 项 | 路径 | 为什么 |
| --- | --- | --- | --- |
| 1 | **省电策略 → 无限制** | 设置 → 应用设置 → 应用管理 → 任务 → 省电策略 → 无限制 | MIUI 默认会冻结后台，提醒与番茄计时会被杀 |
| 2 | **自启动** | 设置 → 应用设置 → 授权管理 → 自启动 → 允许"任务" | 重启后闹钟与前台服务需要重新注册 |
| 3 | **通知权限** | 首次启动会弹窗；拒绝后：设置 → 应用设置 → 应用管理 → 任务 → 通知 → 允许 | 提醒、计时通知都依赖它（Android 13 起为运行时权限） |
| 4 | **闹钟和提醒** | 设置 → 应用 → 特殊权限 → 闹钟和提醒 → 允许 | 精确到分钟的提醒需要 `SCHEDULE_EXACT_ALARM` |

### 3.2 建议开（影响体验与测试效率）

| # | 项 | 路径 | 为什么 |
| --- | --- | --- | --- |
| 5 | 锁屏显示 | 设置 → 应用设置 → 应用管理 → 任务 → 其他权限 → 锁屏显示 | 全屏专注与提醒在锁屏可见 |
| 6 | 后台弹出界面 | 同上 → 后台弹出界面 | 从通知点回专注页时不被拦 |
| 7 | USB 调试（安全设置） | 开发者选项 → USB 调试（安全设置） | 允许 `adb shell pm grant` 等自动化操作，省去手动点权限 |
| 8 | 关闭"权限监控" | 开发者选项 → 权限监控 → 关 | MIUI 会在授权时反复弹窗，拖慢测试 |
| 9 | 动画缩放 0.5× | 开发者选项 → 窗口/过渡/Animator 时长缩放 | 手动回归更快（可选，截图前建议改回 1×） |

### 3.3 不需要动

- **MIUI 优化**（`persist.sys.miui_optimization=true`）：保持开启。关闭会破坏系统行为，且与我们的应用无关。
- **USB 配置 / MTP**：adb 不依赖，保持默认即可。

## 4. 装好应用后的自动配置（复制执行）

```bash
ADB="C:/user_development/android-sdk/platform-tools/adb.exe"
PKG=com.witlax.tasktodo

# 1. 通知权限（Android 13+）
"$ADB" shell pm grant $PKG android.permission.POST_NOTIFICATIONS

# 2. 加入电池优化白名单（等价于"无限制"的一部分）
"$ADB" shell cmd deviceidle whitelist +$PKG

# 3. 核对精确闹钟是否允许（应输出 allow）
"$ADB" shell cmd appops get $PKG SCHEDULE_EXACT_ALARM

# 4. 核对通知是否真的放行
"$ADB" shell dumpsys package $PKG | grep -A2 POST_NOTIFICATIONS
```

> `pm grant` 若报 `SecurityException`，说明"USB 调试（安全设置）"未开，见 3.2 第 7 项。

## 5. 验证清单（每次重装/换机后跑一遍）

| 检查 | 命令 | 期望 |
| --- | --- | --- |
| 设备在线 | `adb devices` | 状态为 `device` |
| 安装成功 | `adb install -r app-debug.apk` | `Success` |
| 应用在前台 | `adb shell dumpsys activity activities \| grep mResumedActivity` | 显示我们的 Activity |
| 通知权限 | 见第 4 节第 1 条 | 无报错 |
| 精确闹钟 | 见第 4 节第 3 条 | `allow` |
| 省电白名单 | `adb shell dumpsys deviceidle whitelist \| grep tasktodo` | 出现包名 |
| 日志 | `adb logcat -s flutter` | 能收到应用日志 |

## 6. 已知机型特性（会影响测试判断）

1. **90 Hz 屏幕**：滚动帧率测试要按 90 fps 目标看，不能拿 60 fps 当唯一标准。
2. **393 dp 宽**：属于常规手机宽度，但比 360 dp 的机型宽，布局溢出问题在这台机器上可能看不出来——仍需在小屏（360 dp）模拟器或另一台机上复核。
3. **HyperOS 后台策略**：即使设为"无限制"，长时间息屏后仍可能冻结；提醒测试必须包含"息屏 30 分钟"场景。
4. **无 root**：不能改系统数据库，所有验证走公开 API。

## 7. 临时验证产物

- 临时工程 `%TEMP%/_devcheck`（Flutter 计数器，arm64 调试包 74 MB），仅用于验证安装与渲染，验证后已卸载并删除。
- 截图证据：`%TEMP%/devcheck.png`（可重跑生成）。
