# CKGDT 构建 Android 应用指南

> **课程知识图谱与数字孪生平台 — Android 端构建与分发**

---

## 一、概述

CKGDT 是 Flutter 全平台项目，Android 端可在 **Windows / Linux / macOS** 上构建，CI 使用 **GitHub Actions `ubuntu-latest`** 云端自动构建。

| 项目 | 说明 |
|------|------|
| 构建方式 | 本地 `flutter build apk --release` 或 GitHub Actions `ubuntu-latest` |
| 成本 | 公开仓库免费（2000 分钟/月） |
| 触发方式 | push `master` 分支自动构建 |
| 产物格式 | `app-release.apk`（通用 APK，含 4 ABI） |
| 产物命名 | `课程知识图谱与数字孪生+android+v{版本}.zip`（含 APK + 安装说明） |
| Application ID | `cn.edu.chzu.madkg` |
| 最低 Android 版本 | API 21（Android 5.0） |
| 目标 SDK | 由 Flutter Gradle Plugin 自动管理 |
| Java 版本 | 17（CI `setup-java temurin 17`） |
| Flutter 版本 | 3.35.1（CI `FLUTTER_VERSION`） |
| APK 大小 | ~142 MB（debug 签名，universal） |

> **当前 CI 状态（2026-06-01，v1.17.0）**：`build-android` job **已持续通过**。
> 签名配置尚未启用（使用 debug 签名），正式分发需配置 release keystore（见第三章）。

---

## 二、前置准备

### 2.1 Android Studio / 命令行工具

**Windows 推荐**：安装 Android Studio，自动处理 SDK、模拟器、Gradle。

**仅命令行**：安装 Android SDK 命令行工具 + Java 17：
```bash
# 下载 Android SDK command-line tools
# 设置环境变量
export ANDROID_HOME=/path/to/android/sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools
```

### 2.2 Gradle 缓存（加速构建）

项目使用 Gradle 8.12，配置 `GRADLE_USER_HOME` 环境变量到 SSD 路径：
```
GRADLE_USER_HOME=D:\development\cache\gradle
```

**重要**：首次构建 Gradle 需下载 `gradle-8.12-all.zip`（~140MB），国内网络可能超时。若遇 `Connection timed out`：
```bash
# 删除损坏的 .part 残留
rm -f /d/development/cache/gradle/wrapper/dists/gradle-8.12-all/*/gradle-8.12-all.zip.part
# 确认解压目录和 .ok 标记存在
ls /d/development/cache/gradle/wrapper/dists/gradle-8.12-all/*/
```

### 2.3 Android SDK 平台

`android/local.properties` 配置 SDK 路径：
```
sdk.dir=D:\\development\\Android
flutter.sdk=D:\\development\\flutter_windows_3.35.1-stable\\flutter
```

---

## 三、签名配置（正式分发）

### 3.1 当前状态

CI 和本地构建均使用 **debug 签名**（Android 默认），可直接安装到开启了"未知来源"的设备。
正式分发到应用商店或大规模分发需配置 release 签名。

### 3.2 生成 Release Keystore

```bash
keytool -genkey -v -keystore ~/madkgdt-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias madkgdt
```

按提示输入组织信息和密码。

### 3.3 创建签名配置文件

`android/key.properties`（**禁止 commit，已 gitignore**）：
```
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=madkgdt
storeFile=C:/Users/ldl/madkgdt-release.jks
```

### 3.4 GitHub Actions 签名

添加 GitHub Secrets：
- `ANDROID_KEYSTORE_B64`：`base64 -i madkgdt-release.jks | tr -d '\n'`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_STORE_PASSWORD`

CI 构建时解码 jks 并引用签名配置。

---

## 四、构建与下载

### 4.1 本地构建

```bash
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`（~142 MB）

**减包构建**（仅 ARM，~90MB）：
```bash
flutter build apk --release --target-platform android-arm64,android-arm
```

**AAB 构建**（Google Play）：
```bash
flutter build appbundle --release
```

### 4.2 CI 触发

push `master` 自动触发。或手动：GitHub → Actions → CI → Run workflow。

### 4.3 下载

GitHub Actions → 选择运行 → Artifacts → `android-apk` → 下载 `app-release.apk`。

---

## 五、安装到设备

### 5.1 USB 安装

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### 5.2 直接安装（传文件）

1. APK 传到手机（微信/QQ/网盘/USB）
2. 设置 → 安全 → **允许安装未知来源应用**
3. 点击 APK 文件 → 安装

### 5.3 开发者模式

部分设备需先开启开发者模式：
1. 设置 → 关于本机 → **版本号连续点击 7 次**
2. 返回设置 → 开发者选项 → USB 调试

---

## 六、CI 工作流程详解

### 6.1 当前配置

```yaml
build-android:
  name: Build Android APK
  if: github.event_name == 'push'
  needs: analyze-test
  runs-on: ubuntu-latest
  timeout-minutes: 45
  steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-java@v4
      with:
        distribution: temurin
        java-version: '17'
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.35.1'
        channel: stable
        cache: true
    - run: flutter pub get
    - run: flutter build apk --release
    - uses: actions/upload-artifact@v4
      with:
        name: android-apk
        path: build/app/outputs/flutter-apk/app-release.apk
        retention-days: 14
```

### 6.2 构建流程图

```
push master
    │
    ▼
┌─────────────────┐
│  analyze-test   │  ← 必须通过
│  ubuntu-latest  │
└────────┬────────┘
         │
    ┌────┼────┬────────┐
    ▼    ▼    ▼        ▼
┌────┐┌────┐┌──────┐┌────┐
│Web ││APK ││Win   ││iOS │
└────┘└────┘└──────┘└────┘
```

---

## 七、常见问题

### Q1：构建报 `Unresolved reference: getVersionCode`

`android/app/build.gradle.kts` 使用了过时的 API。修复：将 `flutter.getVersionCode()` 改为直接读取 `local.properties` 或使用新版 Gradle Plugin。

### Q2：Gradle Connection timed out

国内网络偶尔连不上 `services.gradle.org`。确保 `GRADLE_USER_HOME` 缓存完整，删除 `.part` 残留文件后重试。

### Q3：APK 安装失败 "应用未安装"

- 确认已开启"允许安装未知来源"
- 检查设备 Android 版本 ≥ 5.0
- adb 安装可查看详细错误：`adb install -r app-release.apk`

### Q4：构建后 APK 时间戳没变

上一次构建可能静默失败。检查构建日志最后是否包含 `✓ Built build/app/outputs/flutter-apk/app-release.apk`。

---

## 八、可靠性与可用性审核（2026-06-01）

| 维度 | 状态 | 说明 |
|------|:----:|------|
| 本地构建 | ✅ | `flutter build apk --release` 持续通过 |
| CI 构建 | ✅ | GitHub Actions `ubuntu-latest` 多次验证 |
| 签名 | ⚠️ | CI/本地均用 debug 签名，正式分发需配置第三章 |
| Gradle 版本 | ✅ | 8.12，缓存已配置 |
| Java 版本 | ✅ | 17（CI `temurin`） |
| 产物大小 | 142 MB | 含 4 ABI，可减至 ~90MB |
| AAB 支持 | ✅ | `flutter build appbundle --release` |

### 关键踩坑

| # | 问题 | 根因 | 修复 |
|---|------|------|------|
| 1 | Gradle 超时 | 国内网络 + 残留 `.part` | 删 `.part` 重试 |
| 2 | `getVersionCode` 未定义 | `local.properties` 指向 OHOS Flutter | 修正为标准 Flutter SDK |
| 3 | 并行构建冲突 | `build_ohos.bat` 修改 `pubspec.lock` | OHOS 单独构建 |

---

## 九、快速检查清单

- [ ] Android SDK 已安装（`ANDROID_HOME` 已设）
- [ ] Java 17 已安装
- [ ] `android/local.properties` 的 `flutter.sdk` 指向标准 Flutter
- [ ] `GRADLE_USER_HOME` 缓存完整（无 `.part` 残留）
- [ ] `flutter build apk --release` 本地通过
- [ ] GitHub Actions `build-android` job 绿灯
- [ ] APK 已安装到至少一台真机验证
