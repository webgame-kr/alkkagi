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
	match str(th.get("deco", "")):
		"junk":
			# 기름 얼룩 + 4칸 격자
			for i in 7:
				var cc := rect.position + Vector2(float((i * 397) % int(maxf(1.0, rect.size.x))), float((i * 211) % int(maxf(1.0, rect.size.y))))
				_ellipse(ci, cc, 60.0 + i * 9.0, 24.0 + i * 4.0, float(i), Color(0, 0, 0, 0.18))
			var st := 160.0
			var gx := rect.position.x
			while gx < rect.end.x:
				ci.draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), Color(1, 1, 1, 0.05), 2.0)
				gx += st
			var gy := rect.position.y
			while gy < rect.end.y:
				ci.draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), Color(1, 1, 1, 0.05), 2.0)
				gy += st
		"magic":
			# 별 (반짝임은 magic_live 가 위에 얹는다)
			for i in 90:
				var sx := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
				var sy := fposmod(sin(i * 78.233) * 12345.678, 1.0)
				var sr := 0.3 + fposmod(sin(i * 3.1) * 999.0, 1.0) * 1.4
				ci.draw_circle(rect.position + Vector2(sx, sy) * rect.size, sr, Color(220 / 255.0, 225 / 255.0, 1.0, 0.35))
		"pirate":
			# 바다 물결
			var wy := rect.position.y + 20.0
			var row := 0
			while wy < rect.end.y:
				var wx := rect.position.x - 40.0 + (row % 2) * 30.0
				while wx < rect.end.x:
					ci.draw_arc(Vector2(wx, wy), 14.0, PI * 1.15, PI * 1.85, 8, Color(1, 1, 1, 0.10), 2.0, true)
					wx += 60.0
				wy += 34.0
				row += 1
		"clock":
			# 남색 바탕에 흐린 톱니바퀴들
			for i in 7:
				var gx2 := rect.position.x + fposmod(i * 311.0 + 60.0, maxf(1.0, rect.size.x))
				var gy2 := rect.position.y + fposmod(i * 173.0 + 30.0, maxf(1.0, rect.size.y))
				var gr := 30.0 + fposmod(i * 47.0, 40.0)
				_gear(ci, Vector2(gx2, gy2), gr, Color(226 / 255.0, 194 / 255.0, 122 / 255.0, 0.07))
		"lab":
			# 흰 실험실 타일과 비커·배선 장식
			var ts := 48.0
			var gx := rect.position.x
			while gx < rect.end.x:
				ci.draw_line(Vector2(gx, rect.position.y), Vector2(gx, rect.end.y), Color(0, 0, 0, 0.06), 1.0)
				gx += ts
			var gy := rect.position.y
			while gy < rect.end.y:
				ci.draw_line(Vector2(rect.position.x, gy), Vector2(rect.end.x, gy), Color(0, 0, 0, 0.06), 1.0)
				gy += ts
			for i in 6:
				var bx := rect.position.x + fposmod(i * 263.0, maxf(1.0, rect.size.x))
				var by := rect.position.y + fposmod(i * 157.0 + 40.0, maxf(1.0, rect.size.y))
				var flask := PackedVector2Array([Vector2(bx - 6, by - 26), Vector2(bx + 6, by - 26), Vector2(bx + 6, by - 12), Vector2(bx + 20, by + 14), Vector2(bx - 20, by + 14), Vector2(bx - 6, by - 12)])
				ci.draw_colored_polygon(flask, Color(182 / 255.0, 242 / 255.0, 60 / 255.0, 0.10))
				flask.append(flask[0])
				ci.draw_polyline(flask, Color(0, 0, 0, 0.10), 1.5, true)
		"manga":
			# 가장자리로 갈수록 커지는 망점
			var ctr := rect.get_center()
			var mx := maxf(rect.size.x, rect.size.y)
			var stp := 10.0
			var yy := rect.position.y
			var rowi := 0
			while yy < rect.end.y:
				var xx := rect.position.x + (stp * 0.5 if rowi % 2 == 1 else 0.0)
				while xx < rect.end.x:
					var d := Vector2(xx, yy).distance_to(ctr) / mx
					var r := maxf(0.0, d - 0.25) * 5.0
					if r > 0.2:
						ci.draw_circle(Vector2(xx, yy), r, Color(0, 0, 0, 0.10))
					xx += stp
				yy += stp
				rowi += 1


## 2~10. 판. square: 2인 정사각 판.
static func board(ci: CanvasItem, c: Vector2, R: float, u: float, square: bool, th: Dictionary, t := 0.0) -> void:
	var outline: Color = th["outline"]
	var deco: String = th.get("deco", "")
	var rail_r := R + 0.62 * u
	# 2. 판 그림자
	if square:
		_rrect(ci, Rect2(c - Vector2(R + 0.75 * u, R + 0.75 * u) + Vector2(0, 0.35 * u), Vector2.ONE * 2.0 * (R + 0.75 * u)), th["shadow"], 0.5 * u)
	else:
		ci.draw_circle(c + Vector2(0, 0.35 * u), R + 0.75 * u, th["shadow"])
	# 3. 레일: 위→아래 밝은·기본·어두운 (만화 창고는 먹색 레일 + 흰 선)
	if deco == "manga":
		_shape(ci, c, R + 0.6 * u, square, Color("111111"))
		_shape_line(ci, c, R + 0.3 * u, square, Color.WHITE, 0.08 * u)
	else:
		_rail(ci, c, rail_r, square, th)
	if deco == "pirate" and not square:
		# 굵은 밧줄 테두리: 꼬임 무늬
		var twists := 90
		for i in twists:
			var a0 := TAU * i / twists
			var p1 := c + Vector2.from_angle(a0) * (R + 0.18 * u)
			var p2 := c + Vector2.from_angle(a0 + TAU / twists * 0.9) * (R + 0.62 * u)
			ci.draw_line(p1, p2, Color("8A6F3E"), maxf(1.5, 0.09 * u), true)
	if deco == "clock" and not square:
		# 황동 톱니 테두리
		var teeth := 72
		for i in teeth:
			var a0 := TAU * i / teeth
			var p1 := c + Vector2.from_angle(a0 - 0.012) * (R + 0.55 * u)
			var p2 := c + Vector2.from_angle(a0 + 0.012) * (R + 0.55 * u)
			var p3 := c + Vector2.from_angle(a0 + 0.02) * (R + 0.8 * u)
			var p4 := c + Vector2.from_angle(a0 - 0.02) * (R + 0.8 * u)
			ci.draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), Color("B8913F"))
	if deco == "lab":
		# 형광 연두·검정 경고 띠
		if square:
			_dashed_rect2(ci, c, R + 0.32 * u, 0.26 * u, Color("B6F23C"), Color("1A1A1A"), 48)
		else:
			for i in 48:
				ci.draw_arc(c, R + 0.32 * u, TAU * i / 48.0, TAU * (i + 1) / 48.0, 4, Color("1A1A1A") if i % 2 == 1 else Color("B6F23C"), 0.26 * u, false)
	if deco == "junk":
		# 노랑·검정 경고 띠와 볼트 8개
		if square:
			_dashed_rect2(ci, c, R + 0.32 * u, 0.26 * u, Color("FFC23D"), Color("1A1A1A"), 48)
		else:
			for i in 48:
				ci.draw_arc(c, R + 0.32 * u, TAU * i / 48.0, TAU * (i + 1) / 48.0, 4, Color("1A1A1A") if i % 2 == 1 else Color("FFC23D"), 0.26 * u, false)
		for i in 8:
			var ang := i * PI / 4.0 + PI / 8.0
			var bp := c + Vector2.from_angle(ang) * (R + 0.32 * u) if not square else c + Vector2(cos(ang), sin(ang)).normalized() * (R + 0.32 * u) / maxf(absf(cos(ang)), absf(sin(ang))) * 0.999
			ci.draw_circle(bp, 0.13 * u, Color("9AA0A6"))
			ci.draw_arc(bp, 0.13 * u, 0, TAU, 12, Color("111111"), 1.5, true)
	elif deco == "magic":
		pass  # 도는 점선은 magic_live 가 매 프레임 그린다
	if deco == "manga":
		pass
	elif square:
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
		var k := float(i) / steps
		var rad := R * (1.0 - k * 0.97)
		var cc := c.lerp(light, k)
		if square:
			rad = minf(rad, _rect_room(cc, c, R))
		ci.draw_circle(cc, rad, fe.lerp(fc, k))
	# 6. 격자 (공방): 펠트 안쪽만
	if th["grid"]:
		_grid(ci, c, R, u * 0.5, Color(1, 1, 1, 0.05), square)
		_grid(ci, c, R, u, Color(1, 1, 1, 0.11), square)
	# 공방 무늬
	if deco == "junk":
		var k := -R
		while k <= R:
			var h := R if square else sqrt(maxf(0.0, R * R - k * k))
			ci.draw_line(c + Vector2(-h, k), c + Vector2(h, k), Color(0, 0, 0, 0.12), maxf(1.0, 0.06 * u))
			k += 0.6 * u
	elif deco == "pirate":
		# 갑판 널: 가로 판자와 못 자국
		var py := -R
		var pi2 := 0
		while py < R:
			var h3 := R if square else sqrt(maxf(0.0, R * R - py * py))
			ci.draw_line(c + Vector2(-h3, py), c + Vector2(h3, py), Color(0, 0, 0, 0.16), maxf(1.0, 0.05 * u))
			var off := (pi2 % 3) * 0.33
			var jx := -R + off * 3.0 * u
			while jx < R:
				if absf(jx) < h3 - 4.0:
					ci.draw_line(c + Vector2(jx, py), c + Vector2(jx, py + 0.9 * u), Color(0, 0, 0, 0.12), 1.0)
					ci.draw_circle(c + Vector2(jx + 0.15 * u, py + 0.2 * u), maxf(1.0, 0.05 * u), Color(0, 0, 0, 0.22))
				jx += 3.0 * u
			py += 0.9 * u
			pi2 += 1
	elif deco == "clock" and not square:
		# 시간 눈금: 12칸 굵게, 60칸 가늘게, 가운데 법랑 원
		for i in 60:
			var a1 := TAU * i / 60.0
			var big := i % 5 == 0
			var r0 := R * (0.86 if big else 0.9)
			ci.draw_line(c + Vector2.from_angle(a1) * r0, c + Vector2.from_angle(a1) * R * 0.95, Color(226 / 255.0, 194 / 255.0, 122 / 255.0, 0.35 if big else 0.18), maxf(1.0, (0.08 if big else 0.03) * u))
		ci.draw_arc(c, R * 0.3, 0, TAU, 48, Color(226 / 255.0, 194 / 255.0, 122 / 255.0, 0.14), 1.5, true)
		ci.draw_arc(c, R * 0.62, 0, TAU, 64, Color(226 / 255.0, 194 / 255.0, 122 / 255.0, 0.10), 1.0, true)
	elif deco == "lab":
		var tk := u
		var k2 := -R
		while k2 <= R:
			var h2 := R if square else sqrt(maxf(0.0, R * R - k2 * k2))
			ci.draw_line(c + Vector2(-h2, k2), c + Vector2(h2, k2), Color(0, 0, 0, 0.07), 1.0)
			ci.draw_line(c + Vector2(k2, -h2), c + Vector2(k2, h2), Color(0, 0, 0, 0.07), 1.0)
			k2 += tk
	elif deco == "magic":
		ci.draw_arc(c, R * 0.55, 0, TAU, 64, Color(201 / 255.0, 213 / 255.0, 1.0, 0.16), 1.5, true)
		var star := PackedVector2Array()
		for i in 6:
			var a := -PI / 2.0 + i * 4.0 * PI / 5.0
			star.append(c + Vector2(cos(a), sin(a)) * R * 0.55)
		ci.draw_polyline(star, Color(201 / 255.0, 213 / 255.0, 1.0, 0.16), 1.5, true)
	elif deco == "manga":
		var stp := maxf(0.5 * u, 5.0)
		var yy := -R
		while yy < R:
			var xx := -R
			while xx < R:
				var d := Vector2(xx, yy).length() / R if not square else maxf(absf(xx), absf(yy)) / R
				if d > 0.72 and d < 1.0:
					ci.draw_circle(c + Vector2(xx, yy), (d - 0.72) * stp * 1.4, Color(0, 0, 0, 0.09), true, -1.0, false)
				xx += stp
			yy += stp
	# 7. 위험 띠 / 8. 위험 경계 점선
	var dz: Color = th["danger"]
	if deco == "manga":
		# 붉은 빗금 띠
		var kk := -R * 2.0
		while kk < R * 2.0:
			var a := c + Vector2(kk, -R)
			var b := c + Vector2(kk + R, R)
			_hatch_ring(ci, c, R, u, a, b, square)
			kk += 0.28 * u
	elif square:
		ci.draw_rect(Rect2(c - Vector2.ONE * (R - 0.5 * u), Vector2.ONE * 2.0 * (R - 0.5 * u)), Color(dz, 0.16), false, u)
		_dashed_rect(ci, c, R - u, 0.18 * u, th["danger_line"], maxf(1.0, 0.05 * u))
	else:
		if deco != "manga":
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


static func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, ang: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(ang))
	ci.draw_colored_polygon(pts, col)


static func _shape(ci: CanvasItem, c: Vector2, r: float, square: bool, col: Color) -> void:
	if square:
		ci.draw_rect(Rect2(c - Vector2.ONE * r, Vector2.ONE * 2.0 * r), col)
	else:
		ci.draw_circle(c, r, col)


static func _shape_line(ci: CanvasItem, c: Vector2, r: float, square: bool, col: Color, w: float) -> void:
	if square:
		ci.draw_rect(Rect2(c - Vector2.ONE * r, Vector2.ONE * 2.0 * r), col, false, w)
	else:
		ci.draw_arc(c, r, 0, TAU, 96, col, w, true)


static func _dashed_rect2(ci: CanvasItem, c: Vector2, h: float, w: float, c1: Color, c2: Color, n: int) -> void:
	var corners := [c + Vector2(-h, -h), c + Vector2(h, -h), c + Vector2(h, h), c + Vector2(-h, h)]
	var per := n / 4
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		for i in per:
			ci.draw_line(a.lerp(b, float(i) / per), a.lerp(b, float(i + 1) / per), c2 if i % 2 == 1 else c1, w)


## 만화 창고 위험 띠: 판 끝 1칸 안에서만 보이는 붉은 빗금.
static func _hatch_ring(ci: CanvasItem, c: Vector2, R: float, u: float, a: Vector2, b: Vector2, square: bool) -> void:
	var col := Color(224 / 255.0, 78 / 255.0, 58 / 255.0, 0.45)
	var outer := clip_segment(a, b, c, R, square)
	if outer.is_empty():
		return
	var inner := clip_segment(outer[0], outer[1], c, R - u, square)
	if inner.is_empty():
		ci.draw_line(outer[0], outer[1], col, 1.5)
		return
	ci.draw_line(outer[0], inner[0], col, 1.5)
	ci.draw_line(inner[1], outer[1], col, 1.5)


## 마법 상점: 판 둘레를 천천히 도는 점선 (가볍게 매 프레임).
static func magic_live(ci: CanvasItem, c: Vector2, R: float, u: float, t: float) -> void:
	var segs := 40
	var col := Color(201 / 255.0, 213 / 255.0, 1.0, 0.7)
	for i in segs:
		var a0 := TAU * i / segs - t * 0.3 * u / maxf(1.0, R)
		ci.draw_arc(c, R + 0.32 * u, a0, a0 + TAU / segs * 0.22, 3, col, 1.5, true)


static func _gear(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 12
	for i in n * 2:
		var a := TAU * i / (n * 2)
		var rr := r if i % 2 == 0 else r * 0.82
		pts.append(c + Vector2.from_angle(a) * rr)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, 2.0, true)
	ci.draw_arc(c, r * 0.35, 0, TAU, 16, col, 2.0, true)
