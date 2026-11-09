"""디자인 시안(SVG)의 부품 도면을 게임이 그리는 도형 데이터(GDScript)로 바꾼다.

    python tools/svg_to_art.py <Expansion.dc.html> scripts/art_data.gd

- path(M L H V C S Q T A Z, 상대 좌표 포함), rect, circle, ellipse, line, polyline, polygon,
  <g transform> (translate/scale/rotate/matrix), 점선, 투명도를 처리한다.
- 퍽 몸통(회색 기본 퍽과 정면 눈금)은 게임이 직접 그리므로 뺀다.
- 세트 변신 외형의 주인 색(#E0533D)은 "P", 각인 빛(#FF6147)은 "PL" 로 남겨 게임에서 바꿔 칠한다.
- 각인 기호 그룹(translate(-50 -50) 으로 끝나는 그룹)은 위치와 크기만 남긴다.
"""
import math
import re
import sys
import xml.etree.ElementTree as ET

NAMES = {
    "달무리 지팡이": "moon_staff", "별자리 망토": "star_cloak", "월광 장화": "moon_boots",
    "주인공 머리띠": "hero_band", "찢어진 망토": "torn_cape", "각성 운동화": "awaken_shoes",
    "빙결 부채": "ice_fan", "그림자 가위": "shadow_scissors", "운명의 책갈피": "bookmark",
    "유품 리본": "relic_ribbon", "구름 우편함": "cloud_mailbox", "판끝 재봉틀": "edge_sewer",
    "배수로 타이어 평소 모습": "drift_tire", "순보 깔창 평소 모습": "flash_step",
    "고무 주먹 평소 모습": "rubber_fist", "모으고 쏘는 손바닥 평소 모습": "charge_palm",
    "절대영역 방패 평소 모습": "at_field", "통나무 대역 평소 모습": "log_sub",
    "함정 카드 한 장 평소 모습": "trap_card", "5초짜리 스톱워치 평소 모습": "stopwatch",
    "리바운드 운동화 평소 모습": "rebound_shoes", "양손이 바쁜 연금 장갑 평소 모습": "alchemy_glove",
    "메아리 종": "echo_bell", "실매듭 인형": "string_doll", "밤비늘 부적": "night_charm",
    "잉크 한 방울": "ink_drop", "버섯 원탁": "mushroom", "바람 매듭": "wind_knot",
    "그림자 저울": "shadow_scale", "달빛 우물": "moon_well", "두 번째 발자국": "second_step",
    "옆구리 주문서": "side_scroll", "유리 날개": "glass_wings", "약속의 닻": "anchor",
    "달그림자 마도사 변신 외형": "set_moon", "최후의 주인공 변신 외형": "set_hero",
}
PLAYER_TOKENS = {"#E0533D": "P", "#FF6147": "PL"}

# 게임이 직접 그리는 기본 퍽
PUCK_SKIP = [
    ("circle", {"cx": "61", "cy": "65", "r": "24"}),
    ("circle", {"cx": "60", "cy": "62", "r": "24", "fill": "#8A929C"}),
    ("circle", {"cx": "60", "cy": "62", "r": "15", "fill": "#23272D"}),
    ("path", {"d": "M39 54 A22 22 0 0 1 81 54"}),
    ("path", {"d": "M60 39.5 V45"}),
]


def mat_mul(a, b):
    return (a[0] * b[0] + a[2] * b[1], a[1] * b[0] + a[3] * b[1],
            a[0] * b[2] + a[2] * b[3], a[1] * b[2] + a[3] * b[3],
            a[0] * b[4] + a[2] * b[5] + a[4], a[1] * b[4] + a[3] * b[5] + a[5])


def parse_transform(t):
    m = (1, 0, 0, 1, 0, 0)
    for name, args in re.findall(r'(\w+)\(([^)]*)\)', t or ""):
        v = [float(x) for x in re.split(r'[ ,]+', args.strip()) if x]
        if name == "translate":
            n = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == "scale":
            n = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == "rotate":
            a = math.radians(v[0])
            r = (math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0)
            if len(v) == 3:
                n = mat_mul(mat_mul((1, 0, 0, 1, v[1], v[2]), r), (1, 0, 0, 1, -v[1], -v[2]))
            else:
                n = r
        elif name == "matrix":
            n = tuple(v)
        else:
            continue
        m = mat_mul(m, n)
    return m


def apply(m, p):
    return (m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5])


def arc_points(x1, y1, rx, ry, phi, large, sweep, x2, y2, steps=None):
    if rx == 0 or ry == 0:
        return [(x2, y2)]
    phi = math.radians(phi)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1p ** 2 / rx ** 2 + y1p ** 2 / ry ** 2
    if lam > 1:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    num = rx ** 2 * ry ** 2 - rx ** 2 * y1p ** 2 - ry ** 2 * x1p ** 2
    den = rx ** 2 * y1p ** 2 + ry ** 2 * x1p ** 2
    co = math.sqrt(max(0, num / den)) if den else 0
    if large == sweep:
        co = -co
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx = cp * cxp - sp * cyp + (x1 + x2) / 2
    cy = sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = steps or max(4, int(abs(dt) / (math.pi / 12)) + 1)
    out = []
    for i in range(1, n + 1):
        t = t1 + dt * i / n
        x = cx + rx * math.cos(t) * cp - ry * math.sin(t) * sp
        y = cy + rx * math.cos(t) * sp + ry * math.sin(t) * cp
        out.append((x, y))
    return out


def parse_path(d):
    toks = re.findall(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?', d)
    i = 0
    subs = []
    cur = []
    x = y = 0.0
    sx = sy = 0.0
    cmd = None
    last_c = None
    closed = False

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v
    while i < len(toks):
        t = toks[i]
        if re.match(r'[A-Za-z]', t):
            cmd = t
            i += 1
            if cmd in "Zz":
                if cur:
                    subs.append((cur, True))
                cur = []
                x, y = sx, sy
                last_c = None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            nx, ny = num(), num()
            if rel:
                nx += x
                ny += y
            if cur:
                subs.append((cur, False))
            cur = [(nx, ny)]
            x, y, sx, sy = nx, ny, nx, ny
            cmd = "l" if rel else "L"
            last_c = None
        elif c == "L":
            nx, ny = num(), num()
            if rel:
                nx += x
                ny += y
            cur.append((nx, ny))
            x, y = nx, ny
            last_c = None
        elif c == "H":
            nx = num()
            if rel:
                nx += x
            cur.append((nx, y))
            x = nx
            last_c = None
        elif c == "V":
            ny = num()
            if rel:
                ny += y
            cur.append((x, ny))
            y = ny
            last_c = None
        elif c in "CS":
            if c == "C":
                x1, y1 = num(), num()
                if rel:
                    x1 += x
                    y1 += y
            else:
                x1, y1 = (2 * x - last_c[0], 2 * y - last_c[1]) if last_c else (x, y)
            x2, y2, nx, ny = num(), num(), num(), num()
            if rel:
                x2 += x
                y2 += y
                nx += x
                ny += y
            for k in range(1, 11):
                tt = k / 10
                u = 1 - tt
                cur.append((u ** 3 * x + 3 * u * u * tt * x1 + 3 * u * tt * tt * x2 + tt ** 3 * nx,
                            u ** 3 * y + 3 * u * u * tt * y1 + 3 * u * tt * tt * y2 + tt ** 3 * ny))
            last_c = (x2, y2)
            x, y = nx, ny
        elif c in "QT":
            if c == "Q":
                x1, y1 = num(), num()
                if rel:
                    x1 += x
                    y1 += y
            else:
                x1, y1 = (2 * x - last_c[0], 2 * y - last_c[1]) if last_c else (x, y)
            nx, ny = num(), num()
            if rel:
                nx += x
                ny += y
            for k in range(1, 9):
                tt = k / 8
                u = 1 - tt
                cur.append((u * u * x + 2 * u * tt * x1 + tt * tt * nx, u * u * y + 2 * u * tt * y1 + tt * tt * ny))
            last_c = (x1, y1)
            x, y = nx, ny
        elif c == "A":
            rx, ry, phi, la, sw, nx, ny = num(), num(), num(), num(), num(), num(), num()
            if rel:
                nx += x
                ny += y
            cur.extend(arc_points(x, y, rx, ry, phi, int(la), int(sw), nx, ny))
            x, y = nx, ny
            last_c = None
    if cur:
        subs.append((cur, False))
    return subs


def ellipse_pts(cx, cy, rx, ry, n=28):
    return [(cx + rx * math.cos(2 * math.pi * k / n), cy + ry * math.sin(2 * math.pi * k / n)) for k in range(n)]


def round_rect(x, y, w, h, r):
    r = min(r, w / 2, h / 2)
    if r <= 0.01:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = []
    for cx, cy, a0 in [(x + w - r, y + r, -90), (x + w - r, y + h - r, 0), (x + r, y + h - r, 90), (x + r, y + r, 180)]:
        for k in range(5):
            a = math.radians(a0 + 90 * k / 4)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def dashes(pts, closed, pattern):
    if closed:
        pts = pts + [pts[0]]
    out = []
    pat = pattern
    idx = 0
    remain = pat[0]
    on = True
    seg = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        L = math.dist(a, b)
        pos = 0.0
        while L - pos > remain:
            pos += remain
            p = (a[0] + (b[0] - a[0]) * pos / L, a[1] + (b[1] - a[1]) * pos / L)
            if on:
                seg.append(p)
                if len(seg) > 1:
                    out.append(seg)
            seg = [p]
            on = not on
            idx = (idx + 1) % len(pat)
            remain = pat[idx]
        remain -= (L - pos)
        if on:
            seg.append(b)
    if on and len(seg) > 1:
        out.append(seg)
    return out


def norm_color(c):
    if c is None:
        return None
    c = c.strip()
    if c in ("none", "transparent") or c.startswith("url("):
        return None
    if c.startswith("#") and len(c) == 4:
        c = "#" + "".join(ch * 2 for ch in c[1:])
    c = c.upper()
    return PLAYER_TOKENS.get(c, c)


def style_of(el, inherited):
    st = dict(inherited)
    for k in ("fill", "stroke", "stroke-width", "fill-opacity", "stroke-opacity", "opacity", "stroke-dasharray"):
        if el.get(k) is not None:
            st[k] = el.get(k)
    if el.get("style"):
        for part in el.get("style").split(";"):
            if ":" in part:
                k, v = part.split(":", 1)
                if k.strip() in ("fill", "stroke", "stroke-width", "opacity"):
                    st[k.strip()] = v.strip()
    return st


def r2(v):
    return round(v, 2)


def convert(svg_text, skip_puck):
    svg_text = re.sub(r'\{\{[^}]*\}\}', '', svg_text)
    root = ET.fromstring(svg_text)
    shapes = []
    sym = None

    def walk(el, m, st):
        nonlocal sym
        tag = el.tag.split('}')[-1]
        if tag in ("defs", "text", "clipPath", "pattern", "filter", "title"):
            return
        st = style_of(el, st)
        tr = el.get("transform")
        mm = mat_mul(m, parse_transform(tr)) if tr else m
        if tag == "g":
            if tr and tr.strip().endswith("translate(-50 -50)"):
                c = apply(mm, (50, 50))
                s = math.hypot(mm[0], mm[1])
                sym = (r2(c[0]), r2(c[1]), round(s, 3))
                return
            for ch in el:
                walk(ch, mm, st)
            return
        if skip_puck:
            for stag, attrs in PUCK_SKIP:
                if tag == stag and all(el.get(k, "").upper() == v.upper() for k, v in attrs.items()):
                    return
        subs = []
        if tag == "path":
            subs = parse_path(el.get("d"))
        elif tag == "rect":
            x, y = float(el.get("x", 0)), float(el.get("y", 0))
            w, h = float(el.get("width")), float(el.get("height"))
            subs = [(round_rect(x, y, w, h, float(el.get("rx", 0))), True)]
        elif tag == "circle":
            subs = [(ellipse_pts(float(el.get("cx", 0)), float(el.get("cy", 0)), float(el.get("r")), float(el.get("r"))), True)]
        elif tag == "ellipse":
            subs = [(ellipse_pts(float(el.get("cx", 0)), float(el.get("cy", 0)), float(el.get("rx")), float(el.get("ry"))), True)]
        elif tag == "line":
            subs = [([(float(el.get("x1")), float(el.get("y1"))), (float(el.get("x2")), float(el.get("y2")))], False)]
        elif tag in ("polyline", "polygon"):
            v = [float(t) for t in re.split(r'[ ,]+', el.get("points").strip())]
            subs = [(list(zip(v[0::2], v[1::2])), tag == "polygon")]
        else:
            return
        fill = norm_color(st.get("fill", "#000000"))
        stroke = norm_color(st.get("stroke"))
        op = float(st.get("opacity", 1))
        fa = float(st.get("fill-opacity", 1)) * op
        sa = float(st.get("stroke-opacity", 1)) * op
        sw = float(st.get("stroke-width", 1)) * math.hypot(mm[0], mm[1])
        dash = st.get("stroke-dasharray")
        for pts, closed in subs:
            pts = [apply(mm, p) for p in pts]
            clean = [pts[0]]
            for p in pts[1:]:
                if math.dist(p, clean[-1]) > 0.05:
                    clean.append(p)
            pts = clean
            if fill and len(pts) >= 3 and tag != "line":
                shapes.append(["f", fill, round(fa, 3), 0, True, [r2(c) for p in pts for c in p]])
            if stroke and sw > 0 and len(pts) >= 2:
                is_closed = closed or tag in ("rect", "circle", "ellipse", "polygon")
                if dash:
                    pat = [float(t) for t in re.split(r'[ ,]+', dash.strip()) if t]
                    pat = [p * math.hypot(mm[0], mm[1]) for p in pat]
                    for seg in dashes(pts, is_closed, pat):
                        shapes.append(["s", stroke, round(sa, 3), r2(sw), False, [r2(c) for p in seg for c in p]])
                else:
                    shapes.append(["s", stroke, round(sa, 3), r2(sw), is_closed, [r2(c) for p in pts for c in p]])

    for ch in root:
        walk(ch, (1, 0, 0, 1, 0, 0), {})
    return shapes, sym


def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    if isinstance(v, float):
        s = ("%.3f" % v).rstrip("0").rstrip(".")
        return s if s not in ("", "-0") else "0"
    return str(v)


def main(src, dst):
    html = open(src, encoding="utf-8").read()
    out = {}
    syms = {}
    for m in re.finditer(r'<svg([^>]*)>(.*?)</svg>', html, flags=re.S):
        attrs = m.group(1)
        lab = re.search(r'aria-label="([^"]*)"', attrs)
        if not lab or lab.group(1) not in NAMES:
            continue
        pid = NAMES[lab.group(1)]
        if pid in out:
            continue
        svg = '<svg xmlns="http://www.w3.org/2000/svg">' + m.group(2) + '</svg>'
        shapes, sym = convert(svg, not pid.startswith("set_"))
        out[pid] = shapes
        if sym:
            syms[pid] = sym
    lines = ['extends RefCounted', '## 자동 생성: tools/svg_to_art.py — 디자인 시안 「확장 부품과 새 세트」의 도면.',
             '## 도형: [f(채움)|s(선), 색("#RRGGBB" | "P" 주인 색 | "PL" 밝은 주인 색), 투명도, 선 굵기, 닫힘, 좌표 배열].',
             '## 좌표는 도면 좌표 (퍽 중심 60,62 · 위가 정면).', '']
    lines.append('const SHAPES := {')
    for pid, shapes in out.items():
        lines.append('\t"%s": [' % pid)
        for s in shapes:
            lines.append('\t\t' + gd_value(s) + ',')
        lines.append('\t],')
    lines.append('}')
    lines.append('')
    lines.append('## 세트 변신 외형의 각인 위치와 크기 (도면 좌표).')
    lines.append('const SYMBOLS := {')
    for pid, s in syms.items():
        lines.append('\t"%s": [%s, %s, %s],' % (pid, gd_value(float(s[0])), gd_value(float(s[1])), gd_value(float(s[2]))))
    lines.append('}')
    open(dst, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print("parts:", len(out), "missing:", sorted(set(NAMES.values()) - set(out)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
