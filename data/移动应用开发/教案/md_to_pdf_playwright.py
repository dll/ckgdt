"""
使用Playwright将教案Markdown文件批量转换为PDF
"""
import os
import glob
import asyncio
from markdown import markdown
from playwright.async_api import async_playwright

# CSS样式
css_style = '''
<style>
@page {
    size: A4;
    margin: 2cm;
}
body {
    font-family: "Microsoft YaHei", "SimSun", "Noto Sans CJK SC", sans-serif;
    font-size: 11pt;
    line-height: 1.8;
    color: #333;
    max-width: 100%;
}
h1 {
    font-size: 20pt;
    color: #1a5276;
    border-bottom: 3px solid #1a5276;
    padding-bottom: 12px;
    margin-top: 0;
    page-break-before: always;
}
h1:first-of-type {
    page-break-before: auto;
}
h2 {
    font-size: 15pt;
    color: #2874a6;
    margin-top: 25px;
    border-left: 5px solid #2874a6;
    padding-left: 12px;
    page-break-after: avoid;
}
h3 {
    font-size: 13pt;
    color: #2e86c1;
    margin-top: 20px;
    page-break-after: avoid;
}
h4 {
    font-size: 11pt;
    color: #3498db;
    margin-top: 15px;
}
table {
    width: 100%;
    border-collapse: collapse;
    margin: 15px 0;
    font-size: 10pt;
    page-break-inside: avoid;
}
th, td {
    border: 1px solid #bbb;
    padding: 8px 10px;
    text-align: left;
    vertical-align: top;
}
th {
    background-color: #f0f0f0;
    font-weight: bold;
    color: #1a5276;
}
tr:nth-child(even) {
    background-color: #f9f9f9;
}
code {
    background-color: #f4f4f4;
    padding: 2px 6px;
    border-radius: 3px;
    font-family: "Consolas", "Courier New", monospace;
    font-size: 10pt;
    color: #c7254e;
}
pre {
    background-color: #f8f8f8;
    padding: 15px;
    border-radius: 5px;
    border: 1px solid #e0e0e0;
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
    border-left: 4px solid #3498db;
    margin: 15px 0;
    padding: 12px 20px;
    background-color: #f8f9fa;
    color: #555;
    font-style: italic;
}
ul, ol {
    margin: 10px 0;
    padding-left: 30px;
}
li {
    margin: 5px 0;
}
strong {
    color: #1a5276;
    font-weight: bold;
}
hr {
    border: none;
    border-top: 2px solid #eee;
    margin: 25px 0;
}
p {
    margin: 10px 0;
    text-align: justify;
}
</style>
'''

async def md_to_pdf(md_file, pdf_file, browser):
    """将单个md文件转换为pdf"""
    print(f'转换: {os.path.basename(md_file)}')
    
    # 读取md内容
    with open(md_file, 'r', encoding='utf-8') as f:
        md_content = f.read()
    
    # 转换为HTML
    html_content = markdown(
        md_content,
        extensions=['tables', 'fenced_code', 'toc', 'nl2br']
    )
    
    # 包装完整HTML
    full_html = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>{os.path.basename(md_file).replace('.md', '')}</title>
    {css_style}
</head>
<body>
{html_content}
</body>
</html>'''
    
    # 创建临时HTML文件
    temp_html = md_file.replace('.md', '_temp.html')
    with open(temp_html, 'w', encoding='utf-8') as f:
        f.write(full_html)
    
    try:
        # 使用Playwright生成PDF
        page = await browser.new_page()
        await page.goto(f'file:///{os.path.abspath(temp_html)}')
        await page.pdf(
            path=pdf_file,
            format='A4',
            margin={
                'top': '2cm',
                'bottom': '2cm',
                'left': '2cm',
                'right': '2cm'
            },
            print_background=True
        )
        await page.close()
        print(f'  -> 已生成: {os.path.basename(pdf_file)}')
    finally:
        # 删除临时文件
        if os.path.exists(temp_html):
            os.remove(temp_html)

async def main():
    # 获取所有md文件
    md_files = sorted(glob.glob('*.md'))
    md_files = [f for f in md_files if f not in ['generate_lesson_plans.py', 'md_to_pdf.py', 'md_to_pdf_playwright.py']]
    
    print(f'找到 {len(md_files)} 个教案文件')
    print('=' * 50)
    
    async with async_playwright() as p:
        # 启动浏览器
        browser = await p.chromium.launch()
        
        for md_file in md_files:
            pdf_file = md_file.replace('.md', '.pdf')
            try:
                await md_to_pdf(md_file, pdf_file, browser)
            except Exception as e:
                print(f'  -> 错误: {e}')
        
        await browser.close()
    
    print('=' * 50)
    print('转换完成!')

if __name__ == '__main__':
    asyncio.run(main())
