"""디자인 「공방 · 태엽 시계탑」「공방 · 해적 선착장」의 부품·세트 변신 도면과
「신규 공방 강화 외형」의 강화 후 도면을 게임 도형으로 바꾼다.

    python tools/svg_ws_to_art.py <project 폴더> scripts/art_ws_data.gd

각 보드의 SVG 순서: 입장 3 · 경기장 1 · 기믹 3 · 세트 변신 1 · 부품 17 (세트 3 → 단품 14, 보드 글 순서).
강화 보드는 (강화 전, 강화 후) 28쌍: 시계탑 단품 14 → 선착장 단품 14.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_to_art as A  # noqa: E402

CLOCK = ["hour_hammer", "late_key", "minute_spring", "time_spring", "reserve_bow", "rewind_watch", "slow_arrow", "order_swap",
         "hourglass", "metronome", "alarm_clock", "wind_mouse", "shock_spring", "slow_spring", "replay_spring", "time_capsule", "tick_step"]
PIRATE = ["parrot_hat", "hook_hand", "peg_leg", "hole_cannon", "spyglass", "bolas", "smoke_powder", "flag_signal",
          "rum_barrel", "water_pump", "plank_dock", "treasure_chest", "jump_board", "wind_sail", "lifeboat", "oar", "helm"]


def svgs_of(path):
    html = open(path, encoding="utf-8").read()
    return re.findall(r'<svg[^>]*>(.*?)</svg>', html, flags=re.S)


def strip_group(body, head):
    """body 에서 head 로 시작하는 <g> 를 짝이 맞는 </g> 까지 지운다."""
    i = body.find(head)
    if i < 0:
        return body
    depth = 0
    j = i
    while j < len(body):
        if body.startswith('<g', j):
            depth += 1
        elif body.startswith('</g>', j):
            depth -= 1
            if depth == 0:
                return body[:i] + body[j + 4:]
        j += 1
    return body


def conv(body, skip_puck):
    body = re.sub(r'<g transform="translate\((100 112|108 116)\)">.*?</g>', '', body, flags=re.S)  # ★
    return A.convert('<svg xmlns="http://www.w3.org/2000/svg">' + body + '</svg>', skip_puck)


def main(folder, dst):
    shapes = {}
    syms = {}
    ups = {}
    for board, ids, set_id in [("WSClock.dc.html", CLOCK, "set_clock"), ("WSPirate.dc.html", PIRATE, "set_captain")]:
        svgs = svgs_of(os.path.join(folder, board))
        assert len(svgs) == 25, (board, len(svgs))
        # 세트 변신: 퍽(빨강 · 동그라미 기호)은 빼고 겉모습만. 퍽은 게임이 주인 색과 기호로 그린다
        body = svgs[7]
        head = '<g transform="translate(60.0 62.0)">'
        cut = body.find(head)
        rest = strip_group(body[cut:], head)
        back, _ = conv(body[:cut], False)
        front, _ = conv(rest, False)
        shapes[set_id] = back
        shapes[set_id + "_front"] = front
        for i, pid in enumerate(ids):
            shapes[pid], _ = conv(svgs[8 + i], True)
    up = svgs_of(os.path.join(folder, "WSUpgrade.dc.html"))
    assert len(up) == 56, len(up)
    for i, pid in enumerate(CLOCK[3:] + PIRATE[3:]):
        ups[pid], _ = conv(up[2 * i + 1], True)
    lines = ['extends RefCounted', '## 자동 생성: tools/svg_ws_to_art.py — 디자인 「공방 · 태엽 시계탑」「공방 · 해적 선착장」「신규 공방 강화 외형」.',
             '## 형식은 art_data.gd 와 같다 (퍽 중심 60,62 · 위가 정면).', '', 'const SHAPES := {']
    for pid, sh in shapes.items():
        lines.append('\t"%s": [' % pid)
        for s in sh:
            lines.append('\t\t' + A.gd_value(s) + ',')
        lines.append('\t],')
    lines.append('}')
    lines.append('')
    lines.append('const SYMBOLS := {')
    for pid, s in syms.items():
        lines.append('\t"%s": [%s, %s, %s],' % (pid, A.gd_value(float(s[0])), A.gd_value(float(s[1])), A.gd_value(float(s[2]))))
    lines.append('}')
    lines.append('')
    lines.append('## 강화 후 외형')
    lines.append('const UP := {')
    for pid, sh in ups.items():
        lines.append('\t"%s": [' % pid)
        for s in sh:
            lines.append('\t\t' + A.gd_value(s) + ',')
        lines.append('\t],')
    lines.append('}')
    open(dst, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print("parts", len(shapes), "ups", len(ups), "syms", list(syms))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
