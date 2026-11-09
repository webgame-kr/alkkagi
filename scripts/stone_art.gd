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

## 만화 연출 중인 알: 모든 색을 먹선 흑백으로 그린다.
static var mono := false
static var _poly_ok := {}


## 판 위의 퍽. symbol: 0~7 플레이어 각인. tick: 정면 눈금.
static func draw(ci: CanvasItem, parts: Dictionary, magnet_side: int, col: Color, alpha := 1.0, symbol := -1, tick := true) -> void:
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
	var mirror := (x == "magnet" or x == "shield") and magnet_side < 0
	if p != "":
		_prop(ci, p, a)
	if w != "":
		_weapon(ci, w, a)
	if x != "":
		_aux(ci, x, a, mirror)
	_puck(ci, col, a, symbol, tick)


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
static func draw_symbol(ci: CanvasItem, symbol: int, col: Color, a: float, center: Vector2, scale: float, rotate: bool) -> void:
	var c := _al(col, a)
	var wdt := 4.5 * scale
	var f := func(v: Vector2) -> Vector2:
		var d := v - Vector2(50, 50)
		if rotate:
			d = Vector2(-d.y, d.x)
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
			ci.draw_arc(center, 9 * scale, 0, TAU, 20, c, wdt, true)
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


## HUD용 퍽 아이콘 (똑바로 선 모습). size: 지름 px.
static func draw_icon(ci: CanvasItem, center: Vector2, size: float, col: Color, symbol: int, alpha := 1.0) -> void:
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


static func draw_data(ci: CanvasItem, id: String, a: float, mirror: bool, col := Color.WHITE) -> void:
	var shapes: Array = ArtData.SHAPES[id]
	for i in shapes.size():
		var sh: Array = shapes[i]
		var flat: Array = sh[5]
		var pts := PackedVector2Array()
		for k in range(0, flat.size(), 2):
			pts.append(T(Vector2(flat[k], flat[k + 1]), mirror))
		var c := _al(_shape_color(sh[1], col), a * sh[2])
		if sh[0] == "f":
			var key := "%s:%d" % [id, i]
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
