extends RefCounted
## 경기장 그리기 (디자인 사양 「경기장 그리기 순서와 크기」). 길이는 칸(퍽 지름) 단위.
## c: 판 중심(화면), R: 판 반지름(px, 정사각은 반 변), u: 1칸(px).

## 1. 바깥 배경: 단색 + 나뭇결 / 다크는 방사형.
static func background(ci: CanvasItem, rect: Rect2, th: Dictionary, t := 0.0) -> void:
	ci.draw_rect(rect, th["bg"])
	if th["bg_center"] != th["bg"]:
		var ctr := rect.get_center()
		var maxr := rect.size.length() * 0.55
		var steps := 24
		for i in steps:
			var k := float(i) / steps
			ci.draw_circle(ctr, maxr * (1.0 - k), Color(th["bg_center"], 0.09))
	var grain: Color = th["grain"]
	if grain.a > 0.0:
		var y := rect.position.y + 6.0
		var row := 0
		while y < rect.end.y:
			var pts := PackedVector2Array()
			var ph := float(row) * 1.7
			var x := rect.position.x
			while x <= rect.end.x + 40.0:
				pts.append(Vector2(x, y + sin(x * 0.011 + ph) * 3.0 + sin(x * 0.037 + ph * 2.3) * 1.2))
				x += 40.0
			ci.draw_polyline(pts, grain, 1.0, true)
			y += 9.0 + float((row * 7) % 5)
			row += 1


## 2~10. 판. square: 2인 정사각 판.
static func board(ci: CanvasItem, c: Vector2, R: float, u: float, square: bool, th: Dictionary) -> void:
	var outline: Color = th["outline"]
	var rail_r := R + 0.62 * u
	# 2. 판 그림자
	if square:
		_rrect(ci, Rect2(c - Vector2(R + 0.75 * u, R + 0.75 * u) + Vector2(0, 0.35 * u), Vector2.ONE * 2.0 * (R + 0.75 * u)), th["shadow"], 0.5 * u)
	else:
		ci.draw_circle(c + Vector2(0, 0.35 * u), R + 0.75 * u, th["shadow"])
	# 3. 레일: 위→아래 밝은·기본·어두운
	_rail(ci, c, rail_r, square, th)
	if square:
		ci.draw_rect(Rect2(c - Vector2.ONE * rail_r, Vector2.ONE * 2.0 * rail_r), outline, false, maxf(1.0, 0.05 * u))
	else:
		ci.draw_arc(c, rail_r, 0, TAU, 128, outline, maxf(1.0, 0.05 * u), true)
	# 4. 레일 빛 번짐 (다크)
	var glow: Color = th["rail_glow"]
	if glow.a > 0.0:
		for i in 6:
			var k := float(i) / 6.0
			var w := 0.08 * u + 0.8 * u * k
			var a := 0.5 * (1.0 - k) * (1.0 - k)
			if square:
				var rr := R + 0.1 * u
				ci.draw_rect(Rect2(c - Vector2.ONE * rr, Vector2.ONE * 2.0 * rr), Color(glow, a * 0.6), false, w)
			else:
				ci.draw_arc(c, R + 0.1 * u, 0, TAU, 128, Color(glow, a * 0.6), w, true)
		if square:
			var r2 := R + 0.1 * u
			ci.draw_rect(Rect2(c - Vector2.ONE * r2, Vector2.ONE * 2.0 * r2), glow, false, maxf(1.0, 0.08 * u))
		else:
			ci.draw_arc(c, R + 0.1 * u, 0, TAU, 128, glow, maxf(1.0, 0.08 * u), true)
	# 5. 펠트: 왼쪽 위(-0.25R, -0.3R)에서 퍼지는 방사형
	var fc: Color = th["felt_c"]
	var fe: Color = th["felt_e"]
	if square:
		ci.draw_rect(Rect2(c - Vector2(R, R), Vector2(2 * R, 2 * R)), fe)
	else:
		ci.draw_circle(c, R, fe)
	var light := c + Vector2(-0.25, -0.3) * R
	var steps := 30
	for i in range(1, steps):
		var t := float(i) / steps
		var rad := R * (1.0 - t * 0.97) * (1.0 if not square else 1.0)
		var cc := c.lerp(light, t)
		if square:
			rad = minf(rad, _rect_room(cc, c, R))
		ci.draw_circle(cc, rad, fe.lerp(fc, t))
	# 6. 격자 (공방): 펠트 안쪽만
	if th["grid"]:
		_grid(ci, c, R, u * 0.5, Color(1, 1, 1, 0.05), square)
		_grid(ci, c, R, u, Color(1, 1, 1, 0.11), square)
	# 7. 위험 띠 / 8. 위험 경계 점선
	var dz: Color = th["danger"]
	if square:
		ci.draw_rect(Rect2(c - Vector2.ONE * (R - 0.5 * u), Vector2.ONE * 2.0 * (R - 0.5 * u)), Color(dz, 0.16), false, u)
		_dashed_rect(ci, c, R - u, 0.18 * u, th["danger_line"], maxf(1.0, 0.05 * u))
	else:
		ci.draw_arc(c, R - 0.5 * u, 0, TAU, 128, Color(dz, 0.16), u, true)
		_dashed_circle(ci, c, R - u, 0.18 * u, th["danger_line"], maxf(1.0, 0.05 * u))
	# 펠트 테두리
	if square:
		ci.draw_rect(Rect2(c - Vector2(R, R), Vector2(2 * R, 2 * R)), outline, false, maxf(1.0, 0.05 * u))
	else:
		ci.draw_arc(c, R, 0, TAU, 128, outline, maxf(1.0, 0.05 * u), true)
	# 9. 가운데 표시
	ci.draw_arc(c, 0.18 * u, 0, TAU, 20, Color(1, 1, 1, 0.35), maxf(1.0, 0.04 * u), true)
	# 10. 위쪽 조명: 왼쪽 위에서 퍼지는 흰색
	var li: float = th["light"]
	var lp := c + Vector2(-0.35, -0.45) * R
	var lr := R * 0.42
	var n := 10
	for i in n:
		var k2 := float(i) / n
		ci.draw_circle(lp, lr * (1.0 - k2), Color(1, 1, 1, li / n))


## 판 안의 선분을 펠트 원(또는 사각)으로 자른다. 잘린 결과가 없으면 빈 배열.
static func clip_segment(a: Vector2, b: Vector2, c: Vector2, R: float, square: bool) -> Array:
	if square:
		var lo := c - Vector2(R, R)
		var hi := c + Vector2(R, R)
		var t0 := 0.0
		var t1 := 1.0
		var d := b - a
		for ax in 2:
			if absf(d[ax]) < 0.0001:
				if a[ax] < lo[ax] or a[ax] > hi[ax]:
					return []
				continue
			var ta := (lo[ax] - a[ax]) / d[ax]
			var tb := (hi[ax] - a[ax]) / d[ax]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		if t0 >= t1:
			return []
		return [a + d * t0, a + d * t1]
	var f := a - c
	var dd := b - a
	var A := dd.dot(dd)
	if A < 0.0001:
		return [a, b] if f.length() <= R else []
	var B := 2.0 * f.dot(dd)
	var C := f.dot(f) - R * R
	var disc := B * B - 4.0 * A * C
	if disc <= 0.0:
		return []
	var sq := sqrt(disc)
	var s0 := maxf(0.0, (-B - sq) / (2.0 * A))
	var s1 := minf(1.0, (-B + sq) / (2.0 * A))
	if s0 >= s1:
		return []
	return [a + dd * s0, a + dd * s1]


static func _rect_room(p: Vector2, c: Vector2, R: float) -> float:
	var d := p - c
	return minf(R - absf(d.x), R - absf(d.y))


static func _rail(ci: CanvasItem, c: Vector2, r: float, square: bool, th: Dictionary) -> void:
	var hi: Color = th["rail_hi"]
	var mid: Color = th["rail"]
	var lo: Color = th["rail_lo"]
	var pts := PackedVector2Array()
	if square:
		pts = PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, -r), c + Vector2(r, 0), c + Vector2(r, r), c + Vector2(-r, r), c + Vector2(-r, 0)])
	else:
		for i in 96:
			pts.append(c + Vector2.from_angle(TAU * i / 96.0) * r)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(_grad3(hi, mid, lo, (p.y - c.y + r) / (2.0 * r)))
	ci.draw_polygon(pts, cols)


static func _grad3(a: Color, b: Color, c: Color, t: float) -> Color:
	if t < 0.5:
		return a.lerp(b, t * 2.0)
	return b.lerp(c, (t - 0.5) * 2.0)


static func _grid(ci: CanvasItem, c: Vector2, R: float, g: float, col: Color, square: bool) -> void:
	var off := 0.0
	while off < R - 0.5:
		for sgn in ([1.0, -1.0] if off > 0.0 else [1.0]):
			var o: float = off * sgn
			var h := R if square else sqrt(maxf(0.0, R * R - o * o))
			ci.draw_line(c + Vector2(o, -h), c + Vector2(o, h), col, 1.0)
			ci.draw_line(c + Vector2(-h, o), c + Vector2(h, o), col, 1.0)
		off += g


static func _dashed_circle(ci: CanvasItem, c: Vector2, r: float, gap: float, col: Color, w: float) -> void:
	var circ := TAU * r
	var n := maxi(12, int(circ / (gap * 2.0)))
	for i in n:
		var a0 := TAU * i / n
		var a1 := a0 + TAU / n * 0.5
		ci.draw_arc(c, r, a0, a1, 3, col, w, true)


static func _dashed_rect(ci: CanvasItem, c: Vector2, h: float, gap: float, col: Color, w: float) -> void:
	var corners := [c + Vector2(-h, -h), c + Vector2(h, -h), c + Vector2(h, h), c + Vector2(-h, h)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var L := a.distance_to(b)
		var n := maxi(4, int(L / (gap * 2.0)))
		for i in n:
			ci.draw_line(a.lerp(b, float(i) / n), a.lerp(b, (i + 0.5) / n), col, w)


static func _rrect(ci: CanvasItem, r: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.draw(ci.get_canvas_item(), r)
