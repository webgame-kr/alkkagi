extends RefCounted
## 부품 데이터. 슬롯, 발동 시점, 설명, 충격량 같은 수치를 한곳에서 관리한다.
## 효과를 실행하는 코드는 parts.gd 에 있다.

const SLOT_LABEL := {"weapon": "무기", "aux": "보조", "prop": "추진"}
const SLOTS := ["weapon", "aux", "prop"]

## power: 상대 알에 주는 속도 변화(px/s). range: 작동 거리(px).
const CATALOG := {
	# ── 무기 ──────────────────────────────────────────────
	"pea": {"name": "콩알총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면으로 탄환 한 발. 처음 맞힌 알을 밀고 사라진다.",
		"power": 380.0, "bullet": true},
	"shotgun": {"name": "산탄총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면 부채꼴로 탄환 세 발. 가까운 알은 여러 발을 맞는다.",
		"power": 200.0, "spread_deg": 13.0, "bullet": true},
	"hook": {"name": "갈고리", "slot": "weapon", "when": "발사 직후",
		"desc": "정면의 첫 상대 알을 내 쪽으로 당긴다.",
		"power": 560.0, "range": 440.0},
	"claw": {"name": "집게", "slot": "weapon", "when": "첫 정면 충돌",
		"desc": "정면에서 처음 맞힌 상대 알을 잠깐 붙잡고 함께 밀고 간다.",
		"hold": 0.8},
	"nose": {"name": "고무코", "slot": "weapon", "when": "첫 정면 충돌",
		"desc": "상대를 세게 밀고 내 알은 뒤로 살짝 튕긴다.",
		"power": 400.0, "bounce": 170.0},
	"stamp": {"name": "자리바꿈 도장", "slot": "weapon", "when": "약한 샷의 첫 충돌",
		"desc": "힘 45% 이하로 처음 맞힌 상대 알과 자리를 바꾸고 둘 다 멈춘다.",
		"max_power": 0.45},
	"copier": {"name": "고장 난 복사기", "slot": "weapon", "when": "첫 충돌",
		"desc": "충돌 지점에 포탑을 남긴다. 다음 내 샷 때 설치할 때의 조준 방향으로 한 발 쏘고 사라진다.",
		"power": 380.0},
	# ── 보조 ──────────────────────────────────────────────
	"magnet": {"name": "자석팔", "slot": "aux", "when": "발사 직후",
		"desc": "장착한 쪽의 가까운 상대 알 하나를 끌어당긴다. 장착할 때 좌우를 고른다.",
		"power": 520.0, "range": 300.0},
	"bumper": {"name": "접이식 범퍼", "slot": "aux", "when": "첫 측면 충돌",
		"desc": "범퍼가 펴져 부딪힌 알을 옆으로 민다.",
		"power": 440.0},
	"flipper": {"name": "오리발", "slot": "aux", "when": "첫 충돌 직후",
		"desc": "옆쪽의 가까운 알 하나에 짧은 발차기를 날린다.",
		"power": 420.0, "range": 140.0},
	"decal": {"name": "데칼코마니 포신", "slot": "aux", "when": "무기가 탄환을 쏠 때",
		"desc": "판 중심을 사이에 둔 반대편 대칭 위치에서 대칭 방향으로 보조탄이 나온다.",
		"needs": "bullet"},
	"umbrella": {"name": "거울 우산", "slot": "aux", "when": "첫 충돌",
		"desc": "충돌 지점에 거울을 편다. 다음 바퀴 끝까지, 누구의 탄환이든 한 발을 반사하면 접힌다.",
		"half_len": 42.0},
	"spring": {"name": "스프링 분신", "slot": "aux", "when": "첫 충돌",
		"desc": "옆으로 작은 고무 알을 튕겨 보낸다. 처음 맞힌 알을 밀고 사라진다.",
		"power": 380.0, "speed": 760.0},
	"carousel": {"name": "회전목마 팔", "slot": "aux", "when": "첫 측면 충돌",
		"desc": "부딪힌 상대 알을 잡아 내 반대편으로 휘둘러 던진다.",
		"power": 330.0},
	"bubble": {"name": "버블 프린터", "slot": "aux", "when": "샷이 끝날 때",
		"desc": "지나온 길 중간에 방울을 남긴다. 다음 샷부터 처음 닿은 알을 옆으로 민다.",
		"power": 400.0, "radius": 16.0, "rounds": 1},
	"mine": {"name": "지뢰 배출기", "slot": "aux", "when": "알이 멈출 때",
		"desc": "멈춘 자리에 지뢰를 놓는다. 다음 샷부터 알이 닿으면 터져 주변 알을 밀어낸다.",
		"power": 560.0, "radius": 26.0, "blast": 135.0, "rounds": 2},
	# ── 추진 ──────────────────────────────────────────────
	"rocket": {"name": "로켓", "slot": "prop", "when": "첫 충돌 직후",
		"desc": "발사 방향으로 한 번 더 가속한다.",
		"power": 650.0},
	"retro": {"name": "역추진 로켓", "slot": "prop", "when": "첫 충돌 직후",
		"desc": "발사 반대 방향으로 가속한다. 상대를 치고 판 안쪽으로 빠져나온다.",
		"power": 620.0},
	"reel": {"name": "리턴 릴", "slot": "prop", "when": "첫 충돌 직후",
		"desc": "출발점에 걸어둔 줄이 감겨 내 알을 끌어당긴다. 돌아오는 길에도 부딪힌다.",
		"accel": 2600.0, "max_speed": 820.0, "time": 1.3},
	"chute": {"name": "낙하산", "slot": "prop", "when": "판 끝 구역에 들어갈 때",
		"desc": "내 알이 판 끝 구역에 들어가면 한 번 급제동한다. 너무 빠르면 그대로 떨어질 수 있다.",
		"power": 550.0},
	# ── 신규 무기 ─────────────────────────────────────────
	"trex_head": {"name": "티라노 머리", "slot": "weapon", "when": "첫 정면 충돌", "set": "trex",
		"desc": "정면에서 처음 부딪힌 상대 알을 잠깐 물고 발사 방향으로 밀어낸다.",
		"power": 300.0},
	"sucker": {"name": "빨판총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면으로 빨판을 쏜다. 맞은 알은 이번 샷에 한 번 짧게 감속한다. 도망가는 알을 세워 몸통으로 칠 수 있다.",
		"speed": 1150.0, "brake": 0.3},
	"umbrella_gun": {"name": "우산총", "slot": "weapon", "when": "발사 순간",
		"desc": "정면으로 접힌 우산을 쏜다. 일정 거리를 지나면 펼쳐지며 옆으로 넓은 범위의 알을 민다.",
		"speed": 900.0, "open_dist": 190.0, "radius": 90.0, "power": 340.0},
	"roller": {"name": "페인트 롤러", "slot": "weapon", "when": "첫 정면 충돌",
		"desc": "처음 정면으로 맞은 알 뒤로 미끄러운 띠를 남긴다. 띠 위를 지나는 알은 마찰이 줄어 더 멀리 미끄러진다.",
		"length": 200.0, "width": 44.0, "friction": 0.3, "rounds": 1},
	# ── 신규 보조 ─────────────────────────────────────────
	"trex_arm": {"name": "티라노 팔", "slot": "aux", "when": "첫 측면 충돌", "set": "trex",
		"desc": "옆으로 부딪힌 상대 알 하나를 내 알 앞쪽으로 끌어온다."},
	"shield": {"name": "딱지 방패", "slot": "aux", "when": "처음 탄환을 맞을 때", "side": true,
		"desc": "이 알이 처음 탄환을 맞으면 방패가 뒤집히며 탄환을 옆으로 튕겨낸다. 튕기는 쪽은 장착할 때 고른다."},
	"tambourine": {"name": "탬버린", "slot": "aux", "when": "첫 충돌",
		"desc": "첫 충돌 지점에서 진동이 퍼진다. 직접 부딪히지 않은 가까운 알도 조금씩 밀려난다.",
		"radius": 130.0, "power": 240.0},
	"track": {"name": "바퀴 자국", "slot": "aux", "when": "멈출 때",
		"desc": "멈출 때 지나온 길에 짧은 홈을 남긴다. 다음 샷부터 처음 홈을 밟은 알이 홈 방향으로 살짝 꺾인다.",
		"length": 140.0, "turn_deg": 30.0, "rounds": 1},
	# ── 신규 추진 ─────────────────────────────────────────
	"trex_leg": {"name": "티라노 다리", "slot": "prop", "when": "첫 몸통 충돌 직후", "set": "trex",
		"desc": "첫 몸통 충돌 뒤 두 발로 버텨 내 알의 반동을 줄인다.",
		"keep": 0.25},
	"crab": {"name": "게걸음 바퀴", "slot": "prop", "when": "첫 충돌 직후", "side": true,
		"desc": "첫 충돌 직후 장착할 때 고른 좌우 방향으로 짧게 튄다.",
		"power": 480.0},
	"clockwork": {"name": "딸깍 태엽", "slot": "prop", "when": "약한 샷 뒤 잠깐 뒤",
		"desc": "힘 50% 이하로 쏘면 출발은 느리지만 잠깐 뒤 한 번 가속한다. 가속할 위치를 조준 중 표시한다.",
		"max_power": 0.5, "delay": 0.45, "power": 520.0},
	"brake": {"name": "도장 브레이크", "slot": "prop", "when": "속도가 떨어질 때",
		"desc": "쏜 알의 속도가 일정 수준 아래로 떨어지면 한 번 급정지한다. 다음 턴에 쓸 자리를 정확히 잡기 좋다.",
		"threshold": 260.0},
}

## 세트: 같은 알에 세 부품을 모두 달면 전용 동작이 열린다.
const SETS := {"trex": {"name": "메카 티라노", "parts": ["trex_head", "trex_arm", "trex_leg"],
	"move": "물고 던지기", "short": {"trex_head": "머리", "trex_arm": "팔", "trex_leg": "다리"},
	"throw_power": 420.0}}

## 장착할 때 좌우를 고르는 부품. 보조는 Stone.magnet_side, 추진은 Stone.prop_side 에 저장.
const SIDE_PARTS := ["magnet", "shield", "crab"]

## 탄환을 쏘는 무기(데칼코마니 포신의 조건).
const BULLET_WEAPONS := ["pea", "shotgun"]


static func ids() -> Array:
	return CATALOG.keys()


static func get_part(id: String) -> Dictionary:
	return CATALOG.get(id, {})


static func part_name(id: String) -> String:
	if id == "":
		return "-"
	return CATALOG[id]["name"]


static func slot_of(id: String) -> String:
	return CATALOG[id]["slot"]


static func num(id: String, key: String) -> float:
	return float(CATALOG[id][key])


## 이 알에서 부품이 실제로 작동할 수 있는지. 조건이 안 맞으면 이유를 돌려준다.
static func unmet_need(id: String, stone_parts: Dictionary) -> String:
	var need: String = CATALOG.get(id, {}).get("needs", "")
	if need == "bullet" and not BULLET_WEAPONS.has(stone_parts.get("weapon", "")):
		return "탄환 무기(콩알총·산탄총)가 있어야 작동"
	return ""


static func set_of(id: String) -> String:
	return CATALOG.get(id, {}).get("set", "")


## 이 알에 달린 세트 부품 수. {set, count, missing:[id]}
static func set_progress(stone_parts: Dictionary, set_id := "trex") -> Dictionary:
	var have := 0
	var missing: Array = []
	for pid in SETS[set_id]["parts"]:
		if stone_parts.values().has(pid):
			have += 1
		else:
			missing.append(pid)
	return {"set": set_id, "count": have, "missing": missing, "total": SETS[set_id]["parts"].size()}


static func set_complete(stone_parts: Dictionary, set_id := "trex") -> bool:
	return set_progress(stone_parts, set_id)["count"] == SETS[set_id]["parts"].size()


## 예: "메카 티라노 2/3 · 다리 필요"
static func set_label(stone_parts: Dictionary, set_id := "trex") -> String:
	var pr := set_progress(stone_parts, set_id)
	if pr["count"] == 0:
		return ""
	var st: Dictionary = SETS[set_id]
	if pr["count"] == pr["total"]:
		return "%s 완성 · %s" % [st["name"], st["move"]]
	var need: Array = []
	for m in pr["missing"]:
		need.append(st["short"][m])
	return "%s %d/%d · %s 필요" % [st["name"], pr["count"], pr["total"], "·".join(need)]
