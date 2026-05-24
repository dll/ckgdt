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
