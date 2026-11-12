extends RefCounted
## 퍽과 부품 실루엣. 디자인 시안 「퍽과 부품 실루엣」의 도면 좌표를 그대로 옮겼다.
## 도면 좌표: 퍽 중심 (60, 62), 반지름 24, 위쪽(-y)이 조준 방향.
## 무기는 앞, 보조는 오른쪽(자석팔 왼쪽 장착이면 좌우 반전), 추진은 뒤에 붙는다.
## draw() 는 퍽 중심을 원점, 진행 방향을 +x 로 둔 월드 단위 공간에서 부른다.

const R := 22.0                 # 월드에서 퍽 반지름 (world.gd STONE_R)
const K := R / 24.0             # 도면 1단위 → 월드

const OUT := Color("0E1013")
const STEEL := Color("C3C9D0")
const STEEL_D := Color("6F7782")
const BRASS := Color("C9A15A")
const RED := Color("D2452F")
const WHITE := Color("E9ECEF")
const CORE := Color("23272D")
const NEUTRAL := Color("8A929C")
const TICK := Color("F2F4F1")

const C0 := Vector2(60, 62)     # 도면의 퍽 중심
const ArtData = preload("res://scripts/art_data.gd")
const ArtUp = preload("res://scripts/art_up_data.gd")
const ArtWs = preload("res://scripts/art_ws_data.gd")
## 세트 변신 겉모습 (퍽 위·아래 두 겹): 세트 id → 도형 이름
const WS_SETS := {"clock": "set_clock", "captain": "set_captain", "director": "set_director"}
const WS_SET_PARTS := {"clock": ["hour_hammer", "late_key", "minute_spring"], "captain": ["parrot_hat", "hook_hand", "peg_leg"]}

## 만화 연출 중인 알: 모든 색을 먹선 흑백으로 그린다.
static var mono := false
static var _poly_ok := {}
## 공방 스킨 (디자인 「알 디자인 시안 · 공방 스킨 6종」): 그날 공방 재질로 알 겉모습만 바뀐다. "" 이면 기본 금속 퍽.
static var skin := ""
## 판 위에서는 퍽 몸통을 화면 공간에서 따로 그린다 (draw_puck_top). 이때 draw() 는 부품만 그린다.
static var skip_body := false
## draw() 가 몸통까지 그릴 때 로컬 공간이 화면에 대해 돌아간 각도 (도감·카드 그림은 정면이 위: -PI/2).
static var view_rot := -PI / 2.0
static var outline := Color("1A1D21")
static var shadow := Color(40 / 255.0, 25 / 255.0, 10 / 255.0, 0.32)


## 판 위의 퍽. symbol: 0~7 플레이어 각인. tick: 정면 눈금.
## ups: 강화된 슬롯 {slot: true} → 디자인 「강화 외형」 모양으로 그린다.
static func draw(ci: CanvasItem, parts: Dictionary, magnet_side: int, col: Color, alpha := 1.0, symbol := -1, tick := true, ups := {}) -> void:
	var a := alpha
	var w: String = parts.get("weapon", "")
	var x: String = parts.get("aux", "")
	var p: String = parts.get("prop", "")
	if w == "trex_head" and x == "trex_arm" and p == "trex_leg":
		draw_mecha(ci, col, a, symbol)
		return
	if w == "moon_staff" and x == "star_cloak" and p == "moon_boots":
		draw_set_form(ci, "set_moon", col, a, symbol)
		return
	if w == "hero_band" and x == "torn_cape" and p == "awaken_shoes":
		draw_set_form(ci, "set_hero", col, a, symbol)
		return
	var ws_set := ws_set_of(parts)
	if ws_set != "":
		# 시계공 · 선장: 겉모습 뒤쪽 → 주인 색 퍽 → 겉모습 앞쪽
		var key: String = WS_SETS[ws_set]
		draw_data(ci, key, a, false, col, ArtWs.SHAPES[key], "ws:" + key)
		if not skip_body:
			draw_puck_shadow(ci, Vector2.ZERO, R, a, view_rot)
			draw_puck_top(ci, Vector2.ZERO, R, col, symbol, 0.0, a, view_rot)
			draw_front(ci, parts, col, a)
		return
	var mirror := (x == "magnet" or x == "shield") and magnet_side < 0
	# 만화 강화 부품의 충격 모양 판은 다른 부품보다 뒤에
	for slot in ["prop", "weapon", "aux"]:
		var id: String = parts.get(slot, "")
		if ups.get(slot, false) and ArtUp.SHAPES.has(id):
			_up_plate(ci, id, a)
	if p != "":
		if not _up(ci, p, a, false, ups.get("prop", false)):
			_prop(ci, p, a)
	if w != "":
		if not _up(ci, w, a, false, ups.get("weapon", false)):
			_weapon(ci, w, a)
	if x != "":
		if not _up(ci, x, a, mirror, ups.get("aux", false)):
			_aux(ci, x, a, mirror)
	if not skip_body:
		draw_puck_shadow(ci, Vector2.ZERO, R, a, view_rot)
		draw_puck_top(ci, Vector2.ZERO, R, col, symbol, 0.0, a, view_rot)


static func ws_set_of(parts: Dictionary) -> String:
	for sid in WS_SET_PARTS:
		var ok := true
		var arr: Array = WS_SET_PARTS[sid]
		if parts.get("weapon", "") != arr[0] or parts.get("aux", "") != arr[1] or parts.get("prop", "") != arr[2]:
			ok = false
		if ok:
			return sid
	return ""


## 세트 변신 겉모습 가운데 퍽 위에 오는 겹 (외알 안경, 코트 깃 …). 판 위에서는 화면이 퍽을 그린 뒤 부른다.
static func draw_front(ci: CanvasItem, parts: Dictionary, col: Color, a := 1.0) -> void:
	var ws_set := ws_set_of(parts)
	if ws_set == "":
		return
	var key: String = WS_SETS[ws_set] + "_front"
	draw_data(ci, key, a, false, col, ArtWs.SHAPES[key], "ws:" + key)


static func is_set_form(parts: Dictionary) -> bool:
	var w: String = parts.get("weapon", "")
	var x: String = parts.get("aux", "")
	var p: String = parts.get("prop", "")
	return (w == "trex_head" and x == "trex_arm" and p == "trex_leg") or (w == "moon_staff" and x == "star_cloak" and p == "moon_boots") \
		or (w == "hero_band" and x == "torn_cape" and p == "awaken_shoes")


# ── 좌표 변환 ────────────────────────────────────────────
## 도면 점 → 로컬(+x 정면). 도면의 위(-y)가 +x, 도면의 오른쪽(+x)이 +y(진행 방향 오른쪽).
static func T(v: Vector2, mirror := false) -> Vector2:
	var d := v - C0
	if mirror:
		d.x = -d.x
	return Vector2(-d.y, d.x) * K


static func _pts(arr: Array, mirror := false) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in arr:
		out.append(T(v, mirror))
	return out


static func _al(c: Color, a: float) -> Color:
	if mono:
		var g := clampf((c.r * 0.3 + c.g * 0.59 + c.b * 0.11) * 1.35 - 0.12, 0.0, 1.0)
		return Color(g, g, g, c.a * a)
	return Color(c.r, c.g, c.b, c.a * a)


static func poly(ci: CanvasItem, pts: Array, fill: Color, a: float, mirror := false, stroke := 2.0) -> void:
	var pp := _pts(pts, mirror)
	ci.draw_colored_polygon(pp, _al(fill, a))
	if stroke > 0.0:
		var closed := pp.duplicate()
		closed.append(pp[0])
		ci.draw_polyline(closed, _al(OUT, a), stroke * K, true)


static func rect(ci: CanvasItem, x: float, y: float, w: float, h: float, fill: Color, a: float, mirror := false, stroke := 2.0) -> void:
	poly(ci, [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)], fill, a, mirror, stroke)


static func circ(ci: CanvasItem, c: Vector2, r: float, fill: Color, a: float, mirror := false, stroke := 2.0) -> void:
	var cc := T(c, mirror)
	if fill.a > 0.0:
		ci.draw_circle(cc, r * K, _al(fill, a))
	if stroke > 0.0:
		ci.draw_arc(cc, r * K, 0, TAU, 24, _al(OUT, a), stroke * K, true)


static func ring(ci: CanvasItem, c: Vector2, r: float, col: Color, width: float, a: float, mirror := false) -> void:
	ci.draw_arc(T(c, mirror), r * K, 0, TAU, 24, _al(col, a), width * K, true)


static func line(ci: CanvasItem, pts: Array, col: Color, width: float, a: float, mirror := false) -> void:
	ci.draw_polyline(_pts(pts, mirror), _al(col, a), width * K, true)


static func dashed(ci: CanvasItem, p0: Vector2, p1: Vector2, col: Color, width: float, dash: float, a: float, mirror := false) -> void:
	ci.draw_dashed_line(T(p0, mirror), T(p1, mirror), _al(col, a), width * K, dash * K)


## 2차 베지어를 점 배열로.
static func qbez(p0: Vector2, c: Vector2, p1: Vector2, steps := 8) -> Array:
	var out: Array = []
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		out.append(p0 * u * u + c * 2.0 * u * t + p1 * t * t)
	return out


## 3차 베지어를 점 배열로.
static func bez(p0: Vector2, c1: Vector2, c2: Vector2, p1: Vector2, steps := 10) -> Array:
	var out: Array = []
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		out.append(p0 * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + p1 * t * t * t)
	return out


## 도면 좌표 원호 (각도: 도면 기준, 0 = 오른쪽, 시계 방향 증가).
static func arc_pts(c: Vector2, r: float, from_deg: float, to_deg: float, steps := 12) -> Array:
	var out: Array = []
	for i in steps + 1:
		var ang := deg_to_rad(lerpf(from_deg, to_deg, float(i) / steps))
		out.append(c + Vector2(cos(ang), sin(ang)) * r)
	return out


# ── 퍽 ───────────────────────────────────────────────────

static func _puck(ci: CanvasItem, col: Color, a: float, symbol: int, tick: bool) -> void:
	ci.draw_circle(T(Vector2(61, 65)), 24 * K, Color(0, 0, 0, 0.35 * a))
	circ(ci, C0, 24, col, a)
	line(ci, arc_pts(Vector2(60, 60.6), 22, 197, 343), Color(1, 1, 1, 0.38), 2.0, a)
	circ(ci, C0, 15, CORE, a)
	line(ci, arc_pts(Vector2(60, 63), 11.5, 205, 335, 8), Color(1, 1, 1, 0.08), 1.5, a)
	if symbol >= 0:
		draw_symbol(ci, symbol, col, a, T(C0), 0.55 * K, true)
	if tick:
		line(ci, [Vector2(60, 39.5), Vector2(60, 45)], TICK, 2.5, a)


## 플레이어 각인 (원·삼각·사각·마름모·육각·십자·두 줄·갈매기). 100단위 도면, 중심 (50,50).
## rotate: 판 위 퍽처럼 로컬(+x 정면) 공간이면 true, 화면에 똑바로 그릴 땐 false.
static func draw_symbol(ci: CanvasItem, symbol: int, col: Color, a: float, center: Vector2, scale: float, rotate: bool, width := -1.0, turn := 0.0) -> void:
	var c := _al(col, a)
	var wdt := 4.5 * scale if width < 0.0 else width
	var f := func(v: Vector2) -> Vector2:
		var d := v - Vector2(50, 50)
		if rotate:
			d = Vector2(-d.y, d.x)
		if turn != 0.0:
			d = d.rotated(turn)
		return center + d * scale
	var pl := func(arr: Array, closed: bool) -> void:
		var pp := PackedVector2Array()
		for v in arr:
			pp.append(f.call(v))
		if closed:
			pp.append(pp[0])
		ci.draw_polyline(pp, c, wdt, true)
	match symbol % 8:
		0:
			ci.draw_arc(center, 10 * scale, 0, TAU, 20, c, wdt, true)
		1:
			pl.call([Vector2(50, 38.5), Vector2(61.5, 58.5), Vector2(38.5, 58.5)], true)
		2:
			pl.call([Vector2(41, 41), Vector2(59, 41), Vector2(59, 59), Vector2(41, 59)], true)
		3:
			pl.call([Vector2(50, 38), Vector2(62, 50), Vector2(50, 62), Vector2(38, 50)], true)
		4:
			pl.call([Vector2(50, 38.5), Vector2(60, 44.2), Vector2(60, 55.8), Vector2(50, 61.5), Vector2(40, 55.8), Vector2(40, 44.2)], true)
		5:
			pl.call([Vector2(50, 39), Vector2(50, 61)], false)
			pl.call([Vector2(39, 50), Vector2(61, 50)], false)
		6:
			pl.call([Vector2(39, 45), Vector2(61, 45)], false)
			pl.call([Vector2(39, 55), Vector2(61, 55)], false)
		7:
			pl.call([Vector2(39, 56), Vector2(50, 45), Vector2(61, 56)], false)


# ── 퍽 몸통 (디자인 사양 「퍽 디자인」) ──────────────────
## u: 퍽 반지름(px). front: 정면 방향(로컬 각도). rot: 로컬 공간이 화면에 대해 돌아간 각도.
## 빛·그림자·각인은 화면 기준(왼쪽 위 조명, 각인은 항상 똑바로)이라 rot 만큼 되돌려 그린다.

static func draw_puck_shadow(ci: CanvasItem, c: Vector2, u: float, a := 1.0, rot := 0.0) -> void:
	var pts := _ellipse_rot(c + Vector2(0.12 * u, 0.32 * u).rotated(-rot), 1.02 * u, 0.88 * u, -rot)
	ci.draw_colored_polygon(pts, Color(shadow, shadow.a * a))


## 자리(0~7)마다 고른 알: 실제 각인 기호 · 형태 · 색 (디자인 「알 디자인 시안」, 기획 「방 만들기·알 고르기」).
## 게임은 판 위·HUD 에서 symbol 자리에 자리 번호를 넘기고, 여기서 실제 모습으로 바꾼다.
static var slot_symbols: Array = [0, 1, 2, 3, 4, 5, 6, 7]
static var slot_forms: Array = ["metal", "metal", "metal", "metal", "metal", "metal", "metal", "metal"]
const FORM_NAMES := {"metal": "금속 퍽", "glass": "유리 바둑알", "cap": "병뚜껑", "button": "단추", "hockey": "하키 퍽", "marble": "유리 구슬", "coin": "동전"}


static func draw_puck_top(ci: CanvasItem, c: Vector2, u: float, col: Color, symbol: int, front: float, a := 1.0, rot := 0.0, notch := true) -> void:
	var sym := symbol
	var form := "metal"
	if symbol >= 0 and symbol < 8:
		sym = int(slot_symbols[symbol])
		form = str(slot_forms[symbol])
	if skin != "":
		form = "metal"   # 공방 스킨을 켠 방: 모두 공방 재질 (금속 퍽 + 스킨)
	draw_puck_form(ci, c, u, col, sym, form, front, a, rot, notch)


## 형태를 직접 골라 그린다 (알 고르기 화면 · 대기실 자리 카드)
static func draw_puck_form(ci: CanvasItem, c: Vector2, u: float, col: Color, symbol: int, form: String, front: float, a := 1.0, rot := 0.0, notch := true) -> void:
	if form != "metal" and form != "":
		_draw_form(ci, c, u, col, symbol, form, front, a, rot, notch)
		return
	var oc := _al(outline, a)
	var ow := 0.12 * u
	var down := Vector2(0, 1).rotated(-rot)
	# 옆면 두께
	var side := c + down * 0.16 * u
	ci.draw_circle(side, u, _al(Color(col.r * 0.55, col.g * 0.55, col.b * 0.55), a))
	ci.draw_arc(side, u, 0, TAU, 40, oc, ow, true)
	# 윗면: 왼쪽 위에서 밝은 방사형
	var hi := Color(minf(1.0, col.r * 1.22), minf(1.0, col.g * 1.22), minf(1.0, col.b * 1.22))
	ci.draw_circle(c, u, _al(col, a))
	var lp := c + Vector2(-0.35 * u, -0.45 * u).rotated(-rot)
	var steps := 5
	for i in range(1, steps):
		var t := float(i) / steps
		ci.draw_circle(c.lerp(lp, t), u * (1.0 - t * 0.85), _al(col.lerp(hi, t), a))
	ci.draw_arc(c, u, 0, TAU, 40, oc, ow, true)
	# 안쪽 밝은 테두리 (같은 계열 펠트 위에서도 묻히지 않게)
	ci.draw_arc(c, 0.9 * u, 0, TAU, 40, Color(1, 1, 1, 0.75 * a), 0.09 * u, true)
	# 경사면: 왼쪽 위 흰 호, 오른쪽 아래 검은 호
	ci.draw_arc(c, 0.78 * u, PI - rot, 1.5 * PI - rot, 12, Color(1, 1, 1, 0.35 * a), 0.08 * u, true)
	ci.draw_arc(c, 0.78 * u, 0.0 - rot, 0.5 * PI - rot, 12, Color(0, 0, 0, 0.18 * a), 0.08 * u, true)
	_skin_overlay(ci, c, u, col, a, rot, front)
	# 정면 홈
	if notch:
		draw_notch(ci, c, u, front, a)
	# 광택
	var gl := _ellipse_rot(c + Vector2(-0.35 * u, -0.5 * u).rotated(-rot), 0.42 * u, 0.18 * u, -0.5 - rot)
	ci.draw_colored_polygon(gl, Color(1, 1, 1, 0.32 * a))
	# 각인: 항상 똑바로. 노랑처럼 밝은 퍽은 진한 기호.
	if symbol >= 0:
		var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
		var sc := Color("1B1E22") if lum > 0.62 else Color.WHITE
		var k := 0.42 * u / 11.0
		var w := 0.13 * u
		draw_symbol(ci, symbol, Color(0, 0, 0, 0.35), a, c + down * 0.05 * u, k, false, w, -rot)
		draw_symbol(ci, symbol, sc, a, c, k, false, w, -rot)


static func _ellipse_rot(c: Vector2, rx: float, ry: float, ang: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		out.append(c + Vector2(cos(t) * rx, sin(t) * ry).rotated(ang))
	return out


## HUD용 퍽 아이콘 (똑바로 선 모습). size: 지름 px.
static func draw_icon(ci: CanvasItem, center: Vector2, size: float, col: Color, symbol: int, alpha := 1.0) -> void:
	var u := size * 0.5 * 0.86
	draw_puck_shadow(ci, center, u, alpha)
	draw_puck_top(ci, center + Vector2(0, -0.08 * u), u, col, symbol, -PI / 2.0, alpha)


static func _old_icon(ci: CanvasItem, center: Vector2, size: float, col: Color, symbol: int, alpha := 1.0) -> void:
	var s := size / 80.0
	ci.draw_circle(center + Vector2(0, 4 * s), 40 * s, Color(0, 0, 0, 0.35 * alpha))
	ci.draw_circle(center, 40 * s, _al(col, alpha))
	ci.draw_arc(center, 40 * s, 0, TAU, 32, _al(OUT, alpha), 2.5 * s, true)
	ci.draw_arc(center + Vector2(0, 1.7 * s), 35 * s, deg_to_rad(199), deg_to_rad(341), 16, Color(1, 1, 1, 0.38 * alpha), 3 * s, true)
	ci.draw_circle(center, 25 * s, _al(CORE, alpha))
	ci.draw_arc(center, 25 * s, 0, TAU, 28, _al(OUT, alpha), 2.5 * s, true)
	draw_symbol(ci, symbol, col, alpha, center, s, false)


## 슬롯 위치 아이콘: 회색 링 위의 황동 구간(앞·옆·뒤).
static func draw_slot_icon(ci: CanvasItem, center: Vector2, size: float, slot: String) -> void:
	var s := size / 100.0
	ci.draw_arc(center, 30 * s, 0, TAU, 28, NEUTRAL, 10 * s, true)
	var mid: float = {"weapon": -PI / 2.0, "aux": 0.0, "prop": PI / 2.0}.get(slot, 0.0)
	ci.draw_arc(center, 30 * s, mid - 0.42, mid + 0.42, 8, BRASS, 14 * s, true)
	ci.draw_circle(center, 18 * s, CORE)


# ── 무기 (앞) ────────────────────────────────────────────

static func _weapon(ci: CanvasItem, w: String, a: float) -> void:
	if ArtData.SHAPES.has(w):
		draw_data(ci, w, a, false)
		return
	if ArtWs.SHAPES.has(w):
		draw_data(ci, w, a, false, Color.WHITE, ArtWs.SHAPES[w], "ws:" + w)
		return
	if _lab(ci, w, a, false) or _clock(ci, w, a, false) or _pirate(ci, w, a, false):
		return
	match w:
		"pea":
			rect(ci, 53.5, 14, 13, 28, STEEL, a)
			rect(ci, 50, 8, 20, 9, STEEL_D, a)
			line(ci, [Vector2(56, 22), Vector2(64, 22)], STEEL_D, 1.5, a)
			line(ci, [Vector2(56, 28), Vector2(64, 28)], STEEL_D, 1.5, a)
		"shotgun":
			poly(ci, [Vector2(54, 42), Vector2(54, 28), Vector2(43, 8), Vector2(77, 8), Vector2(66, 28), Vector2(66, 42)], STEEL, a)
			line(ci, [Vector2(47, 13), Vector2(73, 13)], STEEL_D, 2, a)
			line(ci, [Vector2(54, 30), Vector2(66, 30)], STEEL_D, 1.5, a)
		"hook":
			dashed(ci, Vector2(60, 40), Vector2(60, 22), OUT, 2, 2.5, a)
			var hk: Array = bez(Vector2(45, 28), Vector2(43, 12), Vector2(54, 6), Vector2(60, 16))
			hk.append_array(bez(Vector2(60, 16), Vector2(66, 6), Vector2(77, 12), Vector2(75, 28)).slice(1))
			line(ci, hk, OUT, 7, a)
			line(ci, hk, STEEL, 3.5, a)
			rect(ci, 54, 34, 12, 7, BRASS, a)
		"claw":
			for m in [false, true]:
				var pts: Array = bez(Vector2(54, 42), Vector2(40, 32), Vector2(41, 14), Vector2(53, 8))
				pts.append(Vector2(56, 18))
				pts.append_array(bez(Vector2(56, 18), Vector2(50, 22), Vector2(50, 30), Vector2(57, 36)).slice(1))
				poly(ci, pts, STEEL, a, m)
				circ(ci, Vector2(55, 38), 1.6, OUT, a, m, 0)
		"nose":
			rect(ci, 56, 36, 8, 5, STEEL_D, a)
			circ(ci, Vector2(60, 28), 11, RED, a)
			line(ci, arc_pts(Vector2(60, 27), 8, 200, 270, 6), Color(1, 1, 1, 0.5), 2, a)
		"stamp":
			circ(ci, Vector2(60, 11), 6.5, BRASS, a)
			rect(ci, 56.5, 16, 7, 12, STEEL_D, a)
			rect(ci, 46, 27, 28, 12, STEEL, a)
			line(ci, [Vector2(50, 33), Vector2(70, 33)], STEEL_D, 1.5, a)
		"trex_head":
			var hd: Array = bez(Vector2(47, 41), Vector2(45, 28), Vector2(47, 14), Vector2(53, 6))
			hd.append(Vector2(67, 6))
			hd.append_array(bez(Vector2(67, 6), Vector2(73, 14), Vector2(75, 28), Vector2(73, 41)).slice(1))
			poly(ci, hd, STEEL, a)
			line(ci, [Vector2(50, 14), Vector2(52, 18)], OUT, 1.8, a)
			line(ci, [Vector2(50, 22), Vector2(53, 25)], OUT, 1.8, a)
			line(ci, [Vector2(70, 14), Vector2(68, 18)], OUT, 1.8, a)
			line(ci, [Vector2(70, 22), Vector2(67, 25)], OUT, 1.8, a)
			line(ci, qbez(Vector2(51, 31), Vector2(55, 27), Vector2(58, 31)), BRASS, 3, a)
			line(ci, qbez(Vector2(62, 31), Vector2(65, 27), Vector2(69, 31)), BRASS, 3, a)
			for e in [Vector2(54.5, 33), Vector2(65.5, 33)]:
				circ(ci, e, 2, OUT, a, false, 0)
			for e in [Vector2(57, 9.5), Vector2(63, 9.5)]:
				circ(ci, e, 1.3, OUT, a, false, 0)
		"sucker":
			rect(ci, 55, 18, 10, 24, STEEL, a)
			line(ci, [Vector2(60, 18), Vector2(60, 11)], OUT, 3, a)
			var cup: Array = qbez(Vector2(46, 12), Vector2(60, 1), Vector2(74, 12))
			cup.append_array(qbez(Vector2(74, 12), Vector2(60, 9), Vector2(46, 12)).slice(1))
			poly(ci, cup, RED, a)
			line(ci, [Vector2(57, 26), Vector2(63, 26)], STEEL_D, 1.5, a)
			line(ci, [Vector2(57, 32), Vector2(63, 32)], STEEL_D, 1.5, a)
		"umbrella_gun":
			poly(ci, [Vector2(60, 3), Vector2(66, 27), Vector2(54, 27)], Color("E1E6EB"), a)
			line(ci, [Vector2(58, 10), Vector2(57, 22)], Color.WHITE, 1.5, a)
			rect(ci, 50, 25, 20, 17, STEEL, a)
			line(ci, [Vector2(54, 30), Vector2(66, 30)], STEEL_D, 1.5, a)
			line(ci, [Vector2(54, 36), Vector2(66, 36)], STEEL_D, 1.5, a)
		"roller":
			var fr: Array = [[Vector2(60, 41), Vector2(60, 28)], [Vector2(45, 28), Vector2(75, 28)], [Vector2(45, 28), Vector2(45, 20)], [Vector2(75, 28), Vector2(75, 20)]]
			for seg in fr:
				line(ci, seg, OUT, 3, a)
			for seg in fr:
				line(ci, seg, STEEL, 1.2, a)
			rect(ci, 40, 8, 40, 13, Color("8FD0C8"), a)
			for xx in [46.0, 54.0, 62.0, 70.0]:
				line(ci, [Vector2(xx, 11), Vector2(xx, 18)], Color(1, 1, 1, 0.6), 1.5, a)
		"copier":
			rect(ci, 51, 5, 18, 11, WHITE, a)
			rect(ci, 43, 14, 34, 24, STEEL, a)
			line(ci, [Vector2(49, 19), Vector2(55, 25), Vector2(51, 29), Vector2(57, 34)], OUT, 1.8, a)
			rect(ci, 63, 20, 9, 5, STEEL_D, a, false, 0)
			circ(ci, Vector2(47, 34), 1.6, OUT, a, false, 0)
			circ(ci, Vector2(73, 34), 1.6, OUT, a, false, 0)


# ── 보조 (옆) ────────────────────────────────────────────

static func _aux(ci: CanvasItem, x: String, a: float, m: bool) -> void:
	if ArtData.SHAPES.has(x):
		draw_data(ci, x, a, m)
		return
	if ArtWs.SHAPES.has(x):
		draw_data(ci, x, a, m, Color.WHITE, ArtWs.SHAPES[x], "ws:" + x)
		return
	if _lab(ci, x, a, m) or _clock(ci, x, a, m) or _pirate(ci, x, a, m):
		return
	match x:
		"magnet":
			rect(ci, 82, 58, 14, 8, STEEL_D, a, m)
			poly(ci, [Vector2(96, 46), Vector2(112, 46), Vector2(112, 54), Vector2(104, 54), Vector2(104, 70), Vector2(112, 70), Vector2(112, 78), Vector2(96, 78)], STEEL, a, m)
			rect(ci, 104, 46, 8, 8, RED, a, m)
			rect(ci, 104, 70, 8, 8, WHITE, a, m)
		"bumper":
			line(ci, [Vector2(84, 50), Vector2(92, 54), Vector2(84, 58), Vector2(92, 62), Vector2(84, 66), Vector2(92, 70), Vector2(84, 74)], OUT, 2.5, a, m)
			rect(ci, 92, 42, 10, 40, STEEL, a, m)
			circ(ci, Vector2(97, 47), 1.6, OUT, a, m, 0)
			circ(ci, Vector2(97, 77), 1.6, OUT, a, m, 0)
		"flipper":
			poly(ci, [Vector2(82, 56), Vector2(98, 54), Vector2(113, 43), Vector2(108, 62), Vector2(115, 78), Vector2(98, 69), Vector2(82, 68)], BRASS, a, m)
			line(ci, [Vector2(98, 55), Vector2(98, 68)], OUT, 1.5, a, m)
			line(ci, [Vector2(106, 50), Vector2(103, 62), Vector2(108, 72)], OUT, 1.5, a, m)
		"decal":
			rect(ci, 82, 53, 30, 18, STEEL, a, m)
			line(ci, [Vector2(97, 53), Vector2(97, 71)], OUT, 1.5, a, m)
			poly(ci, [Vector2(86, 62), Vector2(93, 57), Vector2(93, 67)], OUT, a, m, 0)
			poly(ci, [Vector2(108, 62), Vector2(101, 57), Vector2(101, 67)], OUT, a, m, 0)
		"umbrella":
			poly(ci, [Vector2(91, 36), Vector2(99, 70), Vector2(91, 80), Vector2(83, 70)], Color("E1E6EB"), a, m)
			line(ci, [Vector2(89, 46), Vector2(92, 66)], Color.WHITE, 2, a, m)
			var h: Array = [Vector2(91, 80), Vector2(91, 88)]
			h.append_array(bez(Vector2(91, 88), Vector2(91, 93), Vector2(94, 95), Vector2(98, 92), 6))
			line(ci, h, OUT, 2.5, a, m)
		"spring":
			line(ci, [Vector2(83, 62), Vector2(87, 54), Vector2(91, 70), Vector2(95, 54), Vector2(99, 70), Vector2(102, 62)], OUT, 2.5, a, m)
			circ(ci, Vector2(110, 62), 8, BRASS, a, m)
		"carousel":
			var arc: Array = arc_pts(Vector2(98, 62), 22, 270, 360, 10)
			for i in range(0, arc.size() - 1, 2):
				line(ci, [arc[i], arc[i + 1]], OUT, 1.8, a, m)
			rect(ci, 86, 57, 28, 10, STEEL, a, m)
			circ(ci, Vector2(112, 62), 7, STEEL, a, m)
			circ(ci, Vector2(88, 62), 6, BRASS, a, m)
		"bubble":
			line(ci, [Vector2(83, 62), Vector2(98, 62)], OUT, 4, a, m)
			ring(ci, Vector2(105, 62), 7, OUT, 2.5, a, m)
			circ(ci, Vector2(112, 45), 6, Color(0.749, 0.890, 0.918, 0.8), a, m)
			circ(ci, Vector2(102, 38), 3.5, Color(0.749, 0.890, 0.918, 0.8), a, m)
		"trex_arm":
			var arm := [Vector2(83, 63), Vector2(98, 57), Vector2(104, 42)]
			line(ci, arm, OUT, 8, a, m)
			line(ci, arm, STEEL, 4, a, m)
			line(ci, [Vector2(104, 42), Vector2(99, 34)], OUT, 3, a, m)
			line(ci, [Vector2(104, 42), Vector2(110, 35)], OUT, 3, a, m)
			circ(ci, Vector2(98, 57), 3.2, BRASS, a, m, 1.5)
		"shield":
			poly(ci, [Vector2(84, 50), Vector2(96, 50), Vector2(84, 62)], BRASS, a, m, 0)
			poly(ci, [Vector2(108, 50), Vector2(108, 62), Vector2(96, 50)], BRASS, a, m, 0)
			poly(ci, [Vector2(96, 50), Vector2(108, 62), Vector2(96, 74), Vector2(84, 62)], STEEL, a, m, 0)
			poly(ci, [Vector2(84, 50), Vector2(108, 50), Vector2(108, 74), Vector2(84, 74)], Color(0, 0, 0, 0), a, m)
			line(ci, [Vector2(84, 50), Vector2(108, 74)], OUT, 1.5, a, m)
			line(ci, [Vector2(108, 50), Vector2(84, 74)], OUT, 1.5, a, m)
		"tambourine":
			rect(ci, 82, 59, 8, 6, STEEL_D, a, m)
			ring(ci, Vector2(102, 62), 12, OUT, 7, a, m)
			ring(ci, Vector2(102, 62), 12, BRASS, 3.5, a, m)
			for b in [Vector2(102, 50), Vector2(114, 62), Vector2(102, 74), Vector2(93.5, 53.5), Vector2(110.5, 70.5)]:
				circ(ci, b, 3.2, STEEL, a, m, 1.5)
		"track":
			rect(ci, 82, 59, 7, 6, STEEL_D, a, m)
			rect(ci, 89, 46, 15, 32, Color("3A4048"), a, m)
			for yy in [51.0, 57.0, 63.0, 69.0]:
				line(ci, [Vector2(91, yy), Vector2(102, yy + 3)], STEEL, 2, a, m)
		"mine":
			rect(ci, 82, 50, 22, 24, STEEL, a, m)
			rect(ci, 98, 56, 4, 12, OUT, a, m, 0)
			circ(ci, Vector2(112, 82), 7, STEEL_D, a, m)
			circ(ci, Vector2(112, 82), 2.5, RED, a, m, 0)
			circ(ci, Vector2(86, 54), 1.6, OUT, a, m, 0)
			circ(ci, Vector2(86, 70), 1.6, OUT, a, m, 0)


# ── 추진 (뒤) ────────────────────────────────────────────

static func _prop(ci: CanvasItem, p: String, a: float) -> void:
	if ArtData.SHAPES.has(p):
		draw_data(ci, p, a, false)
		return
	if ArtWs.SHAPES.has(p):
		draw_data(ci, p, a, false, Color.WHITE, ArtWs.SHAPES[p], "ws:" + p)
		return
	if _lab(ci, p, a, false) or _clock(ci, p, a, false) or _pirate(ci, p, a, false):
		return
	match p:
		"rocket":
			poly(ci, [Vector2(53, 92), Vector2(44, 104), Vector2(53, 104)], STEEL_D, a)
			poly(ci, [Vector2(67, 92), Vector2(76, 104), Vector2(67, 104)], STEEL_D, a)
			rect(ci, 53, 82, 14, 22, STEEL, a)
			poly(ci, [Vector2(54, 104), Vector2(66, 104), Vector2(70, 113), Vector2(50, 113)], BRASS, a)
		"retro":
			for xx in [30.0, 90.0]:
				line(ci, [Vector2(xx, 90), Vector2(xx, 64)], OUT, 9, a)
				line(ci, [Vector2(xx, 90), Vector2(xx, 64)], STEEL, 4.5, a)
			rect(ci, 28, 84, 64, 10, STEEL, a)
			poly(ci, [Vector2(25, 64), Vector2(35, 64), Vector2(33, 54), Vector2(27, 54)], BRASS, a)
			poly(ci, [Vector2(85, 64), Vector2(95, 64), Vector2(93, 54), Vector2(87, 54)], BRASS, a)
		"reel":
			dashed(ci, Vector2(60, 108), Vector2(60, 119), OUT, 1.8, 2.5, a)
			line(ci, [Vector2(60, 97), Vector2(77, 106)], OUT, 2.5, a)
			circ(ci, Vector2(79, 107), 4.5, BRASS, a)
			circ(ci, Vector2(60, 97), 11, STEEL, a)
			line(ci, [Vector2(60, 87), Vector2(60, 107)], STEEL_D, 1.8, a)
			line(ci, [Vector2(50, 97), Vector2(70, 97)], STEEL_D, 1.8, a)
			circ(ci, Vector2(60, 97), 3, OUT, a, false, 0)
		"trex_leg":
			for lg in [[Vector2(50, 82), Vector2(46, 100)], [Vector2(70, 82), Vector2(74, 100)]]:
				line(ci, lg, OUT, 9, a)
				line(ci, lg, STEEL, 5, a)
			for toe in [[Vector2(46, 100), Vector2(38, 110)], [Vector2(46, 100), Vector2(46, 113)], [Vector2(46, 100), Vector2(54, 110)],
					[Vector2(74, 100), Vector2(66, 110)], [Vector2(74, 100), Vector2(74, 113)], [Vector2(74, 100), Vector2(82, 110)]]:
				line(ci, toe, OUT, 3, a)
			circ(ci, Vector2(46, 100), 3, BRASS, a, false, 1.5)
			circ(ci, Vector2(74, 100), 3, BRASS, a, false, 1.5)
		"crab":
			line(ci, [Vector2(60, 84), Vector2(60, 96)], OUT, 3, a)
			line(ci, [Vector2(44, 96), Vector2(76, 96)], OUT, 3, a)
			rect(ci, 30, 90, 20, 12, Color("3A4048"), a)
			rect(ci, 70, 90, 20, 12, Color("3A4048"), a)
			for xx in [34.0, 40.0, 46.0, 74.0, 80.0, 86.0]:
				line(ci, [Vector2(xx, 93), Vector2(xx, 99)], STEEL, 1.5, a)
		"clockwork":
			rect(ci, 57, 84, 6, 12, STEEL_D, a)
			var key: Array = bez(Vector2(60, 96), Vector2(52, 92), Vector2(40, 96), Vector2(40, 105))
			key.append_array(bez(Vector2(40, 105), Vector2(40, 114), Vector2(52, 116), Vector2(60, 108)).slice(1))
			key.append_array(bez(Vector2(60, 108), Vector2(68, 116), Vector2(80, 114), Vector2(80, 105)).slice(1))
			key.append_array(bez(Vector2(80, 105), Vector2(80, 96), Vector2(68, 92), Vector2(60, 96)).slice(1))
			poly(ci, key, BRASS, a)
			circ(ci, Vector2(50, 105), 3.5, CORE, a, false, 0)
			circ(ci, Vector2(70, 105), 3.5, CORE, a, false, 0)
		"brake":
			rect(ci, 56, 84, 8, 9, STEEL_D, a)
			rect(ci, 45, 92, 30, 9, STEEL, a)
			rect(ci, 43, 100, 34, 8, RED, a)
			for xx in [49.0, 55.0, 61.0, 67.0, 73.0]:
				line(ci, [Vector2(xx, 102), Vector2(xx, 106)], OUT, 1.2, a)
		"chute":
			rect(ci, 45, 80, 30, 24, Color("7E8C64"), a)
			line(ci, [Vector2(47, 91), Vector2(73, 91)], OUT, 1.8, a)
			line(ci, [Vector2(75, 96), Vector2(80, 96)], OUT, 1.8, a)
			ring(ci, Vector2(84, 96), 4, BRASS, 2.5, a)


# ── 메카 티라노 (세 부품이 한 알에 모였을 때의 변신 외형) ──
## 장갑판은 주인 색, 강철 골격은 공통. 등판 장갑과 가시는 팔의 반대편(왼쪽)에만.

static func draw_mecha(ci: CanvasItem, col: Color, a: float, symbol: int) -> void:
	var dark := col.darkened(0.32)
	ci.draw_colored_polygon(_ellipse(Vector2(62, 68), 36, 54), Color(0, 0, 0, 0.28 * a))
	# 꼬리
	poly(ci, [Vector2(51, 82), Vector2(69, 82), Vector2(67, 94), Vector2(53, 94)], STEEL, a)
	poly(ci, [Vector2(53, 93), Vector2(67, 93), Vector2(65.5, 104), Vector2(54.5, 104)], STEEL, a)
	poly(ci, [Vector2(54.5, 103), Vector2(65.5, 103), Vector2(64, 113), Vector2(56, 113)], STEEL, a)
	poly(ci, [Vector2(58, 84), Vector2(62, 84), Vector2(62, 92), Vector2(58, 92)], col, a, false, 0)
	poly(ci, [Vector2(58.5, 95), Vector2(61.5, 95), Vector2(61.5, 102), Vector2(58.5, 102)], col, a, false, 0)
	poly(ci, [Vector2(56, 112), Vector2(64, 112), Vector2(60, 124)], BRASS, a)
	# 다리 두 개 (좌우 대칭)
	for m in [false, true]:
		line(ci, [Vector2(40, 98), Vector2(42, 108)], OUT, 6, a, m)
		line(ci, [Vector2(40, 98), Vector2(42, 108)], STEEL, 3, a, m)
		poly(ci, [Vector2(33, 106), Vector2(45, 106), Vector2(47, 112), Vector2(31, 112)], STEEL, a, m)
		for toe in [[Vector2(32, 112), Vector2(27, 120)], [Vector2(39, 112), Vector2(39, 122)], [Vector2(46, 112), Vector2(50, 120)]]:
			line(ci, toe, OUT, 3.2, a, m)
			line(ci, toe, BRASS, 1.4, a, m)
		poly(ci, [Vector2(45, 74), Vector2(33, 82), Vector2(35, 99), Vector2(47, 97), Vector2(51, 84)], col, a, m)
		poly(ci, [Vector2(45, 74), Vector2(51, 84), Vector2(47, 97), Vector2(42, 97.5), Vector2(45, 84)], dark, a, m, 0)
		line(ci, [Vector2(36, 84), Vector2(44, 79)], Color(1, 1, 1, 0.35), 1.5, a, m)
		circ(ci, Vector2(40, 90), 2.4, BRASS, a, m, 1.2)
	# 등판 장갑과 가시 (왼쪽)
	var plates := [
		[[Vector2(31, 45), Vector2(22, 42), Vector2(28.5, 51)], [Vector2(41, 41), Vector2(31, 45), Vector2(28, 56), Vector2(39, 55)], Vector2(35, 50)],
		[[Vector2(28, 57), Vector2(19, 58), Vector2(26.5, 64)], [Vector2(38, 54), Vector2(28, 56), Vector2(26, 68), Vector2(37, 67)], Vector2(32, 61)],
		[[Vector2(27, 70), Vector2(19, 75), Vector2(28, 76)], [Vector2(37, 66), Vector2(26.5, 69), Vector2(30, 81), Vector2(41, 77)], Vector2(33, 73)]]
	for pl in plates:
		poly(ci, pl[0], BRASS, a)
		poly(ci, pl[1], col, a)
		circ(ci, pl[2], 1.4, OUT, a, false, 0)
	line(ci, [Vector2(31, 46), Vector2(40, 42)], Color(1, 1, 1, 0.4), 1.4, a)
	line(ci, [Vector2(28.5, 57), Vector2(37.5, 55)], Color(1, 1, 1, 0.4), 1.4, a)
	line(ci, [Vector2(27, 70), Vector2(36.5, 67)], Color(1, 1, 1, 0.4), 1.4, a)
	# 팔 (오른쪽): 유압 실린더와 세 발톱
	var arm := [Vector2(88, 56), Vector2(101, 52), Vector2(106, 39)]
	line(ci, arm, OUT, 8, a)
	line(ci, arm, STEEL, 4.2, a)
	line(ci, [Vector2(86, 61), Vector2(100, 56)], OUT, 3.6, a)
	line(ci, [Vector2(86, 61), Vector2(100, 56)], STEEL_D, 1.6, a)
	for cl in [qbez(Vector2(106, 39), Vector2(99, 32), Vector2(101, 25)), qbez(Vector2(106, 39), Vector2(113, 32), Vector2(111, 25)), qbez(Vector2(106, 39), Vector2(104, 34), Vector2(100, 33))]:
		line(ci, cl, OUT, 3.6, a)
		line(ci, cl, BRASS, 1.5, a)
	circ(ci, Vector2(101, 52), 3, BRASS, a, false, 1.4)
	poly(ci, [Vector2(79, 49), Vector2(92, 46), Vector2(96, 57), Vector2(84, 63)], col, a)
	poly(ci, [Vector2(84, 63), Vector2(96, 57), Vector2(94.5, 53), Vector2(83, 58)], dark, a, false, 0)
	line(ci, [Vector2(81, 50), Vector2(91, 47.5)], Color(1, 1, 1, 0.4), 1.4, a)
	# 목
	var neck: Array = qbez(Vector2(48, 42), Vector2(60, 36), Vector2(72, 42))
	neck.append(Vector2(70, 46))
	neck.append_array(qbez(Vector2(70, 46), Vector2(60, 41), Vector2(50, 46)).slice(1))
	poly(ci, neck, STEEL_D, a)
	# 머리: 이빨 줄, 볏, 바이저
	var hd: Array = bez(Vector2(45.5, 40), Vector2(42.5, 30), Vector2(44.5, 16), Vector2(51, 7))
	hd.append_array(qbez(Vector2(51, 7), Vector2(60, 1), Vector2(69, 7)).slice(1))
	hd.append_array(bez(Vector2(69, 7), Vector2(75.5, 16), Vector2(77.5, 30), Vector2(74.5, 40)).slice(1))
	hd.append_array(qbez(Vector2(74.5, 40), Vector2(60, 45), Vector2(45.5, 40)).slice(1))
	poly(ci, hd, STEEL, a)
	for yy in [13.0, 19.0, 25.0, 31.0]:
		var xo := 48.2 if yy == 13.0 else 46.6
		var xt := 45.0 if yy == 13.0 else 43.0
		poly(ci, [Vector2(xo, yy), Vector2(xt, yy + 2.2), Vector2(xo, yy + 4.2)], WHITE, a, false, 1)
		poly(ci, [Vector2(120 - xo, yy), Vector2(120 - xt, yy + 2.2), Vector2(120 - xo, yy + 4.2)], WHITE, a, false, 1)
	var crest: Array = qbez(Vector2(57, 6), Vector2(60, 4.5), Vector2(63, 6))
	crest.append(Vector2(62.2, 28))
	crest.append(Vector2(57.8, 28))
	poly(ci, crest, col, a, false, 1.5)
	poly(ci, [Vector2(48.5, 29), Vector2(56.5, 25.5), Vector2(57.5, 31), Vector2(49.5, 34)], Color("3A4048"), a, false, 1.5)
	poly(ci, [Vector2(71.5, 29), Vector2(63.5, 25.5), Vector2(62.5, 31), Vector2(70.5, 34)], Color("3A4048"), a, false, 1.5)
	line(ci, [Vector2(51, 35.5), Vector2(69, 35.5)], Color(1.0, 0.42, 0.29, 0.35), 5, a)
	line(ci, [Vector2(51, 35.5), Vector2(69, 35.5)], Color("FF6B4A"), 2.2, a)
	line(ci, [Vector2(55, 35.5), Vector2(57, 35.5)], Color("FFE3D6"), 2.2, a)
	line(ci, [Vector2(56, 11), Vector2(57, 15)], OUT, 1.5, a)
	line(ci, [Vector2(64, 11), Vector2(63, 15)], OUT, 1.5, a)
	line(ci, qbez(Vector2(49, 16), Vector2(51, 10), Vector2(56, 7)), Color(1, 1, 1, 0.5), 1.5, a)
	# 몸통 퍽
	circ(ci, C0, 24, col, a)
	var q: Array = [C0]
	q.append_array(arc_pts(C0, 24, 0, 90, 10))
	poly(ci, q, Color(dark, 0.6), a, false, 0)
	line(ci, arc_pts(Vector2(60, 60.6), 22, 197, 343), Color(1, 1, 1, 0.38), 2.0, a)
	for rv in [[Vector2(71, 73), Vector2(76.6, 78.6)], [Vector2(49, 73), Vector2(43.4, 78.6)], [Vector2(49, 51), Vector2(43.4, 45.4)], [Vector2(71, 51), Vector2(76.6, 45.4)]]:
		line(ci, rv, OUT, 1.3, a)
	circ(ci, C0, 15, CORE, a)
	ring(ci, C0, 12, Color(1.0, 0.42, 0.29, 0.55), 1.4, a)
	if symbol >= 0:
		draw_symbol(ci, symbol, col, a, T(C0), 0.55 * K, true)


static func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		out.append(T(c + Vector2(cos(t) * rx, sin(t) * ry)))
	return out


# ── 도형 데이터 (art_data.gd) ────────────────────────────

static func _shape_color(tok: String, col: Color) -> Color:
	if tok == "P":
		return col
	if tok == "PL":
		return col.lightened(0.18)
	return Color(tok)


## 강화 외형: 충격 판(첫 도형, 퍽 중심의 큰 별 모양)은 _up_plate 가 먼저 그린다.
static func _up(ci: CanvasItem, id: String, a: float, mirror: bool, on: bool) -> bool:
	if on and ArtWs.UP.has(id):
		draw_data(ci, id, a, mirror, Color.WHITE, ArtWs.UP[id], "wsup:" + id)
		return true
	if not on or not ArtUp.SHAPES.has(id):
		return false
	draw_data(ci, id, a, mirror, Color.WHITE, ArtUp.SHAPES[id], "up:" + id, 1 if _has_plate(id) else 0)
	return true


static func _has_plate(id: String) -> bool:
	var sh: Array = ArtUp.SHAPES[id]
	return not sh.is_empty() and sh[0][1] == "#FFF3C4" and (sh[0][5] as Array).size() >= 40


static func _up_plate(ci: CanvasItem, id: String, a: float) -> void:
	if not _has_plate(id):
		return
	var sh: Array = ArtUp.SHAPES[id][0]
	var flat: Array = sh[5]
	var pts := PackedVector2Array()
	for k in range(0, flat.size(), 2):
		pts.append(T(Vector2(flat[k], flat[k + 1])))
	ci.draw_colored_polygon(pts, _al(Color("FFF3C4"), a))
	pts.append(pts[0])
	ci.draw_polyline(pts, _al(Color("111111"), a), 2.0 * K, true)


static func draw_data(ci: CanvasItem, id: String, a: float, mirror: bool, col := Color.WHITE, shapes_in = null, key_id := "", from := 0) -> void:
	var shapes: Array = ArtData.SHAPES[id] if shapes_in == null else shapes_in
	if key_id == "":
		key_id = id
	for i in range(from, shapes.size()):
		var sh: Array = shapes[i]
		var flat: Array = sh[5]
		var pts := PackedVector2Array()
		for k in range(0, flat.size(), 2):
			pts.append(T(Vector2(flat[k], flat[k + 1]), mirror))
		var c := _al(_shape_color(sh[1], col), a * sh[2])
		if sh[0] == "f":
			var key := "%s:%d" % [key_id, i]
			if not _poly_ok.has(key):
				_poly_ok[key] = not Geometry2D.triangulate_polygon(pts).is_empty()
			if _poly_ok[key]:
				ci.draw_colored_polygon(pts, c)
			else:
				# 자기 교차 도형: 볼록 껍질로 대신 칠한다
				var hull := Geometry2D.convex_hull(pts)
				if hull.size() >= 3:
					ci.draw_colored_polygon(hull, c)
		else:
			if sh[4]:
				pts.append(pts[0])
			ci.draw_polyline(pts, c, maxf(0.6, sh[3] * K), true)


## 달그림자 마도사·최후의 주인공 변신 외형 (퍽까지 한 몸으로 그린다).
static func draw_set_form(ci: CanvasItem, id: String, col: Color, a: float, symbol: int) -> void:
	draw_data(ci, id, a, false, col)
	if symbol >= 0 and ArtData.SYMBOLS.has(id):
		var sy: Array = ArtData.SYMBOLS[id]
		draw_symbol(ci, symbol, col.lightened(0.18), a, T(Vector2(sy[0], sy[1])), sy[2] * K, true)


## 판 위 정면 표시: 자리마다 고른 형태에 맞게 (홈 · 점 · 은색 톱니 · 실 땀)
static func draw_front_mark(ci: CanvasItem, c: Vector2, u: float, front: float, a: float, slot: int, col: Color) -> void:
	var form := "metal"
	if slot >= 0 and slot < 8 and skin == "":
		form = str(slot_forms[slot])
	var fd := Vector2.from_angle(front)
	match form:
		"glass", "marble":
			ci.draw_circle(c + fd * 0.8 * u, 0.09 * u, _al(col.darkened(0.6), a))
		"cap":
			ci.draw_colored_polygon(PackedVector2Array([c + fd * 1.1 * u + fd.orthogonal() * 0.13 * u, c + fd * 1.1 * u - fd.orthogonal() * 0.13 * u, c + fd * 0.86 * u]), _al(Color("E9ECEF"), a))
		"button":
			ci.draw_line(c + fd * 0.62 * u, c + fd * 0.92 * u, _al(Color("F4EBD8"), a), 0.09 * u, true)
		"coin":
			ci.draw_colored_polygon(PackedVector2Array([c + fd * 0.8 * u + fd.orthogonal() * 0.12 * u, c + fd * 0.8 * u - fd.orthogonal() * 0.12 * u, c + fd * 0.66 * u]), _al(Color("8C6A2E"), a))
		_:
			draw_notch(ci, c, u, front, a)


static func draw_notch(ci: CanvasItem, c: Vector2, u: float, front: float, a := 1.0) -> void:
	var fd := Vector2.from_angle(front)
	var fp := fd.orthogonal()
	ci.draw_colored_polygon(PackedVector2Array([c + fd * u + fp * 0.2 * u, c + fd * u - fp * 0.2 * u, c + fd * 0.7 * u]), _al(outline, a))



# ── 엉뚱한 발명 연구소 부품 ─────────────────────────────
const LIME := Color("B6F23C")
const GLASS := Color("CFF3FF")


static func _lab(ci: CanvasItem, id: String, a: float, m: bool) -> bool:
	match id:
		"shrink_ray":
			rect(ci, 55, 18, 10, 24, STEEL, a)
			poly(ci, [Vector2(48, 18), Vector2(72, 18), Vector2(66, 8), Vector2(54, 8)], LIME, a)
			circ(ci, Vector2(60, 13), 3, Color.WHITE, a, false, 1.0)
		"remote":
			rect(ci, 52, 10, 16, 30, Color("2A2E35"), a)
			circ(ci, Vector2(60, 18), 3.5, RED, a, false, 1.0)
			rect(ci, 55, 26, 4, 4, LIME, a, false, 1.0)
			rect(ci, 61, 26, 4, 4, LIME, a, false, 1.0)
			line(ci, [Vector2(60, 10), Vector2(60, 3)], OUT, 2.0, a)
		"sticky":
			rect(ci, 54, 16, 12, 26, STEEL, a)
			circ(ci, Vector2(60, 12), 7, LIME, a)
			line(ci, [Vector2(56, 18), Vector2(55, 23)], Color("7FB81E"), 2.0, a)
		"tilter":
			rect(ci, 50, 30, 20, 12, STEEL_D, a)
			poly(ci, [Vector2(46, 26), Vector2(74, 16), Vector2(74, 22), Vector2(46, 32)], LIME, a)
			circ(ci, Vector2(60, 26), 3, BRASS, a, false, 1.0)
		"merge_bolt":
			rect(ci, 82, 56, 12, 12, STEEL_D, a, m)
			poly(ci, [Vector2(94, 50), Vector2(110, 50), Vector2(110, 74), Vector2(94, 74)], STEEL, a, m)
			line(ci, [Vector2(98, 56), Vector2(106, 62), Vector2(98, 68)], LIME, 3.0, a, m)
		"decoy":
			line(ci, [Vector2(84, 62), Vector2(96, 58)], OUT, 1.5, a, m)
			circ(ci, Vector2(104, 54), 10, Color("FF8FB1"), a, m)
			circ(ci, Vector2(100, 50), 2.5, Color.WHITE, a, m, 0.0)
		"coupling":
			circ(ci, Vector2(96, 62), 9, RED, a, m)
			circ(ci, Vector2(96, 62), 4, CORE, a, m, 0.0)
			dashed(ci, Vector2(105, 62), Vector2(116, 62), LIME, 2.0, 3.0, a, m)
		"repel":
			poly(ci, [Vector2(84, 46), Vector2(94, 42), Vector2(94, 82), Vector2(84, 78)], LIME, a, m)
			line(ci, [Vector2(98, 50), Vector2(104, 46)], LIME, 2.0, a, m)
			line(ci, [Vector2(98, 62), Vector2(106, 62)], LIME, 2.0, a, m)
			line(ci, [Vector2(98, 74), Vector2(104, 78)], LIME, 2.0, a, m)
		"split_capsule":
			poly(ci, [Vector2(50, 86), Vector2(70, 86), Vector2(70, 104), Vector2(50, 104)], GLASS, a)
			line(ci, [Vector2(60, 86), Vector2(57, 95), Vector2(63, 98), Vector2(60, 104)], OUT, 1.5, a)
			circ(ci, Vector2(55, 99), 2.5, LIME, a, false, 0.0)
			circ(ci, Vector2(65, 92), 2.5, LIME, a, false, 0.0)
		"weight":
			poly(ci, [Vector2(48, 106), Vector2(72, 106), Vector2(68, 86), Vector2(52, 86)], Color("4A4F57"), a)
			rect(ci, 56, 82, 8, 5, STEEL_D, a, false, 1.5)
			line(ci, [Vector2(55, 98), Vector2(65, 98)], STEEL, 2.0, a)
		"ghost":
			poly(ci, [Vector2(48, 108), Vector2(48, 92), Vector2(54, 85), Vector2(66, 85), Vector2(72, 92), Vector2(72, 108), Vector2(66, 103), Vector2(60, 108), Vector2(54, 103)], Color(1, 1, 1, 0.75), a, false, 1.5)
			circ(ci, Vector2(56, 94), 1.8, OUT, a, false, 0.0)
			circ(ci, Vector2(64, 94), 1.8, OUT, a, false, 0.0)
		"inflate":
			circ(ci, Vector2(60, 98), 11, Color("FFB347"), a)
			line(ci, [Vector2(60, 86), Vector2(60, 82)], OUT, 2.0, a)
			line(ci, [Vector2(54, 93), Vector2(57, 91)], Color.WHITE, 2.0, a)
		_:
			return false
	return true


# ── 태엽 시계탑 부품 ─────────────────────────────────────
const NAVY := Color("26305A")
const CREAM := Color("F3EAD3")


static func _spiral(ci: CanvasItem, c: Vector2, r: float, turns: float, col: Color, w: float, a: float, m := false) -> void:
	var pts: Array = []
	var n := int(24 * turns)
	for i in n + 1:
		var t := float(i) / n
		pts.append(c + Vector2.from_angle(t * TAU * turns) * r * (0.15 + 0.85 * t))
	line(ci, pts, col, w, a, m)


static func _clock(ci: CanvasItem, id: String, a: float, m: bool) -> bool:
	match id:
		# 무기 (위)
		"hour_hammer":
			rect(ci, 57, 16, 6, 24, BRASS, a)
			rect(ci, 46, 8, 28, 11, STEEL_D, a)
			poly(ci, [Vector2(60, 2), Vector2(64, 9), Vector2(56, 9)], NAVY, a, false, 1.2)
		"time_spring":
			rect(ci, 57, 26, 6, 14, STEEL_D, a)
			circ(ci, Vector2(60, 20), 10, BRASS, a)
			_spiral(ci, Vector2(60, 20), 8, 2.5, OUT, 1.4, a)
			rect(ci, 44, 17, 6, 6, BRASS, a, false, 1.2)
			rect(ci, 70, 17, 6, 6, BRASS, a, false, 1.2)
		"reserve_bow":
			rect(ci, 57, 10, 6, 30, Color("8A6237"), a)
			line(ci, [Vector2(42, 22), Vector2(50, 14), Vector2(60, 12), Vector2(70, 14), Vector2(78, 22)], STEEL_D, 3.0, a)
			line(ci, [Vector2(42, 22), Vector2(60, 28), Vector2(78, 22)], OUT, 1.0, a)
			poly(ci, [Vector2(60, 3), Vector2(63, 9), Vector2(57, 9)], STEEL, a, false, 1.2)
		"rewind_watch":
			rect(ci, 57, 28, 6, 12, BRASS, a)
			circ(ci, Vector2(60, 20), 11, CREAM, a)
			ring(ci, Vector2(60, 20), 11, BRASS, 2.5, a)
			line(ci, [Vector2(60, 20), Vector2(60, 13)], OUT, 1.6, a)
			line(ci, [Vector2(60, 20), Vector2(55, 23)], OUT, 1.6, a)
			line(ci, [Vector2(66, 12), Vector2(70, 16), Vector2(66, 17)], RED, 1.6, a)
		"slow_arrow":
			rect(ci, 58.5, 8, 3, 32, Color("8A6237"), a, false, 1.0)
			poly(ci, [Vector2(60, 0), Vector2(65, 9), Vector2(55, 9)], STEEL, a, false, 1.2)
			poly(ci, [Vector2(60, 34), Vector2(66, 40), Vector2(54, 40)], CREAM, a, false, 1.0)
			circ(ci, Vector2(68, 24), 4, CREAM, a, false, 1.0)
		"order_swap":
			rect(ci, 57, 30, 6, 10, STEEL_D, a)
			rect(ci, 46, 12, 28, 18, NAVY, a)
			line(ci, [Vector2(50, 18), Vector2(68, 18)], BRASS, 2.0, a)
			poly(ci, [Vector2(70, 18), Vector2(65, 15), Vector2(65, 21)], BRASS, a, false, 0)
			line(ci, [Vector2(70, 25), Vector2(52, 25)], BRASS, 2.0, a)
			poly(ci, [Vector2(50, 25), Vector2(55, 22), Vector2(55, 28)], BRASS, a, false, 0)
		# 보조 (옆)
		"late_key":
			rect(ci, 82, 59, 16, 6, BRASS, a, m)
			circ(ci, Vector2(103, 62), 7, BRASS, a, m)
			circ(ci, Vector2(103, 62), 3, NAVY, a, m, 1.0)
			rect(ci, 86, 65, 3, 5, BRASS, a, m, 1.0)
		"hourglass":
			rect(ci, 82, 59, 8, 6, STEEL_D, a, m)
			rect(ci, 90, 46, 18, 3, Color("8A6237"), a, m)
			rect(ci, 90, 75, 18, 3, Color("8A6237"), a, m)
			poly(ci, [Vector2(92, 49), Vector2(106, 49), Vector2(99, 62), Vector2(106, 75), Vector2(92, 75), Vector2(99, 62)], Color(0.85, 0.92, 1.0, 0.8), a, m, 1.2)
			poly(ci, [Vector2(94, 74), Vector2(104, 74), Vector2(99, 66)], Color("E2C27A"), a, m, 0)
		"metronome":
			rect(ci, 82, 59, 8, 6, STEEL_D, a, m)
			poly(ci, [Vector2(92, 76), Vector2(110, 76), Vector2(104, 46), Vector2(98, 46)], Color("8A6237"), a, m)
			line(ci, [Vector2(101, 72), Vector2(106, 50)], OUT, 1.6, a, m)
			circ(ci, Vector2(105, 55), 2.5, BRASS, a, m, 1.0)
		"alarm_clock":
			rect(ci, 82, 59, 8, 6, STEEL_D, a, m)
			circ(ci, Vector2(100, 63), 10, RED, a, m)
			circ(ci, Vector2(100, 63), 7, CREAM, a, m, 1.0)
			circ(ci, Vector2(94, 52), 4, BRASS, a, m, 1.2)
			circ(ci, Vector2(106, 52), 4, BRASS, a, m, 1.2)
			line(ci, [Vector2(100, 63), Vector2(100, 58)], OUT, 1.4, a, m)
		"wind_mouse":
			rect(ci, 82, 59, 6, 6, STEEL_D, a, m)
			poly(ci, [Vector2(88, 66), Vector2(96, 54), Vector2(108, 58), Vector2(112, 66), Vector2(104, 72), Vector2(92, 72)], Color("A7ADB4"), a, m)
			circ(ci, Vector2(100, 54), 4, Color("E7B7B0"), a, m, 1.2)
			circ(ci, Vector2(108, 63), 1.4, OUT, a, m, 0)
			line(ci, [Vector2(96, 72), Vector2(94, 78), Vector2(100, 78)], BRASS, 2.0, a, m)
		"shock_spring":
			rect(ci, 82, 58, 6, 8, STEEL_D, a, m)
			line(ci, [Vector2(88, 62), Vector2(92, 52), Vector2(96, 72), Vector2(100, 52), Vector2(104, 72), Vector2(108, 52), Vector2(110, 62)], BRASS, 3.0, a, m)
			rect(ci, 109, 52, 5, 20, STEEL, a, m)
		# 추진 (뒤)
		"minute_spring":
			rect(ci, 56, 84, 8, 6, STEEL_D, a)
			circ(ci, Vector2(60, 100), 12, BRASS, a)
			_spiral(ci, Vector2(60, 100), 10, 3.0, OUT, 1.4, a)
			line(ci, [Vector2(60, 100), Vector2(68, 94)], NAVY, 2.0, a)
		"slow_spring":
			rect(ci, 56, 84, 8, 6, STEEL_D, a)
			circ(ci, Vector2(60, 101), 12, Color("C08A4E"), a)
			_spiral(ci, Vector2(60, 101), 10, 2.2, Color("6B4523"), 2.0, a)
		"replay_spring":
			rect(ci, 56, 84, 8, 6, STEEL_D, a)
			circ(ci, Vector2(60, 101), 12, Color("2A2E35"), a)
			for k in 5:
				circ(ci, Vector2(60, 101) + Vector2.from_angle(TAU * k / 5.0) * 7.0, 2.2, CREAM, a, false, 0)
			circ(ci, Vector2(60, 101), 2.5, BRASS, a, false, 0)
		"time_capsule":
			rect(ci, 56, 84, 8, 6, STEEL_D, a)
			rect(ci, 52, 90, 16, 22, Color("9FC4E8"), a)
			rect(ci, 52, 90, 16, 9, Color("E2C27A"), a)
			circ(ci, Vector2(60, 106), 2.5, NAVY, a, false, 0)
		"tick_step":
			rect(ci, 56, 84, 8, 6, STEEL_D, a)
			for k in 3:
				poly(ci, [Vector2(48 + k * 9, 92), Vector2(55 + k * 9, 92), Vector2(56 + k * 9, 106), Vector2(47 + k * 9, 106)], BRASS if k == 1 else STEEL, a, false, 1.2)
		_:
			return false
	return true


# ── 해적 선착장 부품 ─────────────────────────────────────
const WOOD := Color("9A6A3A")
const WOOD_D := Color("6B4523")
const ROPE := Color("D8C08A")
const SEA := Color("3E8FB0")


static func _pirate(ci: CanvasItem, id: String, a: float, m: bool) -> bool:
	match id:
		# 무기 (위)
		"parrot_hat":
			poly(ci, [Vector2(42, 30), Vector2(78, 30), Vector2(70, 18), Vector2(60, 22), Vector2(50, 18)], Color("1E2228"), a)
			circ(ci, Vector2(60, 26), 2.5, WHITE, a, false, 0)
			poly(ci, [Vector2(62, 18), Vector2(70, 8), Vector2(74, 12), Vector2(68, 20)], Color("2FA35A"), a, false, 1.2)
			circ(ci, Vector2(71, 9), 3.5, Color("E0533D"), a, false, 1.2)
			poly(ci, [Vector2(74, 9), Vector2(78, 11), Vector2(74, 12)], Color("F2C14E"), a, false, 0)
		"hole_cannon":
			rect(ci, 53, 10, 14, 30, Color("2A2E35"), a)
			rect(ci, 51, 8, 18, 5, STEEL_D, a)
			circ(ci, Vector2(60, 34), 6, WOOD, a)
		"spyglass":
			poly(ci, [Vector2(55, 40), Vector2(65, 40), Vector2(66, 24), Vector2(54, 24)], BRASS, a)
			rect(ci, 56, 10, 8, 15, Color("C9A15A"), a)
			circ(ci, Vector2(60, 9), 4, Color("9FD3F0"), a, false, 1.2)
		"bolas":
			rect(ci, 57, 28, 6, 12, WOOD_D, a)
			line(ci, [Vector2(60, 28), Vector2(48, 14)], STEEL_D, 2.0, a)
			line(ci, [Vector2(60, 28), Vector2(72, 14)], STEEL_D, 2.0, a)
			circ(ci, Vector2(47, 12), 5, Color("5A6068"), a)
			circ(ci, Vector2(73, 12), 5, Color("5A6068"), a)
		"smoke_powder":
			rect(ci, 55, 26, 10, 14, Color("2A2E35"), a)
			circ(ci, Vector2(60, 18), 8, Color("C9CED6"), a, false, 1.2)
			circ(ci, Vector2(52, 12), 6, Color("DDE1E6"), a, false, 1.2)
			circ(ci, Vector2(68, 11), 6, Color("DDE1E6"), a, false, 1.2)
		"flag_signal":
			rect(ci, 58.5, 6, 3, 34, WOOD_D, a, false, 1.0)
			poly(ci, [Vector2(61, 7), Vector2(76, 11), Vector2(61, 17)], RED, a, false, 1.2)
			poly(ci, [Vector2(61, 18), Vector2(72, 21), Vector2(61, 25)], Color("F2C14E"), a, false, 1.0)
		# 보조 (옆)
		"hook_hand":
			rect(ci, 82, 58, 10, 8, WOOD_D, a, m)
			line(ci, [Vector2(92, 62), Vector2(104, 62), Vector2(110, 56), Vector2(108, 48), Vector2(102, 46)], STEEL, 3.5, a, m)
		"rum_barrel":
			rect(ci, 82, 59, 6, 6, STEEL_D, a, m)
			rect(ci, 88, 50, 22, 24, WOOD, a, m)
			rect(ci, 88, 55, 22, 3, Color("3A3F45"), a, m, 0)
			rect(ci, 88, 66, 22, 3, Color("3A3F45"), a, m, 0)
		"water_pump":
			rect(ci, 82, 58, 10, 8, STEEL_D, a, m)
			rect(ci, 92, 52, 12, 20, SEA, a, m)
			rect(ci, 104, 58, 8, 8, STEEL, a, m)
			line(ci, [Vector2(96, 52), Vector2(96, 46), Vector2(102, 46)], STEEL_D, 2.0, a, m)
		"plank_dock":
			rect(ci, 82, 58, 6, 8, STEEL_D, a, m)
			rect(ci, 88, 54, 24, 16, WOOD, a, m)
			line(ci, [Vector2(88, 59), Vector2(112, 59)], WOOD_D, 1.2, a, m)
			line(ci, [Vector2(88, 65), Vector2(112, 65)], WOOD_D, 1.2, a, m)
			circ(ci, Vector2(92, 56.5), 1.2, OUT, a, m, 0)
		"treasure_chest":
			rect(ci, 82, 59, 6, 6, STEEL_D, a, m)
			rect(ci, 88, 56, 22, 16, WOOD, a, m)
			poly(ci, [Vector2(88, 56), Vector2(110, 56), Vector2(106, 48), Vector2(92, 48)], WOOD_D, a, m)
			rect(ci, 97, 58, 4, 5, Color("F2C14E"), a, m, 1.0)
		"jump_board":
			rect(ci, 82, 59, 6, 6, STEEL_D, a, m)
			poly(ci, [Vector2(88, 74), Vector2(112, 74), Vector2(112, 52)], WOOD, a, m)
			line(ci, [Vector2(94, 70), Vector2(108, 58)], WOOD_D, 1.2, a, m)
		# 추진 (뒤)
		"wind_sail":
			rect(ci, 58.5, 84, 3, 28, WOOD_D, a, false, 1.0)
			poly(ci, [Vector2(62, 88), Vector2(78, 98), Vector2(62, 108)], Color("F3EAD3"), a, false, 1.4)
			poly(ci, [Vector2(58, 90), Vector2(46, 100), Vector2(58, 106)], Color("F3EAD3"), a, false, 1.4)
		"lifeboat":
			rect(ci, 56, 84, 8, 5, STEEL_D, a)
			poly(ci, [Vector2(44, 92), Vector2(76, 92), Vector2(70, 108), Vector2(50, 108)], Color("E06A3C"), a)
			ring(ci, Vector2(60, 100), 5, WHITE, 2.5, a)
		"oar":
			rect(ci, 56, 84, 8, 5, STEEL_D, a)
			line(ci, [Vector2(52, 88), Vector2(70, 110)], WOOD_D, 3.0, a)
			poly(ci, [Vector2(66, 104), Vector2(74, 106), Vector2(76, 116), Vector2(70, 114)], WOOD, a, false, 1.2)
		"helm":
			rect(ci, 56, 84, 8, 5, STEEL_D, a)
			ring(ci, Vector2(60, 100), 9, WOOD, 3.0, a)
			for k in 6:
				var d := Vector2.from_angle(TAU * k / 6.0)
				line(ci, [Vector2(60, 100) + d * 3.0, Vector2(60, 100) + d * 13.0], WOOD_D, 2.0, a)
			circ(ci, Vector2(60, 100), 3, BRASS, a, false, 1.0)
		"peg_leg":
			rect(ci, 56, 84, 8, 6, STEEL_D, a)
			poly(ci, [Vector2(56, 90), Vector2(64, 90), Vector2(62, 112), Vector2(58, 112)], WOOD, a)
			rect(ci, 55, 110, 10, 3, Color("3A3F45"), a, false, 1.0)
		_:
			return false
	return true



## 공방 스킨: 주인 색 면적 · 기호 · 정면 표시는 그대로 두고 재질만 얹는다.
static func _skin_overlay(ci: CanvasItem, c: Vector2, u: float, col: Color, a: float, rot: float, front: float) -> void:
	match skin:
		"museum":
			# 금 액자 테를 두른 대리석
			ci.draw_arc(c, 1.02 * u, 0, TAU, 40, _al(Color("B8902F"), a), 0.16 * u, true)
			ci.draw_arc(c, 0.92 * u, 0, TAU, 40, _al(Color("F2D88A"), a), 0.03 * u, true)
			for i in 16:
				ci.draw_circle(c + Vector2.from_angle(TAU * i / 16.0 - rot) * 1.02 * u, 0.035 * u, _al(Color("E8C766"), a))
			for v in [[Vector2(-0.5, -0.2), Vector2(0.1, 0.3)], [Vector2(0.2, -0.55), Vector2(0.45, 0.1)]]:
				ci.draw_line(c + (v[0] as Vector2).rotated(-rot) * u, c + (v[1] as Vector2).rotated(-rot) * u, Color(0.73, 0.69, 0.64, 0.5 * a), 0.03 * u, true)
		"junk":
			# 육각 너트 각인과 리벳 네 개
			var hx := PackedVector2Array()
			for i in 7:
				hx.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0 - rot) * 0.66 * u)
			ci.draw_polyline(hx, Color(0, 0, 0, 0.32 * a), 0.07 * u, true)
			for i in 4:
				var rp := c + Vector2.from_angle(PI / 4.0 + PI / 2.0 * i - rot) * 0.8 * u
				ci.draw_circle(rp, 0.07 * u, _al(Color("C3C9D0"), a))
				ci.draw_arc(rp, 0.07 * u, 0, TAU, 8, Color(0, 0, 0, 0.5 * a), 0.025 * u, true)
		"magic":
			# 달빛이 도는 마법석, 둘레에 별 룬
			ci.draw_circle(c, 0.55 * u, Color(1, 1, 1, 0.12 * a))
			for i in 10:
				var sp := c + Vector2.from_angle(TAU * i / 10.0 - rot) * 1.12 * u
				ci.draw_circle(sp, 0.045 * u, Color(0.92, 0.9, 1.0, 0.8 * a))
		"toon":
			# 굵은 먹선과 망점 그림자
			ci.draw_arc(c, u, 0, TAU, 40, _al(Color("111111"), a), 0.2 * u, true)
			for yy in range(1, 5):
				for xx in range(1, 5):
					var dp := c + Vector2(0.18 * u * xx, 0.18 * u * yy).rotated(-rot)
					if dp.distance_to(c) < 0.85 * u:
						ci.draw_circle(dp, 0.04 * u, Color(0, 0, 0, 0.25 * a))
			ci.draw_line(c + Vector2(-0.62 * u, -0.25 * u).rotated(-rot), c + Vector2(-0.3 * u, -0.62 * u).rotated(-rot), Color(1, 1, 1, 0.85 * a), 0.1 * u, true)
		"lab":
			# 배양 접시 속 형광 물감과 기포
			ci.draw_arc(c, 1.06 * u, 0, TAU, 40, Color(0.9, 0.97, 0.97, 0.9 * a), 0.14 * u, true)
			ci.draw_arc(c, 1.13 * u, 0, TAU, 40, Color(0.4, 0.5, 0.5, 0.6 * a), 0.03 * u, true)
			for bp in [Vector2(0.45, 0.35), Vector2(0.55, -0.1), Vector2(-0.5, 0.45)]:
				ci.draw_arc(c + (bp as Vector2).rotated(-rot) * u, 0.07 * u, 0, TAU, 10, Color(1, 1, 1, 0.8 * a), 0.025 * u, true)
		"clock":
			# 황동 테 문자판, 꼭지가 정면
			ci.draw_arc(c, 0.97 * u, 0, TAU, 40, _al(Color("C9A15A"), a), 0.12 * u, true)
			for i in 12:
				var ang := TAU * i / 12.0
				ci.draw_line(c + Vector2.from_angle(ang) * 0.72 * u, c + Vector2.from_angle(ang) * 0.82 * u, Color(1, 1, 1, 0.55 * a), 0.04 * u, true)
			var fd := Vector2.from_angle(front)
			ci.draw_circle(c + fd * 1.08 * u, 0.12 * u, _al(Color("C9A15A"), a))
			ci.draw_arc(c + fd * 1.08 * u, 0.12 * u, 0, TAU, 10, _al(outline, a), 0.04 * u, true)
		"pirate":
			# 울퉁불퉁한 금화와 밀랍 인장
			var cn := PackedVector2Array()
			for i in 13:
				var ang2 := TAU * i / 12.0
				cn.append(c + Vector2.from_angle(ang2) * u * (1.1 + 0.05 * float(i % 2)))
			ci.draw_polyline(cn, _al(Color("E2C27A"), a), 0.16 * u, true)
			ci.draw_polyline(cn, Color(0.42, 0.3, 0.12, 0.6 * a), 0.03 * u, true)



# ── 알 형태 7종 (금속 퍽 외 6종) ─────────────────────────
static func _sym_col(col: Color) -> Color:
	var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
	return Color("1B1E22") if lum > 0.62 else Color.WHITE


static func _draw_form(ci: CanvasItem, c: Vector2, u: float, col: Color, symbol: int, form: String, front: float, a: float, rot: float, notch: bool) -> void:
	var oc := _al(outline, a)
	var down := Vector2(0, 1).rotated(-rot)
	var fd := Vector2.from_angle(front)
	var k := 0.42 * u / 11.0
	var w := 0.13 * u
	match form:
		"glass":
			# 유리 바둑알: 둥근 광택, 기호는 음각처럼 은은하게, 정면은 작은 점
			ci.draw_circle(c + down * 0.1 * u, u, Color(0, 0, 0, 0.25 * a))
			ci.draw_circle(c, u, _al(col.darkened(0.35), a))
			var hi := col.lerp(Color.WHITE, 0.55)
			for i in range(1, 7):
				var t := float(i) / 7.0
				ci.draw_circle(c.lerp(c + Vector2(-0.3 * u, -0.35 * u).rotated(-rot), t), u * (1.0 - t * 0.8), _al(col.lerp(hi, t * 0.9), a))
			ci.draw_arc(c, u, 0, TAU, 40, _al(col.darkened(0.55), a), 0.04 * u, true)
			ci.draw_colored_polygon(_ellipse_rot(c + Vector2(-0.35 * u, -0.42 * u).rotated(-rot), 0.32 * u, 0.18 * u, -0.5 - rot), Color(1, 1, 1, 0.6 * a))
			if notch:
				ci.draw_circle(c + fd * 0.8 * u, 0.08 * u, _al(col.darkened(0.6), a))
			draw_symbol(ci, symbol, col.darkened(0.55), a * 0.9, c, k, false, w * 0.9, -rot)
		"cap":
			# 병뚜껑: 톱니 테두리, 한 칸만 은색이 정면
			var pts := PackedVector2Array()
			var teeth := 24
			for i in teeth * 2:
				var ang := TAU * i / (teeth * 2) - rot
				pts.append(c + Vector2.from_angle(ang) * u * (1.08 if i % 2 == 0 else 0.96))
			var sh := PackedVector2Array()
			for q in pts:
				sh.append(q + down * 0.14 * u)
			ci.draw_colored_polygon(sh, _al(col.darkened(0.5), a))
			ci.draw_colored_polygon(pts, _al(col.darkened(0.12), a))
			pts.append(pts[0])
			ci.draw_polyline(pts, oc, 0.06 * u, true)
			ci.draw_circle(c, 0.8 * u, _al(col, a))
			ci.draw_arc(c, 0.8 * u, 0, TAU, 32, Color(0, 0, 0, 0.25 * a), 0.05 * u, true)
			if notch:
				ci.draw_colored_polygon(PackedVector2Array([c + fd * 1.1 * u + fd.orthogonal() * 0.13 * u, c + fd * 1.1 * u - fd.orthogonal() * 0.13 * u, c + fd * 0.86 * u]), _al(Color("E9ECEF"), a))
			draw_symbol(ci, symbol, _sym_col(col), a, c, k, false, w, -rot)
		"button":
			# 단추: 테두리 고리, 구멍 네 개, 실 땀이 정면
			ci.draw_circle(c + down * 0.12 * u, u, _al(col.darkened(0.45), a))
			ci.draw_circle(c, u, _al(col, a))
			ci.draw_arc(c, u, 0, TAU, 40, oc, 0.08 * u, true)
			ci.draw_arc(c, 0.82 * u, 0, TAU, 36, _al(col.darkened(0.22), a), 0.12 * u, true)
			for i in 4:
				var hp := c + Vector2.from_angle(PI / 4.0 + PI / 2.0 * i - rot) * 0.5 * u
				ci.draw_circle(hp, 0.09 * u, _al(col.darkened(0.55), a))
			if notch:
				ci.draw_line(c + fd * 0.62 * u, c + fd * 0.92 * u, _al(Color("F4EBD8"), a), 0.09 * u, true)
			draw_symbol(ci, symbol, _sym_col(col), a, c, k * 0.75, false, w * 0.8, -rot)
		"hockey":
			# 하키 퍽: 검은 고무에 주인 색 띠
			ci.draw_circle(c + down * 0.14 * u, u, _al(Color("0E0F11"), a))
			ci.draw_circle(c, u, _al(Color("1E2024"), a))
			ci.draw_arc(c, 0.76 * u, 0, TAU, 40, _al(col, a), 0.26 * u, true)
			ci.draw_arc(c, u, 0, TAU, 40, oc, 0.07 * u, true)
			if notch:
				draw_notch(ci, c, u, front, a)
			draw_symbol(ci, symbol, col.lightened(0.15), a, c, k * 0.8, false, w, -rot)
		"marble":
			# 유리 구슬: 맑은 구에 주인 색 띠 무늬
			ci.draw_circle(c + down * 0.1 * u, u, Color(0, 0, 0, 0.22 * a))
			ci.draw_circle(c, u, _al(col.lerp(Color.WHITE, 0.72), a))
			for j in 2:
				var band := PackedVector2Array()
				for i in 17:
					var t := float(i) / 16.0
					var x := -0.9 + 1.8 * t
					band.append(c + Vector2(x * u, (sin(t * PI * 2.0 + j * 1.5) * 0.18 + (j - 0.5) * 0.45) * u).rotated(-rot))
				ci.draw_polyline(band, _al(col, a), 0.2 * u, true)
			ci.draw_arc(c, u, 0, TAU, 40, _al(col.darkened(0.3), a), 0.05 * u, true)
			ci.draw_colored_polygon(_ellipse_rot(c + Vector2(-0.38 * u, -0.45 * u).rotated(-rot), 0.28 * u, 0.15 * u, -0.5 - rot), Color(1, 1, 1, 0.8 * a))
			if notch:
				ci.draw_circle(c + fd * 0.82 * u, 0.08 * u, _al(col.darkened(0.5), a))
			draw_symbol(ci, symbol, Color(1, 1, 1, 0.95), a, c, k * 0.85, false, w * 0.9, -rot)
		"coin":
			# 동전: 금 테두리 눈금, 주인 색은 가운데 원
			ci.draw_circle(c + down * 0.12 * u, u, _al(Color("8C6A2E"), a))
			ci.draw_circle(c, u, _al(Color("E8C98A"), a))
			ci.draw_arc(c, u, 0, TAU, 40, oc, 0.06 * u, true)
			for i in 36:
				var ang2 := TAU * i / 36.0
				ci.draw_line(c + Vector2.from_angle(ang2) * 0.98 * u, c + Vector2.from_angle(ang2) * 0.88 * u, _al(Color("8C6A2E"), a), 0.03 * u, true)
			ci.draw_circle(c, 0.8 * u, _al(Color("C9A15A"), a))
			ci.draw_circle(c, 0.62 * u, _al(col, a))
			ci.draw_arc(c, 0.62 * u, 0, TAU, 32, _al(Color("8C6A2E"), a), 0.05 * u, true)
			if notch:
				ci.draw_colored_polygon(PackedVector2Array([c + fd * 0.8 * u + fd.orthogonal() * 0.12 * u, c + fd * 0.8 * u - fd.orthogonal() * 0.12 * u, c + fd * 0.66 * u]), _al(Color("8C6A2E"), a))
			draw_symbol(ci, symbol, _sym_col(col), a, c, k * 0.72, false, w * 0.85, -rot)
		_:
			draw_puck_form(ci, c, u, col, symbol, "metal", front, a, rot, notch)
