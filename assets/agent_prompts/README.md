# Agent Prompts 配置目录

## 用法

把 `{agentId}.md` 文件放到这里（例如 `tutor.md`），运行时 `BaseAgent.loadEffectivePersona()`
会**优先**加载这里的内容作为 system prompt，**回退**到代码中 `AgentConfig.persona`。

## 已知 agentId（24 个）

| ID | 名称 |
|----|------|
| `assistant` | 通用助手 |
| `tutor` | 课堂助教 |
| `quiz` | 测验生成 |
| `lab` | 实验指导 |
| `lab_grading` | 实验报告 AI 批阅 |
| `assessment` | 考核管理 |
| `assessment_grading` | 项目考核 AI 批阅 |
| `works` | 作品展示指导 |
| `works_grading` | 学生作品 AI 批阅 |
| `safety` | 内容安全审查 |
| `courseware` | 课件生成 |
| `course_gen` | 一键生课 |
| `learning` | 学习路径推荐 |
| `path` | 学习计划制定 |
| `mobile_expert` | 移动开发专家 |
| `ethics` | 学术伦理指导 |
| `achievement` | 成绩分析 |
| `doc_converter` | 文档格式转换 |
| `repo` | Git 仓库分析 |
| `madkg` | 系统使用指南 |
| `voice` | 语音导航 |
| `graph` | 图谱生成与分析 |
| `virtual_student` | 数字孪生-学生人格模拟 |
| `virtual_teacher` | 数字孪生-教师督导辅助 |

## 增量迁移建议

不必一次把 24 个 prompt 全搬到 .md。优先级：
1. **改动频繁**的 prompt（tutor / quiz / lab_grading）—— 抽出来便于教师团队迭代
2. **教学场景敏感**的 prompt（virtual_student / virtual_teacher）—— 可让教研组直接修改人格设定
3. 其它保持代码内 const，避免无意义拆分

## 热更新

- 缓存通过 `PromptLoader.invalidate()` / `PromptLoader.invalidate(agentId)` 清除
- assets 文件改动需要 `flutter pub get` 或重启 app（Flutter 限制）
