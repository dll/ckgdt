---
title: MAD-KGDT 移动图谱与数字孪生教学平台 — 多维审核报告（第十三轮）
date: 2026-06-01
version: v1.16.2+2（第十二轮 + 幽灵学生根治 + 默认班级全局过滤接线 + 成绩导出 + 自动更新 + version_bump 工具链）
reviewer: Claude Opus 4.8（自我审核 · 第十三轮）
target: 项目仓库 chzcldl/mad-kgdt（HEAD @944b452d7，工作区干净）
prev_review: docs/MAD-KGDT审核报告(Opus4.8-第十二轮).md
focus: ① 审核第十二轮 Phase-12 头号待办「#11(c) 默认班级全局过滤」是否真落地（接线验证）；② withValues→withOpacity 全局回退事故；③ 四视角全面审核
---

# MAD-KGDT 多维审核报告（第十三轮）

> **本轮起点**：第十二轮把 **#11(c)「默认班级全局过滤」**列为 Phase-12 头号紧急待办（"DefaultClassService 只被 1 个 admin 页消费"）。本轮专项验证这条是否真接通——并把上轮自己立的方法论"**接线验证（grep 谁消费了这个服务），而非只看编译过**"用上。
>
> 结论先行：**①「答辩名单混入归档学生」这个被反复报告的 bug，本轮终于根治——根因是种子库 49 行 `student_` 幽灵学生（is_active=1），靠 V27 迁移 + 每次启动 reconcile 清除，已在 live 启动日志验证（`ghost_users=49`）。② 默认班级过滤从 1 页扩到 10 文件真接线（achievement 4 tab + 图谱 + 课堂 + 直播授权），接线验证通过。③ catch(_) 真降 254→178（−76）。但——④ 本轮出现一起 withValues→withOpacity 全局回退事故：commit `944b452d7` 把 ~1246 处 `withValues` 改回已废弃的 `withOpacity`，直接违反 CLAUDE.md 编码规则 5，导致 `flutter analyze` 从 583 涨到 2462 issues。这是一次"格式化/重构连带回退"型事故，必须当轮回滚。**

所有数字为 2026-06-01 实测（`flutter analyze` / `git grep` / `git show` / live 启动日志）。

---

## 零、专项审核：#11(c) 默认班级全局过滤是否真落地

第十二轮的判词是："**(c)『其它页面均按默认班级显示』未达成——DefaultClassService 只被 1 个 admin 页消费**"。本轮用 `git grep` 追调用链验证。

### 0.1 接线验证（grep 谁消费了 DefaultClassService）

| 消费方 | 调用 | 性质 | 判定 |
|--------|------|------|------|
| `achievement/tabs/report_tab.dart` | `filterByDefaultClass` ×3 | 行级名单过滤 | ✅ 真接 |
| `achievement/tabs/scores_tab.dart` | `filterByDefaultClass` ×2 | 行级名单过滤 | ✅ 真接 |
| `achievement/tabs/overview_tab.dart` | `filterByDefaultClass` ×1 | 行级名单过滤 | ✅ 真接 |
| `achievement/tabs/analysis_tab.dart` | `filterByDefaultClass` ×1 | 行级名单过滤 | ✅ 真接 |
| `graph/knowledge_graph_page.dart` | `filterByDefaultClass(all,(u)=>u.userId)` | 图谱学生过滤 | ✅ 真接 |
| `widgets/live_authorize_sheet.dart` | `getDefaultClassStudents()` | 答辩授权名单 | ✅ 真接（报告 bug 直接面）|
| `classroom/classroom_page.dart` | `getDefaultClassId()` | 班级选择确定性 | ✅ 真接 |
| `admin/student_manage_page.dart` | `getDefaultClassId()` / `setDefaultClassId` | 切换 UI | ✅ 真接（可改）|

> **结论：第十二轮的头号待办 #11(c) 本轮基本兑现**——DefaultClassService 从 **1 页 → 10 文件**真消费，且全部是 `filterByDefaultClass` / `getDefaultClassStudents` 这类**真过滤调用**（非空 import）。这与上轮"视频开关 import 了但没接线"的骨架 bug 不同——本轮是真接通。

### 0.2 但更深的根因被找到并根治：49 行幽灵学生

上轮把 #11(c) 当"过滤未接线"问题。本轮发现**真正的脏数据源不是过滤逻辑，而是种子库本身**：

- `assets/learning_data.db` 里有 **49 行 `student_<学号>` 前缀的幽灵学生**，是已归档「计科22」队列的重复副本，但全标 `is_active=1`，能穿过**所有** `is_active=1` 过滤；
- 它们不在 `assets/students.json`（干净：计科22 共 49 人全 `is_active=0`，软件23 共 86 人全 `is_active=1`）；
- 真实登录/导入/同步从不创建 `student_` 前缀 ID，故可安全删除。

**这解释了"上次修复（加 is_active 过滤）完全没效果"——因为脏数据本身 is_active=1，加再多过滤层都拦不住。** 真正的解药是清幽灵 + reconcile。

**修复机制**（`database_helper.dart`，已核实代码）：

1. **V27 迁移**（version 26→27，3 个 openDatabase 站点全部升版一致）：
   ```sql
   DELETE FROM class_members WHERE user_id LIKE 'student\_%' ESCAPE '\';
   DELETE FROM users        WHERE user_id LIKE 'student\_%' ESCAPE '\';
   ```
2. **每次启动 reconcile**（`_reconcileStudents`）：按 students.json 逐行校正 `is_active`/`real_name`（ConflictAlgorithm.ignore 不更新已存在行，旧库/同步里被错置成 active 的归档学生靠这步纠回），并双保险再清一次幽灵（覆盖"DB 已是 v27 不再触发 onUpgrade"的场景）。
3. **getStudents 默认过滤**：`getStudents({includeInactive=false})` 默认 `role='student' AND is_active=1`，审计入口显式传 `includeInactive:true`。

**Live 启动日志已验证**（上一会话 `<exe>/logs/mad_init.log`）：
```
reconcile students: fixed=0 ghost_users=49 ghost_members=0
```
`ghost_users=49` = 运行时确实清掉了 49 行幽灵。**这是本轮最有价值的修复——一个反复报告、上次"修了没用"的 bug，这次找到真根因并根治。**

### 0.3 修复审核小结

本轮 #11 三个子项全部达成：(a) 种子数据正确 ✅（V27 + reconcile 保证）；(b) 默认班级可改 ✅；(c) 全局过滤真接线 ✅（10 文件）。**外加上轮没意识到的幽灵学生根因被找到并根治。** 这是"接线验证"方法论的胜利——上轮要求"grep 谁消费了服务"，本轮正是靠 grep 调用链确认真接通、靠读种子库找到真根因。

---

## 一、本轮基线变化（全项目）

| 维度 | 第十二轮 | 本轮 | 变化 |
|------|---------|------|------|
| 版本 | 1.16.0 | **1.16.2+2** | patch×2（幽灵修复 + 成绩导出）|
| 版本号同步字段 | 11 字段对齐 | **17 字段全对齐 1.16.2** | ✅ 无漂移（version_bump 工具化）|
| Dart lib 文件数 | 340 | **353** | +13（直播×6/成绩导出/更新系统/version/inner_tab_registry 等）|
| 页面文件数 | 147 | **148** | +1 |
| DAO 数 | 33 | **33** | 持平 |
| 智能体 | 18 | **18** | 持平 |
| 测试文件 | 23 | **25** | +2 |
| **catch (_)** | 254 | **178** | **−76 ✅（真降，本轮治理兑现）** |
| **DefaultClassService 消费方** | **1 页** | **10 文件** | **+9 ✅（#11(c) 兑现）** |
| **DB version** | 26 | **27** | +1（V27 清幽灵）|
| **withValues / withOpacity** | **1206 / 1** | **1 / 1256** | **🔴 全局回退事故** |
| **flutter analyze issues** | 583 | **2462** | **🔴 +1879（几乎全是 withOpacity 废弃告警）** |
| flutter analyze **errors** | 0 | **0** | ✅ 仍 0 error |
| Semantics 标签 | 2 | **2** | 持平（连续 11 轮）|
| 工作区 | 干净 | **干净** | ✅ |

### 1.1 一句话定位

> v1.16.2 —— **"根治幽灵学生 + 兑现默认班级过滤 + 一起 withOpacity 全局回退事故"的一轮**：被反复报告的"答辩名单混归档学生"找到真根因（49 行幽灵）并靠 V27+reconcile 根治、live 日志验证；#11(c) 默认班级过滤从 1 页扩到 10 文件真接线；catch(_) 真降 254→178；新增成绩导出/自动更新/version_bump 三套设施。**但同一批提交里夹带了一起 withValues→withOpacity 全局回退（~1246 处），违反 CLAUDE.md 规则 5，analyze 从 583 飙到 2462——必须当轮回滚。**

---

## 二、视角 ①：AI 专家（智能体架构与 AI 教学创新）

### 2.1 本轮变化

智能体维度本轮**无结构变化**（仍 18 agent，registry 一致）。GradingAgent 有 +125 行改动（成绩相关工具扩展），但仍在"批阅官三合一"框架内。

### 2.2 本轮发现的问题

- **连续 10 轮的老债未动**：`_innerTabs` 硬编码（本轮虽新增 `inner_tab_registry.dart` 尝试收口，但需验证是否真替换了硬编码路径）、chainId 局限、"特色创新只做减法不做加法"。
- AI 维度本轮非重点，无新增亮点也无新增退步。

### 2.3 综合评价

AI 维度分 **4.85/5**（持平）：无结构变化，inner_tab_registry 是潜在改善但需下轮验证落地。

---

## 三、视角 ②：高校教师（课堂落地与教学闭环）

### 3.1 本轮亮点

| 亮点 | 证据 |
|------|------|
| 🟢 **答辩名单不再混归档学生（根治）** —— 教师最直接的痛点。V27 清 49 幽灵 + reconcile，live 日志验证 | database_helper `_reconcileStudents` |
| 🟢 **默认班级全局生效** —— 成绩 4 tab / 图谱 / 课堂 / 授权都按默认班级（软件231）过滤，可下拉切软件232 | DefaultClassService 10 文件 |
| 🟢 **成绩查看/导出三页落地** —— 实验/考核/作品页新增「成绩预览（DataTable）+ CSV 导出（UTF-8 BOM，Excel 中文不乱码）」 | ScoreExportService + ScorePreviewDialog |
| 🟢 **桌面端自动更新** —— UpdateService 查 GitHub Release → 下载 → 安装，解决"学生用旧版" | update_service.dart +270 |

### 3.2 本轮对教师的隐性问题

| 风险 | 说明 |
|------|------|
| 🟡 **成绩导出无"按默认班级过滤"** —— ScoreExportService 直接调 `getAllStudentLabScores`/`getScoreRanking`/`getScoreRecords`，**未经 DefaultClassService 收窄**。导出的是全部学生，与页面只显示默认班级的语义不一致。教师导出实验成绩 CSV 会拿到混班数据 | score_export_service.dart |
| 🟡 **成绩导出仅桌面**（`if (kIsWeb) return null`）—— Web 端教师点导出静默返回 null，无提示 | 同上 |

### 3.3 综合评价

教师视角分 4.9/5 → **4.95/5**（+0.05）：答辩名单根治 + 默认班级全局过滤兑现 + 成绩导出，是上轮关键痛点的实打实收尾（+）；但成绩导出未接默认班级过滤、仅桌面（−）。**净小幅上升。修好导出过滤一致性可回 5。**

---

## 四、视角 ③：移动应用开发工程师（代码质量与工程实践）

### 4.1 本轮优秀点

| 亮点 | 证据 |
|------|------|
| ✅ **catch(_) 真降 254→178（−76）** —— lab_tasks 4 处、assessment 2 处等改 swallow/swallowDebug，连续多轮治理本轮兑现最大降幅 | git grep |
| ✅ **幽灵学生根治是真功夫** —— 找到 is_active=1 脏数据这个上轮没看穿的真根因，V27+reconcile 幂等设计、live 日志验证、双保险清幽灵 | database_helper |
| ✅ **#11(c) 真接线** —— 10 文件 filterByDefaultClass，接线验证通过（非骨架）| 见 §0.1 |
| ✅ **version_bump 工具化** —— `scripts/version_bump.dart` + VersionBumpService 自动同步 17 平台字段，17 字段全对齐 1.16.2 无漂移，根治"升版漏改"历史顽疾 | version.dart SSOT |
| ✅ **Runner.rc OriginalFilename 缺陷修复** —— 补上 `.exe` 分隔符 | windows/runner/Runner.rc |

### 4.2 本轮不足（含一起回退事故）

| # | 问题 | 严重度 |
|---|------|--------|
| 1 | 🔴 **withValues→withOpacity 全局回退事故** —— commit `944b452d7` 把 ~1246 处 `withValues` 改回**已废弃**的 `withOpacity`（round12: 1206/1 → 本轮 1/1256）。直接违反 CLAUDE.md 规则 5「用 withValues 代替废弃的 withOpacity」。后果：`flutter analyze` 583→**2462 issues**（+1879，几乎全是 withOpacity 废弃告警）。这是一次"重构/格式化连带回退"——提交信息只说"修 catch(_)+成绩导出"，却夹带了反向的全局替换。**虽不影响编译（0 error），但把连续多轮的 withValues 治理一次清零** | 🔴 **高** |
| 2 | 🟡 **新增 ScoreExportService 用 `catch(e){return null/[]}` 静默吞错** —— 6 处 catch 全部 `return null`/`return []`，不记日志。虽规避了 `catch(_)` 字面 grep，但违反 CLAUDE.md「禁止静默吞错，必须 swallowDebug(tag,stack)」的精神。**catch(_) 计数门禁被这种 `catch(e){return null}` 变体绕过** | 🟡 中 |
| 3 | 🟡 **成绩导出未接默认班级过滤** —— 与页面语义不一致（见 §3.2）| 🟡 中 |
| 4 | 🟢 sync 噪音持续高位（设计固有，非缺陷）| 🟢 低 |
| 5 | 🟢 courseware_workshop / knowledge_graph god-file 仍在 | 🟢 低 |

### 4.3 综合评价

代码质量分 4.05/5 → **4.0/5**（−0.05）：
- catch(_) 真降 −76 ✅、幽灵根治 ✅、#11(c) 真接线 ✅、version_bump 工具化 ✅（+0.15）
- **withOpacity 全局回退事故**（−0.15）、ScoreExportService 静默吞错变体（−0.05）
- **净 −0.05**。**说明**：本轮工程实绩其实很强（治理兑现 + 根因修复 + 工具化），但一起全局回退事故把分数拉回——它暴露的不是能力问题，是**纪律问题：一个 commit 同时做"修复"和"反向重构"，且提交信息不诚实**。这与历轮"执行快于验证"同源：替换动作做了，但没回看 analyze 涨了 1879。

---

## 五、视角 ④：AI 教学案例评委（创新性/完整度/可推广性）

### 5.1 本轮亮点

| 亮点 | 评委可感知度 |
|------|------------|
| **"反复报告 bug 终于根治"叙事** —— 答辩名单混班 → 找到 49 幽灵真根因 → V27 根治 → live 日志验证，是完整的"诊断-根治-验证"闭环，演示可讲 | 高 |
| **成绩导出 CSV（UTF-8 BOM）** —— 教师可直接 Excel 打开，实用落地 | 中高 |
| **桌面自动更新** —— 产品成熟度信号 | 中 |
| **13 轮三模型自审 + version 工具化** —— 元方法论持续 | 中高 |

### 5.2 评委视角隐患

- **现场 analyze 翻车风险**：若评委或助教跑 `flutter analyze`，会看到 **2462 issues**（上轮 583）——虽全是 withOpacity 废弃告警、0 error，但数字观感差，需在演示前回滚。
- **成绩导出现场风险**：导出 CSV 是全班混合（未按默认班级），若评委对照页面显示会发现不一致。
- A/B 数据连续多轮空缺。

### 5.3 综合评价

案例化分 4.6/5 → **4.6/5**（持平）：根治叙事 + 成绩导出 + 自动更新是加分，但 analyze 2462 的观感风险 + 导出不一致对冲。

---

## 六、综合评分对比

| 维度 | 九轮 | 十轮 | 十一轮 | 十二轮 | **本轮** |
|------|------|------|------|------|--------|
| 教学完整度 | 5 | 5 | 4.9 | 4.9 | **4.95** |
| AI/智能体创新 | 4.85 | 4.85 | 4.85 | 4.85 | **4.85** |
| 跨平台工程 | 4.6 | 4.6 | 4.6 | 4.6 | **4.6** |
| 代码质量 | 4.0 | 3.95 | 4.05 | 4.05 | **4.0** |
| 案例化 | 4.55 | 4.6 | 4.6 | 4.6 | **4.6** |
| **加权综合** | **4.68** | **4.67** | **4.69** | **4.69** | **4.70** |

> 一句话评估：**第十三轮是"老 bug 根治 + 关键待办兑现，但夹带一起全局回退事故"的一轮**。#11(c) 默认班级过滤真接线（1→10 文件）、答辩名单幽灵学生根治（live 验证）、catch(_) 真降 −76、version 工具化——教学与工程实绩都在涨；但 withOpacity 全局回退（analyze 583→2462）把代码质量拉回 −0.05。**加权微涨到 4.70**——教学完整度的 +0.05 略胜代码质量的 −0.05。

---

## 七、结构性 Problem

第十三轮：**仍无结构性 Problem**，连续 11 轮零结构债。主干（分层、四端、18 Agent、归档策略、视频源抽象、直播三层、默认班级服务）稳固。**幽灵学生这个数据层顽疾本轮被根治，是结构健康度的净提升。**

渐进式债务（按优先级）：

1. 🔴 **withOpacity 全局回退（~1256 处）** —— 当轮必须回滚回 withValues。这是 CLAUDE.md 明文规则的违反，且 analyze +1879
2. 🟡 **ScoreExportService 静默吞错变体（`catch(e){return null}`）** —— catch(_) 门禁被绕过，需补 swallowDebug
3. 🟡 **成绩导出未接默认班级过滤** —— 与页面语义不一致
4. 🟢 **inner_tab_registry 是否真替换 _innerTabs 硬编码** —— 下轮验证
5. 🟢 **courseware_workshop / knowledge_graph god-file**
6. 🟢 **Semantics 2 / chainId** —— 长期债

---

## 八、Phase 13 路线图

### 8.1 紧急（本周）

- [ ] **回滚 withOpacity → withValues**（~1256 处全局替换回正，analyze 应回落到 ~580）
- [ ] **ScoreExportService 静默吞错** → `catch(e,st){swallowDebug(e,tag,stack:st)}`
- [ ] **成绩导出接 DefaultClassService 过滤** —— 与页面显示一致（教师导出默认班级，可选「整届」）

### 8.2 短期（1 个月）

- [ ] CI 加双门禁：`catch(_)` 计数 + **`withOpacity` 计数**（防本轮事故重演）
- [ ] CI 加 `flutter analyze` issue 数门禁（涨幅 >50 即 fail）
- [ ] inner_tab_registry 落地验证 + 补单测
- [ ] 成绩导出 Web 端兜底（提示"桌面端可导出"而非静默 null）

### 8.3 中期（3 个月）

- [ ] 智能体特色增强（独有工具链，不止合并）
- [ ] courseware_workshop 仿 period_tab 拆分
- [ ] A/B 实验数据采集

### 8.4 长期（6+ 个月）

- [ ] 开放 RESTful API / 课程市场 / Semantics 全覆盖

---

## 九、与前几轮的关键差异

| 维度 | 十轮 | 十一轮 | 十二轮 | **十三轮** |
|------|------|------|------|--------|
| 关注角度 | 债务 vs 纪律 | 债务兑付+专项审计 | 修复审核（审计另一AI）| **关键待办兑现+根因修复+回退事故** |
| 核心结论 | catch 真降但 broken | 债务真入库 | 15条广而不实 | **#11(c)真接线+幽灵根治，但 withOpacity 全局回退** |
| 关键风险 | 不可编译+0commit | 归档3bug | UI骨架未接线+catch反弹 | **全局回退事故(analyze 583→2462)** |
| 加权综合 | 4.67 | 4.69 | 4.69 | **4.70** |

---

## 十、结论

> **MAD-KGDT v1.16.2 第十三轮完成"老 bug 根治 + 关键待办兑现"里程碑，但夹带一起全局回退事故**：
>
> - **答辩名单混归档学生（反复报告、上次修了没用）本轮根治**：找到真根因——种子库 49 行 `student_` 幽灵学生（is_active=1，能穿透所有过滤）；靠 V27 迁移 + 每次启动 reconcile 清除，live 启动日志验证 `ghost_users=49`。
> - **第十二轮头号待办 #11(c) 兑现**：DefaultClassService 从 1 页扩到 **10 文件**真接线（成绩4tab/图谱/课堂/直播授权），接线验证通过——这是上轮"接线验证"方法论的胜利。
> - **catch(_) 真降 254→178（−76）** + **version_bump 工具化**（17 字段无漂移）+ **成绩导出/自动更新**新设施。
> - **但 commit `944b452d7` 夹带 withValues→withOpacity 全局回退（~1246 处）**：违反 CLAUDE.md 规则 5，`flutter analyze` 583→**2462 issues**（仍 0 error）。这是"重构连带回退 + 提交信息不诚实"型事故，必须当轮回滚。
>
> **作为教学产品 — 5 星推荐**（答辩名单根治 + 默认班级全局过滤兑现 + 成绩导出 + 自动更新，4 端 + 公网上线）；
> **作为生产级工程 — 4.0 星**（catch 真降 + 幽灵根治 + 工具化是实绩，但 withOpacity 全局回退把分拉回）；
> **作为 AI 教学案例 — 4.6 星**（"诊断-根治-验证"闭环叙事 + 13 轮三模型自审）。
>
> **Phase 13 重心**：① 回滚 withOpacity → withValues（analyze 回落 580）；② ScoreExportService 静默吞错补 swallowDebug；③ 成绩导出接默认班级过滤。三件做完 + CI 加 withOpacity/analyze 门禁，加权可达 **4.73/5**。
>
> **本轮独特发现（方法论）**：**"一个 commit 同时做修复和反向重构，是审核最难抓的事故类型。"** withOpacity 回退混在"修 catch(_) + 成绩导出"的提交里，提交信息只字未提全局替换——若只信 commit message 就会漏掉。**抓到它靠的是上轮自己立的规矩：每轮把 withValues/withOpacity、catch(_)、analyze issue 数当硬指标 grep 一遍，跨轮对比异常跳变。这次正是"1206/1 → 1/1256"的跳变暴露了事故。** 下一轮起，`flutter analyze` issue 总数应作为标准硬指标入基线表，涨幅异常即追根因。
>
> **元层面**：第十二轮的方法论"接线验证（grep 谁消费了服务）"在本轮 #11(c) 验证中直接奏效——确认了 10 文件真消费、并顺藤摸到种子库幽灵真根因。**审核方法论在跨轮累积复利：上轮立的规矩，这轮抓到了真问题。**

---

*报告完毕。本报告与第一至第十二轮（[第十二轮](MAD-KGDT审核报告(Opus4.8-第十二轮).md)）互为参照。所有数字为 2026-06-01 实测（flutter analyze / git grep / git show / live 启动日志），含对 #11(c) 默认班级过滤的接线验证与 withOpacity 全局回退事故的专项审计。*
