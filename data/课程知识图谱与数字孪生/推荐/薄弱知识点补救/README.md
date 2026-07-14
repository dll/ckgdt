# 薄弱知识点补救

此目录存放针对学生薄弱知识点的补救资源。

## 文件结构

```
薄弱知识点补救/
├── README.md              # 本文件
├── 补救资源模板/           # 补救资源定义
│   └── 基础补救.json
└── 使用记录/               # 学生使用记录
    └── .gitkeep
```

## 补救资源格式

```json
{
  "remedy_id": "remedy_001",
  "target_concept": "数据建模",
  "difficulty_level": "beginner",
  "resources": [
    {
      "type": "video",
      "title": "数据建模基础讲解",
      "url": "assets/videos/data_modeling_basics.mp4",
      "duration": 15
    },
    {
      "type": "exercise",
      "title": "数据建模练习题",
      "question_count": 10
    }
  ]
}
```

## 触发条件

- 学生测验错误率 > 60%
- 学生在同一知识点停留时间过长
- 学生主动请求帮助
