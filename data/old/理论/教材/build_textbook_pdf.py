"""
合并6章教材MD文件，生成带书脊排版的PDF教材
"""
import os
import asyncio
from markdown import markdown
from playwright.async_api import async_playwright

base_dir = os.path.dirname(os.path.abspath(__file__))
chapters = [
    '第一章_移动应用开发技术体系.md',
    '第二章_原生开发基础.md',
    '第三章_跨平台应用开发.md',
    '第四章_微信小程序开发.md',
    '第五章_鸿蒙多端应用开发.md',
    '第六章_综合开发实践.md',
]

def build_textbook():
    """合并所有章节"""
    parts = []
    
    # 封面
    parts.append('# 移动应用开发')
    parts.append('')
    parts.append('**适用专业**：软件工程')
    parts.append('')
    parts.append('**开课单位**：计算机与信息工程学院')
    parts.append('')
    parts.append('**总学时**：48（讲课：24，实验：24）')
    parts.append('')
    parts.append('**总学分**：2.5')
    parts.append('')
    parts.append('**先修课程**：面向对象程序设计、数据库原理')
    parts.append('')
    parts.append('**考核方式**：考查')
    parts.append('')
    parts.append('---')
    parts.append('\n<div style="page-break-after: always;"></div>\n')
    
    # 目录页
    parts.append('# 目录')
    parts.append('')
    parts.append('- 第一章 移动应用开发技术体系')
    parts.append('- 第二章 原生开发基础')
    parts.append('- 第三章 跨平台应用开发')
    parts.append('- 第四章 微信小程序开发')
    parts.append('- 第五章 鸿蒙多端应用开发')
    parts.append('- 第六章 综合开发实践')
    parts.append('')
    parts.append('---')
    parts.append('\n<div style="page-break-after: always;"></div>\n')
    
    # 各章内容
    for ch in chapters:
        fpath = os.path.join(base_dir, ch)
        print(f'读取: {ch}')
        with open(fpath, 'r', encoding='utf-8') as f:
            content = f.read()
        parts.append(content)
        parts.append('')
        parts.append('\n<div style="page-break-after: always;"></div>\n')
    
    return '\n'.join(parts)

css_style = '''
<style>
@page {
    size: A4;
    margin: 2.5cm 2.5cm 2.5cm 2.5cm;
    @bottom-center {
        content: counter(page);
        font-size: 10pt;
        color: #666;
    }
}
body {
    font-family: "SimSun", "宋体", "Noto Serif CJK SC", serif;
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
    font-size: 28pt;
    margin-top: 25%;
}
h2 {
    font-size: 16pt;
    color: #1a1a1a;
    margin-top: 30px;
    margin-bottom: 12px;
    border-left: 5px solid #333;
    padding-left: 12px;
    page-break-after: avoid;
    font-family: "SimHei", "黑体", sans-serif;
}
h3 {
    font-size: 14pt;
    color: #222;
    margin-top: 22px;
    margin-bottom: 10px;
    page-break-after: avoid;
    font-family: "SimHei", "黑体", sans-serif;
}
h4 {
    font-size: 12pt;
    color: #333;
    margin-top: 16px;
    margin-bottom: 8px;
    page-break-after: avoid;
    font-family: "SimHei", "黑体", sans-serif;
}
p {
    margin: 8px 0;
    text-indent: 2em;
}
ul, ol {
    margin: 8px 0;
    padding-left: 30px;
}
li {
    margin: 4px 0;
    text-align: justify;
}
li p {
    text-indent: 0;
    margin: 4px 0;
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
    vertical-align: top;
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
    font-family: "Consolas", "Courier New", monospace;
    font-size: 10pt;
    color: #c7254e;
}
pre {
    background-color: #f8f8f8;
    padding: 12px 15px;
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    overflow-x: auto;
    font-size: 9pt;
    line-height: 1.5;
    page-break-inside: avoid;
}
pre code {
    background: none;
    padding: 0;
    color: #333;
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
    md_content = build_textbook()
    
    # 保存合并后的MD
    md_path = os.path.join(base_dir, '..', '移动应用开发教材.md')
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
    html_path = os.path.join(base_dir, '..', '移动应用开发教材.html')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(full_html)
    print(f'已保存HTML: {html_path}')
    
    # 生成PDF
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page()
        await page.goto(f'file:///{html_path}')
        
        pdf_path = os.path.join(base_dir, '..', '移动应用开发教材.pdf')
        await page.pdf(
            path=pdf_path,
            format='A4',
            margin={'top': '2.5cm', 'bottom': '2.5cm', 'left': '2.5cm', 'right': '2.5cm'},
            print_background=True
        )
        await browser.close()
        print(f'已生成PDF: {pdf_path}')

if __name__ == '__main__':
    asyncio.run(generate_pdf())
