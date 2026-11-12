extends RefCounted
## 해적 선착장 (개발 보고서 「신규 공방: 해적 선착장」). 판 자체를 바꾸는 공방.
## 공방 규칙 「오늘의 바람」(SYS-07): 바퀴마다 8방향 중 하나. 판 시작 때 정한 순서표대로 (온라인도 같은 판).
##   바람을 받는 것: 바람돛 · 깃발 신호기 · 노 젓기 · 떠다니는 나무 상자 · 소용돌이 튕김.
## 판 경계 함수 (SYS-06): world.is_inside 가 밀물(가장자리 1칸 잠김) · 널빤지(경계 확장)를 함께 본다.
##   구멍(구멍 대포)은 그 위에서 느리게 지나거나 멈추면 빠진다.
## 줄 연결 (SYS-08): 쇠사슬 볼라스. 공중 상태 (SYS-11): 점프 판자. 개조 연동 (SYS-12): 보물 상자.
## 상태는 world.pirate 에 둔다 (비어 있으면 이 공방이 아님).

const D = preload("res://scripts/sim/parts_data.gd")
const C = preload("res://scripts/sim/clock.gd")   # push · speed_for
const CELL := 44.0
const R := 22.0
const FRONT_DOT := 0.75
const WIND_ACC := 260.0        # 바람돛이 받는 바람 (px/s²)
const BARREL_SPEED := 360.0
const BARREL_R := 0.55 * CELL
const CRATE_R := 0.6 * CELL
const HOLE_R := 0.9 * CELL
const AIR_TIME := 0.4


static func on(w) -> bool:
	return not w.pirate.is_empty()


static func setup(w, rng: RandomNumberGenerator) -> void:
	var winds: Array = []
	for i in 60:
		winds.append(rng.randi_range(0, 7))
	w.pirate = {"winds": winds, "wind": winds[1], "tide": 0, "planks": [], "holes": [], "ropes": [], "chests": [],
		"ramps": [], "barrels": [], "air": {}, "cannon": {}, "skip": -1}


## 바퀴 r 의 바람 방향 (단위 벡터)
static func wind_of(w, r: int) -> Vector2:
	if not on(w):
		return Vector2.ZERO
	var arr: Array = w.pirate["winds"]
	return Vector2.from_angle(TAU * int(arr[clampi(r, 0, arr.size() - 1)]) / 8.0)


static func wind(w) -> Vector2:
	return wind_of(w, w.round_no)


## 밀물이 차는 바퀴 (짝수 바퀴)
static func tide_round(r: int) -> bool:
	return r % 2 == 0


static func has_tide(w) -> bool:
	for g in w.gimmicks:
		if g["kind"] == "tide":
			return true
	return false


## 판 경계: 원 반지름에서 밀물만큼 뺀다
static func shrink(w) -> float:
	return float(w.pirate.get("tide", 0)) * CELL if on(w) else 0.0


static func in_plank(w, p: Vector2) -> bool:
	for pk in w.pirate.get("planks", []):
		var off: Vector2 = p - (pk["pos"] as Vector2)
		var dir: Vector2 = pk["dir"]
		var along := off.dot(dir)
		if along >= -CELL * 0.5 and along <= CELL * 1.6 and absf(off.cross(dir)) <= CELL * 0.85:
			return true
	return false


static func _ev(w, pos: Vector2, owner: int, part: String, text: String, big := false) -> void:
	w.emit({"t": "part", "part": part, "pos": pos, "owner": owner, "text": text, "big": big})


static func _has(s, slot: String, part: String) -> bool:
	return s.parts.get(slot, "") == part


# ── 발사 ─────────────────────────────────────────────────

static func on_launch(w, s) -> void:
	if not on(w):
		return
	var sh = w.shot
	var dir: Vector2 = sh.dir
	match s.parts["weapon"]:
		"spyglass":
			s.vel *= 1.1
		"hole_cannon":
			# 포탄: 정면 3칸 앞 (그 앞에 알이 있으면 그 자리)에 떨어져 구멍을 낸다 (1바퀴)
			var spot: Vector2 = s.pos + dir * 3.0 * CELL
			var t0 = _first_on_ray(w, s.pos, dir, 3.0 * CELL, s.id)
			if t0 != null:
				spot = t0.pos
			if w.is_inside(spot):
				w.pirate["holes"].append({"pos": spot, "until": w.round_no + 1, "owner": s.owner})
				w.emit({"t": "shell", "a": s.pos + dir * (R + 8.0), "b": spot, "owner": s.owner})
				_ev(w, spot, s.owner, "hole_cannon", "구멍!", true)
		"smoke_powder":
			for o in w.stones:
				if not o.alive or o.id == s.id:
					continue
				var off: Vector2 = o.pos - s.pos
				if off.length() < 3.0 * CELL and off.normalized().dot(dir) > 0.5:
					o.status["smoke"] = w.round_no + 1
			w.emit({"t": "cone", "pos": s.pos, "dir": dir, "radius": 3.0 * CELL, "owner": s.owner, "smoke": true})
			_ev(w, s.pos + dir * CELL, s.owner, "smoke_powder", "연막")
		"parrot_hat":
			var t = _first_on_ray(w, s.pos, dir, 8.0 * CELL, s.id)
			if t != null and t.owner != s.owner:
				s.status["parrot"] = t.id
				_ev(w, t.pos, s.owner, "parrot_hat", "앵무새가 앉음")
	# 지난 샷에 앵무새가 앉은 알 쪽으로 휜다 (이번 샷 동안)
	if s.status.has("parrot_next"):
		sh.ex["home_to"] = int(s.status["parrot_next"])
		s.status.erase("parrot_next")
	if s.status.has("parrot"):
		s.status["parrot_next"] = s.status["parrot"]
		s.status.erase("parrot")


## 샷 도중 매 단계 (이동 전): 바람돛, 앵무새 유도, 소용돌이, 술통
static func before_move(w, dt: float) -> void:
	if not on(w):
		return
	var sh = w.shot
	if sh != null:
		var s = w.shooter()
		if s != null and s.alive and s.vel != Vector2.ZERO:
			if _has(s, "prop", "wind_sail"):
				s.vel += wind(w) * WIND_ACC * dt
			if sh.ex.has("home_to"):
				var t = w.get_stone(int(sh.ex["home_to"]))
				if t != null and t.alive:
					var want: Vector2 = (t.pos - s.pos).normalized()
					var cur: Vector2 = s.vel.normalized()
					var ang := cur.angle_to(want)
					var step := clampf(ang, -1.2 * dt, 1.2 * dt)
					s.vel = s.vel.rotated(step)
	# 소용돌이: 지름 4칸 안을 지나는 알이 중심 쪽으로 휜다
	for g in w.gimmicks:
		if g["kind"] != "whirlpool":
			continue
		var it: Dictionary = g["items"][0]
		var cpos: Vector2 = it["pos"]
		for s2 in w.stones:
			if not s2.alive or s2.vel == Vector2.ZERO:
				continue
			var off: Vector2 = cpos - s2.pos
			var d := off.length()
			if d < float(it["r"]) and d > 4.0:
				s2.vel += off.normalized() * 520.0 * dt
	# 술통: 판 끝까지 굴러가며 부딪힌 알을 민다
	var keep: Array = []
	for b in w.pirate["barrels"]:
		var bp: Vector2 = b["pos"]
		var bv: Vector2 = b["dir"]
		bp += bv * BARREL_SPEED * dt
		b["pos"] = bp
		for s3 in w.stones:
			if not s3.alive or b["hit"].has(s3.id):
				continue
			if s3.pos.distance_to(bp) < w.radius_of(s3) + BARREL_R:
				b["hit"][s3.id] = true
				s3.vel += (bv + (s3.pos - bp).normalized() * 0.4).normalized() * 380.0
				if w.record_events:
					s3.cause = {"owner": int(b["owner"]), "part": "rum_barrel"}
		if w.is_inside(bp):
			keep.append(b)
	w.pirate["barrels"] = keep


static func busy(w) -> bool:
	return on(w) and not w.pirate["barrels"].is_empty()


## 공중에 뜬 알은 다른 알과 부딪히지 않는다 (점프 판자)
static func skip_pair(w, a, b) -> bool:
	if not on(w):
		return false
	var air: Dictionary = w.pirate["air"]
	return air.has(a.id) or air.has(b.id)


## 나무 의족: 박힌 알은 아주 무겁다 (큰 충격 한 번에 빠진다)
static func mass_k(s) -> float:
	return 40.0 if s.status.has("anchored") else 1.0


# ── 이동 뒤: 줄 · 공중 · 구멍 · 널빤지 · 점프 판자 ─────────

static func after_move(w, dt: float) -> void:
	if not on(w):
		return
	var pr: Dictionary = w.pirate
	# 공중 시간 줄이기
	for id in pr["air"].keys():
		pr["air"][id] = float(pr["air"][id]) - dt
		if float(pr["air"][id]) <= 0.0:
			pr["air"].erase(id)
	# 점프 판자 위를 지나는 알은 한 번 튀어 오른다
	for rp in pr["ramps"]:
		for s in w.stones:
			if s.alive and s.vel.length() > 120.0 and not pr["air"].has(s.id) and s.pos.distance_to(rp["pos"]) < R * 1.1:
				if not rp.has("used") or not rp["used"].has(s.id):
					if not rp.has("used"):
						rp["used"] = {}
					rp["used"][s.id] = true
					pr["air"][s.id] = AIR_TIME
					w.emit({"t": "jump", "pos": s.pos, "owner": s.owner, "stone": s.id})
	# 쇠사슬: 길이 1.5칸을 넘지 않는다
	for rope in pr["ropes"]:
		var a = w.get_stone(int(rope["a"]))
		var b = w.get_stone(int(rope["b"]))
		if a == null or b == null or not a.alive or not b.alive:
			continue
		var d: Vector2 = b.pos - a.pos
		var L := float(rope["len"])
		if d.length() > L:
			var n := d.normalized()
			var over := d.length() - L
			var ma: float = w.mass_of(a)
			var mb: float = w.mass_of(b)
			a.pos += n * over * mb / (ma + mb)
			b.pos -= n * over * ma / (ma + mb)
			var rel: float = (b.vel - a.vel).dot(n)
			if rel > 0.0:
				var imp := rel / (1.0 / ma + 1.0 / mb)
				a.vel += n * imp / ma
				b.vel -= n * imp / mb
	# 널빤지 부두: 쏜 알이 판 끝에 닿으면 그 자리에 널빤지
	var sh = w.shot
	if sh != null:
		var s0 = w.shooter()
		if s0 != null and s0.alive and _has(s0, "aux", "plank_dock") and not sh.used.has("plank_dock") and w.edge_distance(s0.pos) < R * 0.6 and s0.vel.dot(w.outward(s0.pos)) > 0.0:
			sh.used["plank_dock"] = 1
			var o: Vector2 = w.outward(s0.pos)
			pr["planks"].append({"pos": o * (w.size - shrink(w)), "dir": o, "until": w.round_no + 1, "owner": s0.owner})
			_ev(w, s0.pos, s0.owner, "plank_dock", "널빤지!", true)


## 구멍: 위에서 느려지거나 멈춘 알은 빠진다. world._check_out 이 판 밖 판정 전에 부른다.
static func in_hole(w, s) -> bool:
	if not on(w) or pr_empty(w, "holes"):
		return false
	if s.vel.length() > 260.0 or w.pirate["air"].has(s.id):
		return false
	for h in w.pirate["holes"]:
		if s.pos.distance_to(h["pos"]) < HOLE_R * 0.75:
			return true
	return false


static func pr_empty(w, key: String) -> bool:
	return w.pirate.get(key, []).is_empty()


# ── 충돌 ─────────────────────────────────────────────────

static func on_contact(w, s, t, n: Vector2) -> void:
	if not on(w):
		return
	var sh = w.shot
	var front: bool = n.dot(sh.dir) >= FRONT_DOT
	# 쇠사슬 볼라스: 처음 닿은 상대 알 두 개
	if _has(s, "weapon", "bolas") and t.owner != s.owner:
		var got: Array = sh.ex.get("bolas", [])
		if not got.has(t.id) and got.size() < 2:
			got.append(t.id)
			sh.ex["bolas"] = got
			if got.size() == 2:
				w.pirate["ropes"].append({"a": got[0], "b": got[1], "len": 1.5 * CELL + 2.0 * R, "until": w.round_no + 1, "owner": s.owner})
				_ev(w, t.pos, s.owner, "bolas", "사슬로 묶음!", true)
	if _has(s, "weapon", "flag_signal") and not sh.used.has("flag_signal"):
		sh.used["flag_signal"] = 1
		t.status["flag"] = w.round_no + 2
		_ev(w, t.pos, s.owner, "flag_signal", "깃발")
	if not sh.used.has("pi_first"):
		sh.used["pi_first"] = 1
		if _has(s, "prop", "oar"):
			s.vel += wind(w) * C.speed_for(1.5)
			_ev(w, s.pos, s.owner, "oar", "노 젓기")
	if not front and not sh.used.has("pi_side"):
		sh.used["pi_side"] = 1
		if _has(s, "aux", "hook_hand") and t.owner != s.owner:
			# 그 알을 축으로 반 바퀴 휘돈다
			var off: Vector2 = s.pos - t.pos
			s.pos = t.pos - off
			s.vel = -s.vel * 0.85
			w.emit({"t": "swing", "pos": t.pos, "owner": s.owner, "stone": s.id})
			_ev(w, t.pos, s.owner, "hook_hand", "갈고리 휘돌기!", true)
		if _has(s, "aux", "rum_barrel"):
			w.pirate["barrels"].append({"pos": s.pos - n.orthogonal() * (R + BARREL_R) * signf(n.orthogonal().dot(sh.dir) + 0.001), "dir": n, "owner": s.owner, "hit": {s.id: true}})
			_ev(w, s.pos, s.owner, "rum_barrel", "술통 굴러감!")
		if _has(s, "aux", "jump_board"):
			w.pirate["ramps"].append({"pos": s.pos, "dir": sh.dir, "until": w.round_no + 1, "owner": s.owner})
			_ev(w, s.pos, s.owner, "jump_board", "점프 판자")


## 모든 충돌 직후: 나무 의족은 큰 충격이면 빠진다
static func post_collision(w, a, b, imp: float) -> void:
	if not on(w):
		return
	for x in [a, b]:
		if x.status.has("anchored") and imp > 900.0:
			x.status.erase("anchored")
			_ev(w, x.pos, x.owner, "peg_leg", "의족이 빠졌다")


## 쏜 알이 멈췄을 때
static func on_stop(w, s) -> void:
	if not on(w):
		return
	if _has(s, "prop", "peg_leg"):
		s.status["anchored"] = true
		_ev(w, s.pos, s.owner, "peg_leg", "쿵! 박힘")
	if _has(s, "aux", "water_pump"):
		var side: Vector2 = Vector2.from_angle(s.facing).orthogonal() * float(s.magnet_side)
		for o in w.stones:
			if not o.alive or o.id == s.id:
				continue
			var off: Vector2 = o.pos - s.pos
			var along := off.dot(side)
			if along > 0.0 and along < 3.0 * CELL and absf(off.cross(side)) < CELL * 0.8:
				C.push(w, o, side, 0.6, s.owner, "water_pump")
		w.emit({"t": "cone", "pos": s.pos, "dir": side, "radius": 3.0 * CELL, "owner": s.owner, "water": true})
		_ev(w, s.pos, s.owner, "water_pump", "물대포")
	if _has(s, "aux", "treasure_chest") and not w.shot.used.has("treasure_chest"):
		w.shot.used["treasure_chest"] = 1
		w.pirate["chests"].append({"pos": s.pos + Vector2.from_angle(s.facing + PI) * (R * 2.0), "round": w.round_no, "owner": s.owner})
		_ev(w, s.pos, s.owner, "treasure_chest", "보물 상자")
	if _has(s, "prop", "helm"):
		for o in w.stones:
			if not o.alive or o.id == s.id:
				continue
			var off2: Vector2 = o.pos - s.pos
			if off2.length() < R * 2.0 + CELL:
				C.push(w, o, off2.orthogonal().normalized() + off2.normalized() * 0.3, 0.8, s.owner, "helm")
		w.emit({"t": "swing", "pos": s.pos, "owner": s.owner, "stone": s.id})
		_ev(w, s.pos, s.owner, "helm", "타륜 회전")


## 샷이 끝났을 때: 포격 명령 (선장 세트), 구명보트
static func end_shot(w) -> void:
	if not on(w) or w.shot == null:
		return
	var sh = w.shot
	var s = w.shooter()
	if s != null and s.alive and D.set_complete(s.parts, "captain") and int(w.pirate["cannon"].get(s.owner, 0)) != w.round_no and s.owner == sh.owner:
		w.pirate["cannon"][s.owner] = w.round_no
		var dir: Vector2 = sh.dir
		var a: Vector2 = s.pos - dir * 2.5 * w.size
		var b: Vector2 = s.pos + dir * 2.5 * w.size
		w.emit({"t": "cannonball", "a": s.pos - dir * w.size * 1.1, "b": s.pos + dir * w.size * 1.1, "owner": s.owner})
		_ev(w, s.pos, s.owner, "captain_set", "포격 명령!", true)
		C._sweep_path(w, [a, b], s.owner, "captain_set", s.id, R * 0.6)
	for o in w.stones:
		if not o.alive and _has(o, "prop", "lifeboat") and not o.status.has("lifeboat_used") and not o.status.has("lifeboat"):
			o.status["lifeboat"] = true


# ── 차례 이벤트 ──────────────────────────────────────────

## 바퀴 시작: 밀물·썰물 → 바람 변경 → 깃발 흐름
static func round_start(w, round_no: int) -> bool:
	if not on(w):
		return false
	var moved := false
	var pr: Dictionary = w.pirate
	if has_tide(w):
		pr["tide"] = 1 if tide_round(round_no) else 0
		if tide_round(round_no):
			for s in w.stones:
				if s.alive and s.pos.length() > w.size - CELL and not in_plank(w, s.pos):
					s.alive = false
					s.vel = Vector2.ZERO
					w.knockouts.append({"stone": s.id, "owner": s.owner, "cause": {"part": "gm_tide"}})
					w.emit({"t": "out", "pos": s.pos, "owner": s.owner, "cause": {"part": "gm_tide"}, "stone": s.id})
			_ev(w, Vector2(0, -w.size * 0.6), -1, "gm_tide", "밀물!", true)
	pr["wind"] = pr["winds"][clampi(round_no, 0, pr["winds"].size() - 1)]
	var wd := wind_of(w, round_no)
	for s in w.stones:
		if s.alive and int(s.status.get("flag", -1)) >= round_no:
			C.push(w, s, wd, 1.0, -1, "flag_signal")
			moved = true
	return moved


## 바퀴 끝: 1바퀴짜리 설치물 정리, 보물 상자 판정 (pid → 추가 카드 수 를 돌려준다)
static func round_end(w, round_no: int) -> Dictionary:
	var extra := {}
	if not on(w):
		return extra
	var pr: Dictionary = w.pirate
	var keep_c: Array = []
	for ch in pr["chests"]:
		if int(ch["round"]) < round_no:
			for s in w.stones:
				if s.alive and s.pos.distance_to(ch["pos"]) < R + CELL:
					extra[s.owner] = int(extra.get(s.owner, 0)) + 1
			w.emit({"t": "part", "part": "treasure_chest", "pos": ch["pos"], "owner": int(ch["owner"]), "text": "보물 상자 열림"})
		else:
			keep_c.append(ch)
	pr["chests"] = keep_c
	for key in ["holes", "planks", "ramps", "ropes"]:
		pr[key] = pr[key].filter(func(x): return int(x["until"]) > round_no)
	return extra


## 차례 시작: 소용돌이 튕김 → 구명보트 · 나무 의족 풀림
static func turn_start(w, pid: int) -> bool:
	if not on(w):
		return false
	var moved := false
	for g in w.gimmicks:
		if g["kind"] != "whirlpool":
			continue
		var cpos: Vector2 = g["items"][0]["pos"]
		for s in w.stones:
			if s.alive and s.vel == Vector2.ZERO and s.pos.distance_to(cpos) < CELL:
				C.push(w, s, wind(w), 2.0, -1, "gm_whirlpool")
				moved = true
				_ev(w, s.pos, -1, "gm_whirlpool", "소용돌이에 튕김!")
	for s in w.stones:
		if s.owner != pid:
			continue
		s.status.erase("anchored")
		if not s.alive and s.status.has("lifeboat"):
			s.status.erase("lifeboat")
			s.status["lifeboat_used"] = true
			var dirv: Vector2 = s.pos.normalized() if s.pos.length() > 1.0 else Vector2.RIGHT
			var spot: Vector2 = dirv * (w.size - shrink(w) - CELL * 1.2)
			s.alive = true
			s.pos = spot
			s.vel = Vector2.ZERO
			w.emit({"t": "respawn", "pos": spot, "owner": s.owner, "stone": s.id})
			_ev(w, spot, s.owner, "lifeboat", "구명보트로 복귀 · 이번 차례 쉼", true)
			w.pirate["skip"] = pid
	return moved


## 차례 종료: 떠다니는 나무 상자가 바람 따라 1칸 (판 끝에 닿으면 반대편에서)
static func turn_end(w, _pid: int) -> bool:
	if not on(w):
		return false
	var moved := false
	var wd := wind(w)
	for g in w.gimmicks:
		if g["kind"] != "crates":
			continue
		for it in g["items"]:
			var from: Vector2 = it["pos"]
			var to: Vector2 = from + wd * CELL
			if to.length() > w.size - CELL * 0.8:
				to = -from.normalized() * (w.size - CELL * 1.2)
			# 지나가는 길의 알을 밀어낸다
			if C._sweep_path(w, [from, to], -1, "gm_crates", -1, CRATE_R):
				moved = true
			it["pos"] = to
			w.emit({"t": "walker", "kind": "crate", "a": from, "b": to, "owner": -1})
	return moved


## 나무 상자는 샷 도중 단단한 장애물
static func collide(w) -> void:
	if not on(w):
		return
	for g in w.gimmicks:
		if g["kind"] != "crates":
			continue
		for it in g["items"]:
			var bp: Vector2 = it["pos"]
			for s in w.stones:
				if not s.alive:
					continue
				var rr: float = w.radius_of(s) + CRATE_R
				var d: Vector2 = s.pos - bp
				if d.length() < rr and d.length() > 0.001:
					var nrm := d.normalized()
					s.pos = bp + nrm * rr
					var vn: float = s.vel.dot(nrm)
					if vn < 0.0:
						s.vel = (s.vel - 2.0 * vn * nrm) * 0.6
						w.emit({"t": "hit", "pos": bp + nrm * CRATE_R, "strength": -vn, "a": s.id, "b": s.id, "n": nrm, "gimmick": "crates"})


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
