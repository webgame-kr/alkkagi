extends RefCounted
## 최후의 주인공 개편 (디자인 「최후의 주인공 · 투지와 라스트 컷」).
## 주인공 부품을 단 알은 「투지」(0~3)가 쌓인다. 세 칸이 차고 세트가 완성되면 라스트 컷.
##   상대 샷에 맞아 밀림 +1 · 내 다른 알이 떨어짐 +2 · 주인공 알이 마지막 알이 됨 → 바로 3 · 망토로 가장자리에서 버팀 +1
## 머리띠: 투지만큼 강한 정면 충격파(투지는 쓰지 않음). 망토: 판 밖으로 나갈 뻔하면 판마다 한 번 버팀(누구의 샷이든).
## 운동화: 첫 충돌 직후 투지 1칸을 써서 한 번 더 돌진.
## 라스트 컷: 판 끝까지 멈추지 않고 관통 돌진, 부딪힌 알은 옆으로, 판 끝에서 망토로 반드시 멈춘다.

const D = preload("res://scripts/sim/parts_data.gd")
const R := 22.0
const MAX_GRIT := 3


static func is_hero(s) -> bool:
	for slot in ["weapon", "aux", "prop"]:
		if D.set_of(s.parts.get(slot, "")) == "hero":
			return true
	return false


static func grit(s) -> int:
	return int(s.status.get("grit", 0))


static func add_grit(w, s, n: int, why: String) -> void:
	if s == null or not s.alive or not is_hero(s):
		return
	var before := grit(s)
	var after := mini(MAX_GRIT, before + n)
	if after == before:
		return
	s.status["grit"] = after
	if w.record_events:
		w.emit({"t": "grit", "pos": s.pos, "owner": s.owner, "stone": s.id, "grit": after, "text": why})


static func lastcut_ready(s) -> bool:
	return D.set_complete(s.parts, "hero") and grit(s) >= MAX_GRIT


## 발사 순간: 밀림 판정용 출발 위치를 적고, 머리띠 충격파 · 라스트 컷 시작.
static func on_launch(w, s) -> void:
	var start := {}
	for o in w.stones:
		if o.alive and is_hero(o):
			start[o.id] = o.pos
	w.shot.ex["hero_start"] = start
	var dir: Vector2 = w.shot.dir
	if lastcut_ready(s):
		w.shot.ex["lastcut"] = true
		s.status["grit"] = 0
		s.vel = dir * w.MAX_SPEED
		w.emit({"t": "part", "part": "hero_set", "pos": s.pos, "owner": s.owner, "text": "라스트 컷", "big": true, "stone": s.id})
		return
	if s.parts["weapon"] == "hero_band" and grit(s) < 1:
		w.emit({"t": "fail", "pos": s.pos, "owner": s.owner, "text": "투지 부족", "part": "hero_band"})
	if s.parts["weapon"] == "hero_band" and grit(s) >= 1 and not w.shot.used.has("hero_band"):
		w.shot.used["hero_band"] = 1
		var g := grit(s)
		var rr: float = 90.0 + 55.0 * g
		var pw: float = 180.0 + 120.0 * g
		var spread: float = 0.9 - 0.08 * g   # 3칸은 넓게
		for o in w.stones:
			if not o.alive or o.id == s.id:
				continue
			var off: Vector2 = o.pos - s.pos
			var dist := off.length()
			if dist < rr and dist > 1.0 and off.normalized().dot(dir) > spread:
				o.vel += off.normalized() * pw * (1.0 - dist / rr * 0.5)
				if w.record_events:
					o.cause = {"owner": w.shot.owner, "part": "hero_band"}
		w.emit({"t": "cone", "pos": s.pos, "dir": dir, "radius": rr, "owner": s.owner})
		w.emit({"t": "part", "part": "hero_band", "pos": s.pos + dir * (R + 7.0), "owner": s.owner, "text": "충격파 %d" % g})


## 쏜 알의 충돌. 라스트 컷 중이면 멈추지 않고 관통 (부딪힌 알은 옆으로). true 면 일반 충돌 처리를 건너뛴다.
static func lastcut_collide(w, a, b, nrm: Vector2) -> bool:
	if w.shot == null or not w.shot.ex.get("lastcut", false):
		return false
	var me = null
	var other = null
	if a.id == w.shot.stone_id:
		me = a
		other = b
	elif b.id == w.shot.stone_id:
		me = b
		other = a
	else:
		return false
	var dir: Vector2 = me.vel.normalized() if me.vel != Vector2.ZERO else w.shot.dir
	var side: Vector2 = dir.orthogonal()
	if (other.pos - me.pos).dot(side) < 0.0:
		side = -side
	other.pos = me.pos + (other.pos - me.pos).normalized() * (w.radius_of(me) + w.radius_of(other) + 1.0)
	other.vel = side * 640.0 + dir * 200.0
	if w.record_events:
		other.cause = {"owner": w.shot.owner, "part": "hero_set"}
		w.emit({"t": "hit", "pos": other.pos, "strength": 900.0, "a": me.id, "b": other.id, "n": side})
	return true


## 매 단계: 라스트 컷은 마찰 없이 판 끝까지 달리고, 끝에서 망토로 멈춘다.
static func lastcut_step(w) -> void:
	if w.shot == null or not w.shot.ex.get("lastcut", false):
		return
	var s = w.shooter()
	if s == null or not s.alive:
		w.shot.ex["lastcut"] = false
		return
	if s.vel != Vector2.ZERO:
		s.vel = s.vel.normalized() * w.MAX_SPEED
	# 가장자리에서 출발해도 바로 멈추지 않게: 바깥쪽으로 달리고 있을 때만 판 끝에서 멈춘다
	if w.edge_distance(s.pos) < w.radius_of(s) * 1.1 and s.vel.dot(w.outward(s.pos)) > 0.0:
		s.pos -= w.outward(s.pos) * (w.radius_of(s) * 1.1 - w.edge_distance(s.pos))
		s.vel = Vector2.ZERO
		w.shot.ex["lastcut"] = false
		w.emit({"t": "part", "part": "torn_cape", "pos": s.pos, "owner": s.owner, "text": "버팀!", "big": true})


## 쏜 알의 첫 충돌 직후: 각성 운동화가 투지 1칸을 써서 한 번 더 돌진.
static func on_first_contact(w, s) -> void:
	if s.parts["prop"] == "awaken_shoes" and grit(s) < 1 and not w.shot.ex.get("lastcut", false):
		w.emit({"t": "fail", "pos": s.pos, "owner": s.owner, "text": "투지 부족", "part": "awaken_shoes"})
	if s.parts["prop"] == "awaken_shoes" and grit(s) >= 1 and not w.shot.used.has("awaken_shoes") and not w.shot.ex.get("lastcut", false):
		w.shot.used["awaken_shoes"] = 1
		s.status["grit"] = grit(s) - 1
		s.vel += w.shot.dir * D.num("awaken_shoes", "power")
		w.emit({"t": "part", "part": "awaken_shoes", "pos": s.pos, "owner": s.owner, "text": "각성! 투지 -1"})


## 판 밖으로 나갈 뻔할 때: 찢어진 망토가 판마다 한 번 가장자리에서 버틴다 (누구의 샷이든). 버티면 투지 +1.
static func save_from_edge(w, s) -> bool:
	if s.parts.get("aux", "") != "torn_cape" or s.status.get("cape_used", false):
		return false
	s.status["cape_used"] = true
	var nrm: Vector2 = w.outward(s.pos)
	s.pos = s.pos - nrm * (maxf(0.0, -w.edge_distance(s.pos)) + 3.0)
	s.vel = Vector2.ZERO
	w.emit({"t": "part", "part": "torn_cape", "pos": s.pos, "owner": s.owner, "text": "버팀!", "big": true})
	add_grit(w, s, 1, "망토로 버팀")
	return true


## 샷이 끝났을 때: 밀린 주인공 알 +1, 내 다른 알이 떨어졌으면 +2, 마지막 알이 됐으면 바로 3.
static func on_end(w) -> void:
	if w.shot == null:
		return
	var start: Dictionary = w.shot.ex.get("hero_start", {})
	for o in w.stones:
		if not o.alive or not is_hero(o):
			continue
		if o.owner != w.shot.owner and start.has(o.id) and (o.pos as Vector2).distance_to(start[o.id]) > R:
			add_grit(w, o, 1, "맞아 밀림")
	for k in w.knockouts:
		var owner: int = int(k["owner"])
		for o2 in w.alive_stones_of(owner):
			if is_hero(o2):
				add_grit(w, o2, 2, "동료가 떨어짐")
	for o3 in w.stones:
		# 마지막 알이 되는 순간 한 번만
		if o3.alive and is_hero(o3) and w.alive_stones_of(o3.owner).size() == 1 and not o3.status.get("last_given", false):
			o3.status["last_given"] = true
			add_grit(w, o3, MAX_GRIT, "마지막 알")
