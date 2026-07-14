"""
将教案Markdown文件批量转换为PDF
"""
import os
import glob
from markdown import markdown
from weasyprint import HTML, CSS

# CSS样式
css_style = '''
@page {
    size: A4;
    margin: 2cm;
    @bottom-center {
        content: counter(page);
        font-size: 10pt;
        color: #666;
    }
}
body {
    font-family: "Microsoft YaHei", "SimSun", sans-serif;
    font-size: 11pt;
    line-height: 1.8;
    color: #333;
}
h1 {
    font-size: 18pt;
    color: #1a5276;
    border-bottom: 2px solid #1a5276;
    padding-bottom: 10px;
    margin-top: 30px;
}
h2 {
    font-size: 14pt;
    color: #2874a6;
    margin-top: 25px;
    border-left: 4px solid #2874a6;
    padding-left: 10px;
}
h3 {
    font-size: 12pt;
    color: #2e86c1;
    margin-top: 20px;
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
}
th, td {
    border: 1px solid #ddd;
    padding: 8px;
    text-align: left;
}
th {
    background-color: #f2f2f2;
    font-weight: bold;
}
tr:nth-child(even) {
    background-color: #f9f9f9;
}
code {
    background-color: #f4f4f4;
    padding: 2px 5px;
    border-radius: 3px;
    font-family: Consolas, monospace;
    font-size: 10pt;
}
pre {
    background-color: #f4f4f4;
    padding: 15px;
    border-radius: 5px;
    overflow-x: auto;
    font-size: 9pt;
    line-height: 1.5;
}
blockquote {
    border-left: 4px solid #3498db;
    margin: 15px 0;
    padding: 10px 20px;
    background-color: #f8f9fa;
    color: #555;
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
}
hr {
    border: none;
    border-top: 1px solid #ddd;
    margin: 20px 0;
}
'''

def md_to_pdf(md_file, pdf_file):
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
</head>
<body>
{html_content}
</body>
</html>'''
    
    # 生成PDF
    HTML(string=full_html).write_pdf(
        pdf_file,
        stylesheets=[CSS(string=css_style)]
    )
    print(f'  -> 已生成: {os.path.basename(pdf_file)}')

def main():
    # 获取所有md文件
    md_files = sorted(glob.glob('*.md'))
    md_files = [f for f in md_files if f != 'generate_lesson_plans.py' and f != 'md_to_pdf.py']
    
    print(f'找到 {len(md_files)} 个教案文件')
    print('=' * 50)
    
    for md_file in md_files:
        pdf_file = md_file.replace('.md', '.pdf')
        try:
            md_to_pdf(md_file, pdf_file)
        except Exception as e:
            print(f'  -> 错误: {e}')
    
    print('=' * 50)
    print('转换完成!')

if __name__ == '__main__':
    main()
