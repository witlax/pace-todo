# ADR-0006 Gradle 发行版改用腾讯云镜像

- 状态：已接受
- 日期：2026-11-18
- 类型：环境约束（非产品决策）

## 背景

首次 `flutter build apk --debug` 失败，报错关键行：

```
Gradle threw an error while downloading artifacts from the network.
Gradle task assembleDebug failed with exit code 1
```

定位过程：`gradle-wrapper.properties` 中 `distributionUrl` 指向 `services.gradle.org`，该地址返回 307 重定向到 `github.com/gradle/gradle-distributions/...`，而本机网络访问该 GitHub Releases 地址返回 **502 Bad Gateway**，导致发行版无法下载。

实测可用性：

| 地址 | 结果 |
| --- | --- |
| `services.gradle.org` → GitHub | 307 → **502** |
| `downloads.gradle.org/distributions/...` | 200 |
| `mirrors.cloud.tencent.com/gradle/...` | **200** |
| `mirrors.huaweicloud.com/gradle/...` | 200 |
| `dl.google.com`（Google Maven） | 200 |
| `repo1.maven.org`（Maven Central） | 200 |

## 决策

项目模板中固定 `android/gradle/wrapper/gradle-wrapper.properties`：

```properties
distributionUrl=https\://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-all.zip
```

Maven 仓库保持 `google()` + `mavenCentral()` 不变（实测可达）。Flutter 侧继续使用已配置的 `pub.flutter-io.cn` 与 `storage.flutter-io.cn` 镜像。

## 备选方案

| 方案 | 说明 |
| --- | --- |
| `downloads.gradle.org` | 可用，但跨境链路不稳定，作为备选 |
| 华为云镜像 | 可用，作为第二备选 |
| 本地预置 zip + `file://` | 换机即失效，破坏可复现性，否决 |
| 升级/降级 Gradle 版本规避 | 不解决根因（仍走同一重定向），否决 |

## 后果

- 首次 Android 构建可在数分钟内完成，不再依赖 GitHub Releases。
- 镜像地址写入仓库，换网络环境（如海外）时可能变慢，但不影响正确性。
- 需在 `README` 注明：若镜像失效，改回 `https\://downloads.gradle.org/distributions/gradle-9.3.1-all.zip`。

## 重新评估条件

1. GitHub Releases 恢复可达且速度稳定；
2. 腾讯云镜像下架或版本滞后于项目所需 Gradle；
3. 项目迁移到 CI（GitHub Actions 等），需按 CI 网络环境单独配置。
