# Demo 录制前数据准备清单

> 录制 4 段 demo 视频前，先按本清单造数据，让画面有内容（避免 Dashboard 空白 / 班级问答 0 问 / 调用统计 0 次）。
>
> 两种方式：① **手动操作**（最可靠，直接 click）② **自动 seed**（一键造数据，适合反复重录）。

---

## 方式一：手动操作 checklist（推荐首次录制）

### 准备账号

| 角色 | 学号/工号 | 密码 |
|------|----------|------|
| 学生 A | 2023210586 | 210586 |
| 学生 B | 2023210628 | 210628 |
| 教师 | tea001 | tea001 |
| 管理员 | 419116 | 419116 |

> 密码规则不变：末 6 位。如学校已替换学生数据，用真实学号。

### Demo 1 学生侧（30 秒）— 准备数据

| # | 操作 | 期望状态 |
|---|------|---------|
| 1 | 用学生 A 登录 → 进图谱 → 选 "Flutter 状态管理" 节点 → 学习视频看 30s → 退出 | learning_records 至少 1 条 |
| 2 | 进测验 → 选第 3 章 → 答完 5 题（故意答错 2 道）→ 提交 | quiz_results 1 条；wrong_answers 2 条 |
| 3 | 进收藏 → 把刚看过的节点收藏 | favorites 1 条 |
| 4 | 进实验 Tab → 提交一份实验报告 PDF（用 `data/项目/` 现成 PDF） | lab_submissions 1 条 |

### Demo 2 教师侧（30 秒）— 准备数据

| # | 操作 | 期望状态 |
|---|------|---------|
| 1 | 用教师登录 → 工作台 → 实验管理 | 看到学生 A 提交 |
| 2 | 进 AI 批阅 Tab → 选实验 1 → 标准模式批阅 3 份 | grading_results 3 条；agent_call_logs +3 |
| 3 | 教师审改 1 份分数（拖 slider 改 80→85）→ 核准批阅 | lab_submissions 已批改 1 条 |
| 4 | 进达成度 Tab → 一键生成 PDCA 报告 | audit print preview 有内容 |

### Demo 3 平台与创新（30 秒）— 准备数据

| # | 操作 | 期望状态 |
|---|------|---------|
| 1 | 管理员登录 → 进管理 → 一键生课 → 输入"数据结构"→ 不真生成（演示界面即可） | 不动数据 |
| 2 | 进个人中心 → AI 技能页 → 滑动看 9 个技能卡 | 不动数据 |
| 3 | 切到智能体浮层 → 滚动看 18 个 Agent 列表 | 不动数据 |
| 4 | 进数字孪生 → 输入 "模拟成绩 70 分学生答第 3 章测验" → 等 AI 答 | ai_chat_history +1；agent_call_logs +1（digital_twin） |

### Demo 4 AI 闭环（30 秒，Phase 4 新增）— 准备数据 ⚠️ 重点

> 此段最容易出 "Dashboard 空白" 问题，**录之前一定先造数据**。

| # | 操作 | 期望状态 |
|---|------|---------|
| 1 | 教师登录 → 进 AI 批阅 Tab → **打开"增强批阅"Switch** → 批阅 2 份学生报告 | agent_call_logs 至少 6 条（safety+grading+ethics × 2）；rag_embeddings 已经有 ≥10 条数据（DataLoadingService 会自动灌入）|
| 2 | 教师工作台 → 点 "AI 调用统计"（紫色 insights 图标） | Tab1 排行榜至少有 4 个 Agent；Tab2 调用链路至少有 2 条 chain |
| 3 | 学生 A 登录 → 班级问答 → 发问题（标题"Flutter 动画为什么卡"，正文 100 字）→ 私聊老师 | class_qa 1 条 |
| 4 | 学生 A 进刚发的问题详情页 → **点 "AI 起草回复"** → 等草稿写入文本框 → 不发出（演示功能即可） | ai_chat_history +1（tutor）|
| 5 | 教师 B 登录 → 进同一个问题 → 也点 "AI 起草回复" → 编辑后发出 | class_qa_replies 1 条；author_role=teacher |
| 6 | 学生回看 → 看到教师回复带"老师"chip + class_qa.status 自动转 answered | UI 显示状态 |

### 录制顺序建议

```
1. 关闭学生自动同步（设置→数据同步→关闭定时同步），避免录制时弹通知
2. 桌面端切 Noir 主题（深色 + 紫蓝渐变）
3. 按 Demo 1 → 2 → 3 → 4 顺序录
4. 录前 5 分钟先按本清单造数据
5. 录完 4 段单独导出为 mp4 → 后期合成
```

---

## 方式二：自动 seed 服务（适合重录 / 重置环境）

### 触发方式

仅在 debug build 中可见入口（避免污染发布版数据）：

**位置**：管理员登录 → 个人中心 → "Demo 数据种子"（debug only QuickAction）→ 点 "一键种入"

**实现**：`lib/dev/demo_seed_service.dart`（debug-only，发布时 tree-shake）

### 一键种入会做什么

```
1. lab_submissions: 为学生 A/B/C 各种 1 份示范实验报告（含示意 PDF 路径）
2. agent_call_logs: 直接 INSERT 30 条假调用日志，覆盖：
   - tutor × 8 次（最热）
   - grading × 6 次
   - safety × 4 次  
   - ethics × 4 次
   - quiz × 3 次
   - mobile_expert × 3 次
   - 其它 × 2 次
   含 5 条带 chain_id 的链路（safety→grading→ethics × 5）
3. class_qa + class_qa_replies: 3 个示范问题 + 5 条回复（含 1 条教师采纳）
4. rag_embeddings: 守 RagBootstrap 已运行（启动时自动；若 count=0 主动调）
```

### 撤销

```
"清空 demo 数据" 按钮 → DELETE WHERE created_at > seed_started_at
```

### 安全保障

- 仅在 `kDebugMode == true` 显示入口
- 仅管理员可操作（双重守卫）
- 写入数据带 `meta: 'demo_seed'` 标记，便于撤销
