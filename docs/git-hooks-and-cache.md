# Git Hooks 与构建缓存自动化

## 一、为什么构建会下载依赖？

| 阶段 | 下载内容 | 缓存位置 | 触发条件 |
|------|----------|----------|----------|
| `flutter pub get` | Dart/Flutter 第三方包 | `$PUB_CACHE` (D:\PUB) | `pubspec.yaml` 变化时 |
| Gradle 构建 | Android 构建工具 / Kotlin / AndroidX | `$GRADLE_USER_HOME/caches/` | `android/` 依赖变化时；**首次构建** |
| CMake (Windows) | ANGLE.7z (OpenGL ES) / libmpv.7z | `build/windows/x64/` | **仅首次** Windows 构建 |
| sqlite3.dll | sqflite 预置 DLL | `PUB_CACHE/.../sqlite3_flutter_libs/` | 每次 `flutter pub get` 恢复原版 |

**核心原则**：一旦缓存好，后续构建**不会重新下载**，除非：
- `pubspec.yaml` / `pubspec.lock` 变化 → Gradle/Maven 重新 resolve
- `flutter pub get` 覆盖 sqlite3.dll → 需重跑补丁
- 手动 `flutter clean` / `flutter pub cache clean`

---

## 二、本地缓存架构

```
D:\PUB  ← PUB_CACHE（Dart/Flutter 包，~483 MB）
└── hosted/
    ├── pub.flutter-io.cn/   ← 国内镜像源缓存
    └── pub.dev/              ← 官方源缓存

D:\development\cache\gradle  ← Gradle 构建缓存
├── wrapper/dists/gradle-8.12-all/  ← Gradle Wrapper（解压后 ~300 MB）
└── caches/
    ├── modules-2/           ← Android Maven 依赖
    ├── transforms/          ← AAR 转换缓存
    └── jars-9/              ← JAR 缓存

D:\development\Android  ← Android SDK
├── platforms/android-29..36
├── build-tools/30.0.3..36.1.0
├── ndk/
└── cmdline-tools/
```

### 环境变量配置（系统级）

| 变量 | 值 | 作用 |
|------|-----|------|
| `PUB_CACHE` | `D:\PUB` | Dart 包缓存（本机已配） |
| `PUB_HOSTED_URL` | `https://pub.flutter-io.cn` | 国内镜像源（本机已配） |
| `ANDROID_HOME` | `D:\development\Android` | Android SDK（本机已配） |
| `GRADLE_USER_HOME` | `D:\development\cache\gradle` | Gradle 缓存（**2026-07-22 前未配，已通过 gradle.properties 修复**） |

> `GRADLE_USER_HOME` 此前未设置 → Gradle 默认写到 `C:\Users\ldl\.gradle`，C 盘膨胀且缓存复用失效。  
> **修复**：在 `android/gradle.properties` 中指定 `gradle.user.home`。

---

## 三、Git Hooks 自动化体系

### 3.1 钩子目录

本项目的 Git 钩子统一存放在 `.githooks/`（**已受版本控制**），通过 `core.hooksPath` 指向此目录。

安装命令（每位 dev 克隆后跑一次）：

```bash
# Windows PowerShell
.\scripts\install_hooks.ps1

# 卸载
.\scripts\install_hooks.ps1 -Remove

# 旧版 Bash
bash scripts/install_git_hooks.sh
```

### 3.2 钩子清单

| 钩子 | 触发时机 | 自动执行 | 跳过方式 |
|------|----------|----------|----------|
| `pre-commit` | `git commit` | OHOS 补丁残留检查、大文件(>10MB)拦截、staged `.dart` 语法检查 | `--no-verify` |
| `post-merge` | `git pull` / `git merge` | `pubspec.yaml` 变化时自动 `flutter pub get` | 不可跳过 |
| `post-checkout` | `git checkout <branch>` | `pubspec.yaml` 变化时自动 `flutter pub get` | 不可跳过 |
| `pre-push` | `git push` | `flutter analyze lib/`、`flutter test`、版本号一致性检查 | `--no-verify` |

### 3.3 钩子文件说明

每个钩子都是独立 shell 脚本，存放在 `.githooks/` 目录：

```text
.githooks/
├── pre-commit       # 提交前质量门
├── post-merge       # 合并后 pub get
├── post-checkout    # 切分支后 pub get
└── pre-push         # 推送前全检
```

### 3.4 实现原理

```
用户执行 git pull
  → Git 检测 .githooks/post-merge（通过 core.hooksPath）
  → 脚本对比 ORIG_HEAD..HEAD 看 pubspec.yaml 是否变化
  → 如有变化 → flutter pub get（走本地 PUB_CACHE）
```

```
用户执行 git push
  → Git 检测 .githooks/pre-push
  → 脚本执行 flutter analyze lib/（必须 0 error）
  → 执行 flutter test
  → 检查 lib/core/version.dart 与 pubspec.yaml 版本一致
  → 全部通过才允许推送
```

---

## 四、构建前缓存验证

运行 `scripts/verify_build_cache.ps1` 检查 8 项缓存的完整性：

```bash
.\scripts\verify_build_cache.ps1          # 人类可读报告
.\scripts\verify_build_cache.ps1 -Json    # JSON 输出（供 CI/脚本调用）
.\scripts\verify_build_cache.ps1 -Fix     # 尝试自动修复
```

检查项：
1. **Flutter SDK** — 是否在 PATH 且版本正确
2. **PUB_CACHE** — Dart 包是否已缓存
3. **Gradle 缓存** — `modules-2` 是否存在
4. **Gradle Wrapper** — gradle-8.12 `.ok` 标记是否存在
5. **Android SDK** — platforms / build-tools / ndk
6. **ANGLE.7z** — Windows 视频解码库
7. **sqlite3.dll** — 是否需要补丁（小尺寸 → 需要 patch）
8. **pubspec.lock** — 依赖是否已锁定

如果 `-Fix`，脚本会：
- 运行 `patch_sqlite3.ps1`（如需要）
- 提示缺失的缓存路径

---

## 五、增量构建 vs 全量构建

### 增量构建（推荐日常使用）

```bash
# 只编译变更的代码（~30s - 2min）
flutter build windows --release
flutter build apk --release
```

**不会重新下载**：
- Dart 包（PUB_CACHE 已有）
- Gradle 依赖（已 resolve）
- ANGLE / libmpv（已有 .7z）

**但可能会**：
- `flutter pub get` 重新校验 lockfile（如果 `pubspec.lock` 有变动）
- Gradle 重新 resolve SNAPSHOT 依赖

### 全量构建（出问题时）

```bash
# 清理所有构建产物
flutter clean

# 如需清理 Dart 包缓存（保留 PUB_CACHE 不变）
flutter pub cache repair

# 如需清理 Gradle 缓存
cd android && ./gradlew clean && cd ..
```

### sqlite3.dll 补丁

每次 `flutter pub get` 后必须重跑补丁：

```bash
.\scripts\patch_sqlite3.ps1
```

原因：`pub get` 从 pub 服务器重新下载 `sqlite3_flutter_libs` 包，覆盖了之前补丁过的 dll。  
**优化**：`pre-push` 钩子已包含 `verify_build_cache.ps1` 的 dll 检查，可提前提示。

---

## 六、CI/CD 自动部署

GitHub Actions（`.github/workflows/ci.yml`）已有 `deploy-web` job。

如需本地一键全端发布，使用 release-all 工作流：

```bash
# 由 release-all skill 自动调度（3 端并行）
msbuild Android:  flutter build apk --release
msbuild Windows:  flutter build windows --release
msbuild Web:      flutter build web --release --base-href "/ckgdt/"

# 后续步骤由 skill 自动完成：
#   → 平台文件版本同步（version_bump.dart）
#   → 产物打包入 dist/
#   → gh-pages 部署
#   → Gitee Release 上传
```

---

## 七、常见问题

### Q: 为什么第一次构建这么慢？
Gradle 需要下载 wrapper（~100 MB）+ resolve 依赖（~200 MB），  
ANGLE/libmpv 在 Windows 构建时额外下载 ~30 MB。  
**一次缓存，后续增量**。

### Q: 为什么每次 `flutter pub get` 后 Windows 构建报 sqlite3 崩溃？
见 CLAUDE.md `已知问题与构建修补` 第 1 条。运行 `patch_sqlite3.ps1` 后重建。

### Q: 如何查看当前钩子状态？
```bash
git config --local core.hooksPath
# 应输出: .githooks
```

### Q: 如何临时跳过所有钩子？
```bash
git commit --no-verify
git push --no-verify
```

### Q: 版本号不一致怎么修复？
```bash
dart run scripts/version_bump.dart
```
或手动同步 `lib/core/version.dart` 与 `pubspec.yaml`。

---

## 八、参考

- CLAUDE.md — `Git 工作流` / `常用命令` / `构建产物命名规范`
- `scripts/README.md` — 脚本分类与入口
- `docs/版本号与品牌名单一来源文档.md` — 版本号全量同步清单
- [Git Hooks 官方文档](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
