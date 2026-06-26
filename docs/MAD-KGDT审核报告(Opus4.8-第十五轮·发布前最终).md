---
title: MAD-KGDT 移动图谱与数字孪生教学平台 — 发布前最终总结审核（第十五轮）
date: 2026-06-01
version: v1.17.0+0（首次 iOS 构建里程碑 + OHOS 补丁加固 + 三端构建指南）
reviewer: Claude Opus 4.8（自我审核 · 第十五轮 · 发布前最终）
target: 项目仓库 chzcldl/mad-kgdt（HEAD @56987e81d）
focus: 不做跨轮对比，对整个项目做一次面向发布的总结性横切评估——架构、四视角质量、安全红线、发布就绪度
---

# MAD-KGDT 发布前最终总结审核（第十五轮）

> **本轮性质**：这是**发布前的最终总结审核**，不与历轮逐项对比，而是把项目当作一个"即将交付的整体"来横切评估：它作为教学产品成熟到什么程度？作为工程是否经得起公开发布？有没有发布前必须拦下的硬伤？
>
> **结论先行**：**项目在功能完整度、跨平台覆盖、AI 教学创新、工程纪律四个维度都达到了可发布水准——但存在一条发布前必须处理的安全红线：DeepSeek API Key 硬编码在 3 处源码并已随公开仓库（Gitee + GitHub）长期泄露。** 这条不修，"发布"等于把一个可被任意调用、会产生真实费用的密钥公之于众。除此之外，0 编译错误、4 端构建链齐备、债务纪律有 CI 棘轮兜底，整体是一个**完成度高、结构健康、但带一颗"已引爆的安全雷"**的项目。

所有数字为 2026-06-01 实测（`flutter analyze` / `git grep` / `git log` / `wc -l`，HEAD @56987e81d）。

---

## 零、🔴 发布前阻断项（必须先处理）

> 总结审核的第一职责是：**有没有任何东西能让"发布"这个动作本身变成事故？** 有一条，且严重。

### 0.1 DeepSeek API Key 硬编码 + 公网泄露

实测 `sk-717ef9146311424daa2fbead8ed4682b` 明文出现在 **3 处源码**：

| 文件 | 行 | 上下文 |
|------|----|--------|
| `lib/data/local/database_helper.dart` | 670 | DB 初始化插入默认 AI 配置 |
| `lib/data/local/database_helper.dart` | 1725 | 同上（另一路径） |
| `lib/data/models/ai_config_model.dart` | 30 | provider→key 默认映射表 |

**这违反 CLAUDE.md 明文规则**：「不在代码中硬编码 API Key（默认配置通过 DB 迁移写入）」「AI 与协作 … 不在代码中硬编码 API Key」。

**严重性升级为"已泄露"而非"将泄露"**：`git log -S` 追踪显示该 key 自 commit `0fae0c0bf`（"add AI generation system"）引入，历经 v0.9.0 等多个版本一直在 master，而仓库**已公开镜像到 GitHub `dll/mad-kgdt` 并部署 GitHub Pages**。也就是说这个 key 早已可被任何人从公开源码中提取——它能直接调用 DeepSeek API，产生**真实账单**与**额度滥用**风险，且可能被爬虫自动收割。

**这是本轮唯一的 🔴 红线，也是发布前唯一"必须先做"的事**：

1. **立即在 DeepSeek 控制台吊销/轮换该 key**（泄露既成事实，删代码不能挽回已泄露的旧 key，必须作废它）；
2. 源码 3 处改为留空 / 占位（如 `''`），由用户在「AI 数据设置」页自行填入，或走环境变量 / 构建期注入；
3. 历史提交里的 key 已无法靠"新提交删除"抹掉（git 历史仍可检出旧 commit）——务实做法是**吊销 key**（步骤 1）使其失效，而非尝试 rewrite 整个公开仓库历史（代价高且学生 fork 已扩散）。

> **为什么列为发布前阻断**：其余所有问题（god-file、deprecated、Semantics）都是"慢性债"，发布后慢慢还无碍；唯独这条是"发布动作本身放大伤害"——每多公开一天、多一个下载者，泄露面就扩大一分。**建议在打 release 之前完成 key 吊销 + 源码清除。**

---

## 一、项目全景基线（发布快照）

| 维度 | 实测值 | 评价 |
|------|--------|------|
| 版本 | 1.17.0+0 | 首次 iOS 构建里程碑版 |
| HEAD | 56987e81d | 工作区干净 |
| Dart lib 文件数 | 353 | 中大型单体 |
| Dart lib 行数 | 168,016 | — |
| 页面文件数 | 148 | 功能面广 |
| DAO 数 | 33 | 对应 66 张表 |
| 智能体数 | 18 | 教学 AI 矩阵 |
| 测试文件数 | 25 | 覆盖 core/models/services |
| DB version | 27 | V27 已清幽灵学生 |
| **flutter analyze** | **525 issues** | **0 error / 10 warning / 515 info** |
| catch (_) | 178 | CI 棘轮锁死（ceiling=178）|
| .withOpacity( / .withValues( | **0 / 1268** | 规则5 守住 |
| Semantics 标签 | 2 | 长期无障碍债 |
| 目标平台 | Android / Windows / Web / HarmonyOS / iOS | 5 端构建链齐备 |

### 1.1 一句话定位

> **MAD-KGDT v1.17.0 是一个功能完整、五端覆盖、AI 教学特色突出、且有 CI 工程纪律兜底的成熟教学平台**——发布就绪度高，**唯一卡口是必须先吊销并清除已公网泄露的 DeepSeek API Key**。

---

## 二、视角 ①：AI 专家（智能体架构与 AI 教学创新）

### 2.1 亮点

- **18 智能体矩阵 + RAG**：覆盖辅导/测验/批阅（实验/考核/作品三类批阅）/课件/一键生课/数字孪生（虚拟师生）等教学全链路，`AgentRegistry` + `BaseAgent` 抽象干净，工具调用（NavigationService / DAO）有真实落地。
- **语音 4 层路由**：快速路径 → Tab 映射 → 子页面匹配 → VoiceAgent AI 兜底，且 voice_agent 的内层 tab 清单已从 `kInnerTabRegistry` 注册表生成（SSOT），消除了历轮批评的"prompt 与页面 tab 漂移"。
- **多 provider**：DeepSeek / 智谱 GLM 可切换，配置走 DB（设计正确）——**但默认 key 硬编码进源码，是设计正确、实现破线**（见 §0.1）。

### 2.2 待增强

- 智能体多为"persona + prompt + 通用工具"，**独有工具链深度仍有限**（历轮老评价，本轮持平）：除 graph/批阅类有真实 DAO 工具，多数 agent 差异主要在 persona 文案。
- 教学效果 A/B 数据仍缺，AI 创新"可感知"但"未被量化验证"。

### 2.3 评分：**4.85 / 5**

矩阵完整、RAG + 语音 + 数字孪生构成特色；扣分在工具链深度与效果量化。

---

## 三、视角 ②：高校教师（课堂落地与教学闭环）

### 3.1 亮点

- **教—学—练—评—管五维闭环真实可用**：知识图谱 / 测验 / 视频文档 / 实验提交批阅 / 作品互评 / 三维成绩达成 / 签到课堂互动 / 通知，148 个页面把教学流程铺满。
- **答辩名单幽灵学生根治（本轮重点核实，确认真落地）**：
  - DB 升至 **version 27**，`_migrateToV27`（database_helper.dart:758 真调用 + 2086 行 InitLogger 记录 purge 行数）清除种子库 49 行 `student_` 前缀幽灵学生；
  - `_importStudents` reconcile + 459 行"双保险清幽灵"覆盖"DB 已是 v27 不再触发 onUpgrade"场景；
  - `getStudents({includeInactive=false})`（user_dao.dart:33）默认只返活跃学生，审计入口显式传 true；
  - `live_authorize_sheet`（直播授权，报告 bug 的直接面）已改用 `DefaultClassService.getDefaultClassStudents()`（第 50 行），默认班级有值走单班级过滤、空才回退全体活跃（注释清晰）。
  - **这是教师最大获益点：答辩/直播授权名单不再混入已归档计科22 + 幽灵副本。**
- **成绩导出班级过滤 + swallowDebug**：ScoreExportService 按默认班级过滤、7 处静默吞错改 swallowDebug。

### 3.2 待办

- A/B 教学效果数据仍空缺（无法量化"用了平台学生成绩/参与度是否提升"）。

### 3.3 评分：**4.95 / 5**

五维闭环 + 幽灵根治 + 默认班级全局过滤，教师视角几乎满分；仅缺效果量化。

---

## 四、视角 ③：移动应用开发工程师（代码质量与工程实践）

### 4.1 工程健康度

| 指标 | 值 | 判读 |
|------|----|----|
| 编译错误 | **0** | ✅ 发布硬通过 |
| analyze warning | 10 | 全是死代码/未用变量（unused_local/field/element/import + 1 处恒真比较），无功能风险 |
| analyze info | 515 | 主体是 deprecated（58）+ const 优化建议 |
| catch(_) | 178 | CI 棘轮锁死，只许降不许升 |
| withOpacity | 0 | CI 零容忍门禁 + pre-commit guard 双网 |

### 4.2 工程纪律（项目最强项之一）

- **CI 双门禁**：catch(_) 棘轮（ceiling=178）+ withOpacity 零容忍，且本轮 `/simplify` 刚修复了两道门禁在 `pipefail` 下"0 匹配反而假失败"的隐藏 bug（`{ grep || true; }` 加固，commit 8fa45f4cc）——**门禁本身现已验证可正确 PASS/FAIL**。
- **pre-commit guard**（`check_no_ohos_patch.sh`）拦截 OHOS 补丁态误提交，根治了 944b452d7 式"补丁态泄漏 master → analyze 583→2462"事故。
- **SSOT 模式贯穿**：BuildInfo（版本号单一来源）、DefaultClassService（班级）、kInnerTabRegistry（内层 tab + 漂移断言）。

### 4.3 渐进债务（发布后慢慢还）

| # | 债务 | 严重度 |
|---|------|--------|
| 1 | 🟢 **god-file**：courseware_workshop 3810 行 / knowledge_graph 3558 行 / courseware_service 2595 / database_helper 2220 / learning_hub 2219 | 🟢 低（可维护性，非正确性）|
| 2 | 🟢 **deprecated_member_use 58 处**：`value→initialValue`(34)、Matrix translate/scale(9)、Radio groupValue/onChanged(8)、Color red/green/password | 🟢 低（SDK churn）|
| 3 | 🟢 **Semantics 仅 2**：无障碍长期债 | 🟢 低 |
| 4 | 🟢 **catch(e){return null} 变体 4 处**：绕过 catch(_) 字面门禁的静默吞错残留 | 🟢 低 |
| 5 | 🟡 **analyze 涨幅门禁缺失**：CI 不拦 issue 数异常上涨（历史有 583→2462 先例）| 🟡 中 |

### 4.4 评分：**4.1 / 5**

0 error + CI 棘轮 + pre-commit guard + SSOT 是生产级工程纪律；god-file 与 deprecated 是真实但低危的可维护性债；**API key 硬编码本质是工程实践问题（凭证管理），是这一项无法给更高分的根因**。

---

## 五、视角 ④：AI 教学案例评委（创新性 / 完整度 / 可推广性）

### 5.1 评委可感知亮点

| 亮点 | 可感知度 |
|------|--------|
| **五端真构建**（Android/Win/Web/OHOS/iOS）+ Web 已公网上线（GitHub Pages）| 高 |
| **18 智能体 + 语音导航 + 数字孪生**：现场可演示自然语言导航、AI 批阅 | 高 |
| **15 轮三模型自审 + CI 门禁元方法论**：可讲"用工程纪律防债务反弹/事故重演"，方法论本身是案例素材 | 中高 |
| **0 编译错误 + analyze 525（演示跑 analyze 不翻车）** | 中 |

### 5.2 评委视角隐患

- **A/B 教学效果数据连续多轮空缺**——可推广性论证缺最有力的一环。
- **iOS 仅 CI 无签名编译验证**，真机 demo 需自备 Apple 账号 + 证书（文档已备齐路径）。
- **OHOS 仅真机**（arm64，模拟器 x86 不兼容），现场需带鸿蒙真机。
- ⚠️ 若评委审查源码会直接看到硬编码 key——**既是安全问题，也是评委眼中的"工程规范扣分项"**。

### 5.3 评分：**4.6 / 5**

完整度与创新可感知度高；A/B 缺失 + iOS/OHOS 演示门槛 + key 规范瑕疵对冲。

---

## 六、综合评分（发布前总评）

| 维度 | 分数 | 一句话 |
|------|------|--------|
| 教学完整度 | **4.95** | 五维闭环 + 幽灵根治 + 默认班级过滤 |
| AI / 智能体创新 | **4.85** | 18 矩阵 + RAG + 语音 + 数字孪生 |
| 跨平台工程 | **4.65** | 五端构建链齐备，iOS/OHOS 有演示门槛 |
| 代码质量 | **4.1** | 0 error + CI 棘轮纪律，扣分在 key 硬编码 + god-file |
| 案例化 | **4.6** | 自审方法论 + 公网上线，缺 A/B |
| **加权综合** | **≈ 4.72** | 成熟可发布，唯卡 key 红线 |

---

## 七、结构性评估

**无结构性 Problem。** 主干分层（models→dao→services→pages）、五端、18 Agent、归档策略、默认班级 SSOT、inner_tab 注册表、直播三层、CI 双门禁 + pre-commit guard 均稳固。项目在结构层面**已无可指摘的硬伤**。

唯一跨"结构/安全"边界的问题是 **API key 硬编码**——它不是架构缺陷（配置走 DB 的设计是对的），而是**默认值注入方式的实现失误**，修复成本低（改 3 处 + 吊销 key），但发布前必做。

---

## 八、发布前 Checklist（按优先级）

### 🔴 发布阻断（打 release 前必做）

- [ ] **DeepSeek 控制台吊销/轮换 `sk-717ef914…`**（泄露既成事实，必须作废旧 key）
- [ ] 源码 3 处（database_helper.dart:670/1725、ai_config_model.dart:30）改空值/占位，引导用户在设置页填入
- [ ] 验证：清除后默认无 key，首次进 AI 功能提示"请在设置中配置 API Key"，不崩溃

### 🟡 短期（发布后 1 周）

- [ ] CI 加 `flutter analyze` issue 数涨幅门禁（>50 即 fail，防 583→2462 重演）
- [ ] 4 处 `catch(e){return null}` 变体改 swallowDebug（堵 catch 门禁旁路）
- [ ] 10 个 warning 死代码清理（unused_*，纯净化，0 风险）

### 🟢 中长期

- [ ] 58 处 deprecated_member_use 批量迁移（`value→initialValue` 等）
- [ ] courseware_workshop / knowledge_graph god-file 拆分
- [ ] Semantics 无障碍覆盖
- [ ] A/B 教学效果数据采集

---

## 九、最终结论

> **MAD-KGDT v1.17.0 是一个可发布的成熟教学平台**，三个身份分别评定：
>
> - **作为教学产品 — 5 星**：教—学—练—评—管五维闭环、答辩名单幽灵学生根治、默认班级全局过滤一致、五端覆盖、Web 公网上线，课堂可直接用。
> - **作为生产级工程 — 4.1 星**：0 编译错误、CI 棘轮 + withOpacity 零容忍 + pre-commit guard 三重纪律、SSOT 贯穿；**扣分根因是 API key 硬编码（凭证管理失误）** + god-file/deprecated 低危债。
> - **作为 AI 教学案例 — 4.6 星**：18 智能体 + 数字孪生 + 15 轮自审方法论可讲；缺 A/B 量化与 iOS/OHOS 现场演示便利性。
>
> **发布放行条件（唯一硬卡口）**：**先吊销并清除已公网泄露的 DeepSeek API Key，再打 release。** 这是本轮总结审核唯一的 🔴 阻断项——其余皆为可发布后偿还的慢性债。
>
> **发布前总评：≈ 4.72 / 5，处理 key 红线后即可放行。**
>
> **元层面观察（发布前视角的特殊价值）**：逐轮审核盯的是"相对上一轮变好没有"，容易因为指标平稳（catch/withOpacity/analyze 都没动）而误判"没问题"。**但发布前总结审核换了个问法——"把它公开交付出去，最坏会发生什么"——立刻浮出一条 14 轮逐轮对比都没单独拎出来的红线：一个早已躺在公开仓库里的真实密钥。** 这印证了发布前必须做一次"非增量、面向最坏情况"的横切审计：**慢性债可以缓还，但"发布动作本身会放大的伤害"必须在按下发布键前清零。**

---

*报告完毕。本轮为发布前最终总结审核，不做跨轮对比。所有数字为 2026-06-01 实测（flutter analyze / git grep / git log / wc -l，HEAD @56987e81d）。唯一发布阻断项：DeepSeek API Key 公网泄露，须吊销 + 清除后放行。*
