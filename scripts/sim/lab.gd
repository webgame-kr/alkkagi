extends RefCounted
## 엉뚱한 발명 연구소 (확장 기획 「새 공방」): 알의 크기·무게·개수·주인을 바꾸는 규칙 파괴 부품과 연구소 기믹.
## 알 크기·무게는 Stone.base_size / base_mass 와 잠시 붙는 mods 로 계산한다 (world.size_of / mass_of).

const D = preload("res://scripts/sim/parts_data.gd")
const CELL := 44.0
const TIME_K := 2.5
const R := 22.0

const TILT_SPEED := 0.8 * CELL * TIME_K
const TILT_TIME := 1.2
const COUPLE_LEN := 3.0 * CELL
const SHRINK_RANGE := 9.0 * CELL


# ── 발사 순간 ────────────────────────────────────────────

static func on_launch(w, s) -> void:
	var dir: Vector2 = w.shot.dir
	match s.parts["weapon"]:
		"shrink_ray":
			if _use(w, "shrink_ray"):
				var t = _first_on_ray(w, s.pos, dir, SHRINK_RANGE, s.id)
				var end: Vector2 = s.pos + dir * SHRINK_RANGE
				if t != null:
					end = t.pos
					# 다음 바퀴가 끝날 때까지 지름 0.7배, 무게 0.5배
					t.mods["shrink"] = {"size": 0.7, "mass": 0.5, "until": w.round_no + 1}
					_mark(w, t, "shrink_ray")
				w.emit({"t": "beam", "a": s.pos + dir * (R + 6.0), "b": end, "owner": s.owner, "part": "shrink_ray"})
				_ev(w, s, "shrink_ray", end, {"text": "축소 광선"})
		"tilter":
			if _use(w, "tilter"):
				w.shot.ex["tilt"] = {"dir": dir, "t": TILT_TIME}
				_ev(w, s, "tilter", s.pos, {"text": "판 기울이개", "big": true})
		"sticky":
			if _use(w, "sticky"):
				w.spawn_bullet(s.owner, s.pos + dir * (R + 7.0), dir, D.num("sticky", "power"), "weapon", s.id)
				_ev(w, s, "sticky", s.pos + dir * (R + 7.0))
		"remote":
			pass   # 리모컨은 조준 단계에서 처리 (match.shoot)
	if s.parts["aux"] == "repel" and _use(w, "repel"):
		s.mods["repel"] = {"size": 1.0, "mass": 1.0, "until": w.round_no + 1}
		_ev(w, s, "repel", s.pos, {"text": "반발 코팅"})
	if s.parts["prop"] == "ghost" and _use(w, "ghost"):
		w.shot.ex["ghost"] = s.id
		_ev(w, s, "ghost", s.pos, {"text": "유령 장치"})


# ── 충돌 ─────────────────────────────────────────────────

## 이 두 알은 서로 부딪히지 않는다 (유령 장치, 끈끈이로 붙은 한 덩어리).
static func skip_pair(w, a, b) -> bool:
	if w.shot != null:
		var gid: int = int(w.shot.ex.get("ghost", -1))
		if gid >= 0 and ((a.id == gid and b.owner != a.owner) or (b.id == gid and a.owner != b.owner)):
			return true
	for g in w.glue:
		if (g["a"] == a.id and g["b"] == b.id) or (g["a"] == b.id and g["b"] == a.id):
			return true
	return false


## 충돌 직후 (모든 알 사이): 반발 코팅은 부딪힌 알을 2배로 튕긴다.
static func post_collision(w, a, b, nrm: Vector2, imp: float) -> void:
	if a.mods.has("repel"):
		b.vel += nrm * imp / w.mass_of(b)
	if b.mods.has("repel"):
		a.vel -= nrm * imp / w.mass_of(a)


## 쏜 알이 다른 알에 닿았을 때. true 면 이 충돌의 나머지 처리는 건너뛴다.
static func on_contact(w, s, t, n: Vector2, first: bool) -> bool:
	var ctx = w.shot
	# 합체 볼트: 내 다른 알과 부딪히면 하나로
	if s.parts["aux"] == "merge_bolt" and t.owner == s.owner and not s.mods.has("piece") and not t.mods.has("piece") \
			and not ctx.used.has("merge_bolt") and s.base_size < 1.3 and t.base_size < 1.3:
		ctx.used["merge_bolt"] = 1
		var ms: float = w.mass_of(s)
		var mt: float = w.mass_of(t)
		s.vel = (s.vel * ms + t.vel * mt) / (ms + mt)
		s.pos = (s.pos * ms + t.pos * mt) / (ms + mt)
		for slot in ["weapon", "aux", "prop"]:
			if s.parts[slot] == "" and t.parts[slot] != "":
				s.parts[slot] = t.parts[slot]
		s.base_size = 1.4
		s.base_mass = 2.0
		s.mods["merged"] = {"size": 1.0, "mass": 1.0, "until": 999999}
		t.alive = false
		t.vel = Vector2.ZERO
		w.emit({"t": "merge", "pos": s.pos, "owner": s.owner, "stone": t.id, "into": s.id})
		_ev(w, s, "merge_bolt", s.pos, {"text": "합체!", "big": true})
		return true
	if not first:
		return false
	# 분열 캡슐: 첫 충돌 직후 작은 알 둘로 (판마다 한 번)
	if s.parts["prop"] == "split_capsule" and not s.mods.has("split_done") and not s.mods.has("piece") and not s.mods.has("merged"):
		var v: Vector2 = s.vel
		var piece = w.add_stone(s.owner, s.pos + n.orthogonal() * R * 0.9, s.facing)
		s.pos -= n.orthogonal() * R * 0.9
		for st in [s, piece]:
			st.parts = {"weapon": "", "aux": "", "prop": ""}
			st.ups = {}
			st.base_size = 0.75
			st.base_mass = 0.5
			st.mods["piece"] = {"size": 1.0, "mass": 1.0, "until": 999999}
			st.mods["split_done"] = {"size": 1.0, "mass": 1.0, "until": 999999}
		s.vel = v.rotated(0.45)
		piece.vel = v.rotated(-0.45)
		w.emit({"t": "split", "pos": s.pos, "owner": s.owner, "stone": piece.id})
		_ev(w, s, "split_capsule", s.pos, {"text": "분열!", "big": true})
	# 팽창 풍선: 첫 충돌 직후 다음 바퀴가 끝날 때까지 지름 1.6배
	if s.parts["prop"] == "inflate" and _use(w, "inflate"):
		s.mods["inflate"] = {"size": 1.6, "mass": 1.3, "until": w.round_no + 1}
		_ev(w, s, "inflate", s.pos, {"text": "부풀기"})
	return false


## 끈끈이 탄에 맞은 상대: 다음 내 샷이 끝날 때까지 내 알과 한 덩어리.
static func on_bullet(w, target, p) -> bool:
	if w.shot == null:
		return false
	var src = w.get_stone(w.shot.stone_id)
	if src == null or src.parts["weapon"] != "sticky" or p.source != "weapon" or target.owner == src.owner:
		return false
	if w.shot.used.has("sticky_hit"):
		return false
	w.shot.used["sticky_hit"] = 1
	for g in w.glue:
		if g["b"] == target.id:
			return true
	var off: Vector2 = (target.pos - src.pos)
	off = off.normalized() * (w.radius_of(src) + w.radius_of(target)) if off.length() > 0.1 else Vector2.RIGHT * (w.radius_of(src) + w.radius_of(target))
	w.glue.append({"a": src.id, "b": target.id, "off": off, "owner": src.owner, "made": w.shot_no})
	_mark(w, target, "sticky")
	_ev(w, src, "sticky", target.pos, {"text": "철썩"})
	return true


# ── 이동 ─────────────────────────────────────────────────

static func before_move(w, dt: float) -> void:
	if w.shot == null:
		return
	var tilt = w.shot.ex.get("tilt", null)
	if tilt != null and float(tilt["t"]) > 0.0:
		tilt["t"] = float(tilt["t"]) - dt
		var dir: Vector2 = tilt["dir"]
		for s in w.stones:
			if not s.alive:
				continue
			var along: float = s.vel.dot(dir)
			if along < TILT_SPEED:
				s.vel += dir * (TILT_SPEED - along)
				_mark(w, s, "tilter")


## 이동 뒤: 끈끈이 덩어리와 자석 커플링 줄.
static func after_move(w) -> void:
	for g in w.glue:
		var a = w.get_stone(g["a"])
		var b = w.get_stone(g["b"])
		if a == null or b == null or not a.alive or not b.alive:
			continue
		var ma: float = w.mass_of(a)
		var mb: float = w.mass_of(b)
		var v: Vector2 = (a.vel * ma + b.vel * mb) / (ma + mb)
		var center: Vector2 = (a.pos * ma + (b.pos - g["off"]) * mb) / (ma + mb)
		a.pos = center
		b.pos = center + g["off"]
		a.vel = v
		b.vel = v
	# 자석 커플링: 같은 주인의 가장 가까운 알과 3칸 줄
	for s in w.stones:
		if not s.alive or s.parts["aux"] != "coupling":
			continue
		var best = null
		var bd := INF
		for o in w.stones:
			if o.alive and o.id != s.id and o.owner == s.owner:
				var d: float = o.pos.distance_to(s.pos)
				if d < bd:
					bd = d
					best = o
		if best == null or bd <= COUPLE_LEN:
			continue
		var dirv: Vector2 = (best.pos - s.pos) / bd
		var excess := bd - COUPLE_LEN
		var ms: float = w.mass_of(s)
		var mo: float = w.mass_of(best)
		s.pos += dirv * excess * mo / (ms + mo)
		best.pos -= dirv * excess * ms / (ms + mo)
		var rel: float = (best.vel - s.vel).dot(dirv)
		if rel > 0.0:
			s.vel += dirv * rel * mo / (ms + mo)
			best.vel -= dirv * rel * ms / (ms + mo)


## 쏜 알이 멈췄을 때: 유령 장치는 실체화하며 겹친 알을 밀쳐 내고, 미끼 풍선은 뒤에 풍선을 남긴다.
static func on_stop(w, s) -> void:
	if int(w.shot.ex.get("ghost", -1)) == s.id:
		w.shot.ex.erase("ghost")
		for o in w.stones:
			if not o.alive or o.id == s.id:
				continue
			var d: Vector2 = o.pos - s.pos
			var need: float = w.radius_of(s) + w.radius_of(o)
			if d.length() < need + 6.0:
				var nv: Vector2 = d.normalized() if d.length() > 0.5 else Vector2.RIGHT
				o.pos = s.pos + nv * (need + 1.0)
				o.vel += nv * 520.0
				_mark(w, o, "ghost")
		_ev(w, s, "ghost", s.pos, {"text": "실체화!", "big": true})
	if s.parts["aux"] == "decoy" and not w.shot.used.has("decoy"):
		w.shot.used["decoy"] = 1
		var back: Vector2 = -w.shot.dir
		var spot: Vector2 = s.pos + back * (w.radius_of(s) * 2.0 + 8.0)
		if w.is_inside(spot):
			var dev = w.place_device("decoy", s.owner, s.id, spot, Vector2.RIGHT, w.round_no + 1)
			dev.scale = w.radius_of(s) / R
			_ev(w, s, "decoy", spot, {"text": "미끼 풍선"})


## 샷이 끝났을 때: 끈끈이는 주인의 다음 샷이 끝나면 떨어진다.
static func end_shot(w) -> void:
	if w.shot == null:
		return
	var keep: Array = []
	for g in w.glue:
		if g["owner"] == w.shot.owner and w.shot_no > int(g["made"]):
			continue
		keep.append(g)
	w.glue = keep


## 미끼 풍선: 알처럼 서 있다가 맞으면 터지며 주변 1.5칸의 알을 민다.
static func check_decoys(w) -> void:
	for d in w.devices.duplicate():
		if d.kind != "decoy":
			continue
		var r: float = R * d.scale
		for s in w.stones:
			if not s.alive or s.vel == Vector2.ZERO:
				continue
			if s.pos.distance_to(d.pos) < r + w.radius_of(s):
				w.devices.erase(d)
				for o in w.stones:
					if o.alive and o.pos.distance_to(d.pos) < 1.5 * CELL + R:
						var off: Vector2 = o.pos - d.pos
						o.vel += (off.normalized() if off.length() > 0.5 else Vector2.UP) * 380.0
						_mark(w, o, "decoy")
				w.emit({"t": "boom", "pos": d.pos, "radius": 1.5 * CELL, "owner": d.owner})
				w.emit({"t": "part", "part": "decoy", "pos": d.pos, "owner": d.owner, "text": "펑! 미끼였다"})
				break


# ── 도우미 ───────────────────────────────────────────────

static func _use(w, key: String) -> bool:
	if w.shot.used.has(key):
		return false
	w.shot.used[key] = 1
	return true


static func _ev(w, s, part: String, pos: Vector2, extra := {}) -> void:
	var ev := {"t": "part", "part": part, "pos": pos, "owner": s.owner, "text": D.part_name(part)}
	ev.merge(extra, true)
	w.emit(ev)


static func _mark(w, s, part: String) -> void:
	if w.shot == null or not w.record_events or s.id == w.shot.stone_id:
		return
	s.cause = {"owner": w.shot.owner, "part": part}


static func _first_on_ray(w, from: Vector2, dir: Vector2, max_len: float, skip_id: int):
	var best = null
	var best_t := max_len
	for t in w.stones:
		if not t.alive or t.id == skip_id:
			continue
		var off: Vector2 = t.pos - from
		var along := off.dot(dir)
		if along <= 0.0 or along > best_t:
			continue
		if absf(off.cross(dir)) < w.radius_of(t) + 4.0:
			best_t = along
			best = t
	return best
