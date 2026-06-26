# CKGDT 产品需求文档（PRD）

> **CKGDT** = Course Knowledge Graph and Digital Twin Platform
> 课程知识图谱与数字孪生平台

| 项 | 内容 |
|----|------|
| 版本 | v0.12.0 |
| 状态 | 已上线（教学使用中） |
| 平台 | Android / Windows / Web / HarmonyOS |
| 仓库 | https://gitee.com/chzcldl/mad-kgdt |
| Web 公网 | https://dll.github.io/mad-kgdt/ |
| 维护者 | ldl @ 教育部高校 IT 课程组 |

---

## 1 · 一句话定位

**面向多课程的全栈式教学平台**：把"教—学—练—评—管"五大场景装进 Flutter 单体应用，靠 Gitee 仓库做无服务器跨设备同步，靠 18 个专业 Agent 串起 AI 辅助的全链路。

## 2 · 目标用户与场景

| 角色 | 主场景 | 主要痛点 |
|------|--------|---------|
| **学生**（88 人/班级） | 自学知识图谱、刷题、做实验、提交作品 | 课后无答疑、不知道学到哪、作业反馈慢 |
| **教师**（1-3 人/班级） | 备课、布置实验/考核、批阅、统计达成度 | 88 份作业批阅累、达成度计算手工 |
| **管理员**（1 人） | 课程管理、学生/教师管理、数据导入导出、系统监控 | 各院校需求多样、要做工程认证 |

## 3 · 核心需求与对应模块

| 需求 | 实现 | 关键文件 |
|------|------|---------|
| 知识图谱浏览 + 学习路径推荐 | `graph/` (5 页) + `learning/` (11 页) | `knowledge_graph_page.dart` 4815 行 |
| 章节测验（52 题预置） | `quiz/` (2 页) + 错题本 | `quiz_dao.dart`、52 题 seed DB |
| 实验任务管理 + 报告提交 + AI 批阅 | `lab/` (5 页) + `grading` 统一批阅官 | `lab_tasks_page.dart` 6679 行 |
| 项目考核 + 答辩 + 同行评审 + 贡献分 | `assessment/` (4 页) | 5 张相关表 |
| 学生作品展示 + 互动 | `works/` (2 页) | `student_works` + 4 张互动表 |
| 课程达成度（OBE 反向设计 8 Tab） | `achievement/` (6 页) | `achievement_dao.dart` + 三维成绩表 |
| 班级 / 课堂签到 / 教学管理 | `admin/` (17 页) + `classroom/` | 6 张教学表 |
| AI 多智能体辅助 | 18 个 Agent + RAG | `lib/services/agent/` |
| 跨设备同步（无服务器） | Gitee 仓库 JSON 双向同步 | `sync_service.dart` 1471 行 |
| 三端互通（桌面 + 手机 + Web） | 局域网 P2P + GitHub Pages 公网 | `cross_platform/` (2 页) |
| 数字孪生（学生/教师双模式） | `digital_twin_agent` | 1 个 Agent |
| 一键生课（换课程） | `courseware_agent` + `CourseGeneratorSheet` | `courses` 表 |

## 4 · 非功能要求

| 维度 | 目标 | 现状 |
|------|------|------|
| 启动速度 | 桌面 ≤ 3s，Web ≤ 5s | 已达成 |
| 离线可用 | 核心学习功能离线可用 | 已达成（SQLite seed DB）|
| 跨平台一致性 | 4 端 UI / 数据完全一致 | 已达成 |
| 数据安全 | 学生数据仅自己 + 教师可见 | 部分（Gitee 仓库公开存放）|
| 国际化 | 中英双语 | 待做 |
| 无障碍 | 屏幕阅读器友好 | 待做 |

## 5 · 路线图

参见 [审核报告](../CKGDT审核报告(Opus4.7).md) 第 7 节。

## 6 · 关键设计决策

1. **单体 Flutter 而非 BFF + Native**：教学场景部署难度优先，Flutter 4 端复用 ≥ 90% 代码
2. **Gitee 作消息总线无服务器**：学校机房网络受限不能开服务器，Gitee 当数据库 + 消息队列
3. **多 Agent 矩阵而非单一对话**：每种教学场景（批阅/答疑/生课）专精 prompt + 工具调用
4. **OBE 三维加权达成度**：直接对接工程教育认证标准，平台可作为认证材料
5. **课程数据 + 视觉 / 内容解耦**：`courses` 表切换激活课程，平台不绑死单一课程
