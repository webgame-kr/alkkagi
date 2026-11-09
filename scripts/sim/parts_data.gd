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
}

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
