
import json, sys, os, textwrap

def main():
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        data = json.load(f)

    from PIL import Image, ImageDraw, ImageFont

    title = data.get('title', '')
    chapter = data.get('chapter', '')
    slides = data.get('slides', [])
    out_dir = data.get('output_dir', '.')
    os.makedirs(out_dir, exist_ok=True)

    W, H = 1920, 1080

    # ── 加载字体 ──────────────────────────────────────────────
    font_paths = [
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/msyhbd.ttc",
        "C:/Windows/Fonts/simhei.ttf",
        "C:/Windows/Fonts/simsun.ttc",
    ]
    code_paths = [
        "C:/Windows/Fonts/consola.ttf",
        "C:/Windows/Fonts/cour.ttf",
    ]

    def load(paths, size):
        for p in paths:
            try:
                return ImageFont.truetype(p, size)
            except:
                pass
        return ImageFont.load_default()

    ft_cover  = load(font_paths, 72)
    ft_ch     = load(font_paths, 36)
    ft_title  = load(font_paths, 48)
    ft_sub    = load(font_paths, 28)
    ft_body   = load(font_paths, 26)
    ft_bold   = load([font_paths[1]] + font_paths, 28)
    ft_small  = load(font_paths, 22)
    ft_tiny   = load(font_paths, 18)
    ft_code   = load(code_paths, 20)
    ft_tbl    = load(font_paths, 22)
    ft_tblh   = load([font_paths[1]] + font_paths, 22)

    # ── 颜色常量 ──────────────────────────────────────────────
    DARK_BLUE = '#0958D9'
    BLUE      = '#1677FF'
    WHITE     = '#FFFFFF'
    GRAY      = '#666666'
    LIGHT_BG  = '#F0F4F8'
    CODE_BG   = '#282C34'
    CODE_FG   = '#ABB2BF'

    def draw_wrapped(draw, text, x, y, font, fill, max_w, line_h=None):
        """Draw text with word-wrap, return final y."""
        if not text:
            return y
        if line_h is None:
            try:
                line_h = font.getbbox("测")[3] + 8
            except:
                line_h = 36
        # Estimate chars per line
        try:
            cw = font.getbbox("测测")[2] / 2
        except:
            cw = 20
        chars = max(int(max_w / cw), 10)
        lines = textwrap.wrap(text, width=chars)
        for ln in lines:
            draw.text((x, y), ln, font=font, fill=fill)
            y += line_h
        return y

    idx = 0  # output image counter

    # ══════════════════════════════════════════════════════════
    #  封面
    # ══════════════════════════════════════════════════════════
    idx += 1
    img = Image.new('RGB', (W, H), DARK_BLUE)
    draw = ImageDraw.Draw(img)

    # 装饰线
    draw.rectangle([(0, 0), (W, 10)], fill=BLUE)
    draw.rectangle([(0, H-10), (W, H)], fill=BLUE)

    # 标题（居中）
    try:
        bbox = draw.textbbox((0,0), title, font=ft_cover)
        tw = bbox[2] - bbox[0]
    except:
        tw = len(title) * 72
    tx = (W - tw) // 2
    draw.text((tx, H//2 - 100), title, font=ft_cover, fill=WHITE)

    # 章节
    if chapter:
        try:
            bbox = draw.textbbox((0,0), chapter, font=ft_ch)
            tw = bbox[2] - bbox[0]
        except:
            tw = len(chapter) * 36
        draw.text(((W - tw)//2, H//2 + 10), chapter, font=ft_ch, fill='#BBCCFF')

    # 底部
    bot = '课程知识图谱与数字孪生平台'
    try:
        bbox = draw.textbbox((0,0), bot, font=ft_small)
        tw = bbox[2] - bbox[0]
    except:
        tw = len(bot) * 22
    draw.text(((W - tw)//2, H - 80), bot, font=ft_small, fill='#99AADD')

    out = f"{out_dir}/slide_{idx:03d}.png"
    img.save(out)
    print(out)

    # ══════════════════════════════════════════════════════════
    #  内容页
    # ══════════════════════════════════════════════════════════
    for si, s in enumerate(slides):
        idx += 1
        img = Image.new('RGB', (W, H), WHITE)
        draw = ImageDraw.Draw(img)

        s_title  = s.get('title', '')
        subtitle = s.get('subtitle', '')
        bullets  = s.get('bullets', [])
        code     = s.get('code', '')
        has_code = bool(code.strip())

        # 顶部蓝色装饰条
        draw.rectangle([(0, 0), (W, 8)], fill=BLUE)

        # 标题
        draw.text((60, 25), s_title, font=ft_title, fill=DARK_BLUE)

        # 页码
        pg = f'{si+1}/{len(slides)}'
        try:
            bbox = draw.textbbox((0,0), pg, font=ft_small)
            pw_ = bbox[2] - bbox[0]
        except:
            pw_ = len(pg) * 22
        draw.text((W - 60 - pw_, 35), pg, font=ft_small, fill=GRAY)

        # 副标题
        top_y = 85
        if subtitle:
            draw.text((60, top_y), subtitle, font=ft_sub, fill=GRAY)
            top_y += 40

        # 分隔线
        draw.line([(60, top_y), (W - 60, top_y)], fill='#DDDDDD', width=2)
        top_y += 15

        # 内容区域
        content_x = 60
        content_w = (W // 2 - 40) if has_code else (W - 120)
        y = top_y

        # 分离 table rows 和普通 bullets
        normal = []
        table_rows = []
        for b in bullets:
            t = str(b)
            if t.startswith('|'):
                table_rows.append(t)
            else:
                normal.append(t)

        # 绘制普通 bullets
        for b in normal:
            if y > H - 80:
                break
            if b.startswith('\u3010'):
                # 子标题 【xxx】
                y += 8
                draw.text((content_x, y), b, font=ft_bold, fill=DARK_BLUE)
                y += 38
            elif b.startswith('  \u00b7'):
                # 缩进项
                draw.text((content_x + 40, y), b.strip(), font=ft_body, fill=GRAY)
                y += 34
            else:
                # 普通要点
                text = f'\u2022 {b}' if not b.startswith('\u2022') else b
                y = draw_wrapped(draw, text, content_x + 10, y, ft_body, '#333333', content_w - 10, 34)
                y += 4

        # 绘制表格
        if table_rows and y < H - 120:
            y += 10
            parsed = []
            for r in table_rows:
                cols = [c.strip() for c in r.strip().strip('|').split('|')]
                if cols:
                    parsed.append(cols)
            if parsed:
                n_cols = max(len(r) for r in parsed)
                col_w = min(content_w // n_cols, 350)
                row_h = 36
                for ri, row in enumerate(parsed):
                    while len(row) < n_cols:
                        row.append('')
                    rx = content_x + 10
                    for ci, val in enumerate(row):
                        x1, y1 = rx, y
                        x2, y2 = rx + col_w, y + row_h
                        if ri == 0:
                            draw.rectangle([(x1, y1), (x2, y2)], fill=DARK_BLUE, outline='#BBBBBB')
                            draw.text((x1 + 8, y1 + 6), val[:20], font=ft_tblh, fill=WHITE)
                        else:
                            bg = LIGHT_BG if ri % 2 == 0 else WHITE
                            draw.rectangle([(x1, y1), (x2, y2)], fill=bg, outline='#CCCCCC')
                            draw.text((x1 + 8, y1 + 6), val[:25], font=ft_tbl, fill='#333333')
                        rx += col_w
                    y += row_h

        # 代码块
        if has_code:
            code_x = W // 2 + 20
            code_w = W - code_x - 40
            code_y = top_y
            # 背景
            draw.rectangle([(code_x, code_y), (W - 40, H - 40)], fill=CODE_BG)
            # 代码头标签
            draw.rectangle([(code_x, code_y), (code_x + 70, code_y + 24)], fill='#3C4049')
            draw.text((code_x + 8, code_y + 3), 'Code', font=ft_tiny, fill='#999999')
            cy = code_y + 30
            for cl in code.strip().split('\n'):
                if cy > H - 60:
                    break
                draw.text((code_x + 15, cy), cl, font=ft_code, fill=CODE_FG)
                cy += 26

        out = f"{out_dir}/slide_{idx:03d}.png"
        img.save(out)
        print(out)

    # ══════════════════════════════════════════════════════════
    #  结束页
    # ══════════════════════════════════════════════════════════
    idx += 1
    img = Image.new('RGB', (W, H), DARK_BLUE)
    draw = ImageDraw.Draw(img)
    draw.rectangle([(0, 0), (W, 10)], fill=BLUE)
    draw.rectangle([(0, H-10), (W, H)], fill=BLUE)

    txt = '谢谢！'
    try:
        bbox = draw.textbbox((0,0), txt, font=ft_cover)
        tw = bbox[2] - bbox[0]
    except:
        tw = 216
    draw.text(((W - tw)//2, H//2 - 80), txt, font=ft_cover, fill=WHITE)

    txt2 = 'Q & A'
    try:
        bbox = draw.textbbox((0,0), txt2, font=ft_ch)
        tw = bbox[2] - bbox[0]
    except:
        tw = 120
    draw.text(((W - tw)//2, H//2 + 30), txt2, font=ft_ch, fill='#BBCCFF')

    out = f"{out_dir}/slide_{idx:03d}.png"
    img.save(out)
    print(out)

    print(f"Total: {idx} images", file=sys.stderr)

if __name__ == '__main__':
    main()
