# 工具目录

`tools/` 存放离线生成、转换、校验类工具。这些工具不是应用运行必需项，但服务课程资源生成、归档模板处理和演示素材制作。

## 当前工具

| 工具 | 用途 |
| --- | --- |
| `compute_resource_checksums.py` | 计算课程资源校验值 |
| `convert_archive_templates.py` | 归档模板转换 |
| `convert_ckgdt_templates.py` | CKGDT 模板转换 |
| `export_student_groups.py` | 导出学生分组 |
| `generate_ckgdt_pdfs.py` | 生成 CKGDT PDF |
| `generate_ckgdt_pptx.py` | 生成 CKGDT PPTX |
| `generate_ckgdt_videos.py` | 生成 CKGDT 视频 |
| `screenshot_app.py` | 应用截图辅助 |
| `check_version.py` | 版本检查 |

## 推荐分类

```text
tools/coursegen/   # 课程资源生成
tools/archive/     # 归档模板转换
tools/media/       # 视频、PPT、PDF、截图生成
tools/qa/          # 校验、检查、报告生成
tools/cache/       # 本地缓存包和临时下载文件，不入库
```

后续迁移工具时，应同步更新本文件和引用脚本。
