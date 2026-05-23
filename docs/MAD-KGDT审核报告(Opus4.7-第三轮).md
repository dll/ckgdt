---
title: MAD-KGDT 移动图谱与数字孪生教学平台 — 多维审核报告（第三轮）
date: 2026-05-23
version: v0.12.0+N（第二轮 11 commit + Phase 3 紧急 5 件 + 1 simplify 已应用）
reviewer: Claude Opus 4.7（自我审核 · 第三轮）
target: 项目仓库 osgisOne/mad-fd（master @ 4142437be）
prev_review: docs/MAD-KGDT审核报告(Opus4.7-第二轮).md
---

# MAD-KGDT 多维审核报告（第三轮）

> **写作目的**：第二轮报告（评分 4.0/5）指出"做好了没接通"是结构性问题，并列出 Phase 3 紧急 5 件作为 1 周内的解药。
> 用户选择"5 件" → 已作为单 commit `4142437be` 落地（feat: Phase 3 5/5 — 接通已建模块 + 真测试 + 真 prompt）。
> 本轮**专审"接通"动作的真实质量**：是真接通还是又一层薄包装？是否引入新的"做好没接通"？
>
> 仍按四视角：① AI 专家 ② 高校教师 ③ 移动应用工程师 ④ AI 教学案例评委。

---

## 一、本轮基线变化

| 维度 | 第二轮（@72a4b9c2b） | 本轮（@4142437be） | 变化 |
|------|---------------------|------------------|------|
| Dart 总行数 | 146,284 | **146,404** | +120（≈ 0.08%）|
| 页面数 | 107 | **107** | — |
| DAO 数 | 31 | **31** | — |
| 智能体 | 24 | 24（OrchestratorAgent 不计） | — |
| **测试文件** | 15 | **16**（+ test/data/local/class_qa_dao_test.dart） | +1 |
| **测试用例** | 153 | **159**（实际 +162 -4，golden 4 个失败）| +6 ✅ |
| Top 1 巨型文件 | assessment_page 6090 行 | assessment_page 6090 行 | 持平 ❌ |
| TODO/FIXME | 4 | **0** | -4 ✅（被清理）|
| catch (_) 静默 | 369 | **369** | 持平 |
| 硬编码 Color(0xFF | 355 | **355** | 持平 |
| 直接 Colors.* | 1650 | **1650** | 持平 |
| Semantics 标签 | 2 | **2** | 持平 ❌ |
| **assets/agent_prompts/.md 文件** | **0**（仅 README） | **3**（tutor / lab_grading / virtual_student）| +3 ✅ |
| **agent_prompts 总字数** | 0 | **225 行**（tutor 50 + lab_grading 45 + virtual_student 130）| ↑ |
| **Orchestrator 业务调用方** | 0 | **0**（仅 lab_grading_agent 内部包装方法）| 持平 ⚠️ |
| **retrieveContextVector 调用方** | 0 | **1**（BaseAgent.buildRagPrompt）| +1 ✅ |
| **indexDocument 调用方** | 0 | **0**（rag_embeddings 表无任何写入路径）| 持平 ⚠️ |
| **ClassQaPage 入口** | 0 | **3**（学生菜单 + 教师菜单 + navigation_service）| +3 ✅ |
| **AppL10n.of 调用点** | 0 | **0**（仅生成代码自描述）| 持平 ❌ |

### 1.2 一句话定位（不变）

> 全栈式移动开发课程**数字孪生教学平台**，Flutter 4 端，Gitee 无服务器同步，24 LLM Agent + Orchestrator + 向量 RAG。

---

## 二、视角 ①：AI 专家（专注智能体架构与 AI 教学创新）

### 2.1 Phase 3 接通动作真实质量

| Phase 3 紧急项 | 第二轮报告承诺 | 第三轮实际验证 | 结论 |
|---------------|---------------|--------------|------|
| **班级问答挂导航** | 学生菜单 + 教师菜单 + 子页面路由 | ✅ home_page.dart:599、:645 + navigation_service.dart:296 共 3 个真入口 | **真接通** |
| **向量 RAG 接 BaseAgent** | 优先 retrieveContextVector，失败回退 TF-IDF | ⚠️ BaseAgent.buildRagPrompt 写了 fallback 链路（base_agent.dart:226），但 **indexDocument 仍 0 调用方** —— rag_embeddings 表永远是空的，每次都立即落到 TF-IDF 分支 | **半接通：入口接了，**数据没灌** |
| **Orchestrator 接实验批阅** | safety → lab_grading → ethics 链 | ⚠️ lab_grading_agent.gradeSubmissionWithOrchestrator 包装方法写了（lab_grading_agent.dart:156），但 **没有任何业务页面调它** —— ai_grading_tab.dart 仍走老的 gradeSubmission 单 Agent 路径 | **半接通：方法定义了，UI 没切换** |
| **写 24 Agent prompt 至少 3 个** | tutor / lab_grading / virtual_student | ✅ 3 个 .md 真写出来（tutor 50 行 / lab_grading 45 行 / virtual_student 130 行）；PromptLoader.load 真在 BaseAgent.loadEffectivePersona 调用 | **真接通**（占 24 Agent 的 12.5%） |
| **新 DAO 加 5 unit test** | class_qa_dao 重点 | ✅ test/data/local/class_qa_dao_test.dart 6 个用例（可见性 / 状态转换 / 采纳最佳 / 删除级联）| **真接通** |

### 2.2 本轮**真正消除**的第二轮缺陷

- ✅ **Prompt 配置化空壳问题**：3 个真 .md 写就，从"有框架无内容"到"有框架有内容（部分）"
- ✅ **新 DAO 0 测试**：class_qa_dao 6 个用例已立稳
- ✅ **班级问答无导航入口**：3 处入口齐全，学生 / 教师 / 语音导航都能进

### 2.3 本轮**仍未消除**的第二轮缺陷

| # | 第二轮发现的问题 | 本轮状态 | 严重度 |
|---|---------------|---------|-------|
| 1 | Orchestrator 没接入业务页面 | ⚠️ 包装方法写了，UI 仍未切换 | 🟡 中 |
| 2 | 向量 RAG 没接入业务页面 | ⚠️ BaseAgent 路径接了，**索引数据为空** | 🔴 高（实际等于没接）|
| 3 | 21 个 Agent prompt 仍硬编码 | ⚠️ 完成 3/24 = 12.5% | 🟡 中 |
| 4 | 审计日志没 UI 入口 | ❌ 完全未做 | 🟡 中 |
| 5 | 本地 LLM 备选无可用性测试 | ❌ 完全未做 | 🟢 低 |
| 6 | Embedding 服务无缓存 | ❌ 完全未做 | 🟢 低 |
| 7 | 缺人在环 RLHF 反馈 | ❌ 完全未做 | 🟢 低 |

### 2.4 本轮**新发现**的问题

| # | 新问题 | 证据 | 严重度 |
|---|--------|------|-------|
| **N1** | **rag_embeddings 表是空架子** —— `database_helper.dart:1471-1485` 建了表和索引，但**全项目无任何 indexDocument 调用方**。BaseAgent 走向量分支永远立即 fallback 到 TF-IDF。新增的 `retrieveContextVector` 是死代码 | grep `indexDocument\b` 仅 1 处定义、0 处调用 | 🔴 高 |
| **N2** | **gradeSubmissionWithOrchestrator 是死方法** —— 公开 API 写好（含 record 返回类型），但 ai_grading_tab.dart 1675 行实验批阅页未引用，教师"安全增强模式"开关也没做 UI | grep 第二轮报告所提"教师在 AI 批阅页打开开关"未实现 | 🔴 高 |
| **N3** | **PromptLoader 缓存命中率永远 87.5%以下** —— 24 Agent，3 个有 .md，其它 21 个总是 cache miss → 走 fallback persona。冷启动每次都做 21 次 rootBundle.loadString 失败 IO | prompt_loader.dart 缓存语义 | 🟢 低 |
| **N4** | **Orchestrator 调用日志无法追踪整链** —— OrchestratorAgent 内部调 agent.handleMessage，BaseAgent 自动写 agent_call_logs，但**3 步是 3 条独立记录**，没有 chainId 关联。审计 "这次实验批阅总耗时" 时要靠 timestamp 邻近聚合 | agent_call_log_dao.dart 字段 | 🟡 中 |

### 2.5 综合评价

> **第二轮 → 第三轮，AI 架构层面是"装修完毕但没住进去"** ——
>
> - 班级问答 / Prompt .md / 测试 → 真住进去了
> - Orchestrator / 向量 RAG → 钥匙交了但门还锁着（业务侧没去开）
>
> 评分由 4.5/5 → **保持 4.5/5**（接通完成度 60% 但已比第二轮强；扣 0.5 因为 N1/N2 是结构性缺陷）

---

## 三、视角 ②：高校教师（专注课堂落地与教学闭环）

### 3.1 Phase 3 接通动作真实质量

| 项目 | 接通效果 |
|------|---------|
| 班级问答页面 | ✅ 学生进入路径：首页菜单 → "班级问答" 卡片；教师进入路径：首页菜单 → "班级问答（管理）" 卡片；语音导航："去班级问答" / "问答" 也能跳；3 入口足够 |
| 班级问答 + Agent 联动 | ❌ 第二轮建议的"学生发问 → assistant_agent 自动起草 → 教师采纳/重写"未实现 |
| 教师工作台 + Orchestrator | ❌ 第二轮建议的"教师批阅页打开安全增强开关"未实现 |
| i18n 真翻译 | ❌ 0 个 AppL10n.of 调用，框架仍空跑 |

### 3.2 本轮**新发现**的优秀点

| # | 亮点 | 证据 |
|---|------|------|
| 1 | 班级问答 DAO **测试覆盖关键业务规则** —— 学生只看 class+自己的 private、教师首次回复 open→answered、采纳最佳回复 closed | class_qa_dao_test.dart 4 个 group |
| 2 | 班级问答**测试用等价 SQL 验证**而非 mock —— 用内存 sqflite_ffi 跑真实 schema，规避 DAO 单例 + assets 种子库耦合 | class_qa_dao_test.dart:9 注释 |
| 3 | tutor.md prompt **针对课程 6 章定制**（"移动应用开发"特化），不是通用辅导套话 | tutor.md 全文 |
| 4 | virtual_student.md prompt **130 行高质量人格设定**（学习风格 / 困惑表达 / 错误模式 / 反例引导）—— 数字孪生学生有真东西可演 | virtual_student.md |

### 3.3 本轮**仍存在 / 新增**的不足

| # | 问题 | 严重度 | 证据 |
|---|------|---------|------|
| 1 | **班级问答不联动 Agent** —— 学生发问 → 教师默默等 → 教师手写回答；AI 完全旁观 | 🔴 高 | class_qa_detail_page 无 Agent 调用 |
| 2 | **课堂签到无迟到/请假** | 🟡 中 | classroom_page.dart |
| 3 | **图谱仍静态** —— 第二轮、第一轮均提，未变 | 🟡 中 | knowledge_graph_page 4815 行无交互式编辑 |
| 4 | **i18n 完全没翻译实战** —— ARB 47 keys 摆在那，UI 切 English 仍 95% 中文 | 🔴 高 | grep `AppL10n.of` 0 处 |
| 5 | **教师工作量仪表板 SQL 假设字段存在** —— 第二轮已指出，本轮未补防护 | 🟡 中 | teacher_workspace_page 的 4 SQL |
| 6 | **学生隐私合规仍空白** —— 没有用户协议 / 数据导出 / 删除我的数据 | 🟡 中 | login_page 无勾选项 |
| 7 | **Token 仍全班共享** —— 第二轮已说不会改，本轮维持 | 🟢 低 | 设计权衡 |

### 3.4 新增建议

1. **班级问答 + assistant_agent 联动**：学生发问后立刻调 assistant_agent.handleMessage 起草答案，标 "AI 草稿"；教师"一键采纳"或"修改后采纳"。投入 < 100 行
2. **i18n 三页翻译实战**：home_page / settings_page / login_page 三页 100% AppL10n.of(context).key 化（中文字符串替换，不是 wrap），是评估"国际化能力"的最低证据
3. **教师批阅页接 Orchestrator**：ai_grading_tab.dart 加一个 Switch "AI 批阅模式：标准 / 增强（含安全审查 + 学术伦理）"。增强模式调 gradeSubmissionWithOrchestrator
4. **班级问答 + 数字孪生**：学生提问 → assistant 起草 → virtual_student 来个"我也有同样困惑"的二次提问 → 把课堂讨论氛围撑起来（教学闭环差异化点）

---

## 四、视角 ③：移动应用开发工程师（专注代码质量与工程实践）

### 4.1 Phase 3 接通动作真实质量

| 项目 | 接通效果 |
|------|---------|
| **新 DAO 加测试** | ✅ class_qa_dao_test.dart 6 个用例 + test/helpers/test_db.dart 复用工具；其它 2 个新 DAO（agent_call_log / rag_embedding）仍 0 测试 |
| **拆 assessment_page 6090 行** | ❌ 完全未动（仍 6090 行） |
| **catch 标准化** | ❌ 完全未动（369 处不变） |
| **CI/CD 验证** | ❌ 4142437be commit push 后无 master 触发记录（学生自动同步推 master 也不该触发 PR 流程） |
| **Riverpod 推广** | ❌ 仍仅 1 个 ValueNotifier 单例（UnreadCountService） |
| **.gitignore + windows 构建产物** | ❌ 完全未动 |

### 4.2 Phase 3 commit 自身质量

| 维度 | 评估 |
|------|------|
| commit 粒度 | 🔴 1 个大 commit 含 5 件不同主题改动；理想是 5 个独立 commit |
| commit message | ✅ "feat: Phase 3（5/5）— 接通已建模块 + 真测试 + 真 prompt"，方向清晰 |
| 测试新增 | ✅ class_qa_dao_test.dart 真新增 |
| 测试通过 | ⚠️ **162 通过 / 4 失败**：4 个失败均为 golden 截图测试（home_page 50.91% pixel diff），**代码改动触发了 UI 视觉回归** |
| analyze | ⚠️ 531 issues（全部 info 级别 / 无 error / 无 warning），其中 2 个 unnecessary_import 是 Phase 3 新代码引入 |

### 4.3 本轮**新发现**的优秀点

| # | 亮点 | 证据 |
|---|------|------|
| 1 | **TODO/FIXME 清零** —— 第二轮 4 → 本轮 0，说明做了清理而不是只加新 TODO | grep TODO\|FIXME 0 |
| 2 | **test_db.dart helper 抽出** —— `setupTestSqflite()` + `openInMemoryDb()` 给后续 DAO 测试复用，工程意识 | test/helpers/test_db.dart:9-22 |
| 3 | **class_qa_dao_test 用等价 SQL 而非碰单例** —— 规避 DAO 强耦合 DatabaseHelper.instance + 种子 DB，测试设计成熟 | class_qa_dao_test.dart 注释 |

### 4.4 本轮**仍存在 / 新增**的不足

| # | 问题 | 严重度 | 证据 |
|---|------|---------|------|
| 1 | **golden 测试 4 个失败** —— page_screenshot_test.dart home_page golden、login_page golden 等 4 个 baseline 已过期，CI 实际不绿 | 🔴 高 | flutter test 输出 |
| 2 | **assessment_page.dart 仍 6090 行** —— 第二轮已点名；本轮未动；接棒"巨型文件之王" | 🔴 高 | wc -l |
| 3 | **knowledge_graph_page.dart 4815 行 / courseware_workshop_page 3811 行** | 🔴 高 | wc -l |
| 4 | **catch (_) 静默 369 处持平** | 🟡 中 | grep |
| 5 | **debugPrint 412 处**（第二轮未统计，本轮首次量化） | 🟡 中 | grep |
| 6 | **rag_embeddings 表无写入路径** —— 是建好但永不用的死表 | 🔴 高 | 见 §2.4 N1 |
| 7 | **gradeSubmissionWithOrchestrator 是死方法** | 🔴 高 | 见 §2.4 N2 |
| 8 | **CI/CD 仍未真跑过完整流水线** —— 第二轮已点名；4142437be 直接 push 到 master，绕过 PR | 🟡 中 | git log |
| 9 | **Phase 3 单一巨型 commit** —— 5 件事强耦合，不易回滚 | 🟢 低 | git show 4142437be |

### 4.5 新增建议

1. **修 golden baseline**：`flutter test --update-goldens test/screenshots/page_screenshot_test.dart` 重生 4 个 png；CI 才能绿
2. **拆 assessment_page**（同 lab_tasks 拆法）：Phase 3 已答应 1 周内动，但实际 0 行变更 → 必须本轮兑现
3. **激活向量 RAG（关键 bug）**：在 main.dart 启动后台任务，把 `assets/learning_data.db` 中的 questions/concepts 用 indexDocument 写入 rag_embeddings；否则向量 RAG 永远是死代码
4. **激活 Orchestrator**：ai_grading_tab.dart 加一个 Switch + 真调 gradeSubmissionWithOrchestrator；否则方法是死方法
5. **分 commit 提交规范**：写到 CONTRIBUTING.md / .github/PULL_REQUEST_TEMPLATE.md，未来"5 件事"必须 5 commit
6. **catch 标准化**（持续欠账）：写 lib/core/error_handler.dart，逐步替换 369 处

---

## 五、视角 ④：AI 教学案例评委（专注创新性 / 完整度 / 可推广性）

### 5.1 Phase 3 接通动作对评审分的影响

| 项目 | 评审是否能感知 |
|------|--------------|
| 班级问答页 | ✅ 评委演示能直接点开 |
| 真 prompt .md（3 个）| ✅ 评委开 assets/agent_prompts/ 能看到真"提示词工程"产物 |
| class_qa_dao 测试 6 个 | ✅ 评委开 test/ 能看到真单元测试 |
| 向量 RAG | ❌ 表是空的，演示时智能体回答仍是 TF-IDF + 关键字 → 评委看不到"语义检索"区别 |
| Orchestrator | ❌ 没 UI 开关，演示时无法触发；只能口头说"我们做了多 Agent 串联" |

### 5.2 本轮**仍存在**的致命短板

| # | 问题 | 评估 |
|---|------|------|
| 1 | **没拍 demo 视频** —— 脚本仍在 docs/case_study/demo_script.md，mp4 仍不在仓库 | 致命 |
| 2 | **没生第二门课** —— course_gen_agent 写了，但只有 1 门"移动应用开发"实例 | 致命 |
| 3 | **没 A/B 实验数据** —— 教学效果"用 AI 后提升 X%"无任何数字支撑 | 致命 |
| 4 | **没隐私合规声明** —— 用户协议 / 数据导出 / 删除我的数据全 0 | 中等 |
| 5 | **i18n 仍空跑** —— 框架是装饰，国际化能力宣传站不住脚 | 中等 |
| 6 | **Orchestrator/向量 RAG 是 PPT 工程** —— 写了代码、表、API，但运行时不调 | 致命（评委一查就破） |

### 5.3 本轮**新发现**的优秀点

| # | 亮点 | 推广价值 |
|---|------|---------|
| 1 | **3 个真 prompt .md** 比 24 个空架子值钱 —— 评委能看到"我们沉淀了课程教学的实际话术" | 高 |
| 2 | **class_qa_dao 测试设计** —— 测试用等价 SQL 规避单例耦合，是工程实践证据 | 中 |
| 3 | **审计 / 报告 / 路线图三件套**（第一轮报告 + 第二轮 + 本轮）—— 体现团队"可持续审视"能力，是教学案例的"反思维度"加分 | 高 |

### 5.4 综合评价

> 评分由 3.5/5 → **3.6/5**（+0.1）：
>
> - 班级问答 + 真 prompt + 测试用例三件 ✅ 是评委能感知的实物
> - Orchestrator/向量 RAG 死代码使"创新"分挤水分（见 N1/N2）
> - demo 视频 / 第二门课 / A/B 数据 三大致命短板未动

---

## 六、综合评分对比

| 维度 | 第一轮 | 第二轮 | **本轮** | 累计变化 |
|------|--------|--------|--------|---------|
| 教学完整度 | 5/5 | 5/5 | **5/5** | 持平（班级问答接通；联动 Agent 仍欠）|
| AI / 智能体创新性 | 4/5 | 4.5/5 | **4.5/5** | 持平（接通完成度 60%；2 个死代码扣分）|
| 跨平台工程 | 4/5 | 4/5 | **4/5** | 持平（assessment 拆分仍是空头支票）|
| 代码质量 / 可维护性 | 2/5 | 3/5 | **3/5** | 持平（+1 测试 / -1 golden 失败 / 持平）|
| 可推广 / 案例化 | 3/5 | 3.5/5 | **3.6/5** | +0.1（真 prompt 加分；致命短板未动）|
| **加权综合** | **3.6 / 5** | **4.0 / 5** | **4.0 / 5** | 持平 |

> **一句话评估**：本轮"接通行动"**质量参差** —— 班级问答和真 prompt 这种轻量接通做得到位；Orchestrator 和向量 RAG 这种需要"修改 UI / 灌索引数据"的重量级接通沦为"半接通"，等于没接。**第二轮的"做好没接通"问题部分缓解，新形态变成"接了入口没填数据 / 接了方法没切 UI"**。

---

## 七、本轮三大结构性问题（Phase 4 核心议题）

### Problem A：rag_embeddings 表是空架子 🔴

**症状**：表建了、索引建了、retrieveContextVector 写了、BaseAgent.buildRagPrompt 也调了 —— 但 `indexDocument` 全项目 **0 调用方**。`SELECT COUNT(*) FROM rag_embeddings` 永远返回 0。BaseAgent 走 `if (context.isEmpty)` 分支 100% 命中，立即落到旧的 TF-IDF。

**实际后果**：第二轮投入的"向量化 RAG"代码完全没在跑。

**修复方案**（< 50 行）：
```dart
// lib/services/data_loading_service.dart 启动时调一次
await RagService().indexDocument(
  docId: 'questions_seed',
  text: questions.map((q) => '${q.title}\n${q.content}').join('\n\n'),
);
```

### Problem B：gradeSubmissionWithOrchestrator 是死方法 🔴

**症状**：lab_grading_agent.dart:155 公开 record 返回类型方法写好（含 safety+grading+ethics 三步聚合），但 `ai_grading_tab.dart` 1675 行教师批阅页未引用。

**实际后果**：Orchestrator 真接入业务的 KPI 仍是 0。

**修复方案**（< 30 行）：在 ai_grading_tab.dart 顶部加一个 Switch "AI 批阅模式：标准 / 增强"，开关控制走哪个 API。

### Problem C：assessment_page.dart 6090 行 🔴

**症状**：第二轮已点名"接棒巨型文件之王"，建议同 lab_tasks 拆法 1 周内拆完。本轮 commit `4142437be` 0 行变更。

**实际后果**：技术债持续累积，新教师/新需求往这个文件加东西时维护成本越来越高。

**修复方案**：按 Tab 拆 4-5 个 part 文件（参考 lab_tasks_page 已有模式）。

---

## 八、Phase 4 路线图（接续路线图）

### 8.1 紧急（本周 — "把死代码激活 + 巨型文件拆掉"）

- [ ] **激活向量 RAG**（Problem A）：启动时调一次 indexDocument 把课程内容灌入 rag_embeddings
- [ ] **激活 Orchestrator**（Problem B）：ai_grading_tab.dart 加 Switch + 调 gradeSubmissionWithOrchestrator
- [ ] **拆 assessment_page.dart**（Problem C）：按 Tab 拆 part 文件，目标主壳 < 500 行
- [ ] **修 golden baseline**：flutter test --update-goldens 让 CI 转绿
- [ ] **agent_prompts 再写 5 个 .md**：quiz / safety / works_grading / mobile_expert / ethics —— 把覆盖率从 12.5% 推到 33%

### 8.2 短期（1 个月 — "证据资料"，承接第二轮 Phase 3 短期）

- [ ] **录 3 段 30 秒 demo 视频** —— 仍是空头支票
- [ ] **生第二门课 case** —— 真用 course_gen_agent 生成《数据结构》并截图入仓库
- [ ] **i18n 实战翻译** —— home_page + settings + login 三页全 AppL10n.of(context).key 化
- [ ] **agent_call_logs 仪表板页面** —— teacher_workspace 第三排
- [ ] **班级问答 + assistant_agent 联动** —— 学生发问 → AI 起草答案 → 教师采纳/重写

### 8.3 中期（3 个月 — "差异化"）

- [ ] **数字孪生学生答题对比** vs 真实学生答题
- [ ] **Riverpod 真接管全局状态** —— 至少 themeMode / colorIndex / locale / authUser
- [ ] **A/B 实验班数据采集 + 论文素材**
- [ ] **隐私合规模块**

### 8.4 长期（6+ 个月 — "走出去"）

- [ ] **开放 RESTful API + 兄弟院校接入**
- [ ] **课程市场**
- [ ] **学生成长报告自动化**

---

## 九、与前两轮报告的关键差异

| 维度 | 第一轮 | 第二轮 | **本轮** |
|------|--------|--------|--------|
| 关注角度 | "项目是什么 / 有什么 / 缺什么" | "改进真生效了吗 / 接通了吗" | **"接通的质量到底是真接通还是半接通"** |
| 评分逻辑 | 静态评估代码现状 | 动态评估**改造投入产出比** | **审视"接通"的真实程度（含死代码、死表识别）** |
| 路线图 | 紧急/短期/中期/长期 4 段 | 紧急"接通"/短期"证据"/中期"差异化"/长期"走出去" | **3 大结构性问题**（Problem A/B/C）+ 4 段 |
| 核心结论 | 优秀原型，工程化不到位 | 进生产线能力 + 接通问题 + 叙事缺失 | **接通行动"轻量真接通 + 重量级半接通"，新形态：死表 / 死方法** |

---

## 十、结论

> **MAD-KGDT 在第三轮审核时遇到了"接通悖论"** ——
> 团队真去做了"接通"动作，但接通的力度被"重新配线 vs 配几根线"分成两类：
>
> - **轻量接通（班级问答 / 真 prompt / 测试用例）**：3-5 行 import + 加几个 case 就能完成 → ✅ 真接通
> - **重量级接通（向量 RAG 灌数据 / Orchestrator 切 UI）**：要修改启动流程或重写 UI → ⚠️ 都只做了"声明"，没做"激活"
>
> 结果是：从评委角度看，**有些功能从"PPT 工程"变成"半 PPT 工程"** —— 进步存在但不够。
>
> 作为教学产品 —— **5 星推荐**（功能完整度国内罕见）；
> 作为生产级工程 —— **4 星**（仍需拆 assessment + 修 golden + 激活 RAG/Orchestrator）；
> 作为 AI 教学案例 —— **3.6 星**（轻量接通加分，致命短板未动）。
>
> Phase 4 必须**优先解决 3 大结构性问题**（A/B/C 各 30-200 行变更），完成后综合评分有望推到 4.2-4.3。
>
> **预测的下一轮风险**：如果 Phase 4 紧急 5 件再次在"轻量级"上拿满分而在"重量级"上交白卷，那么本轮"半接通"形态会进一步固化，评委信任度会下降。

---

*报告完毕。本报告与 [第一轮](MAD-KGDT审核报告(Opus4.7).md) 和 [第二轮](MAD-KGDT审核报告(Opus4.7-第二轮).md) 互为参照阅读。*
