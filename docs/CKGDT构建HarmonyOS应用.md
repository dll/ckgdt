# CKGDT 构建 HarmonyOS 应用指南

> **课程知识图谱与数字孪生平台 — HarmonyOS 端（OpenHarmony）本地构建与分发**

---

## 一、概述

CKGDT 是 Flutter 全平台项目，HarmonyOS 端使用 **flutter_ohos** 社区分支构建。该分支基于 Flutter 3.16 且内置 **Dart SDK 3.4**，与项目主工具链（Flutter 3.35.1 / Dart 3.7+）存在显著 API 差异。本方案通过 **源码补丁 + 依赖降级** 双重策略实现兼容编译。

| 项目 | 说明 |
|------|------|
| 构建方式 | 本地 Windows PowerShell + `build_ohos.bat` |
| Flutter SDK | `D:\development\flutter_ohos`（社区分支，Flutter ~3.16 / Dart 3.4） |
| 签名 | OpenHarmony 调试签名（`ohos/signature/*.p12`） |
| 产物格式 | `.hap`（HarmonyOS Ability Package） |
| 支持设备 | arm64-v8a 真机（**不支持模拟器**，x86_64 引擎缺失） |
| HAP 大小 | ~72–76 MB（release，随版本浮动） |
| 版本要求 | DevEco Studio 5.0+ / OpenHarmony SDK 4.0+ |

---

## 二、前置准备

### 2.1 安装 DevEco Studio

DevEco Studio 提供 `ohpm`（包管理器）和 `hvigor`（构建工具），二者是 HAP 构建的必需组件。

下载地址：https://developer.huawei.com/consumer/cn/deveco-studio/

**推荐路径**（与 `build_ohos.bat` 默认一致）：

```
D:\Program Files\Huawei\DevEco Studio\
```

`build_ohos.bat` 的工具链路径可用**环境变量覆盖**（第十三轮加固后，换机器无需改脚本）：

```bat
REM 不设则用默认值；实际路径不同时设置对应环境变量即可
set "DEVECO_HOME=D:\Program Files\Huawei\DevEco Studio"
REM 脚本内部据此推导 OHPM_HOME / HVIGOR_HOME
```

脚本开跑前会**预检** `flutter_ohos` 与 `ohpm` 是否存在，缺失立即报错退出（早失败易诊断）。

### 2.2 安装 OpenHarmony SDK

DevEco Studio → Settings → SDK → **OpenHarmony** 标签页 → 下载 SDK。

**推荐路径**（与 `build_ohos.bat` 默认一致）：

```
E:\Huawei\OpenHarmony\Sdk
```

若使用不同路径，设置环境变量（无需改脚本）：

```bat
set "OHOS_SDK_HOME=E:\Huawei\OpenHarmony\Sdk"
```

### 2.3 安装 flutter_ohos SDK

从 Gitee 社区仓库 clone flutter_ohos 分支：

```bash
git clone -b ohos-3.16 --single-branch \
  https://gitee.com/openharmony-sig/flutter_flutter.git \
  D:\development\flutter_ohos\flutter
```

> **注意**：不要把 flutter_ohos 加到系统 PATH。`build_ohos.bat` 使用绝对路径调用其 `flutter.bat`，避免污染全局环境。

### 2.4 验证工具链

```cmd
where ohpm
where hvigorw
D:\development\flutter_ohos\flutter\bin\flutter.bat --version
```

三条命令均应正常输出，否则检查 PATH 和安装路径。

---

## 三、构建流程

### 3.1 构建四阶段模型

```
┌─────────────┐   ┌──────────────┐   ┌────────────┐   ┌─────────────┐
│ 1. 源码补丁  │ → │ 2. 依赖降级   │ → │ 3. HAP 编译 │ → │ 4. 源码还原  │
│ ohos_patch   │   │ overrides +   │   │ flutter     │   │ ohos_restore │
│ .ps1         │   │ pub get       │   │ build hap   │   │ .ps1         │
└─────────────┘   └──────────────┘   └────────────┘   └─────────────┘
```

### 3.2 一条命令构建

```cmd
cd D:\FlutterProjects\knowledge_graph_app
cmd /c build_ohos.bat
```

`build_ohos.bat` 执行以下步骤（全自动）：

1. **备份源码** — `ohos_patch.ps1` 将 `lib/` 复制到 `lib.backup/`
2. **源码补丁** — 批量替换 Flutter 3.27+ API 为 3.16 兼容形式
3. **依赖降级** — 复制 `pubspec_overrides_ohos.yaml` → `pubspec_overrides.yaml`
4. **拉取依赖** — `flutter_ohos pub get`
5. **编译 HAP** — `flutter_ohos build hap --release`
6. **清理** — 删除 `pubspec_overrides.yaml`
7. **还原源码** — `ohos_restore.ps1` 将 `lib.backup/` 还原到 `lib/`
8. **修复 pubspec.lock** — 用主 Flutter SDK 升级 `record`/`record_windows`，避免桌面端语音崩溃

### 3.3 ⚠️ 独占构建

`build_ohos.bat` 期间 **禁止并行构建其他平台**（Android / Windows / Web）。

原因：步骤 3 把 `pubspec_overrides.yaml` 放到项目根目录，`dart pub` 全局加载此文件。若此时主 Flutter SDK 执行 `pub get`，会把降级依赖污染到 Android/Windows/Web 的 lock 文件。

### 3.4 ⚠️ 补丁态切勿提交（第十三轮加固）

`ohos_patch.ps1` 是**破坏性补丁**——直接改写 `lib/` 源码（`withValues→withOpacity` 等），靠
`lib.backup/` + `ohos_restore.ps1` 事后还原。**最大风险**：若构建中断、或在补丁态执行了
`git add lib/`，**降级后的代码会被提交进 master**。历史上 commit `944b452d7` 的「`withValues`
全局回退 + 3 个 theme 编译错误」正是这么来的——降级代码混进主干，导致 `flutter analyze`
从 583 飙到 2462、且 `theme_manager.dart` 出现 3 处真编译错误。

**防线**：仓库已加 pre-commit 守卫 `scripts/check_no_ohos_patch.sh`，检测到补丁态签名
（`lib.backup/` 存在 / `pubspec_overrides.yaml` 存在 / 暂存的 theme 用旧名 / 暂存 lib 新增
`.withOpacity(`）即**拒绝提交**。团队成员 clone 后跑一次安装：

```bash
bash scripts/install_git_hooks.sh
```

确属误报需强过：`git commit --no-verify`。

**若构建中断后发现 `lib.backup/` 残留**：先还原再做任何 git 操作——

```powershell
powershell -ExecutionPolicy Bypass -File ohos_restore.ps1
```

---

## 四、源码补丁详解

`ohos_patch.ps1` 负责将项目中使用 Flutter 3.27+ API 的代码降级到 Flutter ~3.16 兼容形式。

### 4.1 补丁清单

| 补丁项 | 原始 API（3.27+） | 降级形式（3.16） | 代码中使用量 | 语义差异 |
|--------|-------------------|-----------------|:----------:|---------|
| 颜色透明度 | `Color.withValues(alpha: x)` | `Color.withOpacity(x)` | ~1257 处 | 数学等价（`alpha × 255` 取整） |
| 主题类名 | `CardThemeData()` | `CardTheme()` | 3 处 | 纯类名重命名 |
| 主题类名 | `DialogThemeData()` | `DialogTheme()` | 3 处 | 同上 |
| 主题类名 | `TabBarThemeData()` | `TabBarTheme()` | 3 处 | 同上 |
| 返回拦截 | `onPopInvokedWithResult:` | `onPopInvoked:` | 0 处 | 代码库未使用，预防性补丁 |
| 下拉初始值 | `DropdownButtonFormField<T>(initialValue:)` | `value:` | 0 处 | 代码库未使用，预防性补丁 |

### 4.2 颜色补丁细节

```
原始：   Colors.blue.withValues(alpha: 0.5)
            ↓ 正则替换（支持多行）
降级：   Colors.blue.withOpacity(0.5)
```

正则（PowerShell .NET regex）：
```powershell
$c -replace '(?s)\.withValues\(\s*alpha:\s*([^)]+)\)', '.withOpacity($1)'
```

- `(?s)` — 单行模式，`.` 匹配换行符（处理 `withValues(\n  alpha: 0.3)` 跨行写法）
- `([^)]+)` — 捕获 `alpha:` 的值表达式（必须不含 `)`）

> **已知限制**：若 `alpha:` 表达式包含嵌套括号（如 `alpha: someFunc(x)`），正则匹配失败。当前代码库无此类写法（1257 处均为直接字面量）。

### 4.3 兼容扩展（兜底）

`lib/core/constants/color_ohos_compat.dart` 提供 `withValues` 的 extension fallback：

```dart
extension ColorOhosCompat on Color {
  Color withValues({double? alpha, ...}) {
    return Color.fromARGB(/*...*/);
  }
}
```

在标准 Flutter 上 `dart:ui` 实例方法优先；在 OHOS 上 instance method 不存在，extension 兜底。

> **第十三轮加固说明**：此前有 76 个 `lib/` 文件 `import` 了该兼容层（由 `tool/add_ohos_shim.py`
> 注入），但构建实际**不依赖**它们——`ohos_patch.ps1` 的 sed 已把所有 `withValues` 替换成
> `withOpacity`。这些 import 是注入残留，已从 master 全部移除以保持主干干净。兼容层文件
> `color_ohos_compat.dart` 本身保留（作为文档化的兜底方案），但不再注入到业务文件。

---

## 五、依赖降级详解

`pubspec_overrides_ohos.yaml` 在构建时复制为 `pubspec_overrides.yaml`，覆盖主 `pubspec.yaml` 的依赖版本。

### 5.1 降级原因

flutter_ohos 基于 Flutter 3.16，内置 Dart SDK **3.4.0**。许多依赖的新版本 `sdk:` 约束高于 3.4：

| 包 | 标准版本 | sdk 约束 | OHOS 降级版本 | 影响 |
|----|---------|----------|-------------|------|
| `syncfusion_flutter_pdf` | 33.x | `>=3.7.0` | 29.1.38 | PDF 生成 API 基本兼容 |
| `file_picker` | 10.x | `>=3.5.0` | 8.3.7 | 教学场景足够 |
| `win32` | 5.13.0 | `>=3.5.0` | 5.5.4 | 仅 Windows 桌面，OHOS 无需 |
| `media_kit_video` | 1.3.x | `>=3.5.0` | 1.2.5 | OHOS 无视频后端，预留 |
| `camera` | 0.11.x | `>=3.5.0` | 0.9.8+1 | OHOS 无相机后端 |
| `camera_android_camerax` | 0.6.30+ | `>=3.6.0` | 0.6.21+1 | 仅 Android |
| `camera_avfoundation` | 0.9.22+ | `>=3.6.0` | 0.9.19 | 仅 iOS/macOS |
| `mobile_scanner` | 5.2.x | `>=3.5.0` | 4.0.1 | QR 扫描 API 兼容 |
| `shared_preferences` | 2.3.x | `>=3.6.0` | 2.2.3 | 键值存储 API 稳定 |
| `path_provider` | 2.1.5+ | `>=3.6.0` | 2.1.3 | 路径获取 API 稳定 |
| `package_info_plus` | 8.3.x | `>=3.6.0` | 8.2.1 | 包信息 API 稳定 |

### 5.2 camera_avfoundation 版本陷阱

`camera_avfoundation` 是 iOS/macOS 独占插件，在 OHOS 上从不执行。但 `pub` 会解析所有平台的传递依赖，且该包的 SDK 约束直接受 Dart 编译器检查。

| 版本 | sdk 约束 | OHOS 兼容 |
|------|---------|:--------:|
| 0.9.23+2 | `>=3.9.0` | ❌ |
| 0.9.22+10 | `>=3.9.0` | ❌ |
| 0.9.21+4 | `>=3.9.0` | ❌ |
| 0.9.19+3 | `>=3.6.0` | ❌ |
| **0.9.19** | **`>=3.4.0`** | **✅** |

必须精确锁定 `"0.9.19"`（不能 `"<0.9.20"`，因 `+3` hotfix 版本的 sdk 约束已上调）。

---

## 六、签名配置

### 6.1 当前签名方案

使用 **OpenHarmony 调试签名**，凭证位于 `ohos/signature/`：

```
ohos/signature/
├── debug.cer          # 调试证书
├── debug.p7b          # 证书链
├── debug.p12          # 密钥库（含私钥）
└── material/          # 签名素材
```

`ohos/build-profile.json5` 通过相对路径引用：

```json5
{
  "signingConfigs": [
    {
      "name": "debug",
      "material": {
        "certpath": "./signature/debug.cer",
        "storepath": "./signature/debug.p12",
        "keypass": "...",
        "storepass": "...",
        // ...
      }
    }
  ]
}
```

### 6.2 限制与替换

| 场景 | 当前方案 | 生产发布方案 |
|------|---------|------------|
| 安装范围 | 开发者模式设备 | 所有商用鸿蒙设备 |
| 证书签发方 | OpenHarmony 调试 CA | 华为 AppGallery CA |
| 有效期 | 1 年 | 视证书而定 |
| 获取方式 | 项目内已提供 | 向华为申请商用证书 |

替换签名凭证时：在华为 AppGallery Connect 申请正式证书和 Profile → 替换 `ohos/signature/` 内文件 → 更新 `build-profile.json5` 中的密码 → 重新构建。

---

## 七、产物与安装

### 7.1 构建产物

```
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

大小约 72–76 MB（release，含 arm64-v8a native 库；v1.16.2 实测 signed HAP 75.8 MB）。

### 7.2 安装到鸿蒙真机

**前提**：设备已开启开发者模式（设置 → 关于手机 → 连续点击软件版本 7 次 → 系统 → 开发者选项 → USB 调试开启）。

使用 `hdc`（HarmonyOS Device Connector）安装：

```cmd
hdc install entry-default-signed.hap
```

或通过 DevEco Studio 的 "Run" 功能推送。

### 7.3 ⚠️ 模拟器限制

```
flutter_ohos 工具链目前只产 arm64-v8a 引擎，不含 x86_64 变体。
华为官方手机模拟器（Pura 90 等）使用 x86_64 镜像，装 HAP 报错：

  code:9568347 install parse native so failed.
  the Abi type supported by the device does not match

无法安装到模拟器 → 演示 / 测试必须使用鸿蒙真机。
```

### 7.4 分发打包

分发 zip 命名遵循 DevEco Studio 官方风格：

```
课程知识图谱与数字孪生+harmonyos+v1.16.2.zip
```

内含：
- `entry-default-signed.hap` — 应用包
- `安装说明.txt` — 中文安装指引 + 默认账号

---

## 八、已知限制

### 8.1 编译时限制

| 限制项 | 原因 | 影响 |
|--------|------|------|
| Dart 语言版本 ≤ 3.4 | flutter_ohos 内置 Dart 3.4 | 无法使用 Dart 3.5+ 语法（records destructuring 等） |
| Flutter API 版本 ~3.16 | flutter_ohos 分支版本 | Color.withValues / toARGB32 / activeThumbColor 等不可用（已补丁） |
| 无 gen_l10n 工具 | flutter_ohos 不含 l10n 生成 | 本地化文本嵌入代码而非 .arb（不影响功能） |
| record/record_windows 1.0.6 crash | OHOS 构建后 lock 残留旧版 | `build_ohos.bat` 末尾自动用主 Flutter SDK 升级 |

### 8.2 运行时限制

| 功能 | 状态 | 原因 |
|------|:----:|------|
| 知识图谱浏览 | ✅ 正常 | 纯 Flutter UI，无平台依赖 |
| 章节测验 | ✅ 正常 | 纯业务逻辑 |
| 学习中心 | ✅ 正常 | 纯 UI |
| 成绩管理 | ✅ 正常 | 纯逻辑 |
| **相机 / 直播** | ❌ 不可用 | `camera` 包无 OHOS 平台后端 |
| **视频播放** | ❌ 不可用 | `media_kit_video` 无 OHOS 平台后端 |
| **文件选择** | ⚠️ 待验证 | `file_picker` 降级至 8.3.7，需真机测试 |
| **QR 扫码** | ⚠️ 待验证 | `mobile_scanner` 降级至 4.0.1，需真机测试 |
| **本地数据库** | ⚠️ 待验证 | `sqflite` + FFI 依赖 OHOS SQLite 原生库 |
| **AI 对话** | ✅ 正常 | HTTP 请求，无平台依赖 |
| **数据同步** | ✅ 正常 | Gitee API，无平台依赖 |

---

## 九、常见问题

### Q1：`hvigor` 报错 "ohpm not found"

**原因**：DevEco Studio 未安装或 PATH 未配置。

**解决**：
```cmd
set OHPM_HOME=D:\Program Files\Huawei\DevEco Studio\tools\ohpm
set PATH=%OHPM_HOME%\bin;%PATH%
```
或直接安装 DevEco Studio 到推荐路径。

### Q2：`camera_avfoundation: language version too high`

**原因**：pub 解析到 `camera_avfoundation 0.9.19+3`（sdk `>=3.6.0`）而非 `0.9.19`（sdk `>=3.4.0`）。

**解决**：在 `pubspec_overrides_ohos.yaml` 中已有精确锁定 `"0.9.19"`。若仍然报错，清理 pub 缓存后重试：

```cmd
flutter_ohos pub cache clean
flutter_ohos pub get
```

### Q3：构建后 Windows 桌面版崩溃（语音录音时）

**原因**：OHOS 构建将 `record_windows` 降级到 1.0.6，该版本有 native crash bug。主 Flutter SDK 构建 Windows 时若 lock 文件残留此版本，就会崩溃。

**缓解**：`build_ohos.bat` 末尾自动用主 Flutter SDK 执行 `pub upgrade record record_windows` 修复。若此步骤报错（主 Flutter 工具链路径问题），手动执行：

```cmd
D:\development\flutter_windows_3.35.1-stable\flutter\bin\flutter.bat pub upgrade record record_windows
```

### Q4：`lib.backup` 残留，源码未还原

**原因**：构建过程中断（Ctrl+C）导致 `ohos_restore.ps1` 未执行。

**解决**：手动还原：
```powershell
powershell -ExecutionPolicy Bypass -File ohos_restore.ps1
```
确认 `lib/` 中文件已还原为原始 API（检查 `activeThumbColor` 而非 `activeColor`）。

### Q5：可以发布到华为应用市场吗？

**可以，但需替换签名**。流程：
1. 在华为 AppGallery Connect 申请应用（Bundle Name 对应 `ohos/AppScope/app.json5`）
2. 获取正式发布证书和 Profile
3. 替换 `ohos/signature/` 内文件
4. 更新 `ohos/build-profile.json5` 签名配置
5. 重新构建 → 上传至 AppGallery Connect

### Q6：为什么不支持鸿蒙模拟器？

flutter_ohos 社区分支目前仅编译 `arm64-v8a` ABI 的 Flutter 引擎。华为 DevEco Studio 提供的官方模拟器运行 `x86_64` 镜像，引擎不匹配导致 native so 无法加载。

可能的未来方案：
- 社区提供 x86_64 引擎构建
- 或使用三方鸿蒙模拟器（若有 arm64 镜像）

---

## 十、构建脚本速查

| 文件 | 用途 | 执行者 |
|------|------|--------|
| `build_ohos.bat` | 总控脚本（路径参数化 + 工具链预检 + 保证 restore） | 开发者 |
| `ohos_patch.ps1` | 备份 + API 降级补丁 | build_ohos.bat |
| `ohos_restore.ps1` | 还原源码 | build_ohos.bat（自动）/ 手动 |
| `pubspec_overrides_ohos.yaml` | 依赖降级配置 | build_ohos.bat（cp） |
| `lib/core/constants/color_ohos_compat.dart` | withValues 扩展兜底（文档化备用，不注入业务文件） | Dart 编译器 |
| `scripts/check_no_ohos_patch.sh` | pre-commit 守卫，拦截补丁态误提交 | git pre-commit 钩子 |
| `scripts/install_git_hooks.sh` | 安装上述钩子（clone 后跑一次） | 开发者 |

> 注：旧的 `build_ohos.cmd` 已删除（路径反斜杠被 `\t`/`\f` 转义损坏，且走过时的 `pubspec_ohos.yaml` 流程）。`build_ohos.bat` 是唯一入口。

**手动操作序列**（理解流程用，正常用 `build_ohos.bat` 即可）：

```powershell
# 1. 补丁
powershell -ExecutionPolicy Bypass -File ohos_patch.ps1

# 2. 依赖降级
copy /Y pubspec_overrides_ohos.yaml pubspec_overrides.yaml

# 3. 构建
D:\development\flutter_ohos\flutter\bin\flutter.bat pub get
D:\development\flutter_ohos\flutter\bin\flutter.bat build hap --release

# 4. 清理
del pubspec_overrides.yaml

# 5. 还原
powershell -ExecutionPolicy Bypass -File ohos_restore.ps1
```

---

## 十一、快速检查清单

- [ ] DevEco Studio 已安装（含 ohpm + hvigor）
- [ ] OpenHarmony SDK 已下载
- [ ] flutter_ohos SDK 已 clone 到 `D:\development\flutter_ohos`
- [ ] 环境变量与实际安装路径一致（`DEVECO_HOME` / `OHOS_SDK_HOME` / `FLUTTER_OHOS_HOME`，或用默认）
- [ ] 已跑 `bash scripts/install_git_hooks.sh` 安装补丁态守卫
- [ ] 调试签名文件 `ohos/signature/*.p12` 存在
- [ ] 无并行构建（Windows/Android/Web 构建不在运行）
- [ ] 构建成功：`ohos/entry/build/default/outputs/default/entry-default-signed.hap`
- [ ] `lib.backup` 已清除（确认 lib/ 已还原为原始代码）
- [ ] `pubspec_overrides.yaml` 已删除
- [ ] `pubspec.lock` 中 `record_windows` 版本 ≥ 1.0.7
- [ ] 鸿蒙真机已开启开发者模式 + USB 调试
- [ ] `hdc install` 安装成功，应用图标出现在桌面
