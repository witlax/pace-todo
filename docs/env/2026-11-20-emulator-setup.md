# Android 模拟器安装与配置（本机专用）

> 目标：在本机跑起模拟器，用于 **360 dp 窄屏布局回归** 与安装/交互验证。
> 提醒：提醒可靠性、前台服务、小组件仍以真机（Mi 10 Pro）为准，模拟器不能替代。
> 状态：**已跑通，可点击、可截图**（2026-11-20，最终配置为 API 35 + 多触点）。

---

## 0. 先说结论：鼠标点不动是两个独立故障叠加

| 故障 | 现象 | 根因 | 处置 |
| --- | --- | --- | --- |
| ① 没有触摸设备 | 鼠标点击完全无反应，键盘能用 | 客户机里只有 `qwerty2` / `AT keyboard` / `Power Button` 三个输入设备，**没有任何 touchscreen**。模拟器把窗口里的鼠标点击转成触摸事件投递给触摸设备，设备不存在就静默丢弃 | 启动必须带 `-screen multi-touch` |
| ② 系统反复崩溃 | 界面卡住几十秒、点击"没反应"、`adb screencap` 失败 | `system_server` 被 `Abort message: 'Assertion failed: !rcEnc->featureInfo()->hasReadColorBufferDma'` 打死，栈在 `GoldfishMapper::readFromHost` → `TaskSnapshotConvertUtil.copyToSwBitmapDirect`。即：系统每次做任务快照（回桌面/切换应用）都读显存，读回触发断言，`system_server` abort 重启 | 换 API 35 镜像（API 37 镜像含此断言） |

两条同时成立时，表现就是"鼠标完全点不动、画面偶尔卡死"。只修一条都不够。

---

## 1. 虚拟化：不需要任何系统改动

| 项 | 实测 | 说明 |
| --- | --- | --- |
| `HypervisorPresent` | True | 已有 hypervisor 在运行（VBS/HVCI + VirtualMachinePlatform） |
| `VirtualizationFirmwareEnabled` | False | **正常现象**：VT-x 被 hypervisor 接管后会这样显示，不是没开 |
| HypervisorPlatform（CIM 查询） | 显示 Disabled | **与实际不符** |
| `emulator -accel-check` | `WHPX(10.0.27858) is installed and usable` | **以这条为准** |

> 判定顺序：先跑 `-accel-check`，再看系统状态。不要凭 CIM/系统信息页下结论。
> 有 hypervisor 时 HAXM/AEHD 必然装不上，属正常。

---

## 2. 安装与实例配置

### 2.1 组件

```bash
SDK="C:/user_development/android-sdk"
"$SDK/cmdline-tools/latest/bin/sdkmanager.bat" "emulator" "system-images;android-35;default;x86_64"
```

| 组件 | 版本 |
| --- | --- |
| Android Emulator | 37.3.10 |
| 系统镜像 | `system-images;android-35;default;x86_64`（Android 15） |

选型理由：

- **API 35 而不是 37**：API 37 镜像的 `mapper.ranchu.so` 带 `hasReadColorBufferDma` 断言，在本机 GPU 上必然打死 `system_server`（见第 0 节）。API 35 无此问题，实测连续切换应用 3 次 `system_server` PID 不变、`screencap` 正常。
- `default`（AOSP）比 Google APIs 版小、启动快、无 Play 服务干扰。
- `x86_64` 与主机同架构，走 WHPX 硬件加速。
- 应用 `minSdk 26`，在 API 35 上运行无兼容问题；`compileSdk 37` 只影响编译。

### 2.2 唯一实例

| AVD | 分辨率 / 密度 | 等效宽度 | 用途 |
| --- | --- | --- | --- |
| `tasks-360dp` | 1080 × 1920 @480 | **360 dp** | 当前唯一实例，主流窄屏代表 |

```bash
"$SDK/cmdline-tools/latest/bin/avdmanager.bat" create avd -n tasks-360dp \
  -k "system-images;android-35;default;x86_64" -d pixel_5
```

写入 `C:\Users\CADX\.android\avd\tasks-360dp.avd\config.ini`：

```ini
hw.lcd.width = 1080
hw.lcd.height = 1920
hw.lcd.density = 480
hw.ramSize = 4096
vm.heapSize = 512
hw.keyboard = no          # 用软键盘，贴近真机；设为 yes 时系统不弹软键盘
hw.screen = multi-touch   # 关键，缺触摸设备就是它的锅
disk.dataPartition.size = 8G
```

> 改了 `config.ini` 后如果没生效，删掉同目录的 `hardware-qemu.ini`（首次启动生成的快照式硬件配置，会盖掉新值）。

---

## 3. 启动（务必用脚本）

```bash
bash scripts/emulator.sh
```

等价命令：

```bash
"$SDK/emulator/emulator.exe" -avd tasks-360dp \
  -gpu host -screen multi-touch -memory 4096 -no-snapshot -no-boot-anim
```

**`-screen multi-touch` 不能省**。可用值：`touch` / `multi-touch` / `no-touch`，默认应为 `multi-touch`，但本机 AVD 生成的 `hardware-qemu.ini` 曾写成 `touch`，客户机因此没有触摸设备。

启动约 40–60 秒。验收：

```bash
ADB="$SDK/platform-tools/adb.exe"
"$ADB" -s emulator-5554 shell getprop sys.boot_completed                 # 1
"$ADB" -s emulator-5554 shell "getevent -pl | grep -c multi_touch"       # 11 ← 不是 0 才正常
"$ADB" -s emulator-5554 shell wm size                                    # 1080x1920
"$ADB" -s emulator-5554 shell wm density                                 # 480
```

`getevent` 里应能看到 `virtio_input_multi_touch_1` … `_11`。**只有键盘和 Power Button = 鼠标一定点不动。**

> 多设备时务必带 `-s`，否则报 `more than one device/emulator`。

---

## 4. 截图：现已可用

```bash
"$ADB" -s emulator-5554 shell screencap -p /sdcard/s.png
"$ADB" -s emulator-5554 pull /sdcard/s.png ./s.png
```

API 37 镜像下这条命令必定失败（同第 0 节②，断言就在截图链路上），拉到的 PNG 只有 72 字节。换 API 35 后正常，实测 92–106 KB。

若再次出现 `hasReadColorBufferDma`，说明又回到了带断言的镜像，直接换镜像，不要在 GPU 参数上折腾——`host` / `swiftshader_indirect` / `angle_indirect` / `-feature -Vulkan` / `-feature -GLDMA` 六种组合都试过，断言照旧。

---

## 5. 排障对照表

| 现象 | 先查什么 | 判据 |
| --- | --- | --- |
| 鼠标点击无反应 | 触摸设备 | `getevent -pl \| grep multi_touch` 为空 → 加 `-screen multi-touch` |
| 点一下卡几十秒 | `system_server` 存活时长 | `ps -A -o ETIME,NAME \| grep system_server` 只有几秒 → 镜像断言问题，换 API 35 |
| `dumpsys window` 报 `Can't find service: window` | 同上 | 系统服务已死，不是命令写错 |
| 应用装上了但界面空白 | 渲染后端 | `logcat \| grep flutter`；swiftshader 下 Impeller 会 `Could not link pipeline program`，改用 `-gpu host` |
| 输入框点了不弹键盘 | `hw.keyboard` | 为 `yes` 时软键盘不弹，改 `no` |

---

## 6. 与真机的分工

| 场景 | 用谁 | 原因 |
| --- | --- | --- |
| 提醒是否准时、息屏后是否被杀 | **真机** | 国产 ROM 后台策略只有真机能复现 |
| 前台服务、锁屏计时 | **真机** | 模拟器不休眠，测不出问题 |
| 小组件 | **真机** | 启动器差异大 |
| 360 dp 布局、字号 1.3 倍 | **模拟器** | 可精确控制分辨率与密度 |
| 深色模式、旋转、多语言 | **模拟器** | 切换快、可脚本化 |
| 交互回归、截图对比 | **模拟器** | 截图与 `input tap` 均可脚本化 |

> 当前阶段真机不参与：提醒与前台服务的真机验证推迟到 M2 再启动。

---

## 7. 资源与清理

| 项 | 大小 |
| --- | --- |
| emulator 包 | 约 500 MB |
| 单个系统镜像 | 约 1.7 GB |
| AVD 数据分区 | 2–8 GB |
| 运行时内存 | 2–4 GB |

```bash
"$SDK/cmdline-tools/latest/bin/avdmanager.bat" delete avd -n tasks-360dp
```

API 37 镜像已不再使用，可删：`sdkmanager --uninstall "system-images;android-37.0;default;x86_64"`（省 1.5 GB）。

---

## 8. 一条命令速查

```bash
SDK="C:/user_development/android-sdk"; ADB="$SDK/platform-tools/adb.exe"
bash scripts/emulator.sh                                            # 启动（含多触点）
"$ADB" -s emulator-5554 shell "getevent -pl | grep -c multi_touch"  # 应为 11
"$ADB" -s emulator-5554 install -r app-release.apk                  # 装包
"$ADB" -s emulator-5554 shell screencap -p /sdcard/s.png            # 截图
"$ADB" -s emulator-5554 emu kill                                    # 关闭
```
