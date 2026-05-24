---
name: build-windows
description: 构建 Windows 桌面 exe + libmpv 视频解码 + Runner.rc 4 处版本号 + ANGLE 镜像下载。触发：用户说"构建 Windows"/"打 exe"/"Windows 发布"。
---

# 构建 Windows 桌面 exe

## 标准命令

```bash
flutter build windows --release
```

**产物**：`build/windows/x64/runner/Release/移动图谱与数字孪生v0.13.0.exe` + 全部 dll + `data/`

**包大小**：~67 MB（zip 后）

## 关键依赖

| dll | 来源 | 作用 |
|-----|------|------|
| libmpv-2.dll | media_kit_libs_windows_video（pubspec）| 视频解码 |
| libEGL.dll / libGLESv2.dll | media_kit_libs_windows_video → ANGLE | OpenGL ES |
| pdfium.dll | pdfium 包 | PDF 渲染 |
| sqlite3.dll | sqlite3_flutter_libs | SQLite |

## ⚠ 已知坑

### 坑 1：ANGLE.7z 下载校验失败（已踩 1 次）

**现象**：CMake 报 `ANGLE.7z Integrity check failed`

**根因**：media_kit_libs_windows_video 首次构建会下载 ANGLE.7z，但 GitHub Releases 在国内有时下载到的是被截断的损坏文件。残留 `gradle-8.12-all.zip.part` 在 `~/.gradle/wrapper/dists/`。

**修复**：用 ghfast 镜像直接下载 + 校验 MD5：

```bash
cd build/windows/x64
rm -f ANGLE.7z*

# ANGLE 包 — MD5: e866f13e8d552348058afaafe869b1ed
curl -L -o ANGLE.7z --max-time 120 \
  "https://ghfast.top/https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"

# libmpv 包 — MD5: a832ef24b3a6ff97cd2560b5b9d04cd8
curl -L -o "mpv-dev-x86_64-20230924-git-652a1dd.7z" --max-time 200 \
  "https://ghfast.top/https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z"

md5sum ANGLE.7z "mpv-dev-x86_64-20230924-git-652a1dd.7z"
# 必须分别匹配上面注释的 MD5

# 重跑
flutter build windows --release
```

CMake 会检查文件已存在且 MD5 通过 → 跳过下载步骤。

### 坑 2：媒体包警告

**现象**：`media_kit: WARNING: package:media_kit_libs_*** not found`

**根因**：`pubspec.yaml` 把 `media_kit_libs_windows_video` 注释了。

**修复**：取消注释这一行 + `flutter pub get`。

## 升版同步（v0.13 → v0.14）

| 文件 | 字段 | 改动 |
|------|------|------|
| `windows/CMakeLists.txt` | `BINARY_OUTPUT_NAME` | `"移动图谱与数字孪生v0.14.0"` |
| `windows/runner/main.cpp` | `window.Create(L"…")` | `L"移动图谱与数字孪生v0.14.0"` |
| `windows/runner/Runner.rc` | **4 处**：`FileDescription` / `InternalName` / `OriginalFilename` / `ProductName` | `FileDescription` / `OriginalFilename` / `ProductName` 带版本号；`InternalName` 不带 |

**不要改**：
- `windows/CMakeLists.txt` 第 3-7 行 `project(knowledge_graph_app)` / `BINARY_NAME` 变量名（必须保持英文 snake_case）

## 打包格式（zip 入 dist/）

```
dist/移动图谱与数字孪生+windows+v0.13.0.zip
└── 整个 build/windows/x64/runner/Release/ 目录内容
    ├── 移动图谱与数字孪生v0.13.0.exe
    ├── libmpv-2.dll
    ├── libEGL.dll
    ├── libGLESv2.dll
    ├── pdfium.dll
    ├── ... 全部 dll
    └── data/  （flutter_assets 等）
```

**用法**：解压后双击 EXE 直接运行，无需安装。

```bash
# 一键打包脚本
cd build/windows/x64/runner/Release
powershell -NoProfile -Command "Compress-Archive -Path '*' -DestinationPath 'D:\FlutterProjects\knowledge_graph_app\dist\移动图谱与数字孪生+windows+v0.13.0.zip' -Force"
```

## 性能 Tips

构建慢（>5 min）原因：
- 首次构建：ANGLE/libmpv 下载（用 ghfast 镜像）+ CMake 配置
- 后续构建：增量编译，~30s

构建中检查 task：
```bash
flutter analyze lib   # 必须 0 error
```

## 不要做的事

❌ **不要**改 `pubspec.yaml` 顶部 `name: knowledge_graph_app`（Flutter 包标识符必须英文）
❌ **不要**忘了 Runner.rc 的 4 处版本号同步
❌ **不要**用 `Compress-Archive` 之外的工具打包（中文文件名兼容性最好）
