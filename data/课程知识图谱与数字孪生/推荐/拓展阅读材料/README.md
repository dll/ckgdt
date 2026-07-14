# 拓展阅读材料

此目录存放根据学生学习兴趣和进度推荐的拓展阅读材料。

## 文件结构

```
拓展阅读材料/
├── README.md              # 本文件
├── 推荐资源模板/           # 推荐资源定义
│   └── 基础推荐.json
└── 使用记录/               # 学生使用记录
    └── .gitkeep
```

## 推荐资源格式

```json
{
  "recommend_id": "rec_001",
  "target_chapter": "第一章",
  "interest_tags": ["知识图谱", "数据建模"],
  "resources": [
    {
      "type": "article",
      "title": "知识图谱在教育中的应用",
      "source": "教育技术期刊",
      "url": "https://example.com/article1",
      "summary": "本文探讨了知识图谱在教育领域的应用..."
    },
    {
      "type": "book",
      "title": "知识图谱：方法与实践",
      "author": "张三",
      "isbn": "978-7-xxx-xxx-x",
      "chapter_relevant": "第2-3章"
    }
  ]
}
```

## 推荐策略

- **基于兴趣**：根据学生历史学习内容推荐相关主题
- **基于进度**：推荐当前章节的深入阅读材料
- **基于目标**：推荐与课程目标相关的拓展资源
