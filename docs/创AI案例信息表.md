# 创 AI 案例信息表

**案例名称**：《移动应用开发》知识图谱与数字孪生教学系统（CKGDT）

---

## 1. 解决的教学问题

《移动应用开发》课程涉及 Android、iOS、Flutter、React Native、小程序、HarmonyOS 六大技术栈，知识点散、迭代快、实验链路长。传统教学难以做到"图谱可视化、个性化辅导、实验全链路批阅、多端真机验证、达成度可量化"。本系统以 AI 为底座，把"教—学—练—评—管"五个环节闭环。

## 2. 开发平台 / 工具

- **前端**：Flutter 3.35 + Dart 3.9（Material Design 3、CustomPainter 绘图谱、fl_chart 雷达 / 折线）
- **本地数据库**：sqflite + 31 个 DAO（66 张表）；rag_embeddings 表存向量
- **大模型**：DeepSeek-Chat / 智谱 GLM-4 / 自部署 Ollama / vLLM（OpenAI 兼容接口）
- **多 Agent**：18 个领域 Agent + Orchestrator 串联（safety → grading → ethics）
- **向量 RAG**：纯 Dart 余弦相似度（Float32 BLOB）+ TF-IDF 回退
- **同步**：Gitee API 无服务器同步（学生 push、教师 pull / 批阅 / push 回）
- **多端**：Android / Windows / Web（GitHub Pages）/ HarmonyOS
- **语音**：讯飞 WebSocket STT + AI 意图识别 + 系统 TTS
- **CI/CD**：GitHub Actions 多平台并行构建

## 3. 特色与创新

- **18 Agent + Orchestrator 链式批阅**，含 safety / ethics 双护栏，全程 chain_id 可追溯。
- **数字孪生学生 / 教师**——AI 模拟答题与教学反思。
- **向量 RAG + LRU 缓存**，开机自动灌入图谱 + 资料 + 题库。
- **OBE 达成度** + **一键 PDF 批阅报告** + **二维码扫码取卷**。
- **隐私合规模块**：用户协议 / 隐私声明 / 数据导出 / 删除我的数据 全闭环。

## 4. 相关网址

- 开源仓库（Gitee 主）：https://gitee.com/chzcldl/mad-kgdt
- 开源仓库（GitHub 镜像）：https://github.com/dll/mad-kgdt
- Web 在线体验：https://dll.github.io/mad-kgdt/

## 5. 配套资源

- ☑ **完整代码**：14.7 万行 Dart，4 端构建产物（APK / EXE / Web / OHOS）
- ☑ **应用文档**：
  - `CLAUDE.md` 项目总览
  - `docs/case_study/PRD.md` 产品需求 / `user_stories.md` 用户故事 / `demo_script.md` 4 段 120 秒演示脚本
  - `docs/CKGDT 审核报告(Opus4.7-第一/二/三轮).md` 三轮自审报告
  - 应用内"使用手册"页 + "我的数据"页 + 18 个 Agent 各自 .md persona

## 6. 案例内容简介

CKGDT 是面向多课程的 Flutter 全平台教学平台，覆盖 Android / Windows / Web / HarmonyOS 四端。系统围绕"教—学—练—评—管"五维度构建：知识图谱可视化浏览、章节测验与错题本、视频与课件资源、实验任务与 AI 批阅、项目考核与答辩、学生作品互评、OBE 达成度三维分析（平时 / 实验 / 考试）。AI 层面集成 18 个专业 Agent，覆盖辅导、批阅、安全、伦理、数字孪生等场景；Orchestrator 编排器把"安全审查 → 主批阅 → 学术伦理建议"串成可追溯链路，结果落库供教师工作台审计。向量 RAG 与 TF-IDF 双路召回，让对话有课程内容支撑。Gitee 无服务器同步把学生提交、教师批阅、班级问答互通到所有终端。已在某高校 88 名学生班级真实使用，沉淀实验报告与作品评分；隐私合规模块保障学生数据可导出 / 可删除。系统全部开源，代码、文档、Web 演示、构建产物三端齐全，可用于工程教育认证与课程思政示范课。
