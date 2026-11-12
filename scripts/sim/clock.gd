extends RefCounted
## 태엽 시계탑 (개발 보고서 「신규 공방: 태엽 시계탑」).
## 시간을 다루는 공방: 효과가 지금이 아니라 "다음 차례 끝", "다음 바퀴 시작"에 터진다.
## 차례 이벤트 큐 (SYS-01): 경기 관리(match)가 바퀴 시작 · 차례 시작 · 차례 종료에 아래 함수를 부르고,
## 움직임이 생기면 그 움직임이 다 멈출 때까지 화면에서 보여 준 다음 경기를 이어 간다.
## 알 상태 (SYS-03): 알의 status 에 표식과 저장 값을 둔다 (알 위 아이콘으로 표시).
## 차례를 넘는 이동 물체 (SYS-05): world.clock["walkers"] (느린 화살 · 태엽 쥐).
## 궤적 재생 (SYS-04): world.clock["replays"] (다시보기 태엽), 샷 시작 자리 (되감기 회중시계).

const D = preload("res://scripts/sim/parts_data.gd")
const P = preload("res://scripts/sim/parts.gd")
const CELL := 44.0
const R := 22.0
const FRONT_DOT := 0.75        # 정면 충돌: 진행 방향과 이루는 각이 약 40도 안

# ── 공통 도우미 ──────────────────────────────────────────

## 이만큼 칸을 미끄러지게 하는 처음 속도 (마찰·끌림을 거꾸로 계산)
static func speed_for(cells: float) -> float:
	var want := cells * CELL
	var lo := 0.0
	var hi := 2400.0
	for _i in 22:
		var mid := (lo + hi) * 0.5
		if _travel(mid) < want:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


static func _travel(v0: float) -> float:
	var v := v0
	var d := 0.0
	var dt := 1.0 / 120.0
	for _i in 1200:
		if v < 6.0:
			break
		d += v * dt
		v = v - P.FRICTION * dt - v * P.DRAG * dt
	return d


static func push(w, s, dir: Vector2, cells: float, owner: int, part: String) -> void:
	if s == null or not s.alive or dir == Vector2.ZERO:
		return
	s.vel += dir.normalized() * speed_for(cells)
	if w.record_events:
		s.cause = {"owner": owner, "part": part}


static func _ev(w, pos: Vector2, owner: int, part: String, text: String, big := false) -> void:
	w.emit({"t": "part", "part": part, "pos": pos, "owner": owner, "text": text, "big": big})


static func state(w) -> Dictionary:
	if w.clock.is_empty():
		w.clock = {"walkers": [], "replays": [], "alarms": []}
	return w.clock


static func _has(s, slot: String, part: String) -> bool:
	return s.parts.get(slot, "") == part


# ── 발사 ─────────────────────────────────────────────────

static func on_launch(w, s) -> void:
	var sh = w.shot
	var dir: Vector2 = sh.dir
	# 예약 석궁: 이번엔 조준만 저장 (다음 내 차례 시작에 그대로 자동 발사)
	if _has(s, "weapon", "reserve_bow") and not sh.ex.get("auto_bow", false):
		s.status["bow"] = {"dir": dir, "power": sh.power, "turn": w.turn_no}
		s.vel = Vector2.ZERO
		sh.ex["bow_saved"] = true
		_ev(w, s.pos, s.owner, "reserve_bow", "조준 예약", true)
		return
	if _has(s, "weapon", "slow_arrow"):
		var st := state(w)
		st["walkers"].append({"kind": "arrow", "pos": s.pos + dir * (R + 12.0), "dir": dir, "left": 3 if P.up(s, "slow_arrow") else 2, "owner": s.owner})
		_ev(w, s.pos + dir * (R + 12.0), s.owner, "slow_arrow", "느린 화살")
	if _has(s, "weapon", "rewind_watch"):
		var starts := {}
		for o in w.stones:
			if o.alive:
				starts[o.id] = o.pos
		sh.ex["starts"] = starts
	var base_v: float = s.vel.length()
	# 분침 태엽: 지난 샷에서 저장한 힘을 더하고, 이번 힘의 절반을 다시 저장
	if _has(s, "prop", "minute_spring"):
		var bonus := float(s.status.get("minute", 0.0))
		if bonus > 0.0:
			s.vel += dir * bonus
			_ev(w, s.pos, s.owner, "minute_spring", "태엽 +%d%%" % int(round(bonus / P.LAUNCH_V * 100.0)))
		s.status["minute"] = minf(base_v * 0.5, 700.0)
	# 충격 태엽: 맞을 때 모아 둔 힘을 더한다
	if _has(s, "aux", "shock_spring"):
		var sb := minf(float(s.status.get("shock", 0.0)), 900.0 if P.up(s, "shock_spring") else 600.0)
		if sb > 20.0:
			s.vel += dir * sb
			_ev(w, s.pos, s.owner, "shock_spring", "충격 반납")
		s.status.erase("shock")
	# 느림보 태엽: 발사 속도 70%, 감속 절반
	if _has(s, "prop", "slow_spring"):
		s.vel *= 0.85 if P.up(s, "slow_spring") else 0.7
		sh.ex["slowpoke"] = s.id
	# 똑딱 걸음: 세 구간으로 끊어 간다
	if _has(s, "prop", "tick_step"):
		var v: float = s.vel.length()
		s.vel = dir * v * 0.5
		sh.ex["tick"] = {"left": 3 if P.up(s, "tick_step") else 2, "pause": 0.0, "v": v * (0.36 if P.up(s, "tick_step") else 0.42)}


## 마찰 배율 (느림보 태엽)
static func friction_k(w, s) -> float:
	if w.shot != null and int(w.shot.ex.get("slowpoke", -1)) == s.id:
		return 0.5
	return 1.0


## 똑딱 걸음: 멈추면 잠깐 쉬었다가 다시 출발
static func before_move(w, dt: float) -> void:
	if w.shot == null or not w.shot.ex.has("tick"):
		return
	var t: Dictionary = w.shot.ex["tick"]
	var s = w.shooter()
	if s == null or not s.alive or int(t["left"]) <= 0:
		w.shot.ex.erase("tick")
		return
	if s.vel.length() > 30.0:
		t["pause"] = 0.0
		return
	t["pause"] = float(t["pause"]) + dt
	if float(t["pause"]) >= 0.22:
		s.vel = w.shot.dir * float(t["v"])
		t["left"] = int(t["left"]) - 1
		t["pause"] = 0.0
		_ev(w, s.pos, s.owner, "tick_step", "똑딱")


static func busy(w) -> bool:
	return w.shot != null and w.shot.ex.has("tick") and int(w.shot.ex["tick"]["left"]) > 0


# ── 충돌 ─────────────────────────────────────────────────

## 쏜 알 s 가 t 에 닿았을 때 (n: s → t)
static func on_contact(w, s, t, n: Vector2) -> void:
	var sh = w.shot
	var front: bool = n.dot(sh.dir) >= FRONT_DOT
	if front and not sh.used.has("ck_front"):
		sh.used["ck_front"] = 1
		if _has(s, "weapon", "hour_hammer"):
			t.status["hand_mark"] = {"dir": sh.dir, "turn": w.turn_no, "by": sh.owner}
			_ev(w, t.pos, s.owner, "hour_hammer", "시곗바늘 표식")
		if _has(s, "weapon", "time_spring"):
			t.status["bomb"] = {"round": w.round_no, "by": sh.owner, "up": P.up(s, "time_spring")}
			_ev(w, t.pos, s.owner, "time_spring", "째깍… 다음 바퀴")
		if _has(s, "weapon", "rewind_watch"):
			sh.ex["rewind"] = t.id
			sh.ex["rewind_up"] = P.up(s, "rewind_watch")
		if _has(s, "weapon", "order_swap") and t.owner != s.owner:
			sh.ex["swap_order"] = t.owner
			_ev(w, t.pos, s.owner, "order_swap", "순서 바꾸기")
	elif not front and not sh.used.has("ck_side"):
		sh.used["ck_side"] = 1
		if _has(s, "aux", "late_key") and t.owner != s.owner:
			sh.ex["delay"] = t.owner
			_ev(w, t.pos, s.owner, "late_key", "늦잠!")
		if _has(s, "aux", "wind_mouse"):
			var st := state(w)
			var md: Vector2 = n.orthogonal() if n.orthogonal().dot(sh.dir) >= 0.0 else -n.orthogonal()
			st["walkers"].append({"kind": "mouse", "pos": s.pos - n * (R + 4.0), "dir": md, "left": 2, "owner": s.owner})
			if P.up(s, "wind_mouse"):
				st["walkers"].append({"kind": "mouse", "pos": s.pos - md * (R + 4.0), "dir": -md, "left": 2, "owner": s.owner})
			_ev(w, s.pos, s.owner, "wind_mouse", "찍찍!")


## 모든 충돌 직후: 내 차례가 아닐 때 맞은 알 (모래시계 방패 · 충격 태엽)
static func post_collision(w, a, b, imp: float) -> void:
	if w.shot == null:
		return
	if w.shot.ex.get("rewind_up", false) and not w.shot.ex.has("rewind2"):
		var rid := int(w.shot.ex.get("rewind", -1))
		if a.id == rid and b.id != w.shot.stone_id:
			w.shot.ex["rewind2"] = b.id
		elif b.id == rid and a.id != w.shot.stone_id:
			w.shot.ex["rewind2"] = a.id
	for x in [a, b]:
		if x.id == w.shot.stone_id or x.owner == w.shot.owner:
			continue
		if _has(x, "aux", "hourglass") and not x.status.has("hg_spent") and int(x.status.get("hg_n", 0)) < (2 if P.up(x, "hourglass") else 1):
			x.status["hourglass"] = (x.status.get("hourglass", Vector2.ZERO) as Vector2) + x.vel
			x.status["hg_n"] = int(x.status.get("hg_n", 0)) + 1
			x.vel = Vector2.ZERO
			_ev(w, x.pos, x.owner, "hourglass", "충격 보류")
		if _has(x, "aux", "shock_spring"):
			x.status["shock"] = minf(900.0 if P.up(x, "shock_spring") else 600.0, float(x.status.get("shock", 0.0)) + imp / w.mass_of(x) * 0.45)


## 쏜 알이 멈췄을 때
static func on_stop(w, s) -> void:
	if _has(s, "aux", "metronome"):
		s.status["metro"] = 1
	if _has(s, "aux", "alarm_clock") and not w.shot.used.has("alarm_clock"):
		w.shot.used["alarm_clock"] = 1
		state(w)["alarms"].append({"pos": s.pos, "owner": s.owner, "round": w.round_no, "r": 3.0 if P.up(s, "alarm_clock") else 2.0})
		_ev(w, s.pos, s.owner, "alarm_clock", "자명종 설치")
	if _has(s, "prop", "time_capsule") and not s.status.has("capsule") and not s.status.has("capsule_used"):
		s.status["capsule"] = s.pos
		_ev(w, s.pos, s.owner, "time_capsule", "캡슐 묻음")


## 샷이 끝났을 때: 되감기, 잔상 저장
static func end_shot(w) -> void:
	var sh = w.shot
	if sh == null:
		return
	if sh.ex.has("rewind2"):
		var t2 = w.get_stone(int(sh.ex["rewind2"]))
		var back2 = sh.ex.get("starts", {}).get(int(sh.ex["rewind2"]))
		if t2 != null and t2.alive and back2 != null:
			t2.pos = back2
			t2.vel = Vector2.ZERO
	if sh.ex.has("rewind"):
		var t = w.get_stone(int(sh.ex["rewind"]))
		var back = sh.ex.get("starts", {}).get(int(sh.ex["rewind"]))
		if t != null and t.alive and back != null:
			t.pos = back
			t.vel = Vector2.ZERO
			_ev(w, back, sh.owner, "rewind_watch", "되감기!", true)
	var s = w.shooter()
	if s != null and _has(s, "prop", "replay_spring") and sh.path.size() >= 2 and not sh.ex.get("bow_saved", false):
		var path: Array = [sh.start]
		path.append_array(sh.path)
		path.append(s.pos)
		state(w)["replays"].append({"owner": s.owner, "path": path, "turn": w.turn_no, "left": 2 if P.up(s, "replay_spring") else 1})


# ── 차례 이벤트 ──────────────────────────────────────────

## 바퀴 시작: 뻐꾸기 시계 → 자명종
static func round_start(w, round_no: int) -> bool:
	var moved := false
	for g in w.gimmicks:
		if g["kind"] == "cuckoo" and (round_no == 3 or round_no == 5):
			var dir := Vector2.from_angle(float(g["dir"]))
			for s in w.stones:
				if s.alive:
					push(w, s, dir, 1.0, -1, "gm_cuckoo")
					moved = true
			_ev(w, Vector2.ZERO, -1, "gm_cuckoo", "뻐꾹! 모두 한 칸", true)
	var st := state(w)
	var keep: Array = []
	for al in st["alarms"]:
		if int(al["round"]) >= round_no:
			keep.append(al)
			continue
		var ap: Vector2 = al["pos"]
		for s in w.stones:
			if not s.alive:
				continue
			var d: float = s.pos.distance_to(ap)
			if d < float(al.get("r", 2.0)) * CELL and d > R * 1.5:
				push(w, s, ap - s.pos, (d - R * 2.0) / CELL * 0.8, int(al["owner"]), "alarm_clock")
				moved = true
		_ev(w, ap, int(al["owner"]), "alarm_clock", "따르릉!", true)
	st["alarms"] = keep
	return moved


## 차례 시작 (pid 의 차례): 예약 석궁 자동 발사 → 모래시계 방패의 미뤄 둔 충격 → 타임캡슐 복귀
static func turn_start(w, pid: int) -> bool:
	var moved := false
	for s in w.stones:
		if s.owner != pid:
			continue
		if s.alive:
			s.status.erase("metro")
			s.status.erase("hg_spent")
		if s.alive and s.status.has("bow") and int(s.status["bow"]["turn"]) < w.turn_no:
			var b: Dictionary = s.status["bow"]
			s.status.erase("bow")
			s.vel = (b["dir"] as Vector2) * P.launch_speed(float(b["power"]))
			if P.up(s, "reserve_bow"):
				for ang in [-0.22, 0.22]:
					var bd: Vector2 = (b["dir"] as Vector2).rotated(ang)
					w.spawn_bullet(s.owner, s.pos + bd * (R + 7.0), bd, 260.0, "weapon", s.id)
			w.emit({"t": "part", "part": "reserve_bow", "pos": s.pos, "owner": s.owner, "text": "예약 발사!", "big": true})
			moved = true
		if s.alive and s.status.has("hourglass"):
			s.vel += s.status["hourglass"]
			s.status.erase("hourglass")
			s.status.erase("hg_n")
			s.status["hg_spent"] = true
			_ev(w, s.pos, s.owner, "hourglass", "모래 다 떨어짐")
			moved = moved or s.vel != Vector2.ZERO
		if not s.alive and s.status.has("capsule") and not s.status.has("capsule_used"):
			var cp: Vector2 = s.status["capsule"]
			var free := true
			for o in w.stones:
				if o.alive and o.pos.distance_to(cp) < R * 2.0:
					free = false
			if free:
				s.alive = true
				s.pos = cp
				s.vel = Vector2.ZERO
				s.status["capsule_used"] = true
				s.status.erase("capsule")
				w.emit({"t": "respawn", "pos": cp, "owner": s.owner, "stone": s.id})
				_ev(w, cp, s.owner, "time_capsule", "캡슐에서 복귀!", true)
				if P.up(s, "time_capsule"):
					for o in w.stones:
						if o.alive and o.id != s.id and o.pos.distance_to(cp) < R * 2.0 + CELL:
							push(w, o, o.pos - cp, 1.0, s.owner, "time_capsule")
							moved = true
	return moved


## 차례 종료 (pid 의 차례가 끝남): 시침 표식 → 시한 태엽 → 메트로놈 → 다시보기 잔상 → 느린 화살·쥐 → 진자·시곗바늘
static func turn_end(w, pid: int) -> bool:
	var moved := false
	for s in w.stones:
		if not s.alive:
			continue
		if s.owner == pid and s.status.has("hand_mark") and int(s.status["hand_mark"]["turn"]) < w.turn_no:
			var hm: Dictionary = s.status["hand_mark"]
			s.status.erase("hand_mark")
			push(w, s, hm["dir"], 1.5, int(hm["by"]), "hour_hammer")
			_ev(w, s.pos, int(hm["by"]), "hour_hammer", "시곗바늘이 민다", true)
			moved = true
	for s in w.stones:
		if s.alive and s.owner == pid and s.status.has("bomb") and int(s.status["bomb"]["round"]) < w.round_no:
			var bm: Dictionary = s.status["bomb"]
			s.status.erase("bomb")
			var out: Vector2 = s.pos.normalized() if s.pos.length() > 1.0 else Vector2.RIGHT
			push(w, s, out, 2.25 if bm.get("up", false) else 1.5, int(bm["by"]), "time_spring")
			_ev(w, s.pos, int(bm["by"]), "time_spring", "펑! 시한 태엽", true)
			moved = true
	for s in w.stones:
		if s.alive and s.owner != pid and s.status.has("metro") and _has(s, "aux", "metronome"):
			var side := 1 if int(s.status["metro"]) > 0 else -1
			s.status["metro"] = -side
			var sd := Vector2.from_angle(s.facing).orthogonal() * side
			var best = null
			var bd := 1.5 * CELL + R * 2.0
			for o in w.stones:
				if not o.alive or o.id == s.id:
					continue
				var off: Vector2 = o.pos - s.pos
				if off.length() < bd and off.normalized().dot(sd) > 0.5:
					bd = off.length()
					best = o
			_ev(w, s.pos + sd * CELL, s.owner, "metronome", "똑" if side > 0 else "딱")
			if best != null:
				push(w, best, best.pos - s.pos, 0.8, s.owner, "metronome")
				moved = true
			if P.up(s, "metronome"):
				for o2 in w.stones:
					if o2.alive and o2.id != s.id and o2 != best:
						var off2: Vector2 = o2.pos - s.pos
						if off2.length() < 1.5 * CELL + R * 2.0 and off2.normalized().dot(-sd) > 0.5:
							push(w, o2, off2, 0.8, s.owner, "metronome")
							moved = true
							break
	var st := state(w)
	var keep_r: Array = []
	for rp in st["replays"]:
		if int(rp["owner"]) == pid or int(rp["turn"]) >= w.turn_no:
			keep_r.append(rp)
			continue
		_ev(w, rp["path"][0], int(rp["owner"]), "replay_spring", "다시보기!", true)
		w.emit({"t": "replay", "path": rp["path"], "owner": int(rp["owner"])})
		moved = _sweep_path(w, rp["path"], int(rp["owner"]), "replay_spring", -1) or moved
		rp["left"] = int(rp.get("left", 1)) - 1
		if int(rp["left"]) > 0:
			rp["turn"] = w.turn_no
			keep_r.append(rp)
	st["replays"] = keep_r
	var keep_w: Array = []
	for wk in st["walkers"]:
		var dir: Vector2 = wk["dir"]
		var from: Vector2 = wk["pos"]
		var dist := (2.5 if wk["kind"] == "arrow" else 2.0) * CELL
		var to: Vector2 = from + dir * dist
		moved = _sweep_path(w, [from, to], int(wk["owner"]), "slow_arrow" if wk["kind"] == "arrow" else "wind_mouse", -1) or moved
		w.emit({"t": "walker", "kind": wk["kind"], "a": from, "b": to, "owner": int(wk["owner"])})
		wk["pos"] = to
		wk["left"] = int(wk["left"]) - 1
		if int(wk["left"]) > 0 and w.is_inside(to):
			keep_w.append(wk)
	st["walkers"] = keep_w
	for g in w.gimmicks:
		match g["kind"]:
			"pendulum":
				var it: Dictionary = g["items"][0]
				var a: Vector2 = it["a"]
				var b: Vector2 = it["b"]
				var at: int = int(it["at"])
				var from2: Vector2 = a if at == 0 else b
				var to2: Vector2 = b if at == 0 else a
				moved = _sweep_path(w, [from2, to2], -1, "gm_pendulum", -1, float(it["r"])) or moved
				it["at"] = 1 - at
				w.emit({"t": "walker", "kind": "pendulum", "a": from2, "b": to2, "owner": -1})
			"clockhand":
				var it2: Dictionary = g["items"][0]
				var a0: float = float(it2["ang"])
				var a1: float = a0 + deg_to_rad(30.0)
				var L: float = float(it2["len"])
				for s in w.stones:
					if not s.alive:
						continue
					var d: float = s.pos.length()
					if d > L + R or d < R:
						continue
					var ang: float = s.pos.angle()
					var rel := wrapf(ang - a0, 0.0, TAU)
					if rel <= a1 - a0 + R / maxf(d, 1.0):
						push(w, s, Vector2.from_angle(ang + PI / 2.0), 1.0, -1, "gm_clockhand")
						moved = true
				it2["ang"] = wrapf(a1, 0.0, TAU)
				w.emit({"t": "walker", "kind": "clockhand", "a": Vector2.from_angle(a0) * L, "b": Vector2.from_angle(a1) * L, "owner": -1})
	return moved


## 경로를 따라 지나가며 닿는 알을 진행 방향으로 민다 (잔상 · 느린 화살 · 쥐 · 진자)
static func _sweep_path(w, path: Array, owner: int, part: String, skip_id: int, rad := R) -> bool:
	var moved := false
	var hit := {}
	for i in range(path.size() - 1):
		var a: Vector2 = path[i]
		var b: Vector2 = path[i + 1]
		var seg := b - a
		if seg.length() < 0.5:
			continue
		var dir := seg.normalized()
		for s in w.stones:
			if not s.alive or s.id == skip_id or hit.has(s.id):
				continue
			var t := clampf((s.pos - a).dot(dir) / seg.length(), 0.0, 1.0)
			var q := a + seg * t
			if s.pos.distance_to(q) < w.radius_of(s) + rad:
				hit[s.id] = true
				var away: Vector2 = s.pos - q
				var pd := (dir + (away.normalized() * 0.5 if away.length() > 0.5 else Vector2.ZERO)).normalized()
				push(w, s, pd, 1.0, owner, part)
				moved = true
	return moved


## 샷 도중: 시곗바늘 막대(판 중심에서 뻗은 막대)와 진자 추는 단단한 장애물
static func collide(w) -> void:
	for g in w.gimmicks:
		if g["kind"] == "clockhand":
			var it: Dictionary = g["items"][0]
			var a := Vector2.ZERO
			var b: Vector2 = Vector2.from_angle(float(it["ang"])) * float(it["len"])
			for s in w.stones:
				if not s.alive:
					continue
				var seg := b - a
				var t := clampf((s.pos - a).dot(seg) / seg.length_squared(), 0.0, 1.0)
				var q := a + seg * t
				var d: Vector2 = s.pos - q
				var rr: float = w.radius_of(s) + 5.0
				if d.length() < rr and d.length() > 0.001:
					var nrm := d.normalized()
					s.pos = q + nrm * rr
					var vn: float = s.vel.dot(nrm)
					if vn < 0.0:
						s.vel = (s.vel - 2.0 * vn * nrm) * 0.7
						w.emit({"t": "hit", "pos": q, "strength": -vn, "a": s.id, "b": s.id, "n": nrm, "gimmick": "clockhand"})
		elif g["kind"] == "pendulum":
			var it2: Dictionary = g["items"][0]
			var bp: Vector2 = it2["a"] if int(it2["at"]) == 0 else it2["b"]
			for s in w.stones:
				if not s.alive:
					continue
				var rr2: float = w.radius_of(s) + float(it2["r"])
				var d2: Vector2 = s.pos - bp
				if d2.length() < rr2 and d2.length() > 0.001:
					var nrm2 := d2.normalized()
					s.pos = bp + nrm2 * rr2
					var vn2: float = s.vel.dot(nrm2)
					if vn2 < 0.0:
						s.vel = (s.vel - 2.0 * vn2 * nrm2) * 0.7
						w.emit({"t": "hit", "pos": bp + nrm2 * float(it2["r"]), "strength": -vn2, "a": s.id, "b": s.id, "n": nrm2, "gimmick": "pendulum"})
