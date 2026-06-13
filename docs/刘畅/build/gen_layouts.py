# -*- coding: utf-8 -*-
"""每种 kind 的幻灯片布局模板。被 gen_html.py 导入。"""

def render_slide(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    fn = LAYOUTS.get(s["kind"])
    if not fn:
        return page(header("SLIDE", idx, total) + std_title(esc(s.get("id",""))) + footer())
    return fn(s, idx, total, C, FIGS, page, header, footer, std_title, esc)


def L_cover(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    from slides_data import TITLE, AUTHOR, ADVISOR, SCHOOL, MAJOR, CLASS, SNO, DATE
    css = f"""
.cv-mark{{position:absolute;top:148px;left:96px;display:flex;align-items:center;gap:24px;z-index:6;}}
.cv-em{{width:80px;height:80px;border:3px solid {C['cyan']};border-radius:50%;
  display:flex;align-items:center;justify-content:center;position:relative;
  box-shadow:0 0 26px rgba(34,211,238,.5);}}
.cv-em::before{{content:'';position:absolute;width:14px;height:14px;border-radius:50%;
  background:{C['cyan']};box-shadow:0 0 16px {C['cyan']};}}
.cv-em::after{{content:'';position:absolute;width:124px;height:124px;border-radius:50%;
  border:1px solid rgba(34,211,238,.28);}}
.cv-org{{font-size:26px;letter-spacing:5px;color:{C['ice']};font-weight:700;}}
.cv-sub{{font-size:17px;letter-spacing:3px;color:{C['dim']};margin-top:8px;font-family:Consolas,monospace;}}
.cv-band{{position:absolute;top:308px;left:98px;font-size:22px;letter-spacing:10px;
  color:{C['cyan']};font-weight:700;}}
.cv-title{{position:absolute;top:362px;left:96px;right:520px;z-index:6;}}
.cv-title h1{{font-size:82px;font-weight:900;line-height:1.2;letter-spacing:2px;
  background:linear-gradient(90deg,#EAF2FF 35%,{C['cyan']});-webkit-background-clip:text;
  -webkit-text-fill-color:transparent;}}
.cv-rule{{width:210px;height:7px;margin-top:36px;border-radius:4px;
  background:linear-gradient(90deg,{C['cyan']},transparent);box-shadow:0 0 24px rgba(34,211,238,.6);}}
.cv-meta{{position:absolute;bottom:148px;left:96px;display:grid;
  grid-template-columns:repeat(2,auto);gap:20px 90px;z-index:6;}}
.cv-meta .row{{display:flex;align-items:center;gap:18px;}}
.cv-meta .lab{{font-size:21px;color:{C['dim']};letter-spacing:4px;min-width:100px;}}
.cv-meta .val{{font-size:25px;color:{C['ice']};font-weight:700;letter-spacing:2px;}}
.cv-radar{{position:absolute;right:120px;top:336px;width:500px;height:500px;opacity:.55;}}
.cv-radar .ring{{position:absolute;border:1px solid rgba(34,211,238,.32);border-radius:50%;}}
.cv-radar .sweep{{position:absolute;inset:0;border-radius:50%;
  background:conic-gradient(from 0deg, rgba(34,211,238,.22), transparent 28%);}}
.cv-radar .dot{{position:absolute;width:12px;height:12px;border-radius:50%;
  background:{C['amber']};box-shadow:0 0 14px {C['amber']};}}
.cv-date{{position:absolute;bottom:150px;right:96px;font-size:23px;color:{C['cyan']};
  letter-spacing:4px;font-weight:700;text-align:right;}}
"""
    rings = "".join(f'<div class="ring" style="inset:{i*62}px;"></div>' for i in range(4))
    radar = f"""<div class="cv-radar"><div class="sweep"></div>{rings}
      <div class="ring" style="inset:0;border-color:rgba(34,211,238,.5);"></div>
      <div class="dot" style="top:30%;left:62%;"></div>
      <div class="dot" style="top:58%;left:40%;background:{C['cyan']};box-shadow:0 0 14px {C['cyan']};"></div>
      <div class="dot" style="top:70%;left:66%;background:{C['green']};box-shadow:0 0 14px {C['green']};"></div></div>"""
    meta = f"""<div class="cv-meta">
      <div class="row"><div class="lab">汇 报 人</div><div class="val">{esc(AUTHOR)}</div></div>
      <div class="row"><div class="lab">指导教员</div><div class="val">{esc(ADVISOR)}</div></div>
      <div class="row"><div class="lab">专　　业</div><div class="val">{esc(MAJOR)}</div></div>
      <div class="row"><div class="lab">期　　班</div><div class="val">{esc(CLASS)}</div></div></div>"""
    inner = f"""{radar}
    <div class="cv-mark"><div class="cv-em"></div>
      <div><div class="cv-org">{esc(SCHOOL)}</div>
      <div class="cv-sub">HETEROGENEOUS AIRCRAFT · COOPERATIVE FORMATION</div></div></div>
    <div class="cv-band">本科毕业设计（论文）· 答辩汇报</div>
    <div class="cv-title"><h1>{esc(TITLE)}</h1><div class="cv-rule"></div></div>
    {meta}<div class="cv-date">{esc(DATE)}</div>{footer()}"""
    return page(inner, css)


def L_outline(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.ol-wrap{{position:absolute;top:298px;left:96px;right:96px;
  display:grid;grid-template-columns:repeat(3,1fr);gap:34px;}}
.ol-card{{position:relative;height:300px;border-radius:18px;padding:44px 40px;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.65));
  border:1px solid {C['panelb']};overflow:hidden;box-shadow:0 18px 44px rgba(0,0,0,.34);}}
.ol-card .bn{{font-family:Consolas,monospace;font-size:92px;font-weight:900;
  color:rgba(34,211,238,.15);position:absolute;right:26px;top:4px;line-height:1;}}
.ol-card h3{{font-size:33px;font-weight:800;margin-bottom:18px;}}
.ol-card p{{font-size:20px;line-height:1.6;color:{C['muted']};}}
.ol-card .ln{{width:54px;height:5px;border-radius:3px;background:{C['cyan']};
  margin-bottom:24px;box-shadow:0 0 16px rgba(34,211,238,.6);}}
"""
    items = [
        ("01","研究背景与意义","智能化无人化作战演进，异构协同成战略制高点"),
        ("02","现状评述与问题","控制优化分离、动态适应不足、异构考虑不充分"),
        ("03","内容与总体框架","控制—管理—优化一体化编队策略体系"),
        ("04","三项关键技术","鲁棒位置控制 · 动态重组 · 经济巡航优化"),
        ("05","综合仿真验证","多阶段多事件作战想定，四维效能评估"),
        ("06","结论与展望","四项创新成果，跨域协同未来方向"),
    ]
    cards = "".join(
        f'<div class="ol-card"><div class="bn">{n}</div><div class="ln"></div>'
        f'<h3>{esc(t)}</h3><p>{esc(d)}</p></div>' for n,t,d in items)
    inner = header("汇报提纲 · OUTLINE", idx, total) + std_title("汇 报 提 纲") \
        + f'<div class="ol-wrap">{cards}</div>' + footer()
    return page(inner, css)


def _bullets_panel(C, items, top=300, left=96, right=820):
    """左侧要点列表。items: (icon_text, title, desc)"""
    rows = ""
    for ic, t, d in items:
        rows += f"""<div class="bl-row">
          <div class="bl-ic">{ic}</div>
          <div><div class="bl-t">{t}</div><div class="bl-d">{d}</div></div></div>"""
    css = f"""
.bl-wrap{{position:absolute;top:{top}px;left:{left}px;right:{right}px;
  display:flex;flex-direction:column;gap:26px;z-index:5;}}
.bl-row{{display:flex;align-items:flex-start;gap:26px;padding:26px 32px;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.55));
  border:1px solid {C['panelb']};border-left:5px solid {C['cyan']};
  border-radius:14px;box-shadow:0 12px 32px rgba(0,0,0,.3);}}
.bl-ic{{flex:none;width:62px;height:62px;border-radius:14px;
  background:rgba(34,211,238,.12);border:1px solid rgba(34,211,238,.4);
  display:flex;align-items:center;justify-content:center;font-size:30px;
  color:{C['cyan']};font-weight:800;}}
.bl-t{{font-size:27px;font-weight:800;margin-bottom:8px;}}
.bl-d{{font-size:20px;line-height:1.55;color:{C['muted']};}}
"""
    return f'<div class="bl-wrap">{rows}</div>', css


def L_background(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    items = [
        ("演","作战形态演进","智能化、无人化、体系化加速发展，异构协同成战略制高点"),
        ("研","世界竞相布局","美军“忠诚僚机”、DARPA“蜂群”，我国“十四五”加快无人作战力量建设"),
        ("挑","四大技术挑战","平台异质 · 环境动态 · 任务多样 · 资源有限"),
        ("需","传统方法失效","静态、同构、单目标的编队方法难以满足复杂战场需求"),
    ]
    blocks, bcss = _bullets_panel(C, items, top=296, right=720)
    side = f"""
.bg-side{{position:absolute;right:96px;top:300px;width:560px;z-index:5;}}
.bg-stat{{padding:34px 38px;border-radius:18px;margin-bottom:26px;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 14px 36px rgba(0,0,0,.34);}}
.bg-stat .big{{font-size:64px;font-weight:900;color:{C['cyan']};font-family:Consolas,monospace;
  text-shadow:0 0 26px rgba(34,211,238,.5);}}
.bg-stat .lab{{font-size:21px;color:{C['muted']};margin-top:6px;letter-spacing:2px;}}
.bg-q{{padding:32px 36px;border-radius:18px;border:1px dashed rgba(251,191,36,.5);
  background:rgba(251,191,36,.06);}}
.bg-q .qt{{font-size:24px;font-weight:800;color:{C['amber']};margin-bottom:12px;letter-spacing:2px;}}
.bg-q p{{font-size:20px;line-height:1.6;color:{C['ice']};}}
"""
    sidehtml = f"""<div class="bg-side">
      <div class="bg-stat"><div class="big">3 类</div><div class="lab">异构平台 · 有人机 / 攻击无人机 / 侦察无人机</div></div>
      <div class="bg-stat"><div class="big">4 重</div><div class="lab">核心挑战 · 异质 · 动态 · 多样 · 受限</div></div>
      <div class="bg-q"><div class="qt">▶ 研究切入点</div>
        <p>面向动态、异构、强对抗、资源约束环境，重构编队策略体系</p></div></div>"""
    inner = header("第一部分 · 研究背景与意义", idx, total) \
        + std_title("研究背景与意义") + blocks + sidehtml + footer()
    return page(inner, bcss + side)


def L_gap(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.gp-cols{{position:absolute;top:298px;left:96px;right:96px;display:grid;
  grid-template-columns:1fr 1fr;gap:40px;z-index:5;}}
.gp-col h3{{font-size:30px;font-weight:800;margin-bottom:24px;display:flex;
  align-items:center;gap:16px;}}
.gp-col h3 .pill{{font-size:18px;padding:5px 16px;border-radius:20px;letter-spacing:2px;}}
.gp-item{{padding:24px 30px;border-radius:14px;margin-bottom:20px;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.55));
  border:1px solid {C['panelb']};}}
.gp-item .t{{font-size:23px;font-weight:700;margin-bottom:8px;color:{C['ice']};}}
.gp-item .d{{font-size:19px;line-height:1.5;color:{C['muted']};}}
.gp-gaps{{position:absolute;bottom:96px;left:96px;right:96px;display:grid;
  grid-template-columns:repeat(3,1fr);gap:28px;z-index:5;}}
.gp-gap{{padding:26px 30px;border-radius:14px;border:1px solid rgba(248,113,122,.45);
  background:rgba(248,113,122,.08);}}
.gp-gap .gt{{font-size:24px;font-weight:800;color:{C['red']};margin-bottom:10px;}}
.gp-gap .gd{{font-size:19px;line-height:1.5;color:{C['ice']};}}
"""
    dom_in = """<div class="gp-item"><div class="t">编队控制理论</div>
      <div class="d">段海滨·鸽群行为 / 朱战霞·协同编队综述 / 郭继峰·角色转换重构</div></div>
      <div class="gp-item"><div class="t">任务分配与燃油经济</div>
      <div class="d">周锐·分布式MPC / 刘树光·涡流节能机理 / 李杰·燃油最优轨迹</div></div>"""
    dom_out = """<div class="gp-item"><div class="t">美国 · 世界领先</div>
      <div class="d">“小精灵”空中回收 / “拒止环境协同” / “天空博格人”忠诚僚机</div></div>
      <div class="gp-item"><div class="t">欧洲 · 未来空战系统</div>
      <div class="d">有人/无人协同为核心，德国DLR涡流利用节能研究</div></div>"""
    gaps = [
        ("控制与优化分离","控制聚焦稳定与精度，管理与优化各自独立，缺乏一体化设计"),
        ("动态适应性不足","多针对静态/预设场景，对成员动态加入退出应对乏力"),
        ("异构特性考虑不足","对平台异质性带来的控制与优化问题缺乏深入分析"),
    ]
    gaphtml = "".join(f'<div class="gp-gap"><div class="gt">不足 {i+1}</div>'
        f'<div class="gd">{esc(t)}<br>{esc(d)}</div></div>'
        for i,(t,d) in enumerate(gaps))
    inner = header("第二部分 · 研究现状评述", idx, total) + std_title("研究现状与关键问题") + f"""
      <div class="gp-cols">
        <div class="gp-col"><h3>国内研究 <span class="pill" style="background:rgba(34,211,238,.15);color:{C['cyan']}">DOMESTIC</span></h3>{dom_in}</div>
        <div class="gp-col"><h3>国外研究 <span class="pill" style="background:rgba(56,189,248,.15);color:{C['cyan2']}">GLOBAL</span></h3>{dom_out}</div>
      </div>
      <div class="gp-gaps">{gaphtml}</div>""" + footer()
    return page(inner, css)


def L_framework(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.fw{{position:absolute;top:300px;left:96px;right:96px;display:grid;
  grid-template-columns:repeat(3,1fr);gap:40px;z-index:5;}}
.fw-col{{position:relative;border-radius:20px;padding:46px 38px 40px;overflow:hidden;
  background:linear-gradient(165deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 18px 46px rgba(0,0,0,.36);}}
.fw-col .glow{{position:absolute;top:-60px;right:-60px;width:200px;height:200px;
  border-radius:50%;filter:blur(40px);opacity:.5;}}
.fw-tag{{font-size:21px;letter-spacing:6px;font-weight:800;margin-bottom:18px;}}
.fw-col h3{{font-size:34px;font-weight:900;margin-bottom:22px;line-height:1.25;}}
.fw-col .ll{{list-style:none;}}
.fw-col .ll li{{font-size:20px;line-height:1.5;color:{C['muted']};margin-bottom:16px;
  padding-left:26px;position:relative;}}
.fw-col .ll li::before{{content:'▹';position:absolute;left:0;color:{C['cyan']};}}
.fw-col .inv{{margin-top:24px;padding-top:20px;border-top:1px dashed {C['panelb']};
  font-size:19px;color:{C['amber']};line-height:1.5;}}
.fw-flow{{position:absolute;bottom:108px;left:96px;right:96px;display:flex;
  align-items:center;justify-content:center;gap:30px;z-index:6;}}
.fw-step{{padding:16px 38px;border-radius:30px;font-size:24px;font-weight:800;
  background:rgba(34,211,238,.12);border:1px solid rgba(34,211,238,.45);color:{C['ice']};}}
.fw-arrow{{font-size:34px;color:{C['cyan']};}}
"""
    cols = [
        ("控制 CONTROL", C['cyan'], "编队位置鲁棒控制",
         ["干扰观测器 + 一致性协议","主动前馈补偿抗扰","Lyapunov-K 时延约束"],
         "创新：被动纠偏 → 主动补偿，精度提升 68%"),
        ("管理 MANAGE", C['amber'], "动态加入/退出",
         ["虚拟结构-角色池解耦","四阶段平滑过渡","角色权重渐进交接"],
         "创新：队形扰动降低 61%，过渡缩短 49%"),
        ("优化 OPTIMIZE", C['green'], "经济巡航协同",
         ["气动耦合油耗建模","异构燃油特性差异","粒子群分层优化"],
         "创新：节油 15.6%，等效航程 +148 km"),
    ]
    colhtml = ""
    for tag, clr, h, lis, inv in cols:
        lhtml = "".join(f"<li>{esc(x)}</li>" for x in lis)
        colhtml += f"""<div class="fw-col"><div class="glow" style="background:{clr}"></div>
          <div class="fw-tag" style="color:{clr}">{esc(tag)}</div>
          <h3>{esc(h)}</h3><ul class="ll">{lhtml}</ul>
          <div class="inv">{esc(inv)}</div></div>"""
    flow = f"""<div class="fw-flow">
      <div class="fw-step">精确控制</div><div class="fw-arrow">→</div>
      <div class="fw-step">动态管理</div><div class="fw-arrow">→</div>
      <div class="fw-step">经济优化</div></div>"""
    inner = header("第三部分 · 研究内容与框架", idx, total) \
        + std_title("控制—管理—优化 一体化框架") + f'<div class="fw">{colhtml}</div>' + flow + footer()
    return page(inner, css)


def L_platforms(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.pf{{position:absolute;top:306px;left:96px;right:96px;display:grid;
  grid-template-columns:repeat(3,1fr);gap:40px;z-index:5;}}
.pf-card{{position:relative;border-radius:20px;padding:40px 36px;overflow:hidden;
  background:linear-gradient(165deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 18px 46px rgba(0,0,0,.36);height:540px;}}
.pf-icon{{width:120px;height:120px;border-radius:24px;margin-bottom:28px;
  display:flex;align-items:center;justify-content:center;font-size:60px;
  border:1px solid {C['panelb']};}}
.pf-role{{font-size:20px;letter-spacing:3px;font-weight:700;margin-bottom:10px;}}
.pf-card h3{{font-size:34px;font-weight:900;margin-bottom:8px;}}
.pf-model{{font-size:19px;color:{C['dim']};margin-bottom:24px;font-family:Consolas,monospace;}}
.pf-card .feat{{font-size:20px;line-height:1.7;color:{C['muted']};margin-bottom:22px;}}
.pf-meta{{font-size:22px;font-weight:800;padding:14px 0;border-top:1px solid {C['panelb']};}}
"""
    cards = [
        ("🛩","指挥节点 · COMMANDER","大型有人机","预警机 / 运输机",
         "航时长 · 指挥决策强<br>机动性受限 · 出动成本高", "比喻：球队“教练”", C['cyan']),
        ("✈","火力节点 · STRIKER","攻击无人机","攻击-11 / 翼龙",
         "速度快 · 机动性好<br>携带武器 · 依赖指控", "比喻：球队“前锋”", C['amber']),
        ("🛰","感知节点 · SCOUT","侦察无人机","无侦-8 / 彩虹",
         "体型小 · 隐蔽性好<br>侦察设备全 · 无打击", "比喻：球队“边锋”", C['green']),
    ]
    h = ""
    for ic, role, name, model, feat, meta, clr in cards:
        h += f"""<div class="pf-card">
          <div class="pf-icon" style="background:rgba(34,211,238,.08);color:{clr}">{ic}</div>
          <div class="pf-role" style="color:{clr}">{esc(role)}</div>
          <h3>{esc(name)}</h3><div class="pf-model">{esc(model)}</div>
          <div class="feat">{feat}</div>
          <div class="pf-meta" style="color:{clr}">{esc(meta)}</div></div>"""
    inner = header("系统建模 · 平台特性分析", idx, total) \
        + std_title("异构平台特性与互补优势") + f'<div class="pf">{h}</div>' + footer()
    return page(inner, css)


def L_architecture(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.ar{{position:absolute;top:308px;left:96px;right:96px;display:flex;
  flex-direction:column;gap:26px;z-index:5;}}
.ar-layer{{position:relative;border-radius:18px;padding:34px 42px;display:flex;
  align-items:center;gap:40px;overflow:hidden;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.55));
  border:1px solid {C['panelb']};box-shadow:0 14px 36px rgba(0,0,0,.3);}}
.ar-num{{flex:none;width:80px;height:80px;border-radius:18px;display:flex;
  align-items:center;justify-content:center;font-size:40px;font-weight:900;
  font-family:Consolas,monospace;}}
.ar-mid{{flex:1;}}
.ar-mid h3{{font-size:32px;font-weight:800;margin-bottom:8px;}}
.ar-mid p{{font-size:20px;color:{C['muted']};line-height:1.5;}}
.ar-side{{flex:none;text-align:right;}}
.ar-side .cyc{{font-size:30px;font-weight:900;font-family:Consolas,monospace;}}
.ar-side .who{{font-size:18px;color:{C['dim']};margin-top:6px;}}
.ar-conn{{position:absolute;left:136px;width:3px;background:rgba(34,211,238,.4);z-index:4;}}
"""
    layers = [
        ("01","任务决策层 · DECISION","任务分配 · 目标指派 · 优先级排序","秒级~分钟级","有人机 / 地面站",C['cyan']),
        ("02","编队规划层 · PLANNING","队形生成 · 重构规划 · 速度剖面协调","百毫秒~秒级","编队长机",C['amber']),
        ("03","轨迹控制层 · CONTROL","位置保持 · 速度跟踪 · 实时扰动补偿","毫秒级","各机飞控",C['green']),
    ]
    h = ""
    for n, t, d, cyc, who, clr in layers:
        h += f"""<div class="ar-layer">
          <div class="ar-num" style="background:rgba(34,211,238,.1);color:{clr};border:1px solid {clr}">{n}</div>
          <div class="ar-mid"><h3>{esc(t)}</h3><p>{esc(d)}</p></div>
          <div class="ar-side"><div class="cyc" style="color:{clr}">{esc(cyc)}</div>
          <div class="who">{esc(who)}</div></div></div>"""
    inner = header("系统建模 · 分层组织架构", idx, total) \
        + std_title("三层编队组织架构 · 纵向解耦") + f'<div class="ar">{h}</div>' + footer()
    return page(inner, css)


def L_problems(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.pb{{position:absolute;top:308px;left:96px;right:96px;display:grid;
  grid-template-columns:repeat(3,1fr);gap:36px;z-index:5;}}
.pb-card{{position:relative;border-radius:20px;padding:44px 38px;overflow:hidden;
  background:linear-gradient(165deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 18px 46px rgba(0,0,0,.36);height:520px;}}
.pb-q{{font-family:Consolas,monospace;font-size:30px;font-weight:900;color:{C['cyan']};
  margin-bottom:20px;}}
.pb-card h3{{font-size:32px;font-weight:900;margin-bottom:20px;line-height:1.25;}}
.pb-goal{{font-size:21px;line-height:1.6;color:{C['muted']};margin-bottom:24px;}}
.pb-eq{{margin-top:auto;padding:20px 24px;border-radius:12px;font-family:Consolas,monospace;
  font-size:21px;color:{C['ice']};background:rgba(0,0,0,.28);border:1px solid {C['panelb']};
  position:absolute;bottom:38px;left:38px;right:38px;}}
.pb-eq .lab{{font-size:16px;color:{C['dim']};display:block;margin-bottom:6px;}}
"""
    cards = [
        ("Q1","编队位置精确控制","使各僚机相对长机的位置误差收敛至零，克服外部扰动、平台差异与通信时延。",
         "目标", "lim‖pᵢ−p₀−dᵢ‖ → 0"),
        ("Q2","成员动态加入/退出","在战损、燃油告警、任务变更时，保障编队整体稳定性与任务连续性。",
         "原则", "渐进式交接 · 平滑过渡"),
        ("Q3","经济巡航协同优化","在安全间距与速度约束下，求解使编队总油耗最小的构型与巡航速度。",
         "目标", "min Σ mᵢ(构型, 速度)"),
    ]
    h = ""
    for q, t, g, lab, eq in cards:
        h += f"""<div class="pb-card"><div class="pb-q">{esc(q)}</div>
          <h3>{esc(t)}</h3><div class="pb-goal">{esc(g)}</div>
          <div class="pb-eq"><span class="lab">{esc(lab)}</span>{esc(eq)}</div></div>"""
    inner = header("系统建模 · 三大核心问题", idx, total) \
        + std_title("三大核心问题数学描述") + f'<div class="pb">{h}</div>' + footer()
    return page(inner, css)


def _chip_flow(C, steps, clr):
    h = '<div class="mf-flow">'
    for i, st in enumerate(steps):
        h += f'<div class="mf-chip">{st}</div>'
        if i < len(steps)-1:
            h += '<div class="mf-ar">→</div>'
    return h + '</div>'

_METHOD_CSS = lambda C: f"""
.mf-lead{{position:absolute;top:300px;left:96px;right:96px;font-size:24px;line-height:1.6;
  color:{C['ice']};z-index:5;}}
.mf-lead b{{color:{C['cyan']};}}
.mf-flow{{position:absolute;top:404px;left:96px;right:96px;display:flex;
  align-items:center;gap:22px;flex-wrap:wrap;z-index:5;}}
.mf-chip{{padding:18px 34px;border-radius:14px;font-size:24px;font-weight:800;
  background:rgba(34,211,238,.1);border:1px solid rgba(34,211,238,.45);color:{C['ice']};}}
.mf-ar{{font-size:30px;color:{C['cyan']};}}
.mf-cmp{{position:absolute;bottom:104px;left:96px;right:96px;display:grid;
  grid-template-columns:1fr 1fr;gap:40px;z-index:5;}}
.mf-box{{border-radius:18px;padding:34px 38px;box-shadow:0 14px 36px rgba(0,0,0,.32);}}
.mf-box h4{{font-size:25px;font-weight:800;margin-bottom:16px;display:flex;gap:12px;align-items:center;}}
.mf-box p{{font-size:20px;line-height:1.6;}}
.mf-bad{{background:rgba(248,113,122,.08);border:1px solid rgba(248,113,122,.4);}}
.mf-bad h4{{color:{C['red']};}} .mf-bad p{{color:#F3C9CD;}}
.mf-good{{background:rgba(52,211,153,.08);border:1px solid rgba(52,211,153,.42);}}
.mf-good h4{{color:{C['green']};}} .mf-good p{{color:#BDEFD9;}}
"""

def _method(s, idx, total, C, FIGS, page, header, footer, std_title, esc,
            kick, title, lead, steps, bad, good):
    flow = _chip_flow(C, steps, C['cyan'])
    inner = header(kick, idx, total) + std_title(title) \
        + f'<div class="mf-lead">{lead}</div>' + flow \
        + f"""<div class="mf-cmp">
          <div class="mf-box mf-bad"><h4>✕ {esc(bad[0])}</h4><p>{esc(bad[1])}</p></div>
          <div class="mf-box mf-good"><h4>✓ {esc(good[0])}</h4><p>{esc(good[1])}</p></div>
        </div>""" + footer()
    return page(inner, _METHOD_CSS(C))

def L_method_dob(s, idx, total, *a):
    C = a[2]; esc=a[-1]
    return _method(s, idx, total, *a,
        kick="关键技术一 · 第三章",
        title="基于干扰观测的鲁棒位置控制",
        lead="在<b>一致性协议</b>基础上引入<b>干扰观测器(DOB)</b>，实现“先补偿、后纠偏”；并以 Lyapunov-Krasovskii 泛函处理<b>通信时延</b>。",
        steps=["残差观测","干扰估计 (Q滤波)","前馈反向补偿","闭环 ISS 稳定"],
        bad=("传统 PID · 被动纠偏","扰动产生位偏后才反应，对持续强扰响应滞后，反复纠偏、精度受限"),
        good=("本文 DOB · 主动补偿","干扰造成显著位偏前即被抵消，PID 仅处理残余误差，精度与抗扰大幅提升"))

def L_method_role(s, idx, total, *a):
    return _method(s, idx, total, *a,
        kick="关键技术二 · 第四章",
        title="角色转换动态加入/退出策略",
        lead="将编队<b>逻辑结构与物理平台解耦</b>：虚拟结构—角色池—物理节点三层映射，配合<b>四阶段平滑过渡</b>。",
        steps=["决策触发","轨迹预规划","角色权重过渡","队形重构"],
        bad=("传统硬切换","成员突变引起队形畸变、扰动大、恢复慢，甚至空中碰撞风险"),
        good=("权重渐进交接","退出权重 1→0、加入 0→1 加权平均，过渡平滑无突变，队形稳定"))

def L_method_fuel(s, idx, total, *a):
    return _method(s, idx, total, *a,
        kick="关键技术三 · 第五章",
        title="气动耦合经济巡航协同优化",
        lead="利用长机<b>翼尖涡上升气流</b>获得升力增益，诱导阻力降低 <b>20%~30%</b>；建立异构油耗模型，<b>粒子群分层优化</b>。",
        steps=["气动收益建模","异构燃油特性","上层 PSO 构型/速度","下层经济轨迹跟踪"],
        bad=("松散编队 · 基准","各机独自克服阻力，无气动协同收益，油耗高、航程受限"),
        good=("优化编队 · 节能","合理配置各机位置获得气动收益，节油 15.6%，等效航程 +148 km"))

def _table_html(C, tbl, esc):
    hl_row = tbl.get("hl_row", -1); hl_col = tbl.get("hl_col", -1)
    th = "".join(f"<th>{esc(h)}</th>" for h in tbl["headers"])
    rows = ""
    for ri, r in enumerate(tbl["rows"]):
        cls = ' class="hl"' if ri == hl_row else ""
        tds = ""
        for ci, c in enumerate(r):
            cc = ' class="hlc"' if ci == hl_col and ci != 0 else ""
            tds += f"<td{cc}>{esc(c)}</td>"
        rows += f"<tr{cls}>{tds}</tr>"
    return f"<table class='dt'><thead><tr>{th}</tr></thead><tbody>{rows}</tbody></table>"

_TABLE_CSS = lambda C: f"""
.dt{{width:100%;border-collapse:collapse;font-size:21px;}}
.dt th{{background:rgba(34,211,238,.14);color:{C['cyan']};font-weight:800;
  padding:18px 18px;text-align:center;letter-spacing:1px;border-bottom:2px solid {C['cyan']};}}
.dt td{{padding:16px 18px;text-align:center;color:{C['ice']};
  border-bottom:1px solid {C['panelb']};}}
.dt td:first-child{{text-align:left;color:{C['muted']};font-weight:700;}}
.dt tr.hl td{{background:rgba(52,211,153,.14);color:#fff;font-weight:800;}}
.dt tr.hl td:first-child{{color:{C['green']};}}
.dt td.hlc{{color:{C['green']};font-weight:800;}}
"""

def _fig_box(FIGS, fname, cap, esc):
    return f"""<div class="fg-box">
      <img src="file:///{FIGS}/{fname}">
      <div class="fg-cap">{esc(cap)}</div></div>"""

def L_fig_table(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = _TABLE_CSS(C) + f"""
.ft{{position:absolute;top:300px;left:96px;right:96px;bottom:120px;
  display:grid;grid-template-columns:1.15fr 1fr;gap:46px;align-items:center;z-index:5;}}
.fg-box{{background:#fff;border-radius:16px;padding:18px;box-shadow:0 18px 46px rgba(0,0,0,.4);}}
.fg-box img{{width:100%;display:block;border-radius:8px;}}
.fg-cap{{text-align:center;color:#33507a;font-size:18px;font-weight:700;margin-top:12px;}}
.ft-right{{display:flex;flex-direction:column;gap:26px;}}
.ft-tbl{{border-radius:16px;padding:30px 30px;background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 14px 36px rgba(0,0,0,.32);}}
.ft-key{{padding:24px 30px;border-radius:14px;border-left:5px solid {C['green']};
  background:rgba(52,211,153,.08);font-size:22px;line-height:1.6;color:{C['ice']};}}
.ft-key b{{color:{C['green']};font-size:26px;}}
"""
    kick = s.get("kick", "仿真验证 · 对比分析")
    keymap = {
        "ch3_result":"平均误差 <b>0.92 m</b> · 较 PID ↓<b>68%</b> · 稳定时间 ↓<b>55%</b>",
        "ch4_result":"队形扰动 28→<b>11 m</b> ↓<b>60.7%</b> · 过渡时间缩短约 <b>50%</b>",
    }
    key = keymap.get(s["id"], "")
    inner = header("仿真验证 · 对比分析", idx, total) \
        + std_title(s.get("fig_cap","仿真结果").split(" ",1)[-1]) + f"""
      <div class="ft">
        {_fig_box(FIGS, s['fig'], s['fig_cap'], esc)}
        <div class="ft-right">
          <div class="ft-tbl">{_table_html(C, s['table'], esc)}</div>
          <div class="ft-key">{key}</div>
        </div></div>""" + footer()
    return page(inner, css)

def L_fig_full(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.ff{{position:absolute;top:296px;left:50%;transform:translateX(-50%);
  bottom:120px;display:flex;flex-direction:column;align-items:center;z-index:5;}}
.fg-box{{background:#fff;border-radius:16px;padding:20px;box-shadow:0 20px 50px rgba(0,0,0,.45);
  height:100%;display:flex;flex-direction:column;}}
.fg-box img{{height:100%;width:auto;max-width:1280px;display:block;border-radius:8px;object-fit:contain;}}
.fg-cap{{text-align:center;color:#33507a;font-size:19px;font-weight:700;margin-top:12px;}}
.ff-legend{{position:absolute;top:300px;right:96px;width:300px;z-index:6;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.7));
  border:1px solid {C['panelb']};border-radius:14px;padding:26px 28px;}}
.ff-legend h4{{font-size:20px;color:{C['cyan']};margin-bottom:16px;letter-spacing:2px;}}
.ff-legend .lg{{display:flex;align-items:center;gap:14px;margin-bottom:14px;font-size:19px;color:{C['ice']};}}
.ff-legend .mk{{width:18px;height:18px;border-radius:4px;}}
"""
    legend = f"""<div class="ff-legend"><h4>编队成员图例</h4>
      <div class="lg"><div class="mk" style="background:{C['red']};border-radius:50%"></div>长机（有人机）</div>
      <div class="lg"><div class="mk" style="background:{C['cyan2']}"></div>攻击无人机</div>
      <div class="lg"><div class="mk" style="background:{C['green']};border-radius:50%"></div>侦察无人机</div></div>"""
    inner = header("仿真验证 · 轨迹可视化", idx, total) \
        + std_title(s["fig_cap"].split(" ",1)[-1]) + legend \
        + f'<div class="ff">{_fig_box(FIGS, s["fig"], s["fig_cap"], esc)}</div>' + footer()
    return page(inner, css)

def L_fig_triple_table(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = _TABLE_CSS(C) + f"""
.tt-figs{{position:absolute;top:296px;left:96px;right:96px;display:grid;
  grid-template-columns:repeat(3,1fr);gap:26px;z-index:5;}}
.fg-box{{background:#fff;border-radius:14px;padding:14px;box-shadow:0 16px 40px rgba(0,0,0,.4);}}
.fg-box img{{width:100%;display:block;border-radius:6px;}}
.fg-cap{{display:none;}}
.tt-cap{{position:absolute;top:660px;left:96px;right:96px;text-align:center;
  font-size:19px;color:{C['muted']};z-index:5;letter-spacing:1px;}}
.tt-tbl{{position:absolute;bottom:96px;left:96px;right:96px;border-radius:16px;
  padding:24px 30px;background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 14px 36px rgba(0,0,0,.32);z-index:5;}}
"""
    figs = "".join(_fig_box(FIGS, f, "", esc) for f in s["figs"])
    tbl = _table_html(C, s["table"], esc) if s.get("table") else ""
    inner = header("仿真验证 · 结果分析", idx, total) \
        + std_title(s["fig_cap"].split(" ",1)[-1] if False else _short_title(s)) \
        + f'<div class="tt-figs">{figs}</div>' \
        + f'<div class="tt-cap">{esc(s["fig_cap"])}</div>' \
        + (f'<div class="tt-tbl">{tbl}</div>' if tbl else "") + footer()
    return page(inner, css)

def _short_title(s):
    return {"ch5_result":"经济巡航优化结果", "ch6_result":"综合效能评估结果"}.get(s["id"], "仿真结果")

def L_scenario(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.sc-comp{{position:absolute;top:300px;left:96px;width:520px;z-index:5;
  border-radius:18px;padding:34px 36px;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 14px 36px rgba(0,0,0,.32);}}
.sc-comp h4{{font-size:24px;color:{C['cyan']};margin-bottom:22px;letter-spacing:2px;}}
.sc-comp .u{{display:flex;align-items:center;gap:16px;margin-bottom:18px;font-size:21px;color:{C['ice']};}}
.sc-comp .u .b{{width:14px;height:14px;border-radius:50%;}}
.sc-time{{position:absolute;top:300px;left:660px;right:96px;z-index:5;}}
.sc-step{{position:relative;padding:22px 28px 22px 76px;margin-bottom:18px;border-radius:14px;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.5));border:1px solid {C['panelb']};}}
.sc-step .n{{position:absolute;left:24px;top:50%;transform:translateY(-50%);
  width:38px;height:38px;border-radius:50%;background:rgba(34,211,238,.15);
  border:1px solid {C['cyan']};color:{C['cyan']};display:flex;align-items:center;
  justify-content:center;font-weight:800;font-family:Consolas,monospace;}}
.sc-step h5{{font-size:23px;font-weight:800;margin-bottom:4px;}}
.sc-step p{{font-size:18px;color:{C['muted']};}}
.sc-step.alert{{border-color:rgba(248,113,122,.5);background:rgba(248,113,122,.08);}}
.sc-step.alert .n{{background:rgba(248,113,122,.18);border-color:{C['red']};color:{C['red']};}}
"""
    units = [("有人预警机 ×1 · 指挥",C['cyan']),("攻击无人机 ×2 · 打击",C['amber']),
             ("侦察无人机 ×2 · 感知",C['green']),("电子战机 ×1 · 干扰掩护","#C084FC")]
    uh = "".join(f'<div class="u"><div class="b" style="background:{c}"></div>{esc(t)}</div>' for t,c in units)
    steps = [
        ("1","巡航突防 (0-400km)","经济巡航编队，最小化燃油消耗",False),
        ("2","区域侦察 (400-600km)","调整为侦察队形，展开搜索",False),
        ("3","目标打击 (600km)","攻击无人机前出，精确打击",False),
        ("4","战中重组","攻击机战损退出 → 侦察机转入攻击角色",True),
        ("5","毁伤评估 + 返航","抵近拍摄 · 重组经济编队返航",False),
    ]
    sh = ""
    for n,t,d,al in steps:
        sh += f'<div class="sc-step{" alert" if al else ""}"><div class="n">{n}</div>'\
              f'<h5>{esc(t)}</h5><p>{esc(d)}</p></div>'
    inner = header("第四部分 · 综合仿真验证", idx, total) \
        + std_title("典型作战想定 · 突防-侦察-打击一体化") \
        + f'<div class="sc-comp"><h4>编队组成 · 6 平台</h4>{uh}'\
          f'<div style="margin-top:20px;padding-top:20px;border-top:1px dashed {C["panelb"]};'\
          f'font-size:20px;color:{C["amber"]};">纵深 800 km · 多阶段多事件</div></div>' \
        + f'<div class="sc-time">{sh}</div>' + footer()
    return page(inner, css)


def L_conclusion(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    css = f"""
.cc-grid{{position:absolute;top:298px;left:96px;right:96px;display:grid;
  grid-template-columns:repeat(2,1fr);gap:30px;z-index:5;}}
.cc-card{{position:relative;border-radius:16px;padding:32px 36px;overflow:hidden;
  background:linear-gradient(160deg,{C['panel']},rgba(14,28,56,.6));
  border:1px solid {C['panelb']};box-shadow:0 14px 36px rgba(0,0,0,.32);}}
.cc-card .ico{{position:absolute;right:28px;top:20px;font-size:46px;opacity:.25;}}
.cc-card h3{{font-size:26px;font-weight:800;margin-bottom:12px;}}
.cc-card p{{font-size:19px;line-height:1.55;color:{C['muted']};}}
.cc-card .kpi{{font-size:30px;font-weight:900;color:{C['green']};margin-top:14px;
  font-family:Consolas,monospace;}}
.cc-future{{position:absolute;bottom:96px;left:96px;right:96px;display:flex;
  gap:20px;z-index:5;}}
.cc-fchip{{flex:1;text-align:center;padding:20px 14px;border-radius:12px;
  background:rgba(34,211,238,.08);border:1px solid rgba(34,211,238,.35);
  font-size:20px;color:{C['ice']};font-weight:700;}}
.cc-fchip span{{display:block;font-size:15px;color:{C['dim']};margin-top:6px;letter-spacing:1px;}}
"""
    cards = [
        ("🎯","一体化研究框架","控制—管理—优化有机融合，避免传统碎片化","系统化体系"),
        ("📡","鲁棒位置控制器","干扰观测器 + 一致性协议，主动抗扰","精度 ↑ 68%"),
        ("🔄","动态管理机制","虚拟结构-角色池 + 四阶段过渡","扰动 ↓ 61%"),
        ("⛽","经济巡航优化","首次系统考虑气动收益与燃油联合优化","节油 15.6%"),
    ]
    ch = ""
    for ic,t,d,k in cards:
        ch += f'<div class="cc-card"><div class="ico">{ic}</div><h3>{esc(t)}</h3>'\
              f'<p>{esc(d)}</p><div class="kpi">{esc(k)}</div></div>'
    futures = [("深度强化学习","在线自适应优化"),("认知电子战","通信-感知-对抗一体"),
               ("跨域协同","空-天-地-海拓展"),("仿真驱动","在线学习与演化")]
    fh = "".join(f'<div class="cc-fchip">{esc(t)}<span>{esc(d)}</span></div>' for t,d in futures)
    inner = header("第五部分 · 结论与展望", idx, total) \
        + std_title("研究结论与创新成果") + f'<div class="cc-grid">{ch}</div>' \
        + f'<div class="cc-future">{fh}</div>' + footer()
    return page(inner, css)


def L_thanks(s, idx, total, C, FIGS, page, header, footer, std_title, esc):
    from slides_data import AUTHOR, ADVISOR, TITLE
    css = f"""
.tk{{position:absolute;inset:0;display:flex;flex-direction:column;
  align-items:center;justify-content:center;z-index:5;}}
.tk-em{{width:110px;height:110px;border:3px solid {C['cyan']};border-radius:50%;
  position:relative;margin-bottom:50px;box-shadow:0 0 36px rgba(34,211,238,.5);}}
.tk-em::before{{content:'';position:absolute;inset:34px;border-radius:50%;
  background:{C['cyan']};box-shadow:0 0 22px {C['cyan']};}}
.tk-em::after{{content:'';position:absolute;inset:-26px;border-radius:50%;
  border:1px solid rgba(34,211,238,.3);}}
.tk h1{{font-size:108px;font-weight:900;letter-spacing:18px;
  background:linear-gradient(90deg,#EAF2FF,{C['cyan']});-webkit-background-clip:text;
  -webkit-text-fill-color:transparent;margin-bottom:28px;}}
.tk .en{{font-size:26px;letter-spacing:10px;color:{C['dim']};font-family:Consolas,monospace;margin-bottom:50px;}}
.tk .ti{{font-size:28px;color:{C['ice']};font-weight:700;margin-bottom:40px;}}
.tk .who{{display:flex;gap:60px;font-size:23px;color:{C['muted']};}}
.tk .who b{{color:{C['cyan']};}}
.tk-rule{{width:260px;height:5px;border-radius:3px;margin:0 auto 44px;
  background:linear-gradient(90deg,transparent,{C['cyan']},transparent);}}
"""
    inner = f"""<div class="tk"><div class="tk-em"></div>
      <h1>敬请指正</h1><div class="en">THANK YOU</div>
      <div class="tk-rule"></div>
      <div class="ti">{esc(TITLE)}</div>
      <div class="who"><div>汇报人 · <b>{esc(AUTHOR)}</b></div>
        <div>指导教员 · <b>{esc(ADVISOR)}</b></div></div></div>{footer()}"""
    return page(inner, css)


LAYOUTS = {
    "cover": L_cover,
    "outline": L_outline,
    "background": L_background,
    "gap": L_gap,
    "framework": L_framework,
    "platforms": L_platforms,
    "architecture": L_architecture,
    "problems": L_problems,
    "method_dob": L_method_dob,
    "method_role": L_method_role,
    "method_fuel": L_method_fuel,
    "fig_table": L_fig_table,
    "fig_full": L_fig_full,
    "fig_triple_table": L_fig_triple_table,
    "fig_triple": L_fig_triple_table,
    "scenario": L_scenario,
    "conclusion": L_conclusion,
    "thanks": L_thanks,
}
