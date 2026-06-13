# -*- coding: utf-8 -*-
"""生成答辩幻灯片 HTML (1920x1080)。
运行: python gen_html.py  -> 输出 build/slides/slide_NN.html
被 Chrome headless 渲染为 PNG。导入 slides_data.SLIDES。
"""
import os, html
from slides_data import (SLIDES, AUTHOR, ADVISOR, SCHOOL, MAJOR, CLASS, SNO, TITLE, DATE)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "slides")
FIGS = os.path.join(HERE, "figs").replace("\\", "/")
os.makedirs(OUT, exist_ok=True)

C = {
    "bg0": "#070D1B", "bg1": "#0A1428", "bg2": "#0E1C38",
    "panel": "#101F3D", "panelb": "#1B3258",
    "cyan": "#22D3EE", "cyan2": "#38BDF8", "ice": "#CFE8FF",
    "amber": "#FBBF24", "red": "#F8717A", "green": "#34D399",
    "text": "#EAF2FF", "muted": "#8FA8C8", "dim": "#5C7290",
    "line": "rgba(120,170,230,0.16)",
}
FONT = "'Microsoft YaHei','PingFang SC','Noto Sans CJK SC',sans-serif"

BASE_CSS = f"""
*{{margin:0;padding:0;box-sizing:border-box;}}
html,body{{width:1920px;height:1080px;overflow:hidden;font-family:{FONT};
  color:{C['text']};background:{C['bg1']};}}
.stage{{position:relative;width:1920px;height:1080px;
  background:
    radial-gradient(1100px 700px at 78% 12%, rgba(34,211,238,0.10), transparent 60%),
    radial-gradient(900px 700px at 12% 92%, rgba(56,189,248,0.08), transparent 60%),
    linear-gradient(135deg,{C['bg0']} 0%,{C['bg1']} 45%,{C['bg2']} 100%);
  overflow:hidden;}}
.grid{{position:absolute;inset:0;
  background-image:linear-gradient({C['line']} 1px,transparent 1px),
    linear-gradient(90deg,{C['line']} 1px,transparent 1px);
  background-size:60px 60px;opacity:.55;}}
.scan{{position:absolute;inset:0;background:repeating-linear-gradient(
  0deg,transparent 0 3px,rgba(0,0,0,0.10) 3px 4px);opacity:.25;}}
.corner{{position:absolute;width:54px;height:54px;border:2px solid {C['cyan']};opacity:.5;}}
.corner.tl{{top:40px;left:40px;border-right:none;border-bottom:none;}}
.corner.tr{{top:40px;right:40px;border-left:none;border-bottom:none;}}
.corner.bl{{bottom:40px;left:40px;border-right:none;border-top:none;}}
.corner.br{{bottom:40px;right:40px;border-left:none;border-top:none;}}
.head{{position:absolute;top:54px;left:96px;right:96px;display:flex;
  align-items:center;justify-content:space-between;z-index:5;}}
.kicker{{display:flex;align-items:center;gap:18px;}}
.kdot{{width:13px;height:13px;border-radius:50%;background:{C['cyan']};
  box-shadow:0 0 16px {C['cyan']};}}
.ktext{{font-size:23px;letter-spacing:6px;color:{C['cyan']};font-weight:700;}}
.kid{{font-size:19px;letter-spacing:3px;color:{C['dim']};font-family:Consolas,monospace;}}
.title{{position:absolute;left:96px;top:118px;z-index:5;}}
.title h1{{font-size:60px;font-weight:800;letter-spacing:2px;line-height:1.15;}}
.title .bar{{width:120px;height:6px;margin-top:24px;border-radius:3px;
  background:linear-gradient(90deg,{C['cyan']},{C['cyan2']});box-shadow:0 0 22px rgba(34,211,238,.6);}}
.foot{{position:absolute;bottom:50px;left:96px;right:96px;display:flex;
  justify-content:space-between;align-items:center;color:{C['dim']};
  font-size:19px;letter-spacing:2px;z-index:5;}}
.foot .fr{{font-family:Consolas,monospace;}}
.accent{{color:{C['cyan']};}} .amber{{color:{C['amber']};}}
.green{{color:{C['green']};}} .red{{color:{C['red']};}}
"""

def esc(s): return html.escape(str(s))

def page(inner, extra_css=""):
    return f"""<!doctype html><html><head><meta charset="utf-8">
<style>{BASE_CSS}{extra_css}</style></head><body>
<div class="stage"><div class="grid"></div><div class="scan"></div>
<div class="corner tl"></div><div class="corner tr"></div>
<div class="corner bl"></div><div class="corner br"></div>
{inner}
</div></body></html>"""

def header(kick, idx, total):
    return f"""<div class="head"><div class="kicker">
      <div class="kdot"></div><div class="ktext">{esc(kick)}</div></div>
      <div class="kid">MAD-FORM · {idx:02d} / {total:02d}</div></div>"""

def footer():
    return f"""<div class="foot"><div>{esc(AUTHOR)} · {esc(MAJOR)}</div>
      <div class="fr">{esc(TITLE)}</div></div>"""

def std_title(t):
    return f'<div class="title"><h1>{t}</h1><div class="bar"></div></div>'

# 布局模板在 gen_layouts.py 中实现
if __name__ == "__main__":
    from gen_layouts import render_slide
    total = len(SLIDES)
    for i, s in enumerate(SLIDES, 1):
        htmlstr = render_slide(s, i, total, C, FIGS, page, header, footer, std_title, esc)
        fn = os.path.join(OUT, f"slide_{i:02d}.html")
        with open(fn, "w", encoding="utf-8") as f:
            f.write(htmlstr)
    print(f"generated {total} html slides -> {OUT}")
