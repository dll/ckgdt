# Agent Prompts 配置目录

## 用法

把 `{agentId}.md` 文件放到这里（例如 `tutor.md`），运行时 `BaseAgent.loadEffectivePersona()`
会**优先**加载这里的内容作为 system prompt，**回退**到代码中 `AgentConfig.persona`。

## 已注册 agentId（18 个）

| ID | 名称 |
|----|------|
| `voice` | 语音助手 |
| `graph` | 图谱大师 |
| `quiz` | 考官 |
| `repo` | 仓管 |
| `assessment` | 考务官 |
| `lab` | 实验员 |
| `works` | 评审团 |
| `achievement` | OBE 专家 |
| `courseware` | 备课大师 |
| `tutor` | 小伴 |
| `doc_converter` | 格式官 |
| `mobile_expert` | 全栈通 |
| `ethics` | 明德 |
| `safety` | 安全监控中心 |
| `archive` | 归档助手 |
| `grading` | 统一批阅官 |
| `digital_twin` | 数字孪生 |
| `assistant` | 通用助手 |

## 兼容 prompt 资产

下列旧 prompt 文件保留给历史数据和迁移兼容，不计入当前 18 个注册智能体：`madkg`、`lab_grading`、`assessment_grading`、`works_grading`、`course_gen`、`learning`、`path`、`virtual_student`、`virtual_teacher`。

## 增量迁移建议

不必一次把 18 个 prompt 全搬到 .md。优先级：
1. **改动频繁**的 prompt（tutor / quiz / lab_grading）—— 抽出来便于教师团队迭代
2. **教学场景敏感**的 prompt（virtual_student / virtual_teacher）—— 可让教研组直接修改人格设定
3. 其它保持代码内 const，避免无意义拆分

## 热更新

- 缓存通过 `PromptLoader.invalidate()` / `PromptLoader.invalidate(agentId)` 清除
- assets 文件改动需要 `flutter pub get` 或重启 app（Flutter 限制）
