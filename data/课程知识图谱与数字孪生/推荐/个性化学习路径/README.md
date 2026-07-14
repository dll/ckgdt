# 个性化学习路径

此目录存放由推荐算法生成的个性化学习路径资源。

## 文件结构

```
个性化学习路径/
├── README.md              # 本文件
├── 路径模板/               # 路径模板定义
│   └── 基础路径.json
└── 历史路径/               # 学生历史路径记录
    └── .gitkeep
```

## 路径模板格式

```json
{
  "path_id": "path_001",
  "name": "基础学习路径",
  "target_objective": "目标1",
  "nodes": [
    {
      "node_id": "node_001",
      "title": "课程知识图谱基础",
      "type": "theory",
      "estimated_time": 30,
      "prerequisites": []
    }
  ]
}
```

## 生成方式

- **自动生成**：由 `LearningPathAgent` 根据学生学习数据实时生成
- **手动创建**：教师可在管理后台手动创建路径模板
- **导入导出**：支持 JSON 格式导入导出
