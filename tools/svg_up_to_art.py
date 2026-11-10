"""디자인 「강화 외형 34종」(UpgradeLook.dc.html)의 강화 후 도면을 게임 도형으로 바꾼다.

    python tools/svg_up_to_art.py <UpgradeLook.dc.html> scripts/art_up_data.gd

보드에는 (강화 전, 강화 후) 그림이 아래 ORDER 순서로 짝지어 있다. 강화 후 그림만 쓴다.
기본 퍽 몸통과 ★ 표시는 게임이 직접 그리므로 뺀다. 만화 부품의 충격 모양 판은 그대로 둔다(맨 뒤).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svg_to_art as A  # noqa: E402

ORDER = ["pea", "magnet", "rocket", "retro", "shotgun", "claw", "sucker", "brake", "mine", "hook",
         "copier", "carousel", "crab", "shadow_scale", "night_charm", "anchor", "echo_bell", "moon_well",
         "wind_knot", "side_scroll", "drift_tire", "flash_step", "rubber_fist", "charge_palm", "at_field",
         "log_sub", "trap_card", "stopwatch", "rebound_shoes", "alchemy_glove", "nose", "flipper", "chute",
         "bumper"]


def main(src, dst):
    html = open(src, encoding="utf-8").read()
    svgs = re.findall(r'<svg[^>]*aria-hidden="true"[^>]*>(.*?)</svg>', html, flags=re.S)
    assert len(svgs) == 2 * len(ORDER), len(svgs)
    lines = ['extends RefCounted', '## 자동 생성: tools/svg_up_to_art.py — 디자인 「강화 외형 34종」의 강화 후 도면.',
             '## 형식은 art_data.gd 와 같다 (퍽 중심 60,62 · 위가 정면).', '', 'const SHAPES := {']
    for i, pid in enumerate(ORDER):
        body = svgs[2 * i + 1]
        body = re.sub(r'<g transform="translate\(100 112\)">.*?</g>', '', body, flags=re.S)  # ★
        shapes, _ = A.convert('<svg xmlns="http://www.w3.org/2000/svg">' + body + '</svg>', True)
        lines.append('\t"%s": [' % pid)
        for s in shapes:
            lines.append('\t\t' + A.gd_value(s) + ',')
        lines.append('\t],')
    lines.append('}')
    open(dst, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    print("ok", len(ORDER))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
