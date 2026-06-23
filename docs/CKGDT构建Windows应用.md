# CKGDT 构建 Windows 应用指南

> **课程知识图谱与数字孪生平台 — Windows 桌面端构建与分发**

---

## 一、概述

CKGDT 是 Flutter 全平台项目，Windows 端使用 **Visual Studio Build Tools + CMake** 编译。CI 使用 **GitHub Actions `windows-latest`** 云端构建。

| 项目 | 说明 |
|------|------|
| 构建方式 | 本地 `flutter build windows --release` 或 GitHub Actions `windows-latest` |
| 成本 | 公开仓库免费（2000 分钟/月） |
| 触发方式 | push `master` 分支自动构建 |
| 产物格式 | `.exe` + 全部 `.dll` + `data/` 目录 |
| 产物命名 | `课程知识图谱与数字孪生+windows+v{版本}.zip`（解压即用） |
| 窗口标题 | `课程知识图谱与数字孪生v{版本}`（由 `windows/runner/main.cpp` 控制） |
| 最低 Windows | Windows 10（Flutter 3.x 要求） |
| Flutter 版本 | 3.35.1 |
| 包大小 | ~66 MB（zip） |

> **当前 CI 状态（2026-06-01，v1.17.0）**：`build-windows` job **已持续通过**。
> 本地构建需安装 Visual Studio 2022 Build Tools + Windows 10 SDK。

---

## 二、前置准备

### 2.1 Visual Studio 2022 Build Tools

下载安装 [Visual Studio 2022 Build Tools](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022)，勾选：
- **MSVC v143 - VS 2022 C++ x64/x86 生成工具**
- **Windows 10 SDK**（或 Windows 11 SDK）
- **CMake C++ 工具**

### 2.2 Flutter 环境

```bash
flutter doctor -v
# 确认 Windows 端显示 ✓
```

### 2.3 依赖 DLL（自动下载）

| DLL | 来源 | 作用 |
|-----|------|------|
| `libmpv-2.dll` | `media_kit_libs_windows_video` | 视频解码 |
| `libEGL.dll` / `libGLESv2.dll` | ANGLE | OpenGL ES → Direct3D |
| `pdfium.dll` | `printing` 包 | PDF 渲染 |
| `sqlite3.dll` | `sqlite3_flutter_libs` | SQLite 数据库 |

首次构建时自动从 GitHub Releases 下载，后续增量构建跳过。

---

## 三、构建

### 3.1 本地构建

```bash
flutter pub get
flutter build windows --release
```

产物：`build/windows/x64/runner/Release/` 整个目录。
- `课程知识图谱与数字孪生v{版本}.exe` — 入口程序
- `*.dll` — 运行时依赖
- `data/` — Flutter assets（字体、图片等）

**构建时间**：首次 ~8 分钟（含 ANGLE/libmpv 下载），增量 ~30 秒。

### 3.2 CI 触发

push `master` 自动触发。或手动：GitHub → Actions → CI → Run workflow。

### 3.3 下载

GitHub Actions → 选择运行 → Artifacts → `windows-release` → 下载整个 Release 目录。

---

## 四、安装与运行

Windows 桌面应用**无需安装**，解压 ZIP 后双击 EXE 直接运行。

### 4.1 基本要求

- Windows 10 或更高版本
- 如果杀毒软件拦截，添加信任（EXE 无签名）
- 首次运行时确保 `data/` 目录与 EXE 同级

### 4.2 视频播放

依赖 `libmpv-2.dll`（~130MB）。若视频无法播放，检查该 DLL 是否存在。

---

## 五、CI 工作流程详解

### 5.1 当前配置

```yaml
build-windows:
  name: Build Windows
  if: github.event_name == 'push'
  needs: analyze-test
  runs-on: windows-latest
  timeout-minutes: 60
  steps:
    - uses: actions/checkout@v4
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.35.1'
        channel: stable
        cache: true
    - run: flutter pub get
    - run: flutter build windows --release
    - uses: actions/upload-artifact@v4
      with:
        name: windows-release
        path: build/windows/x64/runner/Release/
        retention-days: 14
```

### 5.2 版本号同步（4 处）

| 文件 | 字段 |
|------|------|
| `windows/CMakeLists.txt` | `BINARY_OUTPUT_NAME` |
| `windows/runner/main.cpp` | `window.Create(L"...")` |
| `windows/runner/Runner.rc` | `FileDescription` / `OriginalFilename` / `ProductName`（3 处） |
| `windows/runner/Runner.rc` | `InternalName`（**不带版本号**） |

> 升版时由 `VersionBumpService.applyVersion()` 自动同步。

---

## 六、常见问题

### Q1：CMake 报 `ANGLE.7z Integrity check failed`

**根因**：GitHub Releases 在国内下载不稳定，ANGLE.7z 损坏。

**修复**：用镜像手动下载并校验 MD5：
```bash
cd build/windows/x64
rm -f ANGLE.7z*
curl -L -o ANGLE.7z --max-time 120 \
  "https://ghfast.top/https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
# MD5: e866f13e8d552348058afaafe869b1ed
flutter build windows --release
```

### Q2：`media_kit: WARNING: package not found`

确认 `pubspec.yaml` 中 `media_kit_libs_windows_video` 未被注释。

### Q3：视频播放黑屏/崩溃

- 检查 `libmpv-2.dll` 是否存在
- 某些精简版 Windows 缺少 VC++ 运行时：安装 [VC++ Redist](https://aka.ms/vs/17/release/vc_redist.x64.exe)

### Q4：构建时间过长

首次构建需下载 ANGLE（~30MB）和 libmpv（~130MB），总计 ~160MB。后续增量编译 ~30 秒。

---

## 七、可靠性与可用性审核（2026-06-01）

| 维度 | 状态 | 说明 |
|------|:----:|------|
| 本地构建 | ✅ | `flutter build windows --release` 持续通过 |
| CI 构建 | ✅ | GitHub Actions `windows-latest` 多次验证 |
| DLL 依赖 | ✅ | libmpv/ANGLE/pdfium/sqlite3 全部就绪 |
| 版本号 | ✅ | 4 处同步（CMakeLists/main.cpp/Runner.rc） |
| 包大小 | 66 MB | zip 后 ~66 MB |
| 免安装 | ✅ | 解压即用 |

### 关键踩坑

| # | 问题 | 根因 | 修复 |
|---|------|------|------|
| 1 | ANGLE 下载校验失败 | GitHub 国内不稳定 | 镜像下载 + MD5 校验 |
| 2 | 并行构建冲突 | `build_ohos.bat` 修改 `lib/` | OHOS 单独构建 |
| 3 | `flutter build windows` 超时 | 首次下载 160MB 依赖 | 增加 timeout 到 15 分钟 |

---

## 八、快速检查清单

- [ ] Visual Studio 2022 Build Tools 已安装
- [ ] `flutter doctor` 显示 Windows 端 ✓
- [ ] `flutter build windows --release` 本地通过
- [ ] GitHub Actions `build-windows` job 绿灯
- [ ] ZIP 解压到另一台电脑验证能运行
- [ ] `windows/runner/Runner.rc` 4 处版本号对齐
