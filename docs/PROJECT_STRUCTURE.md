# 项目文件组织规范

本项目是 Flutter 多端应用，目录必须同时服务 Android、Windows、Web、HarmonyOS、课程资源包和教学文档。整理原则是：运行必需文件保持稳定，构建产物和日志不得留在根目录，脚本按用途归类，文档按读者和生命周期归类。

## 根目录保留项

| 路径 | 类型 | 说明 |
| --- | --- | --- |
| `pubspec.yaml` | 运行配置 | Flutter 依赖、资源声明、版本号 |
| `analysis_options.yaml` | 开发配置 | Dart/Flutter 静态分析规则 |
| `l10n.yaml` | 运行配置 | Flutter 国际化生成配置 |
| `README.md` / `README.en.md` | 项目说明 | 面向使用者和开发者的入口文档 |
| `CLAUDE.md` | 协作规范 | 记录平台化原则、历史事故和开发约束 |
| `android/ ios/ windows/ web/ linux/ macos/ ohos/` | 平台工程 | Flutter 标准平台目录，不移动 |
| `lib/` | 源码 | 应用业务代码 |
| `test/` | 测试 | 单元、服务、页面、端到端测试 |
| `assets/` | 应用资源 | Flutter 打包资源 |
| `data/` | 课程资源 | 本地演示课程资源，实际按 `.gitignore` 控制 |

## 根目录临时保留项

这些文件仍在代码或文档中被引用，暂不移动：

| 路径 | 原因 | 后续迁移建议 |
| --- | --- | --- |
| `build_ohos.bat` | `ReleaseService` 直接查找根目录脚本 | 后续迁移到 `scripts/build/build_ohos.bat`，并保留根目录兼容 wrapper |
| `ohos_patch.ps1` / `ohos_restore.ps1` | `build_ohos.bat` 直接调用 | 与 OHOS 构建脚本一起迁移 |
| `pubspec_overrides_ohos.yaml` | OHOS 构建流程复制使用 | 迁移到 `scripts/build/ohos/` 后同步文档 |
| `install_vs_components.bat` | Windows 环境安装辅助 | 可迁移到 `scripts/setup/` |

## 推荐目录结构

```text
docs/
  PROJECT_STRUCTURE.md       # 本文件
  README.md                  # 文档入口和分类索引
  architecture/              # 架构图、数据流、类图
  build/                     # 多端构建说明
  audits/                    # 审核报告、发布前审计、平台化报告
  features/                  # 功能设计、修复说明、专项能力说明
  guides/                    # 用户手册、教师/学生/管理员操作指南
  testing/                   # 测试用例、测试报告
  archive/                   # 历史记录和过期方案

scripts/
  README.md                  # 脚本入口
  build/                     # 构建脚本
  release/                   # 发布、打包、上传脚本
  setup/                     # 环境初始化脚本
  hooks/                     # Git hook 和预检
  media/                     # 视频、课件、素材生成脚本
  patches/                   # 构建补丁和二进制补丁

tools/
  README.md                  # 工具入口
  coursegen/                 # 课程资源生成工具
  archive/                   # 归档模板转换工具
  media/                     # 视频/PPT/PDF 生成工具
  qa/                        # 检查、校验、截图工具

logs/
  build/YYYY-MM-DD/          # 本地构建日志，已忽略
  runtime/                   # 本地运行日志，已忽略
```

## 运行必需配置

| 文件 | 是否应入库 | 说明 |
| --- | --- | --- |
| `pubspec.yaml` | 是 | Flutter 主配置 |
| `analysis_options.yaml` | 是 | 静态分析配置 |
| `l10n.yaml` | 是 | 国际化配置 |
| `pubspec.lock` | 否 | 当前策略是不追踪，避免不同 Flutter 版本导致漂移 |
| `.flutter-plugins*` | 否 | Flutter 生成文件 |
| `.env*` / key / keystore | 否 | 敏感配置，禁止提交 |
| `pubspec_overrides.yaml` | 否 | 本地依赖覆盖；OHOS 专用文件另行说明 |

## 脚本规范

1. 脚本文件必须在文件头说明用途、入口命令、依赖环境和输出目录。
2. 破坏性脚本必须明确备份/还原流程，例如 OHOS patch/restore。
3. 构建脚本输出日志必须写入 `logs/build/YYYY-MM-DD/` 或平台构建目录，不得写到根目录。
4. 发布脚本只能读取 `dist/` 中的发布产物。
5. Python 生成缓存、视频中间产物、TTS 音频、临时截图不得入库。

## 文档规范

1. `docs/README.md` 是文档入口，新增文档必须在其中登记。
2. 审核报告进入 `docs/audits/`，功能说明进入 `docs/features/`，构建说明进入 `docs/build/`。
3. 历史事故和开发约束写入 `CLAUDE.md`，面向用户的操作步骤写入 `docs/guides/`。
4. 生成类大文件、音视频、构建输出不得放入 `docs/`，应进入 `dist/`、`logs/` 或忽略目录。

## 当前整理状态

- 已将可移动的根目录临时构建日志移动到 `logs/build/2026-07-05/`。
- 若根目录仍有 `build_*_log*.txt`，通常是文件正被构建/监控进程占用；进程结束后执行 `powershell -ExecutionPolicy Bypass -File scripts/organize_workspace.ps1` 即可整理。
- 已新增 `logs/` 忽略规则。
- 已新增脚本、工具、文档入口说明。
- 已保留根目录 OHOS 构建脚本，避免破坏 `ReleaseService` 和现有构建文档。
