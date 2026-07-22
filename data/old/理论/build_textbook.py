"""
将理论课件MD文件清理后合并成教材，生成PDF
"""
import os
import re
import asyncio
from markdown import markdown
from playwright.async_api import async_playwright

# 文件顺序
files = [
    '第一章 移动应用开发技术体系1_new.md',
    '第一章 移动应用开发技术体系2_new.md',
    '第二章 原生开发基础1_new.md',
    '第二章 原生开发基础2_new.md',
    '第三章 跨平台应用开发1_new.md',
    '第三章 跨平台应用开发2_new.md',
    '第四章 微信小程序开发1_new.md',
    '第四章 微信小程序开发2_new.md',
    '第五章 鸿蒙多端应用开发1_new.md',
    '第五章 鸿蒙多端应用开发2_new.md',
    '第六章 综合开发实践1_new.md',
    '第六章 综合开发实践2_new.md',
]

def clean_file(content):
    """清理单个文件内容"""
    lines = content.split('\n')
    result = []
    in_pretest = False
    in_posttest = False
    skip_until_chapter = False
    
    for line in lines:
        stripped = line.strip()
        
        # 跳过提示词（文件开头到"## 学前测验"之前）
        if stripped.startswith('请为计科大三学生生成'):
            in_pretest = True
            continue
        
        # 检测到学前测验开始
        if stripped.startswith('## 学前测验') or stripped.startswith('# 学前测验'):
            in_pretest = True
            continue
        
        # 检测到章节标题，退出学前测验模式
        if re.match(r'^#+\s+第[一二三四五六]章', stripped):
            in_pretest = False
            skip_until_chapter = False
            # 提取章节标题
            result.append(stripped)
            continue
        
        if in_pretest:
            continue
        
        # 跳过学后测验
        if '学后测验' in stripped or '课后测验' in stripped or '阶段测验' in stripped:
            in_posttest = True
            continue
        
        if in_posttest:
            # 检测到下一个章节或文件结束则停止跳过
            if stripped.startswith('#') and '第' in stripped and '章' in stripped:
                in_posttest = False
            continue
        
        # 跳过空幻灯片标记行
        if stripped.startswith('## 课件文件名称'):
            continue
        if stripped.startswith('### 幻灯片') and '：' in stripped:
            # 只提取幻灯片标题，不输出（避免和- **标题**：重复）
            continue
        
        # 清理幻灯片格式标记
        if stripped.startswith('- **标题**：'):
            title = stripped.replace('- **标题**：', '').strip()
            result.append(f'## {title}')
            continue
        
        if stripped.startswith('- **内容**：'):
            continue
        
        # 清理带**的列表项标记，保留纯文本
        line_cleaned = re.sub(r'^\s*[-*]\s+\*\*([^*]+)\*\*\s*：\s*', r'- **\1**：', line)
        if line_cleaned != line:
            result.append(line_cleaned)
            continue
        
        # 清理缩进列表标记（将缩进的内容提升到正常层级）
        if stripped.startswith('- ') or stripped.startswith('* '):
            cleaned = re.sub(r'^\s*[-*]\s+', '- ', line)
            result.append(cleaned)
            continue
        
        # 保留其他内容行
        if stripped:
            result.append(line)
    
    return '\n'.join(result)

def build_textbook():
    """构建教材内容"""
    all_content = []
    
    # 教材封面/标题
    all_content.append('# 移动应用开发教材')
    all_content.append('')
    all_content.append('**适用专业**：软件工程')
    all_content.append('')
    all_content.append('---')
    all_content.append('')
    
    for fname in files:
        fpath = os.path.join(os.path.dirname(__file__), fname)
        print(f'处理: {fname}')
        
        with open(fpath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        cleaned = clean_file(content)
        if cleaned.strip():
            all_content.append(cleaned)
            all_content.append('')
            all_content.append('---')
            all_content.append('')
    
    return '\n'.join(all_content)

# CSS样式
css_style = '''
<style>
@page {
    size: A4;
    margin: 2.5cm 2cm 2.5cm 2cm;
    @bottom-center {
        content: counter(page);
        font-size: 10pt;
        color: #666;
    }
}
body {
    font-family: "SimSun", "宋体", "Noto Sans CJK SC", serif;
    font-size: 11pt;
    line-height: 1.8;
    color: #333;
    text-align: justify;
}
h1 {
    font-size: 22pt;
    color: #1a1a1a;
    text-align: center;
    border-bottom: 3px solid #333;
    padding-bottom: 15px;
    margin-top: 0;
    page-break-before: always;
    font-family: "SimHei", "黑体", sans-serif;
}
h1:first-of-type {
    page-break-before: auto;
    border-bottom: none;
    font-size: 26pt;
    margin-top: 30%;
}
h2 {
    font-size: 16pt;
    color: #1a1a1a;
    margin-top: 25px;
    margin-bottom: 12px;
    border-left: 5px solid #333;
    padding-left: 12px;
    page-break-after: avoid;
    font-family: "SimHei", "黑体", sans-serif;
}
h3 {
    font-size: 13pt;
    color: #333;
    margin-top: 18px;
    margin-bottom: 8px;
    page-break-after: avoid;
    font-family: "SimHei", "黑体", sans-serif;
}
h4 {
    font-size: 11pt;
    color: #444;
    margin-top: 12px;
    margin-bottom: 6px;
    font-family: "SimHei", "黑体", sans-serif;
}
ul, ol {
    margin: 8px 0;
    padding-left: 25px;
}
li {
    margin: 4px 0;
    text-align: justify;
}
p {
    margin: 8px 0;
    text-indent: 2em;
}
p:first-of-type {
    text-indent: 0;
}
strong {
    font-weight: bold;
    color: #1a1a1a;
}
hr {
    border: none;
    border-top: 1px solid #ddd;
    margin: 20px 0;
}
table {
    width: 100%;
    border-collapse: collapse;
    margin: 15px 0;
    font-size: 10pt;
    page-break-inside: avoid;
}
th, td {
    border: 1px solid #999;
    padding: 8px 10px;
    text-align: left;
}
th {
    background-color: #f5f5f5;
    font-weight: bold;
}
tr:nth-child(even) {
    background-color: #fafafa;
}
code {
    background-color: #f4f4f4;
    padding: 2px 5px;
    font-family: "Consolas", monospace;
    font-size: 10pt;
}
pre {
    background-color: #f8f8f8;
    padding: 12px;
    border: 1px solid #e0e0e0;
    overflow-x: auto;
    font-size: 9pt;
    line-height: 1.5;
    page-break-inside: avoid;
}
blockquote {
    border-left: 3px solid #666;
    margin: 10px 0;
    padding: 8px 15px;
    background-color: #f9f9f9;
    color: #555;
}
</style>
'''

async def generate_pdf():
    """生成PDF"""
    md_content = build_textbook()
    
    # 保存清理后的MD
    md_path = os.path.join(os.path.dirname(__file__), '移动应用开发教材.md')
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write(md_content)
    print(f'已保存MD: {md_path}')
    
    # 转换为HTML
    html_body = markdown(md_content, extensions=['tables', 'fenced_code', 'nl2br'])
    
    full_html = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>移动应用开发教材</title>
    {css_style}
</head>
<body>
{html_body}
</body>
</html>'''
    
    # 保存HTML
    html_path = os.path.join(os.path.dirname(__file__), '移动应用开发教材.html')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(full_html)
    print(f'已保存HTML: {html_path}')
    
    # 使用Playwright生成PDF
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()
        await page.goto(f'file:///{html_path}')
        
        pdf_path = os.path.join(os.path.dirname(__file__), '移动应用开发教材.pdf')
        await page.pdf(
            path=pdf_path,
            format='A4',
            margin={'top': '2.5cm', 'bottom': '2.5cm', 'left': '2cm', 'right': '2cm'},
            print_background=True
        )
        await browser.close()
        print(f'已生成PDF: {pdf_path}')

if __name__ == '__main__':
    asyncio.run(generate_pdf())
