---
name: build-android
description: 构建 Android APK + Gradle 缓存配置 + 签名 + ABI 选择。触发：用户说"构建 Android"/"打 APK"/"Android 发布"。
---

# 构建 Android APK

## 标准命令

```bash
flutter build apk --release
```

**产物**：`build/app/outputs/flutter-apk/app-release.apk`

**包大小**：~76 MB（zip 后 76M ≈ apk 本身）

## 环境变量配置

```
GRADLE_USER_HOME=D:\development\cache\gradle
PUB_CACHE=D:\PUB（按需）
```

**Gradle 缓存路径必须有 8.12 版本**：
```
D:\development\cache\gradle\wrapper\dists\gradle-8.12-all\<hash>\
├── gradle-8.12          ← 解压目录必须在
└── gradle-8.12-all.zip.ok ← 完整下载标记
```

## ⚠ 已知坑

### 坑 1：Connection timed out 找 services.gradle.org

**现象**：`Exception in thread "main" java.net.ConnectException: Connection timed out`

**根因**：`services.gradle.org` 在中国大陆访问不稳定 + 缓存目录有 `.part` 残留：
```
D:/development/cache/gradle/wrapper/dists/gradle-8.12-all/<hash>/
└── gradle-8.12-all.zip.part   ← 这个是损坏的下载临时文件
```

**修复**：
```bash
# 1. 删 .part 残留
rm -f "/d/development/cache/gradle/wrapper/dists/gradle-8.12-all/*/gradle-8.12-all.zip.part"

# 2. 验证 .ok 标记 + 解压目录存在
ls /d/development/cache/gradle/wrapper/dists/gradle-8.12-all/*/
# 应该看到：gradle-8.12/  gradle-8.12-all.zip.ok

# 3. 重跑
flutter build apk --release
```

### 坑 2：PUB_CACHE 指向不存在的目录

**现象**：`Error when reading '/D:/PUB/...': 系统找不到指定的文件`

**根因**：之前曾设过 `PUB_CACHE=D:\PUB`，但目录被清了。pubspec.lock 还指向 `/D:/PUB`。

**修复**：
```bash
PUB_CACHE=/c/Users/ldl/AppData/Local/Pub/Cache flutter pub get
# 让默认 cache 接管，重新解析 lockfile
```

或永久 unset：删 PUB_CACHE 环境变量。

### 坑 3：APK 时间戳没变（构建跳过了）

**现象**：`flutter build apk --release` 报 SUCCESS，但 `app-release.apk` 时间戳是几小时前。

**根因**：上一次构建失败但 task 仍 exit 0（Gradle 失败信号没传出去）。

**修复**：检查 build/_build_apk_*.txt 日志最后 5 行，确认有 `✓ Built build\app\outputs\flutter-apk\app-release.apk` 字样才算真成功。

## 升版同步（v0.13 → v0.14）

| 文件 | 字段 |
|------|------|
| `android/app/src/main/res/values/strings.xml` | `app_name` "移动图谱与数字孪生v0.14.0" |
| `android/app/build.gradle.kts` | versionCode / versionName（如有显式配）|

## 签名配置

**当前**：debug 签名（开发用）。正式发版需要：

1. 生成 keystore：
   ```bash
   keytool -genkey -v -keystore ~/madkgdt-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias madkgdt
   ```

2. `android/key.properties`（**不要 commit**）：
   ```
   storePassword=xxx
   keyPassword=xxx
   keyAlias=madkgdt
   storeFile=/c/Users/ldl/madkgdt-release.jks
   ```

3. `android/app/build.gradle.kts` signingConfigs.release 引用 key.properties

## 打包格式（zip 入 dist/）

```
dist/移动图谱与数字孪生+android+v0.13.0.zip
├── app-release.apk
└── 安装说明.txt（含开发者选项 / 未知来源安装 / 默认账号）
```

```bash
mkdir -p dist/_apk_pkg
cp build/app/outputs/flutter-apk/app-release.apk dist/_apk_pkg/移动图谱与数字孪生-v0.13.0.apk
cat > dist/_apk_pkg/安装说明.txt <<EOF
=== Android 安装 ===
1. 设置 → 关于本机 → 版本号点 7 次 → 启用开发者模式
2. 设置 → 安全 → 允许安装未知来源应用
3. USB 传到手机或直接打开 apk 文件
4. 默认账号：学生 2023211985/211985 / 教师 206004 / 管理员 419116
EOF
cd dist/_apk_pkg && powershell.exe -NoProfile -Command "Compress-Archive -Path '*' -DestinationPath '..\\移动图谱与数字孪生+android+v0.13.0.zip' -Force"
cd /d/FlutterProjects/knowledge_graph_app && rm -rf dist/_apk_pkg
```

## ABI 选择（AAB / 多 APK）

当前默认 universal apk 含 4 个 ABI：armeabi-v7a / arm64-v8a / x86 / x86_64。

**减包**（如要分发 Google Play）：
```bash
flutter build apk --release --target-platform android-arm64,android-arm
# 排除 x86 — 国内手机基本都是 ARM
```

**AAB**（Google Play 推荐）：
```bash
flutter build appbundle --release
# 产物：build/app/outputs/bundle/release/app-release.aab
```

## 不要做的事

❌ **不要** unset GRADLE_USER_HOME（C 盘空间会被 ~/.gradle 撑爆）
❌ **不要** commit key.properties / *.jks / *.keystore（gitignore 必须）
❌ **不要**忘了 strings.xml 升版（任务栏图标的应用名不会变）
