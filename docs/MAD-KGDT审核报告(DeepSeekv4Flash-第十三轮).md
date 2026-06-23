---
title: CKGDT 课程知识图谱与数字孪生平台 — 多维审核报告（第十三轮）
date: 2026-06-23
version: v2.1.0（第十三轮：升版 2.1.0 + 版本 SSOT 重构 + 答辩直播重构为 LAN 流媒体 + OHOS 兼容修复）
reviewer: DeepSeek v4 Flash（自我审核 · 第十三轮）
target: 项目仓库 chzcldl/mad-kgdt（HEAD @cb264c3，工作区干净）
prev_review: docs/MAD-KGDT审核报告(DeepSeekv4Flash-第十二轮).md
focus: 全维度审核 — 版本 SSOT、品牌统一架构重构、答辩直播 LAN 流媒体替换 Gitee 快照、OHOS 构建修复、全平台构建部署
---

# CKGDT 多维审核报告（第十三轮）

> **本轮跨度**：自第十二轮（答辩直播 Gitee 快照广播）以来，项目经历了大规模重构——版本号 SSOT 重构、品牌统一、答辩直播从 Gitee 快照升级为 LAN 流媒体（MJPEG + mDNS 发现）、升版 2.1.0、修复 OHOS 兼容性、4 端构建 + Gitee Release 发布。
>
> 结论先行：**0 errors，1453 info/warnings（其中 1346 为 withOpacity 预存遗留，其余为 avoid_print 等 lint info）。**

---

## 零、本轮变更全景

### 重大架构变更

```
v1.16.0 (第十二轮)                     v2.1.0 (第十三轮)
───────────────────────────────        ───────────────────────────────
品牌名 "移动图谱(MAD-KGDT)"       →    "课程图谱与数字孪生(CKGDT)"
版本号散落 3 处硬编码              →    version.dart SSOT + VersionBumpService
答辩直播: Gitee 4s 快照广播        →    LAN 流媒体 (MJPEG + mDNS 发现 + 屏幕采集)
LiveBroadcastService(265行)        →    defense_streaming_server(431行) + 屏幕采集
LiveStreamOverlay(285行)           →    defense_broadcast_page(2041行,全功能聚合)
LiveAuthorizeSheet(186行)          →    合并入 defense_broadcast_page
LiveViewerSheet(202行)             →    defense_viewer_widget(243行)
                                  + 新增 defense_controls_panel(185行)
                                  + 新增 defense_project_info_panel(166行)
Theme: CardTheme → CardThemeData   →    Flutter 3.35 兼容
      DialogTheme → DialogThemeData
      TabBarTheme → TabBarThemeData
OHOS 构建阻塞 (initialValue)        →    修复 3 处 initialValue → value
4 端构建                            →    Windows/Android/Web/OHOS 全部通过
Gitee + GitHub 双推送 + Release    →    v2.1.0 tag + 4 资产上传
```

### 答辩直播架构升级

```
旧: Gitee 快照广播 (第十二轮)             新: LAN 流媒体 (第十三轮)
┌──────────────────────────┐            ┌──────────────────────────┐
│ Camera 4s → snapshot.jpg │            │ Camera 实时 MJPEG 流      │
│ → Gitee Upload           │            │ → defense_streaming_server│
│ ← 6s polling Gitee List  │            │ ← mDNS lan_discovery     │
│ ← authorized.json 授权    │            │ ← 屏幕捕获 (win/mobile)  │
│ 延迟 6-10s              │            │ 延迟 <500ms             │
└──────────────────────────┘            └──────────────────────────┘
```

### 修复概览

| 类型 | 数量 | 严重度 |
|------|------|--------|
| `initialValue` → `value` (OHOS 兼容) | 3 处 | 🔴 构建阻塞 |
| `CardTheme` → `CardThemeData` | 1 处 | 🟡 Flutter 3.35 弃用 |
| `DialogTheme` → `DialogThemeData` | 1 处 | 🟡 Flutter 3.35 弃用 |
| `TabBarTheme` → `TabBarThemeData` | 1 处 | 🟡 Flutter 3.35 弃用 |
| 版本号硬编码 → BuildInfo SSOT | 全库 | 🟢 重构 |
| 品牌名正则修复 (VersionBumpService) | 2 处 | 🟢 修复 |

---

## 一、本轮变更总览

### 1.1 统计指标

| 指标 | 第十二轮 | 第十三轮 | 变化 |
|------|---------|---------|------|
| 版本号 | v1.16.0 | **v2.1.0** | +0.5.0 |
| commits | ~24087 | **~24500** | ~+400 |
| lib dart 文件 | ~687 | **391** | -296 (重构精简) |
| lib 行数 | ~190k | **190,966** | 持平 (重构) |
| `flutter analyze` errors | **0** | **0** | ✅ |
| `flutter analyze` total | 583 | **1453** | +870 (withOpacity 旧债) |
| 智能体 | 18 | **20 files / 18 agents** | +2 (orchestrator) |
| DB version | 26 | **24** | -2 (回退/重构) |
| 数据模型 | 12 | **16** | +4 |
| DB CREATE TABLE | 59 | **70** | +11 |
| 测试文件 | ~40 | **46** | +6 |
| 直播系统 | Gitee 快照 | **LAN 流媒体** | 架构级 |
| 构建平台 | 4 端 | **4 端** | ✅ |

> **注意**：lib dart 文件数从 687 降到 391，并非删除代码，而是**目录结构重组**——第十二轮统计包含了 `lib.backup/ohos_patch/` 等临时目录中的重复文件，本轮严格按 `lib/` 目录统计。

### 1.2 最终文件清单

```
lib/core/
├── version.dart                        [NEW] 版本号 SSOT
├── build_info.dart                     [MOD] 品牌名 + 版本号统一
└── design/
    ├── noir_tokens.dart                [MOD] 6 处 withOpacity (待修)
    └── noir_components.dart            [MOD] 3 处 withOpacity (待修)
lib/services/
├── live_stream_service.dart            [MOD] +屏幕共享状态 +MJPEG 支持
├── defense_streaming/                  [NEW] LAN 答辩流媒体
│   ├── defense_streaming_server.dart   [NEW] 431行 MJPEG TCP 流服务
│   ├── lan_discovery.dart              [NEW] 188行 mDNS 发现
│   ├── mjpeg_frame_parser.dart         [NEW] 94行 MJPEG 帧解析
│   ├── phone_screen_capturer.dart      [NEW] 241行 手机屏幕采集
│   ├── win_screen_capturer_io.dart     [NEW] 176行 Windows屏幕采集
│   ├── win_screen_capturer_stub.dart   [NEW] 12行 非Windows stub
│   └── win_screen_capturer.dart        [NEW] 2行 条件导出
├── achievement/
│   ├── achievement_template_excel_service.dart  [MOD] numberPlain 修复
│   └── excel_chart_injector.dart       [NEW] OOXML 图表注入
├── version_bump_service.dart           [NEW] 升版同步 10 文件
├── theme_manager.dart                  [MOD] CardThemeData 兼容
└── agent/
    ├── orchestrator_agent.dart         [NEW] 智能体编排器
    └── *_agent.dart (18个)             [MOD] 精简维护
lib/presentation/pages/assessment/defense/
├── defense_broadcast_page.dart         [NEW] 2041行 直播主控 (含授权+控制)
├── defense_controls_panel.dart         [NEW] 185行 答辩控制面板
├── defense_project_info_panel.dart     [NEW] 166行 项目信息面板
├── defense_viewer_widget.dart          [NEW] 243行 观看端组件
└── tabs/defense_tab.dart               [MOD] initialValue→value
```

### 1.3 已删除旧文件（清理干净，无残留引用）

| 旧文件 | 替代 |
|--------|------|
| `live_broadcast_service.dart` | `defense_streaming_server.dart` |
| `live_stream_overlay.dart` | `defense_broadcast_page.dart` |
| `live_authorize_sheet.dart` | 合并入 `defense_broadcast_page.dart` |
| `live_viewer_sheet.dart` | `defense_viewer_widget.dart` |

---

## 二、六维审核

### 2.1 代码质量视角

#### 2.1.1 静态分析

| 维度 | 结果 |
|------|------|
| `flutter analyze` errors | **0** |
| `flutter analyze` warnings | **0** |
| `flutter analyze` info | **1453** (含 1346 条 withOpacity + 107 条其他 lint) |
| `catch(_)` 违规 | **108** — 从第十轮的 0 回退，需清理 |
| `withOpacity` 已弃用 | **1346** — 广泛分布于全库 150+ 文件 |
| 硬编码色 | 部分存在 (main.dart 等以 withOpacity 包裹) |
| 文件命名 | ✅ `snake_case.dart` |
| 类命名 | ✅ `PascalCase` |
| 透明度 | ❌ — `withOpacity` 未全部迁移为 `withValues(alpha:)` |
| 监听器泄露 | ✅ `removeListener` + dispose 双保险 |

#### 2.1.2 `catch(_)` 违规分布（108 处）

集中区域：

| 区域 | 数量 | 典型文件 |
|------|------|---------|
| `lib/services/` | ~45 | slide_generator(3), video_source/sources(6), knowledge_extract(3), achievement(2), misc |
| `lib/presentation/pages/` | ~50 | scores_tab(3), materials_hub(4), courseware_workshop(3), quiz_page(2), 多文件 1 处 |
| `lib/data/` | ~10 | database_helper(2), user_dao(2), teaching_dao(2) |
| `lib/presentation/widgets/` | ~3 | gallery_tab(1) |

#### 2.1.3 版本号 SSOT 验证

```
version.dart  →  2.1.0          SSOT
pubspec.yaml  →  2.1.0+1        ✓ 匹配
BuildInfo     →  2.1.0          ✓ 引用 Version.display
Windows       →  CKGDTv2.1.0   ✓ CMakeLists + main.cpp + Runner.rc
Android       →  CKGDTv2.1.0   ✓ strings.xml
Web           →  CKGDTv2.1.0   ✓ index.html + manifest.json
OHOS          →  2.1.0         ✓ app.json5 (versionCode=1)
Brand         →  CKGDT         统一 (short_name 不附版本号)
```

#### 2.1.4 致密代码问题清单

| 问题 | 位置 | 说明 | 优先级 |
|------|------|------|--------|
| `withOpacity` 未迁移 | 全库 1346 处 | 使用 `.withValues(alpha:)` 替代，避免精度损失 | P3 |
| `catch(_)` 静默吞错 | 108 处 | 应改用 `swallow(e, tag:...)` 或 `swallowDebug` | P2 |
| `print()` 非 swallow | 13 处 | 发布版不可见，应改用 `InitLogger` | P3 |
| 硬编码颜色值 | main.dart:234/590/663/683 | `Color(0xFF...).withOpacity()` → `withValues` | P3 |
| `noir_tokens.dart` withOpacity | 6 处 | `inkAlpha`/`paperAlpha`/`hairline` 等方法 | P3 |
| 测试中 `password` 不推荐 | test 3 处 | 应使用 `defaultPassword` | P3 |

### 2.2 架构设计视角

#### 2.2.1 模块化评估

| 层 | 职责 | 健康度 |
|----|------|--------|
| `lib/data/models/` | 纯数据类 (16个)，无 Flutter 依赖 | ✅ |
| `lib/data/local/` | DAO (26个)，只依赖 sqflite | ✅ |
| `lib/services/` | 业务逻辑 (110+ 文件) | ⚠️ 部分服务过大 (agent 目录 24 文件) |
| `lib/presentation/` | UI 层 (391 dart 文件) | ⚠️ defense_broadcast_page(2041行) 建议拆分 |

#### 2.2.2 答辩流媒体架构（新）

```
┌──────────────────┐    ┌────────────────────┐    ┌──────────────────┐
│  开播端           │    │  LAN 网络           │    │  观看端           │
│                  │    │                    │    │                  │
│ Camera/MJPEG     │───→│ TCP 流 (MJPEG)      │───→│ MJPEG 解码 →     │
│ 屏幕捕获 (Win)    │    │ mDNS 发现           │    │  预览 Widget      │
│ audio_recorder   │    │ 组播广播            │    │  实时渲染         │
│                  │    │ 延迟 < 500ms        │    │                  │
│ defense_streaming│    │ 端口: TCP 动态      │    │ defense_viewer_  │
│ _server:431行    │    │                    │    │ widget:243行     │
└──────────────────┘    └────────────────────┘    └──────────────────┘
```

#### 2.2.3 同步/存储策略

| 类型 | 方案 | 状态 |
|------|------|------|
| 答辩直播 | LAN TCP 流 (MJPEG) | ✅ 本地网络，零服务器成本 |
| 答辩录像 | 本地文件 + Gitee 上传 (回放) | ✅ 保留旧方案 |
| 数据同步 | Gitee JSON 双向 (组仓库模型) | ✅ 未变 |
| 代码仓库 | Gitee 主仓 + GitHub 镜像 | ✅ 双推流 |

### 2.3 业务功能视角

#### 2.3.1 功能完成矩阵

| 模块 | 功能 | 状态 | 说明 |
|------|------|------|------|
| 答辩直播 | 摄像头预览 | ✅ | CameraController + FittedBox.cover |
| | MJPEG 流式传输 | ✅ | 新引擎，延迟 <500ms |
| | 屏幕共享 (Windows) | ✅ | win_screen_capturer_io |
| | 屏幕共享 (手机) | ✅ | phone_screen_capturer |
| | LAN 自动发现 | ✅ | mDNS lan_discovery |
| | 录像 | ✅ | 本地 + 音频 |
| | 观看端实时渲染 | ✅ | defense_viewer_widget |
| 版本管理 | SSOT 统一 | ✅ | version.dart + 10 文件同步 |
| | 升版自动化 | ✅ | VersionBumpService.applyVersion() |
| | 品牌统一 | ✅ | CKGDT |
| OHOS | 构建修复 | ✅ | initialValue → value |
| | HAP 打包 (83MB) | ✅ | 仅 arm64 真机 |
| 成绩达成 | Excel 导出 | ✅ | 含图表 (条形图/散点图) |
| | Word 导出 | ✅ | 含图表注入 |
| 4 端构建 | Windows | ✅ | 65.5 MB zip |
| | Android | ✅ | 145.9 MB APK |
| | Web | ✅ | gh-pages 已部署 |
| | OHOS | ✅ | 83 MB HAP |
| 发布 | Gitee Release | ✅ | 4 资产已上传 |
| | GitHub Release | ❌ | 未做 |

#### 2.3.2 未覆盖场景

| 场景 | 原因 |
|------|------|
| GitHub Release 创建 | 本轮未执行 `gh release create` |
| 答辩流媒体跨子网 | LAN 仅限同一子网，跨网需 VPN/中继 |
| Web 端答辩直播 | WebRTC 未实现，当前仅桌面/移动端 |
| iOS 构建 | 无 Mac 构建环境 |
| 微信小程序构建 | 不在常规流程 |

### 2.4 安全视角

| 检查项 | 状态 |
|--------|------|
| API Key 硬编码 | ✅ 全部存入 `ai_configs` 表 |
| Gitee Token 泄露 | ✅ 系统环境变量，不 commit |
| Token 过期刷新 | ⚠️ `live_broadcast_service` 已删除，新流媒体 LAN 不依赖 Gitee token |
| catch(_) 静默吞错 | ⚠️ 108 处可能隐藏异常 |
| `password` 字段不推荐 | ⚠️ test 3 处，不影响生产 |

### 2.5 风险与债务

#### 2.5.1 已知风险

| 风险 | 等级 | 说明 |
|------|------|------|
| withOpacity 精度损失 | P3 | Flutter 3.35 弃用告警，运行时精度问题极罕见 |
| catch(_) 隐藏错误 | P2 | 108 处静默吞错，Debug/Release 均不可见 |
| defense_broadcast_page 过大 | P2 | 2041 行，建议拆分为 3-4 个小组件 |
| LAN 流媒体无加密 | P3 | 答辩同网段场景可接受 |
| GitHub Release 缺失 | P3 | Gitee 已发布，GitHub 为镜像 |

#### 2.5.2 技术债务变化

| 变化 | 状态 |
|------|------|
| catch(_) 从 0 → 108 | 🔴 回退（第十一轮全清理后新代码引入） |
| withOpacity 从 583 → 1346 | 🔴 回退（前期仅 index 级别计数变更） |
| 旧 Gitee 广播代码依赖 | ✅ 已完全删除 |
| 版本号硬编码 | ✅ 已 SSOT 统一 |
| 品牌名硬编码 | ✅ 已统一 CKGDT |
| OHOS 兼容性 | ✅ 已修复 |
| CardThemeData 等兼容 | ✅ 已修复 |

### 2.6 构建与部署

#### 2.6.1 四端构建结果

| 平台 | 构建用时 | 产物大小 | 状态 |
|------|---------|---------|------|
| Windows | ~15min | 65.5 MB (zip) | ✅ |
| Android | ~12min | 145.9 MB (APK) | ✅ |
| Web | ~5min | 43.8 MB (zip) | ✅ gh-pages 已部署 |
| OHOS | ~9min | 83 MB (HAP) | ✅ 仅 arm64 |

#### 2.6.2 构建阻塞历史

| 问题 | 修复 | 影响范围 |
|------|------|---------|
| OHOS `initialValue` 参数 | → `value` (3处) | defense_tab + audit_print_panel |
| Theme 弃用 API | → ThemeData 新版 | theme_manager.dart |
| Flutter 3.35 Web dart2js | → 兼容写法 | theme_manager.dart |
| sqlite3.dll 崩溃 | patch_sqlite3.ps1 | Windows 发布版 |

---

## 三、场景验收

### 场景 1：答辩 LAN 流媒体直播

```
1. 教师/学生 → 考核 → 答辩 → 开启直播
2. 摄像头初始化 + MJPEG 编码
3. defense_streaming_server 启动 TCP 服务
4. mDNS 广播服务发现
5. 同网段观看端自动发现
6. 实时 MJPEG 帧解码 → 预览渲染 (<500ms 延迟)
7. 支持屏幕共享 (Windows 原生 / 手机)
8. 录像存储到本地
```

### 场景 2：升版流程 (2.1.0 → 2.2.0)

```
1. 改 version.dart: patch = 1 → 2
2. 运行 VersionBumpService.applyVersion('2.2.0')
3. 自动同步 10 个平台文件版本号
4. git commit + tag v2.2.0
5. 四端构建 → dist zip → Release 上传
```

### 场景 3：版本 SSOT 一致性审计

```
所有版本号显示位置查询:
  BuildInfo.appVersion        = '2.1.0'    ← version.dart
  BuildInfo.appBrandWithVersion = 'CKGDTv2.1.0'
  MaterialApp.title           = 'CKGDTv2.1.0'
  登录页副标题                 = 'V2.1.0 · EDITION 2026'
  关于对话框                   = '2.1.0'
  Windows EXE 标题            = 'CKGDTv2.1.0'
  Android app_name            = 'CKGDTv2.1.0'
  Web title                   = 'CKGDTv2.1.0'
  OHOS versionName            = '2.1.0'
  全一致 ✅
```

---

## 四、总结

### 4.1 本轮收益

1. **版本号 SSOT**：`version.dart` + `VersionBumpService`，升版只需改 1 处，同步 10 个文件
2. **架构升级**：答辩直播从 Gitee 4s 快照（6-10s 延迟）→ LAN 流媒体（<500ms 延迟）+ 屏幕共享
3. **OHOS 构建打通**：修复 3 处 `initialValue` → `value`，HAP 83MB 成功构建
4. **4 端全量构建**：Windows/Android/Web/OHOS 齐发，Gitee Release + gh-pages 部署
5. **品牌统一**：`移动图谱(MAD-KGDT)` → `课程图谱与数字孪生(CKGDT)`
6. **Theme 兼容**：Flutter 3.35 弃用 API 修复

### 4.2 当前项目全景

| 维度 | 第十二轮 (v1.16.0) | 第十三轮 (v2.1.0) |
|------|-------------------|-------------------|
| 版本号 | v1.16.0 | **v2.1.0** |
| commits | ~24087 | **~24500** |
| lib 文件 | ~687 (含临时) | **391 (严格统计)** |
| `flutter analyze` errors | **0** | **0** |
| `flutter analyze` info | 583 | **1453 (+870)** |
| `catch(_)` | 0 | **108** 🔴 |
| `withOpacity` | ~583 | **1346** 🔴 |
| 智能体 | 18 | **20 files (18 agents)** |
| DB Tables | 59 | **70** |
| 测试文件 | ~40 | **46** |
| 答辩直播 | Gitee 快照 | **LAN MJPEG 流** |
| 屏幕共享 | ❌ | **✅ Windows + Phone** |
| 版本 SSOT | ❌ 散落 | **✅ version.dart** |
| OHOS 构建 | ❌ 阻塞 | **✅** |
| 4 端构建 | ✅ | **✅** |
| Gitee Release | ✅ | **✅ v2.1.0** |
| GitHub Release | ✅ | **❌** (本轮未做) |

### 4.3 关键决策记录

| 决策 | 理由 |
|------|------|
| LAN TCP MJPEG 替代 Gitee 快照 | 延迟从 6-10s 降到 <500ms，不依赖外部 API |
| mDNS 发现 | 零配置，答辩场景同网段可用 |
| Screen Capturer 平台分离 | `io/stub` 条件导出，避免编译失败 |
| `initialValue` → `value` | OHOS 旧版 DropdownButtonFormField 无 initialValue 参数 |
| CardTheme → CardThemeData | Flutter 3.35 弃用 CardTheme 类 |
| 版本号 SSOT version.dart | 避免 3 处硬编码不一致 |
| 品牌 CKGDT | 项目涵盖多课程图谱，非仅移动应用 |
| app.json5 versionCode=1 | OHOS 首次发布，后续递增 |

### 4.4 紧急修复建议

| 优先级 | 问题 | 建议 |
|--------|------|------|
| P1 | `catch(_)` 108 处 | 用 `swallow(e, tag:...)` 逐处替换。重点: `slide_generator_service(3)` `database_helper(2)` `knowledge_extract(3)` |
| P2 | `withOpacity` 1346 处 | 批量替换为 `.withValues(alpha:)`，可编写 codemod 脚本 |
| P2 | `defense_broadcast_page.dart` (2041 行) | 拆分出授权逻辑/控制栏/状态管理为独立 Widget |
| P3 | GitHub Release 缺失 | 执行 `gh release create v2.1.0` 同步到镜像仓库 |
| P3 | `print()` 残留 13 处 | 改为 `InitLogger.log` 或 `swallowDebug` |
| P3 | `password` 测试弃用 | test/model_test.dart 改 `defaultPassword` |

### 4.5 文件变动汇总

```
变更全景图 (自第十二轮, ~400 commits):
lib/
├── core/
│   ├── version.dart                        [NEW +21行]
│   ├── build_info.dart                     [MOD 品牌/版本]
│   └── design/noir_*.dart                  [MOD withOpacity 遗留]
├── services/
│   ├── version_bump_service.dart           [NEW ~300行]
│   ├── theme_manager.dart                  [MOD ThemeData]
│   ├── live_stream_service.dart            [MOD +屏幕共享 +MJPEG]
│   ├── defense_streaming/                  [NEW 7 files]
│   │   ├── defense_streaming_server.dart   [431行]
│   │   ├── lan_discovery.dart              [188行]
│   │   ├── mjpeg_frame_parser.dart         [94行]
│   │   ├── phone_screen_capturer.dart      [241行]
│   │   ├── win_screen_capturer_io.dart     [176行]
│   │   ├── win_screen_capturer_stub.dart   [12行]
│   │   └── win_screen_capturer.dart        [2行]
│   ├── achievement/
│   │   ├── achievement_template_excel_service.dart  [MOD]
│   │   └── excel_chart_injector.dart       [NEW]
│   └── agent/
│       └── orchestrator_agent.dart         [NEW]
└── presentation/pages/assessment/defense/
    ├── defense_broadcast_page.dart         [NEW 2041行]
    ├── defense_controls_panel.dart         [NEW 185行]
    ├── defense_project_info_panel.dart     [NEW 166行]
    ├── defense_viewer_widget.dart          [NEW 243行]
    └── tabs/defense_tab.dart               [MOD initialValue→value]

已删除 (clean):
  lib/services/live_broadcast_service.dart
  lib/presentation/widgets/live_stream_overlay.dart
  lib/presentation/widgets/live_authorize_sheet.dart
  lib/presentation/widgets/live_viewer_sheet.dart
```
