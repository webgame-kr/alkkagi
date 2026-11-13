extends RefCounted
## 확장 부품(마법·각성·패러디·시스템)과 두 세트(달그림자 마도사, 최후의 주인공)의 효과.
## world.gd 가 정해진 시점마다 부른다: 발사 전후, 이동 전, 충돌 전후, 탄, 장치, 판 끝, 탈락, 샷 끝.
## 이번 샷의 상태는 w.shot.ex 사전에, 알에 남는 상태(봉인·저주)는 Stone.status 에 둔다.

const D = preload("res://scripts/sim/parts_data.gd")
const R := 22.0


static func _use(w, key: String) -> bool:
	if w.shot == null or w.shot.used.has(key):
		return false
	w.shot.used[key] = true
	return true


static func _ev(w, owner: int, part: String, pos: Vector2, extra := {}) -> void:
	var ev = {"t": "part", "part": part, "pos": pos, "owner": owner, "text": D.part_name(part)}
	ev.merge(extra, true)
	w.emit(ev)
	if D.is_anime(part):
		w.emit({"t": "manga", "part": part, "pos": pos, "owner": owner, "stone": extra.get("stone", -1)})


static func _free(w, p: Vector2, ignore: Array) -> bool:
	if not w.is_inside(p):
		return false
	for o in w.stones:
		if o.alive and not ignore.has(o.id) and o.pos.distance_to(p) < R * 2.0:
			return false
	return true


static func _ex(w) -> Dictionary:
	return w.shot.ex


# ── 발사 ─────────────────────────────────────────────────

## 부품 효과보다 먼저: 봉인, 저주, 마지막 알 여부, 충전.
static func on_launch_pre(w, s, opts: Dictionary) -> void:
	var ex = _ex(w)
	ex["last_stone"] = w.alive_stones_of(s.owner).size() == 1
	ex["charged"] = opts.get("charged", false)
	ex["scroll_left"] = _scroll_dist(s, w.shot.power)
	# 그림자 가위의 봉인: 이번 발사 한 번만 그 슬롯이 쉰다.
	var sealed: String = s.status.get("sealed", "")
	if sealed != "" and s.parts[sealed] != "":
		ex["sealed"] = [sealed, s.parts[sealed]]
		s.parts[sealed] = ""
		w.emit({"t": "part", "part": "shadow_scissors", "pos": s.pos, "owner": s.owner, "text": "봉인됨"})
	s.status.erase("sealed")
	# 밤비늘 부적의 저주: 출발점 뒤로 그림자가 튀어나와 가까운 알을 민다.
	if s.status.get("cursed", -1) >= 0:
		var by: int = s.status["cursed"]
		s.status.erase("cursed")
		var back: Vector2 = -w.shot.dir
		var best = null
		var bd = D.num("night_charm", "range")
		for o in w.stones:
			if not o.alive or o.id == s.id:
				continue
			var off: Vector2 = o.pos - s.pos
			if off.dot(back) > 0.0 and off.length() < bd:
				bd = off.length()
				best = o
		if best != null:
			best.vel += (best.pos - s.pos).normalized() * D.num("night_charm", "power") * (1.8 if s.status.get("cursed_up", false) else 1.0)
		w.emit({"t": "part", "part": "night_charm", "pos": s.pos - w.shot.dir * 30.0, "owner": by, "text": "저주의 그림자"})
	# 구름 표식은 그 알이 다시 발사되면 사라진다.
	for d in w.devices.duplicate():
		if d.kind == "cloud" and d.stone_id == s.id:
			w.devices.erase(d)


static func on_launch(w, s) -> void:
	var ex = _ex(w)
	var dir: Vector2 = w.shot.dir
	var muzzle: Vector2 = s.pos + dir * (R + 7.0)
	match s.parts["weapon"]:
		"moon_staff":
			if _use(w, "moon_staff"):
				w.spawn_proj("orb", s.owner, muzzle, dir, D.num("moon_staff", "speed"), 8.0, 0.0, s.id)
				_ev(w, s.owner, "moon_staff", muzzle)
		"rubber_fist":
			if _use(w, "rubber_fist"):
				w.spawn_proj("fist", s.owner, muzzle, dir, D.num("rubber_fist", "speed"), 9.0, 0.0, s.id)
				_ev(w, s.owner, "rubber_fist", muzzle, {"stone": s.id})
		"ink_drop":
			if _use(w, "ink_drop"):
				w.spawn_proj("ink", s.owner, muzzle, dir, D.num("ink_drop", "speed"), 7.0, 0.0, s.id)
				_ev(w, s.owner, "ink_drop", muzzle)
		"charge_palm":
			if ex.get("charged", false):
				ex["beam_timer"] = D.num("charge_palm", "delay")
		"hero_band":
			pass   # 투지 충격파는 hero.gd
	if s.parts["aux"] == "at_field" and _use(w, "at_field"):
		ex["barrier"] = 2 if _up(s, "at_field") else 1
		_ev(w, s.owner, "at_field", muzzle, {"stone": s.id})


# ── 이동 전: 순간이동, 장벽, 주문서 ─────────────────────

static func before_move(w, dt: float) -> void:
	var s = w.shooter()
	if s == null or not s.alive or s.vel == Vector2.ZERO:
		return
	var ex = _ex(w)
	var v: Vector2 = s.vel
	var vh = v.normalized()
	# 순보 깔창: 정면의 첫 알에 닿기 직전, 그 뒤 빈자리로.
	if s.parts["prop"] == "flash_step" and not w.shot.contacted and not w.shot.used.has("flash_step"):
		for t in w.stones:
			if not t.alive or t.id == s.id:
				continue
			var off: Vector2 = t.pos - s.pos
			var along = off.dot(vh)
			if along <= 0.0:
				continue
			if absf(off.cross(vh)) < R * 0.9 and along < R * 2.0 + v.length() * dt * 2.0 + 2.0:
				var spot: Vector2 = t.pos + vh * (R * 2.0 + 2.0)
				if _free(w, spot, [s.id, t.id]):
					w.shot.used["flash_step"] = true
					var from: Vector2 = s.pos
					s.pos = spot
					if _up(s, "flash_step"):
						s.vel += vh * 260.0   # ★ 착지 뒤 한 번 더 밀고 나간다
					_ev(w, s.owner, "flash_step", spot, {"from": from, "stone": s.id})
				break
	# 절대영역 방패: 알 앞의 장벽이 처음 닿은 알을 민다.
	if ex.get("barrier", false):
		var bp: Vector2 = s.pos + vh * (R + 16.0)
		for o in w.stones:
			if not o.alive or o.id == s.id:
				continue
			if o.pos.distance_to(bp) < R + 10.0:
				o.vel += (vh * 0.7 + (o.pos - bp).normalized() * 0.3).normalized() * D.num("at_field", "power")
				ex["barrier"] = int(ex["barrier"]) - 1
				w.emit({"t": "hexbreak", "pos": bp, "owner": s.owner, "dir": vh})
				break
	# 옆구리 주문서: 충돌 없이 일정 거리를 가면 90도 꺾인다.
	if s.parts["prop"] == "side_scroll" and not w.shot.contacted and not w.shot.used.has("side_scroll"):
		ex["scroll_left"] = ex.get("scroll_left", 0.0) - v.length() * dt
		if ex["scroll_left"] <= 0.0:
			w.shot.used["side_scroll"] = true
			s.vel = v.rotated(PI / 2.0 * s.prop_side)
			_ev(w, s.owner, "side_scroll", s.pos)


## 시간 정지 중인 알은 움직이지도, 부딪히지도 않는다.
static func is_frozen(w, s) -> bool:
	if w.shot == null:
		return false
	var ex = _ex(w)
	if ex.has("orbit") and (int(ex["orbit"]["id"]) == s.id or int(ex["orbit"]["me"]) == s.id):
		return true
	return ex.get("frozen", {}).has(s.id)


## 궤도 마법 길: 표식 알은 옆으로 4칸(호), 내 알은 앞으로 1.1칸 뛴다. side 1 = 왼쪽, -1 = 오른쪽
const ORBIT_CELLS := 4.0
static func orbit_plan(me: Vector2, tpos: Vector2, dir: Vector2, side: int) -> Dictionary:
	var sv: Vector2 = Vector2(dir.y, -dir.x) if side > 0 else Vector2(-dir.y, dir.x)
	var land: Vector2 = tpos + sv * ORBIT_CELLS * 2.0 * R
	var ctrl: Vector2 = tpos + dir * 0.77 * 2.0 * R + sv * 0.68 * 2.0 * R
	var off: Vector2 = tpos - me
	var contact: Vector2 = me + dir * maxf(0.0, off.dot(dir) - sqrt(maxf(0.0, 4.0 * R * R - pow(off.cross(dir), 2.0))))
	return {"land": land, "ctrl": ctrl, "contact": contact, "me_land": contact + dir * 1.1 * 2.0 * R}


static func _qb(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


static func friction_scale(w, p: Vector2) -> float:
	for d in w.devices:
		if d.kind == "ice":
			var off: Vector2 = p - d.pos
			if off.length() <= d.length and off.length() > 0.1:
				if off.normalized().dot(d.dir) >= cos(deg_to_rad(D.num("ice_fan", "spread_deg") * 0.5)):
					return D.num("ice_fan", "friction")
	return 1.0


# ── 지연 효과와 시간 정지 ───────────────────────────────

static func timers(w, dt: float) -> void:
	if w.shot == null:
		return
	var ex = _ex(w)
	var s = w.shooter()
	if ex.has("orbit"):
		var ob: Dictionary = ex["orbit"]
		ob["t"] = float(ob["t"]) + dt
		var tt = w.get_stone(int(ob["id"]))
		var me = w.get_stone(int(ob["me"]))
		var k := 1.0 - pow(1.0 - minf(1.0, float(ob["t"]) / 0.6), 3.0)
		var km := 1.0 - pow(1.0 - minf(1.0, float(ob["t"]) / 0.5), 3.0)
		if tt != null and tt.alive:
			tt.pos = _qb(ob["a"], ob["c"], ob["b"], k)
			tt.vel = Vector2.ZERO
		if me != null and me.alive:
			me.pos = (ob["ma"] as Vector2).lerp(ob["mb"], km)
			me.vel = Vector2.ZERO
		if float(ob["t"]) >= 0.6:
			ex.erase("orbit")
			w.emit({"t": "magic_circle", "pos": ob["b"], "owner": me.owner if me != null else -1})
	if ex.has("beam_timer"):
		ex["beam_timer"] -= dt
		if ex["beam_timer"] <= 0.0:
			ex.erase("beam_timer")
			if s != null and s.alive:
				_beam(w, s)
	if ex.has("echo"):
		ex["echo"]["t"] -= dt
		if ex["echo"]["t"] <= 0.0:
			var e: Dictionary = ex["echo"]
			ex.erase("echo")
			var rr = D.num("echo_bell", "radius")
			for o in w.stones:
				if not o.alive:
					continue
				var off: Vector2 = o.pos - e["pos"]
				var dist = off.length()
				if dist < rr and dist > 0.5:
					o.vel += off / dist * D.num("echo_bell", "power") * (1.0 - dist / rr * 0.6)
			w.emit({"t": "ripple", "pos": e["pos"], "owner": e["owner"], "radius": rr})
			if e.get("again", false):
				# ★ 충격파가 두 번 퍼진다
				ex["echo"] = {"t": D.num("echo_bell", "delay"), "pos": e["pos"], "owner": e["owner"], "again": false}
	if ex.has("freeze_t"):
		ex["freeze_t"] -= dt
		if ex["freeze_t"] <= 0.0:
			for id in ex["frozen"]:
				var o = w.get_stone(id)
				if o != null and o.alive:
					o.vel = ex["frozen"][id]
			ex.erase("freeze_t")
			ex["frozen"] = {}


static func _beam(w, s) -> void:
	var dir: Vector2 = w.shot.dir
	var start: Vector2 = s.pos + dir * (R + 4.0)
	var length: float = w.ray_to_edge(start, dir)
	for o in w.stones:
		if not o.alive or o.id == s.id:
			continue
		var off: Vector2 = o.pos - start
		var along = off.dot(dir)
		if along > 0.0 and along < length and absf(off.cross(dir)) < R + D.num("charge_palm", "width") * 0.5:
			o.vel += dir * D.num("charge_palm", "power")
	w.emit({"t": "beam", "a": start, "b": start + dir * length, "owner": s.owner})
	_ev(w, s.owner, "charge_palm", start, {"stone": s.id})


static func busy(w) -> bool:
	if w.shot == null:
		return false
	var ex = _ex(w)
	return ex.has("beam_timer") or ex.has("echo") or ex.has("freeze_t") or ex.get("retracing", false) or ex.has("orbit")


# ── 충돌 ─────────────────────────────────────────────────

## 정상 충돌 전에. true 를 돌려주면 이 충돌은 처리한 것으로 본다.
static func pre_collision(w, a, b, nrm: Vector2) -> bool:
	if w.shot == null:
		return false
	# 통나무 대역: 이 알은 옆 빈자리로 빠지고, 부딪힌 알은 통나무에 맞고 튕긴다.
	for pair in [[a, b, nrm], [b, a, -nrm]]:
		var me = pair[0]
		var other = pair[1]
		var n: Vector2 = pair[2]
		if me.parts["aux"] != "log_sub" or w.shot.used.has("log_sub:%d" % me.id):
			continue
		var side = n.orthogonal()
		for sgn in [1.0, -1.0]:
			var spot: Vector2 = me.pos + side * sgn * (R * 2.0 + 6.0)
			if _free(w, spot, [me.id, other.id]):
				w.shot.used["log_sub:%d" % me.id] = true
				var log_pos: Vector2 = me.pos
				me.pos = spot
				var rel: Vector2 = other.vel - me.vel
				if rel.dot(n) < 0.0:
					other.vel = other.vel - 2.0 * other.vel.dot(n) * n * 0.9
				else:
					other.vel = other.vel - 2.0 * other.vel.dot(-n) * (-n) * 0.9
				if _up(me, "log_sub"):
					other.vel *= 1.4   # ★ 통나무가 더 세게 튕겨 낸다
				var dev = w.place_device("log", me.owner, me.id, log_pos, n, -1)
				dev.length = float(w.shot_no)
				_ev(w, me.owner, "log_sub", log_pos, {"stone": me.id})
				return true
	return false


## 충돌 직후 (발사한 알이 아닌 두 알 사이 포함).
static func post_collision(w, a, b, point: Vector2) -> void:
	if w.shot == null:
		return
	var ex = _ex(w)
	var s = w.shooter()
	if s == null or not s.alive:
		return
	# 리바운드 운동화: 내가 맞힌 알이 다른 알과 부딪히면 그쪽으로 뛰어든다.
	var ft: int = ex.get("first_target", -1)
	if ft >= 0 and s.parts["prop"] == "rebound_shoes" and not w.shot.used.has("rebound_shoes"):
		if (a.id == ft and b.id != s.id) or (b.id == ft and a.id != s.id):
			w.shot.used["rebound_shoes"] = true
			s.vel = (point - s.pos).normalized() * _nu(s, "rebound_shoes", "power")
			_ev(w, s.owner, "rebound_shoes", s.pos, {"stone": s.id})


## 발사한 알의 충돌. parts.gd on_contact 에서 부른다.
static func on_contact(w, s, t, n: Vector2, v_before: Vector2, t_before: Vector2, first: bool, frontal: bool, side_hit: bool) -> bool:
	var ex = _ex(w)
	var ctx = w.shot
	var opp: bool = t.owner != s.owner
	var dir: Vector2 = ctx.dir
	var contact: Vector2 = s.pos + n * R
	if first:
		ex["first_target"] = t.id
	# 달그림자 마도사 「궤도 마법」: 표식 대상과의 첫 충돌.
	if first and opp and D.set_complete(s.parts, "moon") and ex.get("marks", {}).has(t.id) and not ctx.used.has("moon_set"):
		for k in ["moon_set", "moon_staff_push", "star_cloak", "moon_boots"]:
			ctx.used[k] = true
		# 바뀐 규칙: 표식 알은 고른 쪽(왼쪽 · 오른쪽)으로 정확히 4칸 떨어진 자리까지 호를 그리며 날아가고, 내 알은 앞으로 뛰어 착지한다.
		var orb := orbit_plan(s.pos, t.pos, dir, int(ctx.ex.get("orbit_side", 1)))
		ex["orbit"] = {"id": t.id, "a": t.pos, "c": orb["ctrl"], "b": orb["land"], "t": 0.0, "me": s.id, "ma": s.pos, "mb": orb["me_land"]}
		t.vel = Vector2.ZERO
		s.vel = Vector2.ZERO
		if w.record_events:
			t.cause = {"owner": s.owner, "part": "moon_set"}
		w.emit({"t": "part", "part": "moon_set", "pos": contact, "owner": s.owner, "text": "궤도 마법", "big": true})
		w.emit({"t": "magic_circle", "pos": contact, "owner": s.owner})
		return true
	match s.parts["weapon"]:
		"moon_staff":
			if ex.get("marks", {}).has(t.id) and _use(w, "moon_staff_push"):
				t.vel += n * D.num("moon_staff", "power")
				_ev(w, s.owner, "moon_staff", contact, {"text": "표식 강타"})
		"ice_fan":
			if first and _use(w, "ice_fan"):
				var dv = w.place_device("ice", s.owner, s.id, contact, dir, -1)
				dv.length = D.num("ice_fan", "radius")
				dv.expires_shot = w.shot_no + 1
				_ev(w, s.owner, "ice_fan", contact)
		"shadow_scissors":
			if opp and _use(w, "shadow_scissors"):
				for slot in D.SLOTS:
					if t.parts[slot] != "":
						t.status["sealed"] = slot
						_ev(w, s.owner, "shadow_scissors", t.pos, {"text": "%s 봉인" % D.part_name(t.parts[slot])})
						break
		"alchemy_glove":
			if first and _use(w, "alchemy_glove"):
				var wp: Vector2 = contact + dir * D.num("alchemy_glove", "ahead")
				if w.is_inside(wp):
					var dv2 = w.place_device("wall", s.owner, s.id, wp, -dir, -1)
					dv2.length = D.num("alchemy_glove", "half_len")
					dv2.expires_shot = w.shot_no
					if _up(s, "alchemy_glove"):
						# ★ 돌벽 두 개: 옆으로 나란히 하나 더
						var wp2: Vector2 = wp + dir.orthogonal() * D.num("alchemy_glove", "half_len") * 2.2
						if w.is_inside(wp2):
							var dv3 = w.place_device("wall", s.owner, s.id, wp2, -dir, -1)
							dv3.length = D.num("alchemy_glove", "half_len")
							dv3.expires_shot = w.shot_no
					_ev(w, s.owner, "alchemy_glove", wp, {"stone": s.id})
		"echo_bell":
			if first and _use(w, "echo_bell"):
				ex["echo"] = {"t": D.num("echo_bell", "delay"), "pos": contact, "owner": s.owner, "again": _up(s, "echo_bell")}
				_ev(w, s.owner, "echo_bell", contact)
		"string_doll":
			if opp and _use(w, "string_doll"):
				var u = _nearest(w, t.pos, [s.id, t.id], D.num("string_doll", "range"))
				if u != null:
					ex["link"] = {"a": t.id, "b": u.id, "len": t.pos.distance_to(u.pos) + D.num("string_doll", "slack")}
					w.emit({"t": "thread", "a": t.pos, "b": u.pos, "owner": s.owner})
					_ev(w, s.owner, "string_doll", t.pos)
		"night_charm":
			if opp and _use(w, "night_charm"):
				t.status["cursed"] = s.owner
				t.status["cursed_up"] = _up(s, "night_charm")
				_ev(w, s.owner, "night_charm", t.pos, {"text": "저주"})
	match s.parts["aux"]:
		"star_cloak":
			if first and _use(w, "star_cloak"):
				w.place_device("circle", s.owner, s.id, contact, Vector2.RIGHT, w.round_no + int(D.num("star_cloak", "rounds")))
				_ev(w, s.owner, "star_cloak", contact)
		"stopwatch":
			if first and _use(w, "stopwatch"):
				var frozen = {}
				for o in w.stones:
					if o.alive and o.id != s.id and o.vel.length() > 20.0 and o.pos.distance_to(contact) < D.num("stopwatch", "radius"):
						frozen[o.id] = o.vel
						o.vel = Vector2.ZERO
				if not frozen.is_empty():
					ex["frozen"] = frozen
					ex["freeze_t"] = _nu(s, "stopwatch", "time")
				_ev(w, s.owner, "stopwatch", contact, {"stone": s.id})
		"mushroom":
			if first and _use(w, "mushroom"):
				var side = dir.orthogonal()
				for sgn in [1.0, -1.0]:
					var mp: Vector2 = contact + side * sgn * (R * 2.0 + 10.0)
					if _free(w, mp, []):
						var dv3 = w.place_device("mushroom", s.owner, s.id * 10 + (1 if sgn > 0 else 0), mp, Vector2.RIGHT, w.round_no)
						dv3.length = 0.0
				_ev(w, s.owner, "mushroom", contact)
		"shadow_scale":
			if _use(w, "shadow_scale"):
				var u2 = _nearest(w, t.pos, [s.id, t.id], D.num("shadow_scale", "range"))
				if u2 != null:
					var imp: Vector2 = t.vel - t_before
					var part: Vector2 = imp * _nu(s, "shadow_scale", "share")
					t.vel -= part
					u2.vel += part
					w.emit({"t": "line_fx", "a": t.pos, "b": u2.pos, "owner": s.owner})
					_ev(w, s.owner, "shadow_scale", u2.pos)
		"moon_well":
			if first and _use(w, "moon_well"):
				var wdev = w.place_device("well", s.owner, s.id, contact, Vector2.RIGHT, w.round_no + int(D.num("moon_well", "rounds")))
				if _up(s, "moon_well"):
					wdev.scale = 1.5   # ★ 지름 1.5배
				_ev(w, s.owner, "moon_well", contact)
	if first:
		match s.parts["prop"]:
			"moon_boots":
				if _use(w, "moon_boots"):
					_leap(w, s, false)
			"awaken_shoes":
				pass   # 투지 돌진은 hero.gd
			"edge_sewer":
				if _use(w, "edge_sewer"):
					_place_net(w, s, contact)
	return false


static func _nearest(w, p: Vector2, ignore: Array, range_len: float):
	var best = null
	var bd = range_len
	for o in w.stones:
		if o.alive and not ignore.has(o.id) and o.pos.distance_to(p) < bd:
			bd = o.pos.distance_to(p)
			best = o
	return best


## 월광 장화: 조준 방향으로 짧게 도약 (다른 알을 넘어 착지 자리가 비었을 때만).
static func _leap(w, s, forced: bool) -> void:
	var dir: Vector2 = w.shot.dir
	var spot: Vector2 = s.pos + dir * D.num("moon_boots", "dist")
	if _free(w, spot, [s.id]):
		var from: Vector2 = s.pos
		s.pos = spot
		s.vel = dir * D.num("moon_boots", "speed")
		_ev(w, s.owner, "moon_boots", spot, {"from": from, "text": "도약"})
	elif not forced:
		w.emit({"t": "part", "part": "moon_boots", "pos": s.pos, "owner": s.owner, "text": "착지 자리 없음"})


## 판끝 재봉틀: 첫 충돌 지점에서 가장 가까운 판 끝에 안전망.
static func _place_net(w, s, contact: Vector2) -> void:
	var nrm: Vector2 = w.outward(contact)
	var edge_pt: Vector2
	if w.shape == "circle":
		edge_pt = nrm * w.size
	else:
		edge_pt = contact + nrm * w.edge_distance(contact)
	var dv = w.place_device("net", s.owner, s.id, edge_pt, nrm, w.round_no)
	dv.length = D.num("edge_sewer", "half_len")
	_ev(w, s.owner, "edge_sewer", edge_pt)


# ── 탄 ───────────────────────────────────────────────────

static func handles(kind: String) -> bool:
	return kind in ["orb", "fist", "ink", "ink2"]


static func update_proj(w, p, dt: float) -> void:
	match p.kind:
		"orb":
			# 빛 구슬: 알을 통과하며 표식만 남긴다.
			for o in w.stones:
				if o.alive and o.id != p.ignore_id and o.pos.distance_to(p.pos) < R + p.radius:
					var marks: Dictionary = _ex(w).get("marks", {})
					if not marks.has(o.id):
						marks[o.id] = true
						_ex(w)["marks"] = marks
						w.emit({"t": "mark", "pos": o.pos, "owner": p.owner, "stone": o.id})
		"fist":
			var s = w.get_stone(p.ignore_id)
			if s == null or not s.alive:
				p.alive = false
				return
			if p.source == "fist":
				for o in w.stones:
					if o.alive and o.id != s.id and o.pos.distance_to(p.pos) < R + p.radius:
						o.vel += p.vel.normalized() * D.num("rubber_fist", "power")
						p.source = "back"
						p.power = float(o.id)
						w.emit({"t": "hit", "pos": p.pos, "strength": 600.0})
						break
				if p.travelled >= D.num("rubber_fist", "reach"):
					p.source = "back"
					p.power = -1.0
			else:
				var to: Vector2 = s.pos - p.pos
				if to.length() < R + 6.0:
					p.alive = false
					return
				p.vel = to.normalized() * D.num("rubber_fist", "speed")
				for o in w.stones:
					if o.alive and o.id != s.id and o.id != int(p.power) and o.pos.distance_to(p.pos) < R + p.radius:
						o.vel += (s.pos - o.pos).normalized() * D.num("rubber_fist", "pull")
						p.alive = false
						w.emit({"t": "part", "part": "rubber_fist", "pos": o.pos, "owner": p.owner, "text": "끌어당김"})
						return
		"ink":
			for o in w.stones:
				if o.alive and o.id != p.ignore_id and o.pos.distance_to(p.pos) < R + p.radius:
					p.alive = false
					var d: Vector2 = p.vel.normalized()
					for sgn in [1.0, -1.0]:
						var side: Vector2 = d.orthogonal() * sgn
						w.spawn_proj("ink2", p.owner, o.pos + side * (R + 8.0), side, D.num("ink_drop", "split_speed"), 6.0, D.num("ink_drop", "power"), o.id)
					w.emit({"t": "splat", "pos": p.pos, "owner": p.owner})
					return
		"ink2":
			if p.travelled > D.num("ink_drop", "split_dist"):
				p.alive = false
				return
			for o in w.stones:
				if o.alive and o.id != p.ignore_id and o.pos.distance_to(p.pos) < R + p.radius:
					o.vel += p.vel.normalized() * p.power
					p.alive = false
					return


# ── 장치 ─────────────────────────────────────────────────

static func check_devices(w) -> void:
	for d in w.devices.duplicate():
		match d.kind:
			"circle", "card", "mushroom", "wind", "well":
				_touch_device(w, d)
			"wall":
				_wall(w, d)


static func device_radius(d) -> float:
	match d.kind:
		"circle":
			return D.num("star_cloak", "radius")
		"card":
			return D.num("trap_card", "radius")
		"mushroom":
			return D.num("mushroom", "radius")
		"wind":
			return D.num("wind_knot", "radius")
		"well":
			return D.num("moon_well", "radius") * d.scale
	return 0.0


static func _touch_device(w, d) -> void:
	if not d.armed:
		return
	var r = R + device_radius(d)
	if d.kind == "well":
		r = device_radius(d)
	var entering = null
	var now = {}
	for s in w.stones:
		if not s.alive:
			continue
		if s.pos.distance_to(d.pos) < r:
			now[s.id] = true
			if not d.inside.has(s.id) and entering == null and s.vel.length() > 20.0:
				entering = s
	# 달빛 우물: 들어온 알이 빠져나갈 때 한 번 민다.
	if d.kind == "well" and d.length > 0.5:
		var who = int(d.length) - 1
		if not now.has(who):
			var o = w.get_stone(who)
			if o != null and o.alive and o.vel != Vector2.ZERO:
				o.vel += o.vel.normalized() * D.num("moon_well", "power")
			w.emit({"t": "part", "part": "moon_well", "pos": d.pos, "owner": d.owner, "text": "달빛 밀기"})
			w.devices.erase(d)
			return
	d.inside = now
	if entering == null:
		return
	var s = entering
	match d.kind:
		"circle":
			var radial: Vector2 = (s.pos - d.pos).normalized()
			var tan = radial.orthogonal()
			if tan.dot(s.vel) < 0.0:
				tan = -tan
			s.vel = tan * (maxf(s.vel.length(), 260.0) * 0.6 + D.num("star_cloak", "power"))
			w.emit({"t": "magic_circle", "pos": d.pos, "owner": d.owner})
			w.emit({"t": "part", "part": "star_cloak", "pos": d.pos, "owner": d.owner, "text": "마법진"})
			w.devices.erase(d)
		"card":
			s.vel = -s.vel * 0.9
			if d.scale >= 2.0:
				s.status["slow"] = w.round_no + 1   # ★ 1바퀴 동안 느리게
			_ev(w, d.owner, "trap_card", d.pos, {"text": "함정 발동"})
			w.devices.erase(d)
		"mushroom":
			var away: Vector2 = (s.pos - d.pos).normalized()
			s.vel = away * (s.vel.length() * 0.5 + D.num("mushroom", "power"))
			w.emit({"t": "part", "part": "mushroom", "pos": d.pos, "owner": d.owner, "text": "통!"})
			w.devices.erase(d)
		"wind":
			var cur = s.vel.angle()
			var diff = wrapf(d.dir.angle() - cur, -PI, PI)
			var turn = deg_to_rad(D.num("wind_knot", "turn_deg") * d.scale)
			s.vel = s.vel.rotated(clampf(diff, -turn, turn))
			w.emit({"t": "part", "part": "wind_knot", "pos": d.pos, "owner": d.owner, "text": "바람"})
			w.devices.erase(d)
		"well":
			s.vel *= D.num("moon_well", "slow")
			d.length = float(s.id + 1)
			w.emit({"t": "part", "part": "moon_well", "pos": d.pos, "owner": d.owner, "text": "달빛 우물"})


## 연금 장갑의 돌벽: 이번 샷 동안 알을 튕겨낸다.
static func _wall(w, d) -> void:
	var along: Vector2 = d.dir.orthogonal()
	for s in w.stones:
		if not s.alive or s.vel == Vector2.ZERO:
			continue
		var off: Vector2 = s.pos - d.pos
		var a = off.dot(along)
		if absf(a) > d.length + R * 0.5:
			continue
		var dist = off.dot(d.dir)
		if absf(dist) < R + 4.0:
			var n: Vector2 = d.dir if dist >= 0.0 else -d.dir
			if s.vel.dot(n) < 0.0:
				s.vel = (s.vel - 2.0 * s.vel.dot(n) * n) * 0.9
				s.pos = d.pos + along * a + n * (R + 4.0)
				w.emit({"t": "hit", "pos": d.pos + along * a, "strength": 400.0})


## 장치를 다음 샷부터 켠다 (발사 때 부름).
static func arm_devices(w) -> void:
	for d in w.devices:
		if d.kind in ["circle", "card", "mushroom", "wind", "well"] and not d.armed:
			d.armed = true
			d.inside = {}
			var r = R + device_radius(d)
			if d.kind == "well":
				r = device_radius(d)
			for o in w.stones:
				if o.alive and o.pos.distance_to(d.pos) < r:
					d.inside[o.id] = true


# ── 판 끝 ────────────────────────────────────────────────

## 판 밖으로 나가려는 알을 붙잡는다: 안전망, 유리 날개, 배수로 타이어. 붙잡았으면 true.
static func save_from_edge(w, s) -> bool:
	var nrm: Vector2 = w.outward(s.pos)
	var vh: Vector2 = s.vel.normalized() if s.vel != Vector2.ZERO else nrm
	var cosv = vh.dot(nrm)
	var inside_pt: Vector2 = s.pos - nrm * (w.edge_distance(s.pos) * -1.0 + 3.0) if w.edge_distance(s.pos) < 0.0 else s.pos - nrm * 3.0
	# 판끝 재봉틀 안전망
	for d in w.devices:
		if d.kind != "net":
			continue
		var off: Vector2 = s.pos - d.pos
		var along: float = off.dot(d.dir.orthogonal())
		if absf(along) <= d.length and off.dot(d.dir) > -R:
			s.pos = inside_pt
			s.vel = (s.vel - 2.0 * s.vel.dot(nrm) * nrm) * 0.8
			w.emit({"t": "part", "part": "edge_sewer", "pos": s.pos, "owner": d.owner, "text": "안전망"})
			w.devices.erase(d)
			return true
	if w.shot == null:
		return false
	# 유리 날개
	if s.parts["prop"] == "glass_wings" and not w.shot.used.has("glass:%d" % s.id):
		w.shot.used["glass:%d" % s.id] = true
		if cosv < D.num("glass_wings", "max_cos"):
			s.pos = inside_pt
			s.vel = (s.vel - 2.0 * s.vel.dot(nrm) * nrm) * D.num("glass_wings", "keep")
			w.emit({"t": "part", "part": "glass_wings", "pos": s.pos, "owner": s.owner, "text": "유리 날개"})
			return true
		w.emit({"t": "part", "part": "glass_wings", "pos": s.pos, "owner": s.owner, "text": "날개가 깨졌다"})
	# 배수로 타이어: 비스듬히 넘으면 경계를 타고 달린다.
	if s.parts["prop"] == "drift_tire" and not w.shot.used.has("drift:%d" % s.id) and cosv < D.num("drift_tire", "max_cos"):
		w.shot.used["drift:%d" % s.id] = true
		var tan: Vector2 = s.vel - s.vel.dot(nrm) * nrm
		s.pos = inside_pt - nrm * 4.0
		s.vel = tan * (1.35 if _up(s, "drift_tire") else 0.95)
		_ev(w, s.owner, "drift_tire", s.pos, {"stone": s.id})
		return true
	return false


## 알이 떨어진 직후: 찢어진 망토·라스트 컷, 유품 리본.
static func on_out(w, s) -> void:
	if s.parts["aux"] == "relic_ribbon":
		for slot in ["weapon", "prop"]:
			if s.parts[slot] != "":
				w.relics.append({"owner": s.owner, "part": s.parts[slot]})
				w.emit({"t": "part", "part": "relic_ribbon", "pos": s.pos, "owner": s.owner, "text": "%s 회수" % D.part_name(s.parts[slot])})
				break
	if w.shot == null:
		return
	var me = w.shooter()
	if me == null or not me.alive or s.owner == me.owner:
		return
	# 찢어진 망토 · 라스트 컷은 hero.gd (투지)


# ── 이동 뒤 ──────────────────────────────────────────────

static func after_step(w) -> void:
	if w.shot == null:
		return
	var ex = _ex(w)
	var s = w.shooter()
	# 실매듭 인형: 둘이 많이 벌어지면 뒤처진 알을 한 번 끌어당긴다.
	if ex.has("link"):
		var a = w.get_stone(ex["link"]["a"])
		var b = w.get_stone(ex["link"]["b"])
		if a == null or b == null or not a.alive or not b.alive:
			ex.erase("link")
		elif a.pos.distance_to(b.pos) > ex["link"]["len"]:
			var lag = a if a.vel.length() < b.vel.length() else b
			var lead = b if lag == a else a
			lag.vel += (lead.pos - lag.pos).normalized() * D.num("string_doll", "power")
			w.emit({"t": "thread", "a": a.pos, "b": b.pos, "owner": w.shot.owner})
			w.emit({"t": "part", "part": "string_doll", "pos": lag.pos, "owner": w.shot.owner, "text": "실 당김"})
			ex.erase("link")
	# 두 번째 발자국: 처음 멈추면 지나온 길을 되짚는다.
	if s != null and s.alive and s.parts["prop"] == "second_step":
		if ex.get("retracing", false):
			if s.vel == Vector2.ZERO:
				ex["retracing"] = false
		elif s.vel == Vector2.ZERO and not w.shot.used.has("second_step") and w.shot.path.size() >= 2:
			w.shot.used["second_step"] = true
			var back: Vector2 = (w.shot.path[maxi(0, w.shot.path.size() - 4)] - s.pos)
			if back.length() < 1.0:
				back = -w.shot.dir
			s.vel = back.normalized() * D.num("second_step", "speed")
			ex["retracing"] = true
			_ev(w, s.owner, "second_step", s.pos)


## 되짚는 중에 처음 닿은 알을 밀고 멈춘다 (parts.gd 충돌에서).
static func retrace_hit(w, s) -> void:
	if w.shot != null and _ex(w).get("retracing", false):
		s.vel = Vector2.ZERO
		_ex(w)["retracing"] = false


# ── 샷 끝 ────────────────────────────────────────────────

static func on_end(w, s) -> void:
	var ex = _ex(w)
	if ex.has("sealed") and s != null:
		s.parts[ex["sealed"][0]] = ex["sealed"][1]
	if s != null and s.alive:
		# 약속의 닻: 출발점이 비어 있으면 돌아온다.
		if s.parts["prop"] == "anchor":
			if _free(w, w.shot.start, [s.id]):
				var from: Vector2 = s.pos
				s.pos = w.shot.start
				w.emit({"t": "part", "part": "anchor", "pos": s.pos, "owner": s.owner, "text": "약속의 닻", "from": from})
				if _up(s, "anchor"):
					# ★ 돌아온 자리 주변 알을 밀어낸다
					for o in w.stones:
						if o.alive and o.id != s.id and o.pos.distance_to(s.pos) < R * 2.0 + 44.0:
							o.vel += (o.pos - s.pos).normalized() * 300.0
			else:
				w.emit({"t": "part", "part": "anchor", "pos": s.pos, "owner": s.owner, "text": "출발점이 막힘"})
		match s.parts["aux"]:
			"trap_card":
				var cdev = w.place_device("card", s.owner, s.id, s.pos, Vector2.RIGHT, w.round_no)
				if _up(s, "trap_card"):
					cdev.scale = 2.0
				_ev(w, s.owner, "trap_card", s.pos, {"stone": s.id, "text": "카드 설치"})
			"wind_knot":
				var path: Array = w.shot.path
				var dir: Vector2 = w.shot.dir
				if path.size() >= 2:
					var v: Vector2 = path[path.size() - 1] - path[maxi(0, path.size() - 4)]
					if v.length() > 1.0:
						dir = v.normalized()
				var wnd = w.place_device("wind", s.owner, s.id, s.pos, dir, w.round_no + int(D.num("wind_knot", "rounds")))
				if _up(s, "wind_knot"):
					wnd.scale = 1.6
				w.emit({"t": "part", "part": "wind_knot", "pos": s.pos, "owner": s.owner, "text": "바람 매듭"})
		if s.parts["prop"] == "cloud_mailbox":
			w.place_device("cloud", s.owner, s.id, s.pos, Vector2.RIGHT, -1)
			w.emit({"t": "part", "part": "cloud_mailbox", "pos": s.pos, "owner": s.owner, "text": "구름 표식"})
	# 이번 샷까지인 장치(돌벽, 통나무)와 기한이 지난 얼음
	for d in w.devices.duplicate():
		if d.kind == "log":
			w.devices.erase(d)
		elif d.expires_shot >= 0 and d.expires_shot <= w.shot_no:
			w.devices.erase(d)



# ── 강화(★) 도우미 (parts.gd 와 같은 규칙) ──
static func _up(s, part: String) -> bool:
	if s == null or part == "":
		return false
	var slot := D.slot_of(part)
	return s.ups.get(slot, false) and s.parts.get(slot, "") == part


static func _nu(s, part: String, key: String) -> float:
	var v := D.num(part, key)
	if _up(s, part):
		v *= float(D.UP_NUM.get(part, {}).get(key, 1.0))
	return v


static func _scroll_dist(s, power: float) -> float:
	if _up(s, "side_scroll"):
		return lerpf(2.0, 8.0, clampf(power, 0.0, 1.0)) * 44.0
	return D.num("side_scroll", "dist")
