# HarmonyOS 构建修复进展

## 已修复（代码层）

| 错误 | 数量 | 修复方式 |
|------|------|---------|
| `Color.withValues({alpha:})` 不支持 | 339 | PowerShell 脚本批量替换为 `withOpacity()` |
| `CardThemeData` / `DialogThemeData` / `TabBarThemeData` 不识别 | 6 | 替换为 `CardTheme` / `DialogTheme` / `TabBarTheme`（旧名） |
| `PopScope.onPopInvokedWithResult` 不识别 | 2 | 替换为 `onPopInvoked` |
| `DropdownButtonFormField.initialValue` 不识别 | 2 | 替换为 `value` |
| `lib/l10n/gen/app_localizations.dart` 找不到 | 1 | 移除 import + 用 const fallback |
| `media_kit_video 1.3.1` 用 `onPopInvokedWithResult` | 1 | dependency_overrides 降到 1.2.5 |
| `syncfusion_flutter_pdf 33.x` 要 Dart 3.7+ | — | 降到 24-29.x |
| `file_picker 10.x` 要 Dart 3.5+ | — | 降到 8.3.2 |
| `win32 5.5.5+` 要 Dart 3.5+ | — | 降到 5.5.4 |

## 当前阻塞（环境层）

```
ProcessException: Failed to find "ohpm" in the search path.
  Command: ohpm
```

**根因**：用户机器上 **DevEco Studio 未安装**。

`build_ohos.bat` 中假设：
```
OHPM_HOME=D:\Program Files\Huawei\DevEco Studio\tools\ohpm
HVIGOR_HOME=D:\Program Files\Huawei\DevEco Studio\tools\hvigor
OHOS_BASE_SDK_HOME=E:\Huawei\OpenHarmony\Sdk
```

实际查证：`D:\Program Files\Huawei\` 是**空目录**，DevEco Studio 不在该路径。

> **更新（2026-06-01，第十三轮）**：DevEco 工具链装好后，构建已跑通——
> `ohos/entry/build/default/outputs/default/entry-default-signed.hap`（75.8 MB）已产出，
> `dist/移动图谱与数字孪生+harmonyos+v1.16.2.zip` 已打包。上面的 ohpm 阻塞是历史状态。
> 现在 `build_ohos.bat` 的工具链路径可用环境变量覆盖
> （`DEVECO_HOME` / `OHOS_SDK_HOME` / `FLUTTER_OHOS_HOME` / `FLUTTER_STD_HOME`），
> 并在开跑前预检 `flutter_ohos` 与 `ohpm` 是否存在，早失败易诊断。

## 用户操作步骤

要让 HarmonyOS HAP 构建成功，请：

### 1. 安装 DevEco Studio

下载地址（华为官网）：
https://developer.huawei.com/consumer/cn/deveco-studio/

推荐安装到 `D:\Program Files\Huawei\DevEco Studio\` 路径以匹配脚本默认。

### 2. 配置 OpenHarmony SDK

DevEco Studio 装好后，打开 → Settings → SDK，下载 OpenHarmony SDK 到 `E:\Huawei\OpenHarmony\Sdk`（或修改 build_ohos.bat 中 OHOS_BASE_SDK_HOME 路径）。

### 3. 验证工具链

```cmd
cd D:\FlutterProjects\knowledge_graph_app
where ohpm
where hvigorw
```

两条命令都该输出可执行路径。

### 4. 重跑构建

```cmd
cmd /c build_ohos.bat
```

Dart 代码层补丁已写好，应能直接走通到产出 HAP：`build/ohos/app/out/default/MyApp.hap`

## 已修代码已 push

仓库 commit `bb3802bf1+`：
- `ohos_patch.ps1` / `ohos_restore.ps1`：构建前后批量补丁 + 还原
- `build_ohos.bat`：调用 ps1 + 应用 dependency overrides
- `pubspec_overrides_ohos.yaml`：4 个依赖降版
- `lib/core/ohos_compat.dart`：Color extension 兜底（实际靠 ps1 替换）

## 结论

**代码兼容性 100% 修通**，**只剩工具链安装一步**由用户完成。装好 DevEco Studio 后跑 `build_ohos.bat` 应能直接出 HAP。

---

## 可靠性加固（2026-06-01，第十三轮审核回修）

破坏性补丁流程（`ohos_patch.ps1` 改写 `lib/` → 构建 → `ohos_restore.ps1` 还原）有个事故隐患：
**若构建中断、或在补丁态执行了 `git add lib/`，降级后的代码会被提交进 master**
（commit `944b452d7` 的 withValues 全局回退 + 3 个 theme 编译错误就是这么来的）。本轮加固：

| 项 | 改动 |
|----|------|
| **pre-commit 守卫** | `scripts/check_no_ohos_patch.sh` 检测 4 个补丁态签名（`lib.backup/` 存在、`pubspec_overrides.yaml` 存在、暂存的 theme_manager 用旧版 `CardTheme(`、暂存 lib 新增 `.withOpacity(`），命中拒绝提交。`scripts/install_git_hooks.sh` 一键安装；强过用 `git commit --no-verify` |
| **删除 shim import 残留** | master 上 75 个 `lib/` 文件曾 `import color_ohos_compat.dart`（`add_ohos_shim.py` 注入的死残留，构建实际不依赖它，靠 sed 降级）——已全部移除，主干干净 |
| **删除损坏的 build_ohos.cmd** | 路径反斜杠被 `\t`/`\f` 吃掉、走过时 `pubspec_ohos.yaml` 流程；`build_ohos.bat` 是唯一 canonical 入口 |
| **build_ohos.bat 路径参数化** | 工具链路径改用环境变量回退（`DEVECO_HOME` 等），加开跑前存在性预检，restore 保证执行（含中断路径） |

**仍待办**：`app.json5` 里调试签名 `keyPassword`/`storePassword` 是明文——商用发版前换正式证书并移出版本库。
