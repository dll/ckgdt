---
name: release-all
description: 一键升版 + 多端构建 + dist 打包 + gh-pages + Gitee Release。统一调度 build-windows / build-android / build-web / build-ohos 子技能。触发：用户说"重新构建三端"/"四端齐发"/"全端发布"/"出新版"/"升版发布"。
---

# 一键发布（升版 + 多端 + 打包 + 部署）

这个技能是**调度器**。具体每端细节看对应子技能：
- [build-windows](../build-windows/SKILL.md)
- [build-android](../build-android/SKILL.md)
- [build-web](../build-web/SKILL.md)
- [build-ohos](../build-ohos/SKILL.md)
- [build-ios](../build-ios/SKILL.md)（macOS 限定，常态跳过）
- [build-wxmp](../build-wxmp/SKILL.md)（需备案域名，常态跳过）

## 默认行为

用户说"重新构建三端" / "四端齐发"时，默认只跑 **Windows + Android + Web + HarmonyOS** 4 端。iOS 和 wxmp 不在常规流程里，需用户单独说才跑。

---

## 升版三件套（每次升 minor / major 必做）

### Step 1：升版同步 9 个文件 / 16 处字段

下表用"升 0.13 → 0.14"作示例（实际升版时把 OLD/NEW 替换为对应版本），构建号 `+N` 归零：

| 平台 | 文件 | 字段 |
|------|------|------|
| 全局 | `pubspec.yaml` | `version: 0.14.0+0` |
| 全局 | `lib/main.dart` | `MaterialApp.title` **2 处**（dbLocked + 正常分支）|
| Android | `android/app/src/main/res/values/strings.xml` | `app_name` |
| Windows | `windows/CMakeLists.txt` | `BINARY_OUTPUT_NAME` |
| Windows | `windows/runner/main.cpp` | `window.Create(L"…")` |
| Windows | `windows/runner/Runner.rc` | **4 处**：FileDescription / OriginalFilename / ProductName 带版本号；InternalName 不带 |
| Web | `web/index.html` | `<title>` / `apple-mobile-web-app-title` / `application-name` |
| Web | `web/manifest.json` | `"name"`（带版本）|
| HarmonyOS | `ohos/AppScope/app.json5` | `versionName` "0.14.0" + `versionCode` 14（**只增不减**）|

**不要改**：
- `pubspec.yaml` 顶部 `name: knowledge_graph_app`（包标识符）
- `windows/CMakeLists.txt` 第 3-7 行 `project(knowledge_graph_app)` / `BINARY_NAME` 变量名
- `web/manifest.json` 的 `"short_name"` / `"description"`（不带版本号）
- iOS `CFBundleIdentifier` / 鸿蒙 `bundleName`（一旦发布锁死）

### Step 2：审计命令（升版前 / 后）

```bash
grep -E "version:|app_name|BINARY_OUTPUT_NAME|window\.Create|FileDescription|InternalName|OriginalFilename|ProductName|<title>|apple-mobile-web-app-title|application-name|\"name\"|\"short_name\"|MaterialApp.*title:|versionName|versionCode" \
  pubspec.yaml lib/main.dart \
  android/app/src/main/res/values/strings.xml \
  windows/CMakeLists.txt windows/runner/main.cpp windows/runner/Runner.rc \
  web/index.html web/manifest.json \
  ohos/AppScope/app.json5
```

每条结果应该都包含新版本号（除 `name:` / `BINARY_NAME` / `short_name` / `description` / `bundleName` / `bundleIdentifier`）。

### Step 3：四端并行构建

> 本节及 Step 4-6 沿用"升 0.13 → 0.14"的示例版本号，实际跑时把所有 `0.14.0` 替换为目标版本。

```bash
# 4 端可并行（用 background task）
flutter build apk --release &
flutter build windows --release &
MSYS_NO_PATHCONV=1 flutter build web --release --base-href "/mad-kgdt/" &
./build_ohos.bat &
wait
```

**约 8-15 分钟**（首次需重下 ANGLE / Gradle 等）。

**产物路径**：
| 平台 | 路径 |
|------|------|
| Windows | `build/windows/x64/runner/Release/移动图谱与数字孪生v0.14.0.exe` + 全部 dll |
| Android | `build/app/outputs/flutter-apk/app-release.apk` |
| Web | `build/web/`（base=`/mad-kgdt/`）|
| HarmonyOS | `ohos/entry/build/default/outputs/default/entry-default-signed.hap`（已签名）|

### Step 4：Web 部署 GitHub Pages

```bash
mkdir -p D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy
cp -r D:/FlutterProjects/knowledge_graph_app/build/web/. D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy/
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy init -q -b gh-pages
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy config core.longpaths true
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy add -A
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy \
    -c user.email="ldl@github" -c user.name="ldl" \
    commit -q -m "deploy: web v0.14.0 base=/mad-kgdt/"
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy \
    remote add origin git@github.com:dll/mad-kgdt.git
git -C D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy push -u --force origin gh-pages
rm -rf D:/FlutterProjects/knowledge_graph_app/build/_gh-pages-deploy
```

访问：`https://dll.github.io/mad-kgdt/`（5-10 分钟生效）

### Step 5：打 4 个 zip 入 dist/

命名格式（参考 DevEco 风格）：
```
移动图谱与数字孪生+<端名小写>+v<版本号>.zip
```

> ⚠ **必须用 `scripts/pack_dist_zip.ps1`**，不能用 `Compress-Archive` 直接打。
> PowerShell 5.1 的 `Compress-Archive` 把 ZIP 条目名编码成 OEM/GBK，
> 在 Linux/macOS 或假设 UTF-8 的 unzip 工具上会报"无法解压"或文件名乱码。
> `pack_dist_zip.ps1` 走 .NET `ZipFile.CreateFromDirectory` + UTF8 entryNameEncoding，跨平台安全。

#### Windows
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pack_dist_zip.ps1 \
  -SourceDir "build/windows/x64/runner/Release" \
  -ZipPath   "dist/移动图谱与数字孪生+windows+v0.14.0.zip"
# Release/ 内已含 启动说明.txt（如无，构建前自己 cp 一份进去）
```

#### Android
```bash
mkdir -p dist/_apk_pkg
cp build/app/outputs/flutter-apk/app-release.apk dist/_apk_pkg/移动图谱与数字孪生v0.14.0.apk
# 写 安装说明.txt（参考 build-android）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pack_dist_zip.ps1 \
  -SourceDir "dist/_apk_pkg" \
  -ZipPath   "dist/移动图谱与数字孪生+android+v0.14.0.zip"
rm -rf dist/_apk_pkg
```

#### Web
```bash
mkdir -p dist/_web_pkg
cp -r build/web/* dist/_web_pkg/
# 写 启动说明.txt（参考 build-web）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pack_dist_zip.ps1 \
  -SourceDir "dist/_web_pkg" \
  -ZipPath   "dist/移动图谱与数字孪生+web+v0.14.0.zip"
rm -rf dist/_web_pkg
```

#### HarmonyOS
```bash
mkdir -p dist/_ohos_pkg
cp ohos/entry/build/default/outputs/default/entry-default-signed.hap dist/_ohos_pkg/移动图谱与数字孪生-v0.14.0.hap
# 写 安装说明.txt（参考 build-ohos — 必含模拟器不兼容 + 真机指南）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pack_dist_zip.ps1 \
  -SourceDir "dist/_ohos_pkg" \
  -ZipPath   "dist/移动图谱与数字孪生+harmonyos+v0.14.0.zip"
rm -rf dist/_ohos_pkg
```

### Step 6：commit 升版 + push

```bash
cd /d/FlutterProjects/knowledge_graph_app
git add pubspec.yaml lib/main.dart \
  android/app/src/main/res/values/strings.xml \
  windows/CMakeLists.txt windows/runner/main.cpp windows/runner/Runner.rc \
  web/index.html web/manifest.json \
  ohos/AppScope/app.json5

git commit -m "chore: 升版 v0.14.0

- pubspec / main.dart 主标题 + 9 文件 16 处字段同步
- 4 端构建产物已打包到 dist/
- Web 已 force-push 到 gh-pages

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"

git stash
git pull --rebase
git stash pop
git push origin master
```

---

## 验收清单（每次升版必跑）

- [ ] 9 个文件 16 处版本号字段都改对（按 Step 1 表格逐项核）
- [ ] `flutter analyze lib` 0 error
- [ ] `flutter test test/core test/models test/services test/data` 全过
- [ ] 4 端构建 SUCCESS（看构建日志最后是否有 ✓ Built）
- [ ] dist/ 出 4 个 zip
- [ ] gh-pages 推送成功
- [ ] 访问 `https://dll.github.io/mad-kgdt/` 看到新版（等 5-10 分钟）
- [ ] 鸿蒙 HAP 用真机装一次确认能跑

---

## ⚠ 全局已知坑（跨端）

### 坑 1：远程总在前进
**现象**：每次 push 报 `! [rejected] master -> master (fetch first)`
**根因**：学生客户端不停往 master push 同步数据 commit
**修复**：升版 commit 用 `git stash + git pull --rebase + git stash pop + git push`

### 坑 2：windows/flutter/generated_*.cc 跟踪
**现象**：每次 build 这两个文件变化但内容相同
**修复**：考虑加 `.gitignore`（但目前还没做）

### 坑 3：.dart_tool / build/ 入 dist/
**修复**：dist/ 已 .gitignore 排除大文件不入库

---

## 我们做过的实战日志

| 日期 | 版本 | 备注 |
|------|------|------|
| 2026-05-23 | v0.12.0 | 第一次走通 Web/Android/Windows 三端 + gh-pages |
| 2026-05-24 | v0.13.0 | 加鸿蒙 + 签名 + 4 端 zip 打包；模拟器 ABI 死局 |

下次升版可参考这两次的 commit 历史。

---

## 不要做的事

❌ **不要**只升 pubspec.yaml 不升其它 12 处（任务栏 / 窗口标题不会变）
❌ **不要** versionCode / build number 倒退
❌ **不要**把 dist/zip 入 git（gitignore 已排除）
❌ **不要**忘了 gh-pages 部署后等 5-10 分钟再访问（CDN 延迟）
❌ **不要**在升版时同时 push master + gh-pages —— 分两步，先 master，再 gh-pages
❌ **不要**指望 iOS / wxmp 走自动流程（macOS / 备案要求把它俩排除在常规外）
