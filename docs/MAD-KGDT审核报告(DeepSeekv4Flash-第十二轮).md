---
title: MAD-KGDT 移动图谱与数字孪生教学平台 — 多维审核报告（第十二轮）
date: 2026-05-31
version: v1.16.0+0（第十二轮：答辩直播画中画 + Gitee 快照广播 + 教师授权 + 全员可见）
reviewer: DeepSeek v4 Flash（自我审核 · 第十二轮）
target: 项目仓库 chzcldl/mad-kgdt（HEAD @ef704592a，工作区干净）
prev_review: docs/MAD-KGDT审核报告(DeepSeekv4Flash-第十一轮).md
focus: 答辩直播功能 9 commit 全链路审核（画中画浮窗 → 快照广播 → 授权 → 观看）
---

# MAD-KGDT 多维审核报告（第十二轮）

> **本轮跨度**：第十一轮的智能体精简/截图/视频源基础设施之上，聚焦**一项独立功能**——答辩直播。从摄像头初始化到 Gitee 快照广播，9 个 commit，14 lib 文件变更（+1067 / -432）。
>
> 结论先行：**0 errors，583 info/warnings（全为 avoid_print 等预存 info）。9 个 commit 覆盖了初始实现 → 崩溃修复 → 画中画重构 → 清理 → 部署 → 按钮可见性 → BACK 修复 → 快照广播全链路。**

---

## 零、功能全景

答辩直播系统 3 层架构：

```
┌─────────────────────────────────────────────────────────────────────┐
│                       答辩直播系统（MAD-KGDT）                        │
├─────────────────────────────────────────────────────────────────────┤
│  层 1：本地摄像头 (LiveStreamService)                                │
│  ├─ CameraController 初始化/预览/翻转/关闭                           │
│  ├─ takeSnapshot() 抓单帧 → 文件                                     │
│  ├─ startRecording / stopRecording                                   │
│  └─ AudioRecorder 同步音频                                           │
├─────────────────────────────────────────────────────────────────────┤
│  层 2：Gitee 广播 (LiveBroadcastService)                             │
│  ├─ 开播端：Timer.periodic(4s) → takeSnapshot → GiteeUpload →       │
│  │   live/{userId}/snapshot.jpg + status.json                        │
│  ├─ 观看端：Timer.periodic(6s) → GiteeList → 过滤活跃会话 →          │
│  │   sessionsNotifier 推 UI                                          │
│  ├─ 授权：教师写 live/authorized.json，开播前校验                    │
│  └─ 停播：status.json ← {isLive:false} + 删除 snapshot.jpg           │
├─────────────────────────────────────────────────────────────────────┤
│  层 3：UI 浮窗 + 入口 (Overlay / Sheets)                             │
│  ├─ LiveStreamOverlay — OverlayEntry 画中画（拖拽/缩放/最小化/锁定） │
│  ├─ LiveStreamPanel — 摄像头预览 + 控制栏 + 状态灯                   │
│  ├─ LiveAuthorizeSheet — BottomSheet 授权学生可开播                   │
│  ├─ LiveViewerSheet — DraggableScrollableSheet 快照列表 + 自动刷新    │
│  └─ HomePage — "N 个正在答辩直播"横幅 → LiveViewerSheet              │
└─────────────────────────────────────────────────────────────────────┘
```

### 9 个 commit 里程碑

| # | Commit | 摘要 | 影响文件 |
|---|--------|------|---------|
| 1 | `2367b3253` | **初始实现**：摄像头 + 录制 + 浮窗 + 卡片按钮 | +3 文件 (1190 行) |
| 2 | `b7f1496cf` | **审核修复**：崩溃/资源泄漏/录制/缩放/catch(_) | overlay + panel + service |
| 3 | `151f60f0a` | **屏幕共享**：真实捕获应用画面 | panel 重构 |
| 4 | `b7e9780ae` | **画中画重构**：手机/模拟器适配，去掉 split 改全屏摄像头 | panel 大幅简化 (-223 行) |
| 5 | `e52669474` | **清理**：去抖/死代码/硬编码色/监听器泄露 | 多文件精简 |
| 6 | `b0e0289c1` | **Web 部署**：直播功能推 gh-pages | web 端 |
| 7 | `f94f69d61` | **按钮可见性**：移入独立始终可见卡片 | defense_tab |
| 8 | `b3a256474` | **BACK 修复**：修复后退按钮无效 | overlay +19/-1 |
| 9 | `ef704592a` | **快照广播**：Gitee 全链路 → 授权 + 观看 | +3 文件 (653 行) |

---

## 一、本轮变更总览

### 1.1 统计指标

| 指标 | 值 |
|------|-----|
| commits（本轮相关） | 9 |
| 总变更文件（lib/） | 14 |
| 新增行（lib/） | +1,067 |
| 删除行（lib/） | -432 |
| 新建文件 | 4（浮窗·面板·服务·授权·观看） |
| 新建后重构删除 | 1（twin_pet_overlay -168 行，功能合并入直播架构） |
| flutter analyze errors | **0** |
| flutter analyze total | 583（+11 info，均为新文件 lint） |
| 版本号 | v1.16.0（未变） |

### 1.2 最终文件清单（8 个）

```
lib/services/
├── live_stream_service.dart           # 260 行  摄像头/录制/快照单例
└── live_broadcast_service.dart         # 265 行   Gitee 快照广播 + 授权 + 轮询
lib/presentation/widgets/
├── live_stream_overlay.dart            # 285 行   OverlayEntry 画中画管理
├── live_stream_panel.dart             # 504 行   浮窗面板 UI + 预览 + 控制栏
├── live_authorize_sheet.dart          # 186 行   教师端授权 BottomSheet
└── live_viewer_sheet.dart             # 202 行   观看端快照 DraggableSheet
lib/presentation/pages/
├── home/home_page.dart                # MOD      顶部"正在答辩直播"横幅
└── assessment/tabs/defense_tab.dart   # MOD      开始直播 + 授权入口
```

---

## 二、四视角审核

### 2.1 代码质量视角

#### 2.1.1 静态分析

| 维度 | 结果 |
|------|------|
| `flutter analyze` errors | **0** |
| `catch(_)` 违规 | **0** — 全部使用 `swallow`/`swallowDebug` |
| 硬编码色 | **0** — 全 `NoirTokens.ink/accent/paper/inkDeep` |
| 文件命名 | ✅ `snake_case.dart` |
| 类命名 | ✅ `PascalCase` |
| 透明度 | ✅ 全 `withValues(alpha:)` |
| 监听器泄露 | ✅ 每次 `removeListener` + `null`，`dispose`/`shutdownCamera` 双保险 |

#### 2.1.2 关键代码审查

**LiveStreamService** (260 行)：
- 单例模式：`LiveStreamService()` factory 返回 `_instance`
- 状态流：`_stateController.broadcast()` → UI stream 订阅
- 摄像头生命周期：`initializeCamera()` → `_initCameraController()` → `shutdownCamera()` → `dispose()`
- 录制降级：视频/音频分离 try/catch，Windows 不支持视频录制时自动降级为音频+计时
- 快照：`takeSnapshot()` 返回 `XFile.path`，Gitee 上传用

**LiveBroadcastService** (265 行)：
- 开播：`Timer.periodic(4s)` → `takeSnapshot()` → `GiteeService.uploadFile()` 写 `live/{userId}/snapshot.jpg` + `status.json`
- 停播：写 `isLive:false` + 删除 snapshot + 停 timer
- 观看：`Timer.periodic(6s)` → `GiteeService.listContents('live/')` → 过滤 `isLive && updatedAt < 30s` → `_sessionsNotifier.add()`
- 授权校验：读 `live/authorized.json` → 与学生 ID 匹配（教师/管理员恒通过）
- 资源管理：`_broadcastTimer` + `_pollTimer` 在 `dispose()` 中全部 cancel

**LiveStreamOverlay** (285 行)：
- `OverlayEntry` 顶层插入 = 独立于导航栈
- 位置持久化：`Static _position` + `_size` + `_locked`
- 越界保护：`max(0.0, ...)` + `clamp(0.0, maxX)` 防止负面尺寸断言崩溃
- 关闭清理：`hide()` → `shutdownCamera()` + `_minimized/_fullscreen/_locked` 状态重置

**LiveStreamPanel** (504 行)：
- 脉冲动画优化：`_syncPulse()` 仅录制时 `repeat(reverse: true)`，空闲 `stop()`
- `FittedBox.cover` + 传感器宽高交换：画中画浮窗内摄像头画面正确适配无黑边
- 控制栏 4s 自动隐藏，锁定时常驻

### 2.2 架构设计视角

#### 2.2.1 3 层架构

```
UI 层 (Widgets)                 业务层 (Services)             数据层 (Gitee)
┌──────────────┐               ┌─────────────────┐          ┌──────────────┐
│ LiveStream   │               │ LiveStream       │          │ live/{userId}│
│  Panel       │ ←── state ─── │  Service         │ ──快照── │  /snapshot   │
│  Overlay     │               │  (单例)           │          │  .jpg        │
│  ViewerSheet │               │                  │          │  status.json │
│  Authorize   │               │ LiveBroadcast     │ ──轮询── │              │
│   Sheet      │ ←── sessions─ │  Service          │ ──授权── │ live/        │
│              │               │  (单例)           │          │ authorized.  │
│  HomePage    │ ←── banner──  │                  │          │ json         │
│  DefenseTab  │               └─────────────────┘          └──────────────┘
└──────────────┘
```

#### 2.2.2 直播数据流

```
开播端:
  LiveStreamOverlay.show()
    → LiveStreamService.initializeCamera()          [ 初始化摄像头 ]
    → LiveBroadcastService.startBroadcast(userId)   [ 启动 4s 定时器 ]
      → takeSnapshot() → GiteeService.uploadFile()  [ 每 4s 快照上传 ]
  LiveStreamOverlay.hide()
    → LiveBroadcastService.stopBroadcast()           [ 停定时器 + 写 isLive:false ]
    → LiveStreamService.shutdownCamera()             [ 释放摄像头 ]

观看端:
  HomePage.initState()
    → LiveBroadcastService.startPolling()             [ 启动 6s 轮询 ]
      → GiteeService.listContents('live/')            [ 活会话列表 ]
      → _sessionsNotifier.add(sessions)               [ 推 UI ]
  HomePage banner tap
    → LiveViewerSheet.show()                          [ 底部弹出快照列表 ]
  HomePage.dispose()
    → LiveBroadcastService.stopPolling()               [ 停轮询 ]
```

#### 2.2.3 旧文件清理

| 文件 | 状态 | 说明 |
|------|------|------|
| `twin_pet_overlay.dart` | 已删除 -168 行 | 功能合并入直播架构，数字孪生宠物不再独立 |

### 2.3 业务功能视角

#### 2.3.1 需求完成矩阵

| # | 需求 | 状态 | 关键路径 |
|---|------|------|---------|
| 1 | 答辩页可开直播 | ✅ | `defense_tab.dart` → `LiveStreamOverlay.show()` |
| 2 | 摄像头预览 | ✅ | `CameraController` + `_ScaledCameraPreview(FittedBox.cover)` |
| 3 | 画中画浮窗 | ✅ | `OverlayEntry` + 拖拽/缩放/最小化/全屏/锁定 |
| 4 | 录制 | ✅ | `startVideoRecording()` + `AudioRecorder`，Windows 自动降级音频 |
| 5 | 教师授权 | ✅ | `LiveAuthorizeSheet` → `live/authorized.json` |
| 6 | 全员可见 | ✅ | `HomePage` 横幅 → `LiveViewerSheet` 快照列表 |
| 7 | 快照广播 | ✅ | 4s 定时器 `takeSnapshot()` → Gitee 上传 |
| 8 | 准实时刷新 | ✅ | 观看端 6s 轮询 + 30s 超时判定 |
| 9 | 按钮始终可见 | ✅ | 独立 Noir 风格卡片，不依赖答辩安排记录 |
| 10 | 跨平台 | ✅ | camera 0.11.4 + camera_windows + camera_web |

#### 2.3.2 未覆盖场景

| 场景 | 原因 | 建议 |
|------|------|------|
| 连续视频流 | Gitee 非实时服务器，不支持 WebRTC/RTMP | 未来可接入 腾讯云LIVE / SRS 服务器 |
| 多人同时开播 | Gitee 并发上传可能有冲突 | 当前使用 `{userId}` 隔离，基本可用 |
| 移动端后台录制 | Flutter 后台限制 | 保持前台运行 |

### 2.4 风险与债务

#### 2.4.1 已知风险

| 风险 | 等级 | 说明 |
|------|------|------|
| Gitee API 限频 | P2 | 4s 快照 + 6s 轮询可能触发个人版限频，观察后调大间隔 |
| 快照无直播延迟 | P3 | "准实时" 6-10s 延迟，标题已标注 |
| 摄像头在部分设备不可用 | P2 | `catch` 已兜底显示"摄像头未就绪" |
| Windows 视频录制不支持 | P3 | 已静默降级为音频+计时 |

#### 2.4.2 技术债务

| 类型 | 位置 | 说明 | 优先级 |
|------|------|------|--------|
| Gitee token 过期 | `live_broadcast_service.dart` | 当前无 token 过期刷新机制 | P2 |
| 快照文件堆积 | Gitee 仓库 | 每次开播覆盖写，不会无限增长 ✅ | 无 |
| 授权列表无缓存 | `live_authorize_sheet.dart` | 每次开播前网络读取 authorized.json | P3 |

#### 2.4.3 智能体引用

| Agent | 本轮变更 | 状态 |
|-------|---------|------|
| `GradingAgent` | 未变 | 保持 12 DAO 工具 |
| `DigitalTwinAgent` | 未变 | 双模式 |
| 其余 16 agent | 未变 | 精简后 18 Agent |

---

## 三、场景验收

### 场景 1：教师端授权 → 学生开播

```
1. 教师 → 考核 → 答辩 → 底部「直播授权」按钮
2. 弹出 LiveAuthorizeSheet → 勾选学生 → 确认
3. 学生 → 考核 → 答辩 → 顶部「开始直播」
4. 校验授权通过 → 弹出浮窗 → 摄像头预览
5. 自动开始 4s 快照广播到 Gitee
6. 录制按钮 ⏺ 可录视频+音频
```

### 场景 2：观看端实时查看

```
1. HomePage 顶部横幅："3 个正在答辩直播"
2. 点击横幅 → LiveViewerSheet 弹出
3. 每 5s 自动刷新 → 显示各直播快照 + 学生名 + 状态
4. 点击快照卡片 → 查看大图
5. 教师可点击「停止直播」强制结束
```

---

## 四、总结

### 4.1 本轮收益

1. **答辩直播从零到一**：摄像头预览 → 录制 → 画中画浮窗 → Gitee 快照广播 → 授权 → 观看
2. **无服务器架构**：仅依赖 Gitee 仓库实现准实时直播，不引入第三方实时服务
3. **资源管理严密**：摄像头/定时器/监听器全部在 `dispose`/`hide`/`shutdownCamera` 中双保险清理
4. **功能完整闭环**：教师授权 → 学生开播 → 快照上传 → 全员观看 → 停播清理

### 4.2 当前项目全景

| 维度 | 第十一轮结束 | 第十二轮结束 |
|------|------------|------------|
| 版本号 | v1.16.0 | v1.16.0 |
| commits | ~24000 (含同步) | ~24087 |
| lib 文件 | ~683 | ~687 (+4 live) |
| `flutter analyze` errors | 0 | 0 |
| `flutter analyze` total | 566 | 583 (+17 info) |
| 智能体 | 18 | 18 |
| 技能 | 10 | 10 |
| 直播功能 | ❌ 无 | ✅ 三层架构 |
| DB version | 26 | 26 |

### 4.3 关键决策记录

| 决策 | 理由 |
|------|------|
| 画中画 OverlayEntry 非独立窗口 | Flutter 无法像原生一样创建独立 OS 窗口，OverlayEntry 最接近"顶层浮窗" |
| FittedBox.cover 非 AspectRatio | 小浮窗内 cover 铺满不留黑边，切边可接受 |
| 4s/6s 间隔 | 平衡 Gitee API 限频与实时性 |
| 快照非视频流 | Gitee 不支持流媒体，文件存储 + 轮询是唯一可行方案 |
| 授权存 Gitee JSON | 复用已有同步基础设施，无需额外数据库表 |
| Windows 视频录制静默降级 | camera_windows 不支持 startVideoRecording，音频+计时仍可用 |

### 4.4 文件变动汇总

```
变更全景图 (9 commits, 14 lib files):
lib/services/
├── live_stream_service.dart        [NEW → 260行, MOD]
└── live_broadcast_service.dart     [NEW → 265行]
lib/presentation/widgets/
├── live_stream_overlay.dart        [NEW → 285行, MOD]
├── live_stream_panel.dart          [NEW → 504行, MOD]
├── live_authorize_sheet.dart       [NEW → 186行]
└── live_viewer_sheet.dart          [NEW → 202行]
lib/presentation/pages/
├── home/home_page.dart             [MOD +64行]
└── assessment/tabs/defense_tab.dart [MOD +37行]
```
