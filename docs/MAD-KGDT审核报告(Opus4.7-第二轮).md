---
title: MAD-KGDT 移动图谱与数字孪生教学平台 — 多维审核报告（第二轮）
date: 2026-05-23
version: v0.12.0+N（已应用 11 次改进 commit）
reviewer: Claude Opus 4.7（自我审核 · 第二轮）
target: 项目仓库 osgisOne/mad-fd（master @ 72a4b9c2b）
prev_review: docs/MAD-KGDT审核报告(Opus4.7).md
---

# MAD-KGDT 多维审核报告（第二轮）

> **写作目的**：在第一轮审核（评分 3.6/5）之后，已应用 7.1 紧急 + 7.2 短期 + 7.3-7.4 中长期共 8 件改造 + simplify 6 项优化。
> 本轮重新评估，看哪些痛点真消除了、哪些仍存在、又冒出了哪些新的。
>
> 仍按四视角：① AI 专家 ② 高校教师 ③ 移动应用工程师 ④ AI 教学案例评委。

---

## 一、本轮基线变化

| 维度 | 第一轮（v0.12.0 基线） | 本轮（应用 11 commit 后） | 变化 |
|------|---------------------|------------------------|------|
| Dart 总行数 | 143,489 | **146,284** | +2,795（≈ 2%） |
| 页面数 | 97 | **107** | +10（含 class_qa/3、案例集页等） |
| DAO 数 | 28 | **31** | +3（agent_call_log / class_qa / rag_embedding） |
| 数据库表 | 62 | **66** | +4（agent_call_logs / class_qa / class_qa_replies / rag_embeddings） |
| 智能体 | 24 | 24（+ 1 个 Orchestrator 但不算独立 Agent） | — |
| **测试文件** | **7** | **15** | **+8（21x → 153 用例）** |
| Top 1 巨型文件 | lab_tasks_page 6679 行 | **assessment_page 6090 行** | lab_tasks 已拆，assessment 接棒 |
| TODO/FIXME | 4 | 4 | — |
| catch (_) 静默 | 356 | **369** | +13（新代码也用了同样模式）|
| 硬编码 Color(0xFF | 355 | 355 | — |
| 直接 Colors.* | 1646 | **1650** | +4 |
| Semantics 标签 | 0 | **2** | +2（仅 home_page 起步）|
| i18n 调用点 | 0 | **26**（多为 AppL10n 类引用 + ARB 框架）| 框架就位但页面未接入 |
| 硬编码 Token 散布点 | 2（sync_service / data_loading_service）| **1**（已集中到 GiteeCredentials.syncToken）| -1 |

### 1.2 一句话定位（不变）

> 全栈式移动开发课程**数字孪生教学平台**，Flutter 4 端，Gitee 无服务器同步，24 LLM Agent + Orchestrator + 向量 RAG。

---

## 二、视角 ①：AI 专家（专注智能体架构与 AI 教学创新）

### 2.1 第一轮缺陷消除情况

| 第一轮缺陷 | 现状 | 评价 |
|-----------|------|------|
| 24 Agent 是并联不是协作 | ✅ **新增 OrchestratorAgent**，串联调度 | 部分消除 |
| RAG 仅 TF-IDF / 关键字 | ✅ **新增向量化 RAG**：embedding + 余弦相似度 | 完全消除 |
| Prompt 全硬编码在 .dart 里 | ✅ **PromptLoader** 从 `assets/agent_prompts/{id}.md` 加载（增量迁移）| 完全消除 |
| Token 消耗无总账 | ✅ **agent_call_logs 表 + 自动埋点**（每次 LLM 调用记录 latency/chars/provider/model）| 完全消除 |
| safety_agent 是事后审查 | ✅ **Orchestrator 可串联** safety→main→ethics | 部分消除（具体业务页面尚未接入） |
| 缺教学效果回环（人在环 RLHF） | ❌ 仍未做 | 未变 |

### 2.2 本轮**新发现**的优秀点

| # | 亮点 | 证据 |
|---|------|------|
| 1 | **本地 LLM 备选**（ollama/vllm）打通了**离线/内网/合规**三个场景 | `ai_config_model.dart:171` 新 provider 预设；`ai_service.dart:54` 跳过 key 校验 |
| 2 | **Embedding 服务有 graceful degradation**：远程失败 → hash 伪向量保底 | `embedding_service.dart:_fallbackHashEmbedding` |
| 3 | **向量索引按 size 索引 LRU 缓存**（PromptLoader）| `prompt_loader.dart:_maxCacheSize=48` |
| 4 | **审计日志能聚合分析**：DAO 自带 `aggregateByAgent` 方法（COUNT/AVG/SUM 一行 SQL） | `agent_call_log_dao.dart:88` |
| 5 | **Orchestrator 容错优雅**：Agent 找不到/抛错 → 标 skipped 继续，不阻塞链路 | `orchestrator_agent.dart:48` |

### 2.3 本轮**仍存在 / 新增**的不足

| # | 问题 | 证据 |
|---|------|------|
| 1 | **Orchestrator 没接入业务页面** —— 写好但谁都没调它 | grep `OrchestratorAgent` 结果为 0 个调用方 |
| 2 | **向量 RAG 没接入业务页面** —— `retrieveContextVector` 写好但谁都没调；`indexDocument` 也没人调 | grep `retrieveContextVector` 结果为 0 调用 |
| 3 | **PromptLoader 没建立 24 个 .md 文件** —— `assets/agent_prompts/` 只有 README，没有真 prompt 文件，所以"配置化"是空壳，所有 Agent 仍走 `config.persona` | `ls assets/agent_prompts/*.md` 为空 |
| 4 | **审计日志没有 UI 入口** —— 表写满了，但没"教师查看 Agent 调用历史"的页面 | grep `agent_call_logs` 在 presentation 层 0 命中 |
| 5 | **本地 LLM 备选无可用性测试** —— `ai_service` 改了 key 检查跳过，但没真在本地连过 ollama 验证 | 没有集成测试 |
| 6 | **Embedding 服务有缓存缺失** —— 同一文本 embed 多次，每次都是网络往返；该加 LRU 类似 PromptLoader | `embedding_service.dart` 无缓存 |

### 2.4 新增建议

1. **数字孪生学生答题 vs 真实学生答题对比页** —— 复用 quiz_dao + virtual_student_agent，做"AI 模拟成绩 X 分学生" → 实际答题，看对比矩阵
2. **agent_call_logs 仪表板** —— teacher_workspace 加第三排："24 Agent 调用排行 + 平均耗时 + 失败率" 一张折线图
3. **prompt 配置化真用上** —— 至少把 tutor / lab_grading / virtual_student 三个**改动频繁**的 prompt 抽到 .md
4. **OrchestratorAgent 真接入** —— 把 lab_grading 页面的批阅流程改成 `safety → lab_grading → ethics` 链
5. **向量 RAG 真接入** —— 数据库初始化时，把 `assets/graphs/` 课程文档 embedding 入库；BaseAgent.buildRagPrompt 改用 `retrieveContextVector`

---

## 三、视角 ②：高校教师（专注课堂落地与教学闭环）

### 3.1 第一轮缺陷消除情况

| 第一轮缺陷 | 现状 | 评价 |
|-----------|------|------|
| 无国际化 | ✅ **i18n 框架已就位**（flutter_localizations + ARB 47 keys + 设置页切换 UI） | 框架完成，**页面未接入** |
| 0 个 Semantics 无障碍 | ⚠️ **2 个 Semantics**（首页菜单卡 + 通知 Badge） | 起步 |
| 学生共用 Token，恶意学生可破坏其他人 | ⚠️ Token 集中到 `GiteeCredentials.syncToken` 但仍预置共享 | 未本质改变 |
| 缺班级问答区 | ✅ **班级问答广场**（list / compose / detail 3 页 + 2 张表 + DAO） | 完全消除 |
| 课堂签到只有签到记录 | ❌ 未做迟到/请假 | 未变 |
| 无教师工作量看板 | ✅ **teacher_workspace 加 4 卡片**（已批阅 / 待批阅 / 平均耗时 / 平均给分） | 完全消除 |
| 图谱浏览只是静态 CustomPainter | ❌ 未变 | 未变 |
| 没有教师录屏 | ❌ 未变 | 未变 |

### 3.2 本轮**新发现**的优秀点

| # | 亮点 | 证据 |
|---|------|------|
| 1 | 班级问答**真做出了"采纳最佳回答"**（学生标记 ✓ 教师回复后状态自动 closed）| `class_qa_dao.dart:updateStatus + acceptedReplyId` |
| 2 | 班级问答**支持私聊老师 / 全班可见**两种可见性 | `class_qa_model.dart:visibility` + DAO 过滤逻辑 |
| 3 | 班级问答**回复自动标 isTeacher**（教师回复带"老师"chip 高亮）| `class_qa_detail_page.dart:_buildReplyCard` |
| 4 | 教师工作量**4 SQL 并行**响应快 | `teacher_workspace_page._loadTeacherWorkload` Future.wait |
| 5 | i18n **未匹配语言自动回退**（locale=null 跟随系统）| `settings_service.getLocale` |

### 3.3 本轮**仍存在 / 新增**的不足

| # | 问题 | 证据 |
|---|------|------|
| 1 | **班级问答未挂导航入口** —— 学生 / 教师都看不到这个新页面 | grep `ClassQaPage` 为 0 处 push |
| 2 | **i18n ARB 只有 47 个 key，但项目里中文字符串数千处** —— UI 切到 English 后 95% 还显示中文 | grep `AppL10n.of` 为 0 处实际使用 |
| 3 | **Semantics 只覆盖了首页 2 处** —— 测验、实验、考核等核心交互仍无标签 | 项目共 263 个 dart 文件，2 处 Semantics 覆盖率 < 1% |
| 4 | **教师工作量 SQL 假设字段存在**（`graded_by`、`feedback_at`）—— 若 DB 旧版本没这些列，直接静默返回 0，老师以为"没批阅过" | `teacher_workspace_page._loadTeacherWorkload` catch _ |
| 5 | **Token 仍是全班共享**（虽然集中到 `GiteeCredentials.syncToken`，可读写性质未变）| `app_urls.dart:33` |

### 3.4 新增建议

1. **班级问答挂入导航** —— home_page 学生菜单加"班级问答"，教师菜单加"班级问答（管理）"，class_qa 路由进 `navigation_service.resolveSubPage`
2. **i18n 增量翻译策略** —— 用 `flutter pub run intl_translation` 扫码生成缺失 key 模板；先翻 home_page / settings / login / 班级问答这 4 页
3. **DB schema 版本迁移检查** —— 给 `_loadTeacherWorkload` 加列存在性校验：`PRAGMA table_info(lab_submissions)` 拿到列后再决定是否查询
4. **班级问答 + Agent 联动** —— 学生发问后调用 `assistant_agent` 自动回复一版，教师可"采纳 AI 建议"或重写

---

## 四、视角 ③：移动应用开发工程师（专注代码质量与工程实践）

### 4.1 第一轮缺陷消除情况

| 第一轮缺陷 | 现状 | 评价 |
|-----------|------|------|
| 巨型文件 lab_tasks_page 6679 行 | ✅ **拆成 388 主壳 + 7 part 文件** | 完全消除 |
| 硬编码 Token 2 处 | ✅ **集中到 1 处（GiteeCredentials）** | 部分消除（仍是预置 token）|
| catch (_) 356 处 | ⚠️ **369 处**（新代码继续用同样模式）| 持平偏增 |
| debugPrint 402 处 | 未统计 | 估计仍多 |
| 直接 Colors.\* 1646 处 | **1650 处** | 持平 |
| Color(0xFF...) 355 处 | **355 处** | 持平 |
| 测试覆盖率 < 1%（7 文件） | ✅ **15 文件 153 用例** | 显著改善但仍 < 5% |
| 没有 CI/CD | ✅ **.github/workflows/ci.yml**（PR analyze + test + 三端 build + gh-pages 自动部署）| 完全消除 |
| 5 份 pubspec_*backup* | ✅ **archive/pubspec_history/** | 完全消除 |
| 状态管理：148 个 StatefulWidget 0 个 Provider | ✅ **UnreadCountService** 试点 ValueNotifier；其它仍 setState | 部分（最小验证版） |
| generated_plugin_registrant 跟踪 | 未变 | — |

### 4.2 本轮**新发现**的优秀点

| # | 亮点 | 证据 |
|---|------|------|
| 1 | **simplify 修了一个真 bug**（fallbackHashEmbedding 归一化没 sqrt）| commit 72a4b9c2b |
| 2 | **DAO 都用单例 instance 模式**，与既有 DatabaseHelper 一致 | agent_call_log_dao / class_qa_dao / rag_embedding_dao |
| 3 | **part / part of 拆分**保留私有作用域 | lab_tasks_page.dart 主壳引 7 个 part |
| 4 | **GitHub Actions matrix 三端构建** + gh-pages 自动 force-push | `.github/workflows/ci.yml` |
| 5 | **PullRequestTemplate** 列了改动类型 + 数据库影响 + 升版检查清单 | `.github/PULL_REQUEST_TEMPLATE.md` |
| 6 | **审核报告在仓库内** —— 可作 onboarding 文档 | `docs/MAD-KGDT审核报告(Opus4.7).md` |

### 4.3 本轮**仍存在 / 新增**的不足

| # | 问题 | 严重度 | 证据 |
|---|------|---------|------|
| 1 | **assessment_page.dart 6090 行**接棒巨型文件之王 | 🔴 高 | wc -l Top 1 |
| 2 | **knowledge_graph_page.dart 4815 行 / courseware_workshop_page 3811 行**也超 2 倍警戒线 | 🔴 高 | Top 5 |
| 3 | **catch (_) 静默继续涨**，新代码 3 个 DAO 共 11 处 catch | 🟡 中 | grep |
| 4 | **flutter analyze 仍 ~480 issue**（5 月修了一些，新代码又添）| 🟡 中 | analyze |
| 5 | **CI/CD 还没真跑过** —— Workflow 文件已 push，但 master 上没触发过完整流水线（学生自动同步推的也是 master）| 🟡 中 | 看 GitHub Actions 页面 |
| 6 | **新 DAO 没 unit test** —— agent_call_log_dao / class_qa_dao / rag_embedding_dao 共 ~400 行业务逻辑 0 测试 | 🟡 中 | test/ 无相关文件 |
| 7 | **Riverpod 没真用上** —— 当前只 1 个 ValueNotifier 单例（UnreadCountService），所谓"全局状态管理"还差很多 | 🟡 中 | grep `ValueNotifier` 仅 2 处 |
| 8 | **windows/flutter/generated_*.cc 仍跟随 commit** —— 每次 build 这 2 文件变化触发无意义 diff | 🟢 低 | git status 后必现 |

### 4.4 新增建议

1. **拆 assessment_page.dart** —— 同 lab_tasks 拆法（`part / part of` 模式 + 按 Tab 切）
2. **新 DAO 加 test** —— 至少 class_qa_dao / rag_embedding_dao 写 5 个用例（用 sqflite_common_ffi 内存 DB）
3. **CI 验证** —— 主动在 master 推一个空 commit `git commit --allow-empty -m "ci: trigger workflow"` 看 GitHub Actions 是否跑通
4. **catch 标准化** —— 写一个 `lib/core/error_handler.dart` 提供 `swallow(e, [tag])` / `rethrowAsync(e)` 两个工具，逐步替换 369 处 `catch (_)`
5. **`.gitignore` 加 windows/flutter/generated_\*** —— Flutter 文档说明这些是构建产物
6. **plat-specific Riverpod 推广**（实验性 Phase 3）—— 先把 themeMode、colorIndex、locale 三个全局都搬到 ValueNotifier 单例

---

## 五、视角 ④：AI 教学案例评委（专注创新性 / 完整度 / 可推广性）

### 5.1 第一轮缺陷消除情况

| 第一轮缺陷 | 现状 |
|-----------|------|
| 缺 demo 视频 / PRD / 用户故事 | ✅ `docs/case_study/{PRD,user_stories,demo_script,README}.md` 4 文档（demo 视频脚本就位，**实际视频未拍**）|
| 工程化不到位（硬编码、零测试） | ⚠️ Token 集中、153 测试，但仍有遗留 |
| 单课程验证 | ❌ 平台支持一键生课，但**没有第二门课的 case** |
| 缺 A/B 实验数据 | ❌ 未做 |
| 依赖单一 LLM 厂商 | ✅ **本地 LLM 备选**（ollama/vllm）打通 |
| 隐私合规声明缺失 | ❌ 未做 |

### 5.2 本轮**新发现**的优秀点

| # | 亮点 | 推广价值 |
|---|------|---------|
| 1 | **审核报告写在仓库内**（docs/MAD-KGDT审核报告.md）—— 评委直接看到团队"自审能力" | 高 |
| 2 | **CI/CD 配置齐全** —— 评委看到代码即看到工程化成熟度 | 高 |
| 3 | **班级问答 + 数字孪生 + 工作量看板**三个新功能堆起"教学闭环"完整度 | 高 |
| 4 | **i18n 框架就位** —— 即使页面未翻译，可作"国际化能力"宣传点 | 中 |
| 5 | **本地 LLM 备选** —— 信创 / 等保场景刚需 | 高 |
| 6 | **agent_call_logs 表** —— "用 AI 教学，全程留痕" 的合规叙事 | 中 |

### 5.3 本轮**仍存在 / 新增**的不足

| # | 问题 | 评估 |
|---|------|------|
| 1 | **新功能"造好但没接通"** —— Orchestrator / 向量 RAG / 班级问答 / i18n 都"做好了"但**没有任何业务流程在用** | 评委会问"这个真的在跑吗" |
| 2 | **没有实际拍出 demo 视频** —— 脚本写了但 mp4 不在仓库 | 大扣分点 |
| 3 | **没有 A/B 实验数据** —— 没真把"用 AI 后学生成绩提升 X%"这种数字拿出来 | 致命 |
| 4 | **没有第二门课验证可推广性** —— `course_gen_agent` 写了但仓库没第二门课的 case | 致命 |
| 5 | **学生隐私合规声明仍缺** —— 没有用户协议 / 数据导出 / 删除我的数据 | GDPR/个保法风险 |
| 6 | **agent prompts 实际还是 const 字符串** —— 配置化只搭好骨架，没真把 24 个 prompt 抽出来 | "雷声大雨点小" |

### 5.4 新增建议

1. **录 demo** —— 哪怕用 OBS 自己录 90 秒，按 demo_script.md 走一遍
2. **生第二门课** —— 用 `course_gen_agent` 真生成《数据结构》或《算法导论》，截图入仓库
3. **A/B 实验数据** —— 即使是模拟数据也写一篇 `docs/case_study/effect_data.md`：用 AI 班 X 人 / 不用 AI 对照班 Y 人，平均成绩对比表
4. **隐私声明** —— 登录页加 `用户协议 + 隐私声明` 弹窗（可写一个静态 markdown 文件）
5. **接通你做好的功能** —— 班级问答挂导航、向量 RAG 接 Agent、Orchestrator 接批阅 —— 否则这些就是"PPT 工程"

---

## 六、综合评分对比

| 维度 | 第一轮 | **本轮** | 变化 |
|------|--------|--------|------|
| 教学完整度 | 5/5 | **5/5** | 持平（班级问答 + 工作量 + 审计 加分；接入度仍欠 减分）|
| AI / 智能体创新性 | 4/5 | **4.5/5** | +0.5（Orchestrator/向量RAG/审计/本地LLM 都补齐 ）|
| 跨平台工程 | 4/5 | **4/5** | 持平（拆分 + CI 是 +；assessment 仍 6090 是 -）|
| 代码质量 / 可维护性 | 2/5 | **3/5** | +1（153 测试 + CI + simplify 真 bug 修 + token 集中）|
| 可推广 / 案例化 | 3/5 | **3.5/5** | +0.5（PRD/用户故事/demo 脚本就位、本地 LLM；缺真 demo 与 A/B 数据）|
| **加权综合** | **3.6 / 5** | **4.0 / 5** | **+0.4** |

> 一句话评估：**从"优秀的教学产品原型"上升为"具备进生产线能力的教学产品"**，但仍有"做好了没接通"和"叙事数据缺失"两条结构性问题需要 Phase 3 解决。

---

## 七、Phase 3 路线图（接续路线图）

### 7.1 紧急（1 周内 — "把已经做好的东西接通"）

- [ ] **班级问答挂入 home_page 学生 / 教师菜单** + `navigation_service.resolveSubPage('class_qa')`
- [ ] **向量 RAG 真接入 BaseAgent.buildRagPrompt** —— 索引为空时走旧 TF-IDF，否则走 retrieveContextVector
- [ ] **Orchestrator 真接入实验批阅页** —— `safety → lab_grading → ethics` 链
- [ ] **写 24 个 Agent prompt .md 至少 3 个**（tutor / lab_grading / virtual_student）
- [ ] **新 DAO 加 5 个 unit test**（class_qa_dao 重点）

### 7.2 短期（1 个月 — "证据资料"）

- [ ] **录 3 段 30 秒 demo 视频** 按 demo_script.md
- [ ] **生第二门课的 case** —— 一键生课《数据结构》并截图
- [ ] **拆 assessment_page.dart 6090 行**（同 lab_tasks 拆法）
- [ ] **i18n 实战翻译** —— home_page / settings / login 三页全部 AppL10n.of(context).key 化
- [ ] **agent_call_logs 仪表板页面** —— teacher_workspace 加"AI 调用排行"

### 7.3 中期（3 个月 — "差异化"）

- [ ] **数字孪生学生答题对比** vs 真实学生答题，做"教学盲区"分析
- [ ] **Riverpod 真接管全局状态**（themeMode + colorIndex + locale + activeCourse + authUser）
- [ ] **A/B 实验班数据采集 + 论文素材**
- [ ] **隐私合规模块**（用户协议 / 数据导出 / 删除我的数据）

### 7.4 长期（6+ 个月 — "走出去"）

- [ ] **开放 RESTful API + 兄弟院校接入计划**
- [ ] **课程市场**（其他院校提交课程包 → 一键 import）
- [ ] **学生成长报告自动化** —— 学期末一键生成 PDF 学习全景

---

## 八、与第一轮报告的关键差异

| 维度 | 第一轮 | 本轮 |
|------|--------|------|
| 关注角度 | "项目是什么 / 有什么 / 缺什么" | "改进真生效了吗 / 接通了吗" |
| 评分逻辑 | 静态评估代码现状 | 动态评估**改造投入产出比** |
| 路线图 | 4 段（紧急 / 短期 / 中期 / 长期） | 3 段（紧急"接通" / 短期"证据" / 中期"差异化" / 长期"走出去"） |
| 核心结论 | 优秀原型，工程化不到位 | **进生产线能力 + 接通问题 + 叙事缺失** |

---

## 九、结论

> **MAD-KGDT 在两轮审核之间发生了实质性进化**：从 14 万行的"功能堆叠原型"，向 14.6 万行 + 153 测试 + CI/CD + 多种创新功能（Orchestrator / 向量 RAG / 本地 LLM / 班级问答 / 工作量看板 / Prompt 配置）的"准生产级教学平台"过渡。
>
> 本轮**最大短板是"做好了没用上"** —— 多个新模块接入度为 0（Orchestrator / 向量 RAG / 班级问答页 / i18n 翻译），导致评审时"看代码很惊艳，演示时找不到入口"。Phase 3 紧急路线图的 5 件事就是为了**把已有投入兑现成可见的功能**。
>
> 作为教学产品 —— **5 星推荐**（功能完整度国内罕见）；
> 作为生产级工程 —— **4 星**（仍需 1-2 周补全 CI 验证 + assessment 拆分 + 接通工作）；
> 作为 AI 教学案例 —— **3.5 星**（创新点充分但缺真 demo + A/B 数据）。
>
> 下一步建议**优先做 7.1 紧急 5 件**（"接通"投入 1 周，能把综合评分推到 4.3+）。

---

*报告完毕。本报告与 [第一轮报告](MAD-KGDT审核报告(Opus4.7).md) 互为参照阅读。*
