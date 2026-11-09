extends RefCounted
## 알과 부품 실루엣. 알 중심을 원점, 진행 방향을 +x 로 둔 로컬 좌표(월드 단위)에서 그린다.
## 총열·줄감개·접힌 우산처럼 실루엣만으로 구별되게 그리는 것이 목표.

const R := 22.0
const METAL := Color(0.78, 0.80, 0.84)
const DARK := Color(0.16, 0.17, 0.20)


static func draw(ci: CanvasItem, parts: Dictionary, magnet_side: int, col: Color, alpha := 1.0) -> void:
	var a := alpha
	ci.draw_circle(Vector2(2.5, 3.5), R, Color(0, 0, 0, 0.30 * a))
	_prop(ci, parts.get("prop", ""), a)
	_weapon(ci, parts.get("weapon", ""), a)
	var aux: String = parts.get("aux", "")
	_aux(ci, aux, magnet_side if aux == "magnet" else -1, a)
	# 몸통
	ci.draw_circle(Vector2.ZERO, R, _al(col, a))
	ci.draw_circle(Vector2.ZERO, R * 0.72, _al(col.lightened(0.10), a))
	ci.draw_arc(Vector2.ZERO, R - 1.0, 0, TAU, 40, _al(col.darkened(0.40), a), 2.5, true)
	ci.draw_circle(Vector2(-6, -7), 6.5, Color(1, 1, 1, 0.28 * a))
	# 앞쪽 표시
	ci.draw_line(Vector2(R * 0.45, 0), Vector2(R * 0.85, 0), Color(1, 1, 1, 0.55 * a), 3.0, true)


static func _al(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


static func _poly(ci: CanvasItem, pts: Array, c: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array(pts), c)


static func _rect(ci: CanvasItem, pos: Vector2, size: Vector2, c: Color, outline := Color(0, 0, 0, 0)) -> void:
	ci.draw_rect(Rect2(pos, size), c)
	if outline.a > 0.0:
		ci.draw_rect(Rect2(pos, size), outline, false, 1.5)


static func _weapon(ci: CanvasItem, w: String, a: float) -> void:
	var metal := _al(METAL, a)
	var dark := _al(DARK, a)
	match w:
		"pea":
			_rect(ci, Vector2(R - 6, -3.5), Vector2(22, 7), dark)
			_rect(ci, Vector2(R + 13, -4.5), Vector2(4, 9), metal)
		"shotgun":
			for k in [-1, 0, 1]:
				var rot := deg_to_rad(16.0 * k)
				var base := Vector2(R - 6, 0)
				var pts := []
				for p in [Vector2(0, -3), Vector2(16, -3), Vector2(16, 3), Vector2(0, 3)]:
					pts.append(base + p.rotated(rot))
				_poly(ci, pts, dark)
			_rect(ci, Vector2(R - 8, -7), Vector2(6, 14), metal)
		"hook":
			ci.draw_line(Vector2(R - 4, 0), Vector2(R + 16, 0), dark, 3.0, true)
			ci.draw_arc(Vector2(R + 16, 5), 5.0, -PI / 2.0, PI * 0.8, 10, metal, 3.0, true)
		"claw":
			for sy in [-1.0, 1.0]:
				ci.draw_polyline(PackedVector2Array([Vector2(R - 4, 6 * sy), Vector2(R + 12, 12 * sy), Vector2(R + 17, 4 * sy)]), metal, 3.5, true)
		"nose":
			ci.draw_circle(Vector2(R, 0), 9.0, _al(Color(0.45, 0.12, 0.14), a))
			ci.draw_circle(Vector2(R + 2, -3), 3.0, Color(1, 1, 1, 0.25 * a))
		"stamp":
			_rect(ci, Vector2(R - 5, -10), Vector2(11, 20), _al(Color(0.55, 0.36, 0.20), a))
			_rect(ci, Vector2(R + 5, -9), Vector2(3, 18), _al(Color(0.86, 0.20, 0.25), a))
		"copier":
			_rect(ci, Vector2(R - 7, -9), Vector2(15, 18), _al(Color(0.85, 0.86, 0.88), a), dark)
			_rect(ci, Vector2(R + 1, -6), Vector2(5, 12), dark)
			ci.draw_line(Vector2(R + 1, -9), Vector2(R + 8, -18), dark, 2.0, true)
			ci.draw_circle(Vector2(R + 8, -18), 2.5, _al(Color(1, 0.3, 0.3), a))


static func _aux(ci: CanvasItem, x: String, side: int, a: float) -> void:
	var s := float(side)
	var dark := _al(DARK, a)
	match x:
		"magnet":
			var c := Vector2(0, s * (R + 4))
			ci.draw_arc(c, 8.0, 0.0 if s > 0 else PI, PI if s > 0 else TAU, 12, _al(Color(0.85, 0.18, 0.2), a), 5.0, true)
			_rect(ci, Vector2(-10.5, s * (R + 4) - 3), Vector2(5, 6), metal_col(a))
			_rect(ci, Vector2(5.5, s * (R + 4) - 3), Vector2(5, 6), metal_col(a))
		"bumper":
			var y := s * (R + 1) - (6.0 if s < 0 else 0.0)
			_rect(ci, Vector2(-13, y), Vector2(26, 6), _al(Color(0.96, 0.78, 0.15), a), dark)
			ci.draw_line(Vector2(-4, y + 3), Vector2(4, y + 3), dark, 1.5)
		"flipper":
			_poly(ci, [Vector2(-4, s * (R - 2)), Vector2(-24, s * (R + 12)), Vector2(-6, s * (R + 9))], _al(Color(1.0, 0.55, 0.15), a))
		"decal":
			_rect(ci, Vector2(-15, s * (R - 1) - 3), Vector2(16, 6), _al(Color(0.62, 0.35, 0.85), a), dark)
			_rect(ci, Vector2(-15, -s * (R - 1) - 2), Vector2(10, 4), _al(Color(0.62, 0.35, 0.85, 0.45), a))
		"umbrella":
			_poly(ci, [Vector2(-16, s * (R + 1)), Vector2(14, s * (R + 4)), Vector2(-16, s * (R + 9))], _al(Color(0.55, 0.85, 0.95), a))
			ci.draw_line(Vector2(-16, s * (R + 5)), Vector2(-22, s * (R + 5)), dark, 2.0)
			ci.draw_arc(Vector2(-22, s * (R + 8)), 3.0, -PI / 2.0, PI / 2.0 + PI, 8, dark, 1.5)
		"spring":
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(Vector2(-3 + (6 if i % 2 == 0 else -0) - 3, s * (R - 2 + i * 2.6)))
			ci.draw_polyline(pts, metal_col(a), 2.0, true)
			ci.draw_circle(Vector2(0, s * (R + 18)), 4.5, _al(Color(0.95, 0.45, 0.65), a))
		"carousel":
			var a0 := PI / 2.0 * s
			ci.draw_arc(Vector2.ZERO, R + 6, a0 - 0.9, a0 + 0.9, 14, _al(Color(0.25, 0.75, 0.45), a), 4.0, true)
			ci.draw_circle(Vector2.from_angle(a0 + 0.9) * (R + 6), 4.0, dark)
		"bubble":
			ci.draw_circle(Vector2(-10, s * (R + 2)), 5.0, _al(Color(0.35, 0.80, 0.95), a))
			ci.draw_arc(Vector2(-18, s * (R + 9)), 3.5, 0, TAU, 10, Color(0.7, 0.95, 1.0, 0.8 * a), 1.5)
			ci.draw_arc(Vector2(-24, s * (R + 4)), 2.5, 0, TAU, 8, Color(0.7, 0.95, 1.0, 0.6 * a), 1.2)
		"mine":
			var y2 := s * (R - 2) - (10.0 if s < 0 else 0.0)
			_rect(ci, Vector2(-18, y2), Vector2(14, 10), dark)
			ci.draw_line(Vector2(-16, y2 + 2), Vector2(-10, y2 + 8), _al(Color(1, 0.85, 0.1), a), 2.0)
			ci.draw_line(Vector2(-11, y2 + 2), Vector2(-6, y2 + 8), _al(Color(1, 0.85, 0.1), a), 2.0)


static func metal_col(a: float) -> Color:
	return _al(METAL, a)


static func _prop(ci: CanvasItem, p: String, a: float) -> void:
	var metal := _al(METAL, a)
	var dark := _al(DARK, a)
	match p:
		"rocket":
			_poly(ci, [Vector2(-R + 4, -7), Vector2(-R - 9, -10), Vector2(-R - 9, 10), Vector2(-R + 4, 7)], metal)
			_poly(ci, [Vector2(-R - 9, -6), Vector2(-R - 18, 0), Vector2(-R - 9, 6)], _al(Color(1.0, 0.55, 0.1), a))
		"retro":
			for sy in [-1.0, 1.0]:
				var base := Vector2.from_angle(deg_to_rad(42.0) * sy) * (R - 2)
				_poly(ci, [base + Vector2(0, -4), base + Vector2(11, -6), base + Vector2(11, 6), base + Vector2(0, 4)], metal)
				_poly(ci, [base + Vector2(11, -3), base + Vector2(17, 0), base + Vector2(11, 3)], _al(Color(0.3, 0.75, 1.0), a))
		"reel":
			ci.draw_circle(Vector2(-R - 5, 0), 8.0, metal)
			ci.draw_circle(Vector2(-R - 5, 0), 3.5, dark)
			ci.draw_arc(Vector2(-R - 5, 0), 6.0, 0, TAU, 14, _al(Color(0.9, 0.85, 0.6), a), 1.5)
		"chute":
			_rect(ci, Vector2(-R - 9, -10), Vector2(14, 20), _al(Color(0.62, 0.58, 0.36), a), dark)
			ci.draw_line(Vector2(-R - 9, 0), Vector2(-R + 5, 0), dark, 1.5)
