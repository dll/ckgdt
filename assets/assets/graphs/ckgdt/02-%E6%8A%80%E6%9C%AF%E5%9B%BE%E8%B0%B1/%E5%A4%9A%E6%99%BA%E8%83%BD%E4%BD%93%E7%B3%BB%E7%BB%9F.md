# 多智能体系统
*CKGDT 平台 18 个专业 Agent 协作架构*

## 架构概述
- AgentRegistry 单例注册表
- BaseAgent 抽象基类
- AgentConfig 配置（persona/tools/cases）
- AgentSession 多轮对话上下文

## 核心智能体
- voice：语音导航（AI意图识别）
- graph：知识图谱生成与分析
- tutor：智能辅导答疑（RAG）
- quiz：测验题生成
- lab：实验指导
- lab_grading：实验报告AI批阅
- assessment_grading：项目考核AI批阅
- works_grading：学生作品AI批阅

## 教学智能体
- safety：内容安全审查
- courseware：课件生成
- course_gen：一键生课
- learning：学习路径推荐
- path：学习计划制定
- achievement：成绩分析

## 数字孪生智能体
- virtual_student：数字孪生-学生人格模拟
- virtual_teacher：数字孪生-教师督导辅助

## 工具调用机制
- special_agent_tools.dart 路由
- 7种导航动作支持
- RAG检索增强
- 工具执行结果反馈
