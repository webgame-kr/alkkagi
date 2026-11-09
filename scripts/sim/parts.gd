extends RefCounted
## 부품 효과. 세계(world.gd)가 발사·충돌·정지 사건을 넘겨주면 장착된 부품이 반응한다.
## 발사한 알의 부품은 부품마다 한 샷에 한 번만 작동한다 (shot.used).
## 수치는 parts_data.gd 에서 읽는다.

const D = preload("res://scripts/sim/parts_data.gd")

const R := 22.0               # world.gd STONE_R 과 같은 값
const FRONTAL_COS := 0.8      # 진행 방향과 충돌 방향이 이 이상 겹치면 정면 충돌


static func _use(w, key: String) -> bool:
	if w.shot.used.has(key):
		return false
	w.shot.used[key] = true
	return true


static func _part_ev(w, s, part: String, pos: Vector2, extra := {}) -> void:
	var ev := {"t": "part", "part": part, "pos": pos, "owner": s.owner, "text": D.part_name(part)}
	ev.merge(extra, true)
	w.emit(ev)


# ── 발사 순간 ────────────────────────────────────────────

static func on_launch(w, s) -> void:
	var dir: Vector2 = w.shot.dir
	var weapon: String = s.parts["weapon"]
	var aux: String = s.parts["aux"]
	var muzzle: Vector2 = s.pos + dir * (R + 7.0)
	match weapon:
		"pea":
			if _use(w, "pea"):
				_fire(w, s, muzzle, dir, D.num("pea", "power"), aux == "decal")
				_part_ev(w, s, "pea", muzzle)
		"shotgun":
			if _use(w, "shotgun"):
				var spread := deg_to_rad(D.num("shotgun", "spread_deg"))
				for k in [-1, 0, 1]:
					var d2 := dir.rotated(spread * k)
					_fire(w, s, s.pos + d2 * (R + 7.0), d2, D.num("shotgun", "power"), aux == "decal")
				_part_ev(w, s, "shotgun", muzzle)
		"hook":
			if _use(w, "hook"):
				var t = first_on_ray(w, s.pos, dir, D.num("hook", "range"), s.id)
				if t != null and t.owner != s.owner:
					t.vel += (s.pos - t.pos).normalized() * D.num("hook", "power")
					_part_ev(w, s, "hook", t.pos, {"from": s.pos})
				else:
					_part_ev(w, s, "hook", muzzle, {"miss": true})
		"sucker":
			if _use(w, "sucker"):
				w.spawn_proj("sucker", s.owner, muzzle, dir, D.num("sucker", "speed"), 7.0, 0.0, s.id)
				_part_ev(w, s, "sucker", muzzle)
		"umbrella_gun":
			if _use(w, "umbrella_gun"):
				w.spawn_proj("umbrella", s.owner, muzzle, dir, D.num("umbrella_gun", "speed"), 9.0, 0.0, s.id)
				_part_ev(w, s, "umbrella_gun", muzzle)
	if s.parts["prop"] == "clockwork" and w.shot.power <= D.num("clockwork", "max_power"):
		w.shot.clock_timer = D.num("clockwork", "delay")
	if aux == "magnet" and _use(w, "magnet"):
		var t = magnet_target(w, s, dir)
		if t != null:
			var lead: Vector2 = s.pos + dir * 120.0
			t.vel += (lead - t.pos).normalized() * D.num("magnet", "power")
			_part_ev(w, s, "magnet", t.pos, {"from": s.pos})


static func _fire(w, s, pos: Vector2, dir: Vector2, power: float, decal: bool) -> void:
	w.spawn_bullet(s.owner, pos, dir, power, "weapon", s.id)
	if decal:
		# 판 중심을 사이에 둔 반대편에서 반대 방향으로. 판이 점대칭이라 항상 판 안이다.
		var mp: Vector2 = -pos
		w.spawn_bullet(s.owner, mp, -dir, power, "decal", -1)
		if not w.shot.used.has("decal_ev"):
			w.shot.used["decal_ev"] = true
			_part_ev(w, s, "decal", mp)


## 자석팔이 끌어올 상대 알: 장착한 쪽 반평면에서 사거리 안의 가장 가까운 상대.
static func magnet_target(w, s, dir: Vector2):
	var side: Vector2 = dir.rotated(PI / 2.0 * s.magnet_side)
	var best = null
	var best_d := INF
	for t in w.stones:
		if not t.alive or t.owner == s.owner:
			continue
		var off: Vector2 = t.pos - s.pos
		var dist := off.length()
		if dist > D.num("magnet", "range") or off.dot(side) <= 0.0:
			continue
		if dist < best_d:
			best_d = dist
			best = t
	return best


## pos에서 dir로 range 안에서 처음 걸리는 알.
static func first_on_ray(w, pos: Vector2, dir: Vector2, range_len: float, skip_id: int):
	var best = null
	var best_t := INF
	for t in w.stones:
		if not t.alive or t.id == skip_id:
			continue
		var off: Vector2 = t.pos - pos
		var along := off.dot(dir)
		if along <= 0.0 or along > range_len:
			continue
		var perp := absf(off.cross(dir))
		if perp < R * 2.0 and along < best_t:
			best_t = along
			best = t
	return best


# ── 충돌 ─────────────────────────────────────────────────
## s: 발사한 알, t: 부딪힌 알, n: s → t 방향, v_before: 충돌 전 s의 속도.

static func on_contact(w, s, t, n: Vector2, v_before: Vector2) -> void:
	var ctx = w.shot
	var first: bool = not ctx.contacted
	ctx.contacted = true
	var cosv := 0.0
	if v_before.length() > 1.0:
		cosv = v_before.normalized().dot(n)
	var frontal := cosv >= FRONTAL_COS
	var side_hit := not frontal
	var opp: bool = t.owner != s.owner
	var dir: Vector2 = ctx.dir
	var contact: Vector2 = s.pos + n * R

	# 메카 티라노 「물고 던지기」: 세 부품이 한 알에 모였고, 옆면으로 상대에 먼저 닿았을 때 한 번.
	if D.set_complete(s.parts) and side_hit and opp and not ctx.used.has("trex_head") and not ctx.used.has("trex_arm"):
		if _mecha_throw(w, s, t, n, v_before):
			return

	match s.parts["weapon"]:
		"claw":
			if frontal and opp and _use(w, "claw"):
				ctx.grip_id = t.id
				ctx.grip_timer = D.num("claw", "hold")
				ctx.grip_offset = n
				var v := v_before * 0.8
				s.vel = v
				t.vel = v
				_part_ev(w, s, "claw", contact)
		"nose":
			if frontal and _use(w, "nose"):
				t.vel += n * D.num("nose", "power")
				s.vel = -n * D.num("nose", "bounce")
				_part_ev(w, s, "nose", contact)
		"stamp":
			if first and opp and ctx.power <= D.num("stamp", "max_power") and _use(w, "stamp"):
				if _can_swap(w, s, t):
					var a: Vector2 = s.pos
					s.pos = t.pos
					t.pos = a
					s.vel = Vector2.ZERO
					t.vel = Vector2.ZERO
					ctx.swapped = true
					_part_ev(w, s, "stamp", contact)
		"trex_head":
			if frontal and opp and _use(w, "trex_head"):
				t.vel = dir * (v_before.length() * 0.8 + D.num("trex_head", "power"))
				s.vel *= 0.35
				_part_ev(w, s, "trex_head", contact, {"text": "물기"})
		"roller":
			if frontal and _use(w, "roller"):
				var d = w.place_device("slick", s.owner, s.id, t.pos, n, w.round_no + int(D.num("roller", "rounds")))
				d.length = D.num("roller", "length")
				_part_ev(w, s, "roller", contact)
		"copier":
			if first and _use(w, "copier"):
				w.place_device("turret", s.owner, s.id, contact, dir, -1)
				_part_ev(w, s, "copier", contact)

	match s.parts["aux"]:
		"trex_arm":
			if side_hit and opp and _use(w, "trex_arm"):
				_pull_front(w, s, t, v_before)
				_part_ev(w, s, "trex_arm", contact, {"text": "끌어오기"})
		"tambourine":
			if first and _use(w, "tambourine"):
				var rr := D.num("tambourine", "radius")
				for o in w.stones:
					if not o.alive or o.id == s.id or o.id == t.id:
						continue
					var off: Vector2 = o.pos - contact
					var dist := off.length()
					if dist < rr and dist > 0.1:
						o.vel += off / dist * D.num("tambourine", "power") * (1.0 - dist / rr * 0.6)
				w.emit({"t": "ripple", "pos": contact, "owner": s.owner, "radius": rr})
				_part_ev(w, s, "tambourine", contact)
		"bumper":
			if side_hit and _use(w, "bumper"):
				var vd := v_before.normalized()
				var perp := (n - vd * vd.dot(n)).normalized()
				if perp == Vector2.ZERO:
					perp = vd.orthogonal()
				t.vel += perp * D.num("bumper", "power")
				_part_ev(w, s, "bumper", contact)
		"flipper":
			if first and _use(w, "flipper"):
				var o = _nearest_other(w, s, t, D.num("flipper", "range"))
				if o != null:
					o.vel += (o.pos - s.pos).normalized() * D.num("flipper", "power")
					_part_ev(w, s, "flipper", o.pos, {"from": s.pos})
		"umbrella":
			if first and _use(w, "umbrella"):
				w.place_device("mirror", s.owner, s.id, contact, dir, w.round_no + 1)
				_part_ev(w, s, "umbrella", contact)
		"spring":
			if first and _use(w, "spring"):
				# 부딪힌 알의 반대쪽 옆으로 보낸다.
				var side := dir.orthogonal()
				if side.dot(n) > 0.0:
					side = -side
				w.spawn_rubber(s.owner, s.pos + side * (R + 12.0), side, D.num("spring", "speed"), D.num("spring", "power"), s.id)
				_part_ev(w, s, "spring", contact)
		"carousel":
			if side_hit and opp and _use(w, "carousel"):
				var target_pos: Vector2 = s.pos - n * (R * 2.0 + 2.0)
				if _free_spot(w, target_pos, [s.id, t.id]):
					t.pos = target_pos
					t.vel = -n * (v_before.length() * 0.9 + D.num("carousel", "power"))
					_part_ev(w, s, "carousel", target_pos)

	if first and not ctx.swapped:
		match s.parts["prop"]:
			"rocket":
				if _use(w, "rocket"):
					s.vel += dir * D.num("rocket", "power")
					_part_ev(w, s, "rocket", s.pos)
			"retro":
				if _use(w, "retro"):
					s.vel -= dir * D.num("retro", "power")
					_part_ev(w, s, "retro", s.pos)
			"reel":
				if _use(w, "reel"):
					ctx.reel_timer = D.num("reel", "time")
					_part_ev(w, s, "reel", s.pos, {"from": ctx.start})
			"trex_leg":
				if _use(w, "trex_leg"):
					s.vel *= D.num("trex_leg", "keep")
					_part_ev(w, s, "trex_leg", s.pos, {"text": "버티기"})
			"crab":
				if _use(w, "crab"):
					s.vel = dir.rotated(PI / 2.0 * s.prop_side) * D.num("crab", "power")
					_part_ev(w, s, "crab", s.pos)


## 티라노 팔: 옆에 닿은 상대를 내 알 앞쪽으로 끌어온다.
static func _pull_front(w, s, t, v_before: Vector2) -> bool:
	var fwd: Vector2 = v_before.normalized() if v_before.length() > 1.0 else w.shot.dir
	var spot: Vector2 = s.pos + fwd * (R * 2.0 + 1.0)
	if not w.is_inside(spot) or not _free_spot(w, spot, [s.id, t.id]):
		return false
	t.pos = spot
	t.vel = s.vel * 0.3
	return true


## 메카 티라노: 팔로 끌어오고 → 머리가 물어 조준 방향으로 던지고 → 다리가 버틴다.
static func _mecha_throw(w, s, t, n: Vector2, v_before: Vector2) -> bool:
	var ctx = w.shot
	_pull_front(w, s, t, v_before)
	var st: Dictionary = D.SETS["trex"]
	t.vel = ctx.dir * (maxf(v_before.length(), 300.0) * 0.9 + st["throw_power"])
	s.vel *= D.num("trex_leg", "keep")
	for k in ["trex_head", "trex_arm", "trex_leg"]:
		ctx.used[k] = true
	ctx.used["mecha"] = true
	w.emit({"t": "part", "part": "mecha", "pos": t.pos, "owner": s.owner, "text": st["move"], "big": true})
	return true


static func _can_swap(w, s, t) -> bool:
	if not w.is_inside(s.pos) or not w.is_inside(t.pos):
		return false
	return _free_spot(w, s.pos, [s.id, t.id]) and _free_spot(w, t.pos, [s.id, t.id])


static func _free_spot(w, p: Vector2, ignore: Array) -> bool:
	for o in w.stones:
		if not o.alive or ignore.has(o.id):
			continue
		if o.pos.distance_to(p) < R * 2.0:
			return false
	return true


static func _nearest_other(w, s, t, range_len: float):
	var best = null
	var best_d := INF
	for o in w.stones:
		if not o.alive or o.id == s.id or o.id == t.id:
			continue
		var dist: float = o.pos.distance_to(s.pos)
		if dist <= range_len and dist < best_d:
			best_d = dist
			best = o
	return best


# ── 정지 ─────────────────────────────────────────────────

static func on_stop(w, s) -> void:
	match s.parts["aux"]:
		"bubble":
			var mid := path_midpoint(w.shot.path)
			if w.shot.path.size() > 2 and w.is_inside(mid):
				w.place_device("bubble", s.owner, s.id, mid, Vector2.RIGHT, w.round_no + int(D.num("bubble", "rounds")))
				_part_ev(w, s, "bubble", mid)
		"mine":
			w.place_device("mine", s.owner, s.id, s.pos, Vector2.RIGHT, w.round_no + int(D.num("mine", "rounds")))
			_part_ev(w, s, "mine", s.pos)
		"track":
			var g := groove_from_path(w.shot.path, D.num("track", "length"))
			if not g.is_empty() and w.is_inside(g["start"]):
				var d = w.place_device("groove", s.owner, s.id, g["start"], g["dir"], w.round_no + int(D.num("track", "rounds")))
				d.length = g["length"]
				_part_ev(w, s, "track", s.pos)


## 지나온 길의 마지막 length 구간을 곧은 홈으로. {start, dir, length}
static func groove_from_path(path: Array, length: float) -> Dictionary:
	if path.size() < 2:
		return {}
	var end_p: Vector2 = path[path.size() - 1]
	var acc := 0.0
	var start: Vector2 = end_p
	for i in range(path.size() - 1, 0, -1):
		acc += path[i].distance_to(path[i - 1])
		start = path[i - 1]
		if acc >= length:
			break
	var v := end_p - start
	if v.length() < 20.0:
		return {}
	return {"start": start, "dir": v.normalized(), "length": v.length()}


static func path_midpoint(path: Array) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	var half := total * 0.5
	var acc := 0.0
	for i in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if acc + seg >= half and seg > 0.0:
			return path[i - 1].lerp(path[i], (half - acc) / seg)
		acc += seg
	return path[path.size() - 1]


# ── 조준 미리보기 ────────────────────────────────────────
## 지금 샷에 필요한 정보만: 진행 방향, 총탄의 사선, 자석·갈고리의 작동 범위.

static func aim_preview(w, s, dir: Vector2, power: float) -> Array:
	var out: Array = []
	out.append({"k": "move", "a": s.pos, "b": s.pos + dir * (50.0 + 330.0 * power)})
	var weapon: String = s.parts["weapon"]
	var decal: bool = s.parts["aux"] == "decal"
	var dirs: Array = []
	if weapon == "pea":
		dirs = [dir]
	elif weapon == "shotgun":
		var spread := deg_to_rad(D.num("shotgun", "spread_deg"))
		dirs = [dir.rotated(-spread), dir, dir.rotated(spread)]
	for d2 in dirs:
		var p0: Vector2 = s.pos + d2 * (R + 7.0)
		out.append({"k": "bullet", "a": p0, "b": p0 + d2 * w.ray_to_edge(p0, d2)})
		if decal:
			var mp: Vector2 = -p0
			out.append({"k": "decal", "a": mp, "b": mp - d2 * w.ray_to_edge(mp, -d2)})
	if weapon == "hook":
		var rl := D.num("hook", "range")
		out.append({"k": "hook", "a": s.pos, "b": s.pos + dir * rl})
		var t = first_on_ray(w, s.pos, dir, rl, s.id)
		if t != null and t.owner != s.owner:
			out.append({"k": "target", "a": t.pos})
	if s.parts["aux"] == "magnet":
		var side_dir: Vector2 = dir.rotated(PI / 2.0 * s.magnet_side)
		out.append({"k": "magnet", "a": s.pos, "dir": side_dir, "r": D.num("magnet", "range")})
		var t = magnet_target(w, s, dir)
		if t != null:
			out.append({"k": "target", "a": t.pos})
	if weapon == "sucker":
		var p1: Vector2 = s.pos + dir * (R + 7.0)
		out.append({"k": "sucker", "a": p1, "b": p1 + dir * minf(w.ray_to_edge(p1, dir), 420.0)})
	if weapon == "umbrella_gun":
		var p2: Vector2 = s.pos + dir * (R + 7.0)
		var od := D.num("umbrella_gun", "open_dist")
		out.append({"k": "umbrella", "a": p2, "b": p2 + dir * od, "r": D.num("umbrella_gun", "radius")})
	if s.parts["prop"] == "clockwork" and power <= D.num("clockwork", "max_power"):
		out.append({"k": "clock", "a": s.pos + dir * travel_after(power * 1120.0, D.num("clockwork", "delay"))})
	if D.set_complete(s.parts):
		out.append({"k": "mecha", "a": s.pos, "dir": dir})
	if weapon == "stamp":
		out.append({"k": "note", "a": s.pos, "text": "도장 작동" if power <= D.num("stamp", "max_power") else "도장 X (힘 45% 이하)"})
	return out


## 직선으로 미끄러질 때 t초 뒤까지 간 거리 (world.gd 의 마찰과 같은 식, 근사).
static func travel_after(v0: float, t: float) -> float:
	var v := v0
	var x := 0.0
	var dt := 1.0 / 120.0
	var k := 0.0
	while k < t and v > 0.0:
		x += v * dt
		v = maxf(0.0, v - 950.0 * dt - v * 0.25 * dt)
		k += dt
	return x
