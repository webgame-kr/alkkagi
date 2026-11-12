extends RefCounted
## 그랑 뮤제 (기획서 「그랑 뮤제 공방 기획서」). 명화·영화 명장면을 비튼 패러디 부품의 공방.
## 바닥 상태 지도 (SYS-13): 별밤 붓 · 점묘 분무기 자국과 복원실 물감. 칸 격자 대신 지나간 자리마다 둥근 자국을 남긴다.
## 부품 봉인 (SYS-14): 잃어버린 두 팔 조각. 봉인된 부품은 status["m_seal"] 에 넣어 두고 슬롯을 비운다.
## 반응형 회전·회피 (SYS-15): 따라오는 눈빛 액자 · 젖혀 피하기 선글라스 · 빗속의 빙글 우산.
## 설치물 청소 (SYS-16): 이삭 빗자루가 지뢰·함정·자국·구멍·레이저를 지운다.
## 판 전체 되감기 (SYS-17): 영화감독 세트 「컷! 다시 찍어!」는 match.gd 가 샷 직전 판을 통째로 저장해 둔다.
## 상태는 world.museum 에 둔다 (비어 있으면 이 공방이 아님).

const D = preload("res://scripts/sim/parts_data.gd")
const C = preload("res://scripts/sim/clock.gd")   # push · speed_for · _sweep_path
const P = preload("res://scripts/sim/parts.gd")
const CELL := 44.0
const R := 22.0
const FRONT_DOT := 0.75
const MARK_R := 0.6 * CELL
const MARK_GAP := 0.5 * CELL
const MARK_MAX := 40
const SWIRL_TURN := 2.4         # 별밤 붓 자국 위에서 초당 시계 방향으로 휘는 각 (rad)
const BOULDER_SPEED := 430.0
const FIN_R := 0.45 * CELL
const POST_R := 0.3 * CELL
const CART_R := 0.7 * CELL
const PAINT_R := 1.3 * CELL
const VELVET_GAP := 1.6 * CELL
const DOLLY_STEP := 3.0 * CELL
const LASER_LEN := 4.0 * CELL

## 발동 연출: paint(명화 · 금 액자와 화풍) / film(영화 · 영화 비율과 자막)
const ART := {
	"wave_print": ["paint", "wave", "종이에 목판", "1831년풍"],
	"finger_touch": ["paint", "fresco", "천장에 프레스코", "1512년풍"],
	"venus_arms": ["paint", "marble", "대리석 조각", "기원전 100년풍"],
	"scream_bridge": ["paint", "scream", "판지에 템페라", "1893년풍"],
	"follow_eyes": ["paint", "smile", "패널에 유채", "1503년풍"],
	"gleaner_broom": ["paint", "field", "캔버스에 유채", "1857년풍"],
	"starry_brush": ["paint", "star", "캔버스에 유채", "1889년풍"],
	"pointill_spray": ["paint", "dots", "점묘", "1886년풍"],
	"rolling_boulder": ["film", "", "", ""],
	"duel_holster": ["film", "", "", ""],
	"laser_glove": ["film", "", "", ""],
	"rain_umbrella": ["film", "", "", ""],
	"matrix_shades": ["film", "", "", ""],
	"shark_fin": ["film", "", "", ""],
}


static func on(w) -> bool:
	return not w.museum.is_empty()


static func setup(w) -> void:
	w.museum = {"marks": [], "lasers": [], "boulders": [], "fins": [], "film": 0}


static func _ev(w, pos: Vector2, owner: int, part: String, text: String, big := false) -> void:
	w.emit({"t": "part", "part": part, "pos": pos, "owner": owner, "text": text, "big": big})


static func _has(s, slot: String, part: String) -> bool:
	return s.parts.get(slot, "") == part


## 영화 부품이 발동하면 이번 판의 몇 번째 장면인지 (자막 「제○장」)
static func _film(w, pos: Vector2, owner: int, part: String, text: String) -> void:
	w.museum["film"] = int(w.museum.get("film", 0)) + 1
	w.emit({"t": "part", "part": part, "pos": pos, "owner": owner, "text": text, "big": true, "film": int(w.museum["film"])})


# ── 발사 ─────────────────────────────────────────────────

static func on_launch(w, s) -> void:
	if not on(w):
		return
	var sh = w.shot
	var dir: Vector2 = sh.dir
	match s.parts["weapon"]:
		"wave_print":
			# 정면 폭 2칸 · 길이 4칸의 파도가 앞의 알들을 함께 1.5칸 민다
			var L := (6.0 if P.up(s, "wave_print") else 4.0) * CELL
			for o in w.stones:
				if not o.alive or o.id == s.id:
					continue
				var off: Vector2 = o.pos - s.pos
				var along := off.dot(dir)
				if along > R * 0.5 and along < R + L and absf(off.cross(dir)) < CELL + R * 0.5:
					C.push(w, o, dir, 1.5, s.owner, "wave_print")
			w.emit({"t": "m_wave", "pos": s.pos, "dir": dir, "len": L, "owner": s.owner})
			_ev(w, s.pos + dir * CELL, s.owner, "wave_print", "큰 파도!", true)
		"rolling_boulder":
			var br := (1.25 if P.up(s, "rolling_boulder") else 1.0) * CELL
			w.museum["boulders"].append({"pos": s.pos + dir * (R + br + 4.0), "dir": dir, "r": br, "owner": s.owner, "hit": {s.id: true}})
			_film(w, s.pos, s.owner, "rolling_boulder", "굴러오는 신전 바위")
		"duel_holster":
			var foes: Array = []
			for o in w.stones:
				if o.alive and o.owner != s.owner:
					foes.append(o)
			foes.sort_custom(func(a, b): return a.pos.distance_squared_to(s.pos) < b.pos.distance_squared_to(s.pos))
			var shots := mini(foes.size(), 2 if P.up(s, "duel_holster") else 1)
			for i in shots:
				var aim: Vector2 = (foes[i].pos - s.pos).normalized()
				w.spawn_bullet(s.owner, s.pos + aim * (R + 6.0), aim, 380.0, "duel", s.id)
				w.emit({"t": "m_aimline", "a": s.pos, "b": foes[i].pos, "owner": s.owner})
			if shots > 0:
				_film(w, s.pos, s.owner, "duel_holster", "정오의 결투")
		"venus_arms":
			w.spawn_bullet(s.owner, s.pos + dir * (R + 6.0), dir, 220.0, "venus", s.id)
			if P.up(s, "venus_arms"):
				w.spawn_bullet(s.owner, s.pos + dir.rotated(0.18) * (R + 6.0), dir.rotated(0.18), 220.0, "venus", s.id)
		"megaphone":
			# 정면 부채꼴 「액션!」: 가장 가까운 첫 알을 0.6칸
			var best = null
			var bd := 3.0 * CELL + R
			for o in w.stones:
				if not o.alive or o.id == s.id:
					continue
				var off2: Vector2 = o.pos - s.pos
				if off2.length() < bd and off2.normalized().dot(dir) > 0.5:
					bd = off2.length()
					best = o
			if best != null:
				C.push(w, best, (best.pos - s.pos).normalized(), 0.6, s.owner, "megaphone")
			w.emit({"t": "cone", "pos": s.pos, "dir": dir, "radius": 3.0 * CELL, "owner": s.owner, "action": true})
			_ev(w, s.pos + dir * CELL, s.owner, "megaphone", "액션!", true)


## 매 단계 이동 전: 붓 자국 · 바위 · 피하기 · 눈빛 · 클래퍼 정지
static func before_move(w, dt: float) -> void:
	if not on(w):
		return
	var sh = w.shot
	var ms: Dictionary = w.museum
	# 클래퍼보드: 0.3초 동안 모든 알이 멈췄다가 하던 대로 다시 움직인다
	if sh != null and float(sh.ex.get("clap_t", 0.0)) > 0.0:
		sh.ex["clap_t"] = float(sh.ex["clap_t"]) - dt
		for s in w.stones:
			if s.alive and s.vel != Vector2.ZERO:
				var keep: Dictionary = sh.ex["clap_v"]
				keep[s.id] = (keep.get(s.id, Vector2.ZERO) as Vector2) + s.vel
				s.vel = Vector2.ZERO
		if float(sh.ex["clap_t"]) <= 0.0:
			sh.ex.erase("clap_t")
			var vs: Dictionary = sh.ex.get("clap_v", {})
			for id in vs:
				var st = w.get_stone(int(id))
				if st != null and st.alive:
					st.vel = vs[id]
			sh.ex.erase("clap_v")
		return
	if sh != null:
		var me = w.shooter()
		if me != null and me.alive:
			sh.ex["m_v"] = me.vel.length()
	# 별밤 붓 자국: 지나는 알이 시계 방향으로 휜다
	for mk in ms["marks"]:
		if mk["kind"] != "swirl" or (sh != null and int(mk["shot"]) == int(w.shot_no)):
			continue
		var mp: Vector2 = mk["pos"]
		for s in w.stones:
			if s.alive and s.vel != Vector2.ZERO and s.pos.distance_to(mp) < MARK_R:
				s.vel = s.vel.rotated(SWIRL_TURN * float(mk.get("k", 1.0)) * dt)
	# 굴러오는 신전 바위
	var keep_b: Array = []
	for b in ms["boulders"]:
		var bp: Vector2 = b["pos"]
		var bv: Vector2 = b["dir"]
		bp += bv * BOULDER_SPEED * dt
		b["pos"] = bp
		for s3 in w.stones:
			if not s3.alive or b["hit"].has(s3.id):
				continue
			if s3.pos.distance_to(bp) < w.radius_of(s3) + float(b["r"]):
				b["hit"][s3.id] = true
				var side := signf(bv.cross(s3.pos - bp))
				if side == 0.0:
					side = 1.0
				s3.vel += (bv.orthogonal() * side + bv * 0.35).normalized() * 420.0
				if w.record_events:
					s3.cause = {"owner": int(b["owner"]), "part": "rolling_boulder"}
		if w._inside_margin(bp, float(b["r"])):
			keep_b.append(b)
	ms["boulders"] = keep_b
	if sh == null:
		return
	# 상대 샷 중의 반응: 눈빛 액자(몸 돌리기) · 선글라스(피하기)
	for s in w.stones:
		if not s.alive or s.owner == sh.owner:
			continue
		var eyes := _has(s, "aux", "follow_eyes")
		var shades := _has(s, "prop", "matrix_shades")
		if not eyes and not shades:
			continue
		var threat = null
		var tdir := Vector2.ZERO
		var td := 99999.0
		for o in w.stones:
			if not o.alive or o.id == s.id or o.vel.length() < 160.0:
				continue
			var to: Vector2 = s.pos - o.pos
			var d := to.length()
			if d < td and d < 3.0 * CELL and o.vel.normalized().dot(to.normalized()) > 0.9:
				td = d
				threat = o
				tdir = o.vel.normalized()
		for p in w.projs:
			if not p.alive or p.kind != "bullet":
				continue
			var to2: Vector2 = s.pos - p.pos
			var d2 := to2.length()
			if d2 < td and d2 < 2.5 * CELL and p.vel.normalized().dot(to2.normalized()) > 0.97:
				td = d2
				threat = p
				tdir = p.vel.normalized()
		if threat == null:
			continue
		if eyes and not sh.used.has("eyes:%d" % s.id):
			var cap := 2 if P.up(s, "follow_eyes") else 1
			var used: Dictionary = s.status.get("eyes_n", {})
			if int(used.get("turn", -1)) != w.turn_no:
				used = {"turn": w.turn_no, "n": 0}
			if int(used["n"]) < cap:
				used["n"] = int(used["n"]) + 1
				s.status["eyes_n"] = used
				sh.used["eyes:%d" % s.id] = 1
				s.facing = (-tdir).angle()
				if "id" in threat:
					s.status["eyes_guard"] = int(threat.id)
				_ev(w, s.pos, s.owner, "follow_eyes", "눈빛이 따라온다", true)
		if shades and td < 1.8 * CELL and not sh.used.has("shades:%d" % s.id):
			var cap2 := 3 if P.up(s, "matrix_shades") else 2
			if int(s.status.get("shades_n", 0)) < cap2:
				var perp := tdir.orthogonal()
				if perp.dot(s.pos - (threat.pos as Vector2)) < 0.0:
					perp = -perp
				var spot: Vector2 = s.pos + perp * 1.1 * CELL
				if not w.is_inside(spot) or w.edge_distance(spot) < R:
					spot = s.pos - perp * 1.1 * CELL
				if w.is_inside(spot) and w.edge_distance(spot) >= R:
					sh.used["shades:%d" % s.id] = 1
					s.status["shades_n"] = int(s.status.get("shades_n", 0)) + 1
					var from: Vector2 = s.pos
					s.pos = spot
					w.emit({"t": "m_dodge", "a": from, "b": spot, "owner": s.owner, "stone": s.id})
					_film(w, spot, s.owner, "matrix_shades", "젖혀 피하기")


static func busy(w) -> bool:
	if not on(w):
		return false
	if not w.museum["boulders"].is_empty():
		return true
	return w.shot != null and w.shot.ex.has("clap_t")


## 이동 뒤: 붓·점묘 자국 남기기 · 레이저 선
static func after_move(w, _dt: float) -> void:
	if not on(w):
		return
	var ms: Dictionary = w.museum
	var sh = w.shot
	if sh != null:
		var s = w.shooter()
		if s != null and s.alive and s.vel != Vector2.ZERO:
			var kind := ""
			var k := 1.0
			if _has(s, "prop", "starry_brush"):
				kind = "swirl"
				k = 1.5 if P.up(s, "starry_brush") else 1.0
			elif _has(s, "prop", "pointill_spray"):
				kind = "dots"
				k = 2.0 if P.up(s, "pointill_spray") else 1.5
			if kind != "":
				var last: Vector2 = sh.ex.get("m_last", sh.start)
				if s.pos.distance_to(last) >= MARK_GAP and int(sh.ex.get("m_n", 0)) < MARK_MAX:
					sh.ex["m_last"] = s.pos
					sh.ex["m_n"] = int(sh.ex.get("m_n", 0)) + 1
					ms["marks"].append({"pos": s.pos, "kind": kind, "k": k, "until": w.round_no + 1, "owner": s.owner, "shot": w.shot_no})
					if int(sh.ex["m_n"]) == 1:
						_ev(w, s.pos, s.owner, s.parts["prop"], "붓 자국" if kind == "swirl" else "점묘 자국", true)
	# 레이저: 처음 닿은 움직이는 알은 그 자리에 멈춘다
	for lz in ms["lasers"]:
		var a: Vector2 = lz["a"]
		var b: Vector2 = lz["b"]
		var now := {}
		for o in w.stones:
			if not o.alive:
				continue
			var q := Geometry2D.get_closest_point_to_segment(o.pos, a, b)
			if o.pos.distance_to(q) < w.radius_of(o) * 0.8:
				now[o.id] = true
				if not lz["inside"].has(o.id) and o.vel.length() > 30.0:
					o.vel = Vector2.ZERO
					w.emit({"t": "part", "part": "laser_glove", "pos": o.pos, "owner": int(lz["owner"]), "text": "레이저에 멈춤"})
		lz["inside"] = now


## 바닥 상태 지도: 마찰 배율 (점묘 자국 · 복원실 물감)
static func friction_k(w, s) -> float:
	if not on(w):
		return 1.0
	var k := 1.0
	for mk in w.museum["marks"]:
		if mk["kind"] == "dots" and (w.shot == null or int(mk["shot"]) != int(w.shot_no)) and s.pos.distance_to(mk["pos"]) < MARK_R:
			k = maxf(k, float(mk["k"]))
	for g in w.gimmicks:
		if g["kind"] != "paint":
			continue
		for it in g["items"]:
			if s.pos.distance_to(it["pos"]) < float(it["r"]):
				k *= 0.5 if it["color"] == "red" else 2.0
	return k


## 공중 · 무게: 감독 의자를 편 알은 한 번 단단히 버틴다
static func mass_k(s) -> float:
	return 30.0 if s.status.has("chair") else 1.0


# ── 충돌 ─────────────────────────────────────────────────

static func on_contact(w, s, t, n: Vector2) -> void:
	if not on(w):
		return
	var sh = w.shot
	var front: bool = n.dot(sh.dir) >= FRONT_DOT
	var first: bool = not sh.used.has("mu_first")
	sh.used["mu_first"] = 1
	if first and _has(s, "prop", "clapper"):
		# 딱! 모든 알이 0.3초 멈춘다
		sh.ex["clap_t"] = 0.3
		sh.ex["clap_v"] = {}
		_ev(w, s.pos, s.owner, "clapper", "딱!", true)
	if first and _has(s, "aux", "scream_bridge"):
		var rr := (3.5 if P.up(s, "scream_bridge") else 2.5) * CELL
		var c: Vector2 = s.pos + n * R
		for o in w.stones:
			if not o.alive or o.id == s.id or o.id == t.id:
				continue
			var off: Vector2 = o.pos - c
			if off.length() < rr:
				C.push(w, o, off.normalized() if off.length() > 1.0 else n, 0.8, s.owner, "scream_bridge")
		w.emit({"t": "ripple", "pos": c, "radius": rr, "owner": s.owner, "scream": true})
		_ev(w, c, s.owner, "scream_bridge", "으아아아!", true)
	if front and _has(s, "weapon", "finger_touch") and not sh.used.has("finger_touch"):
		sh.used["finger_touch"] = 1
		var v0 := float(sh.ex.get("m_v", s.vel.length()))
		var k := 1.85 if P.up(s, "finger_touch") else 1.5
		t.vel = n * minf(v0 * k, w.MAX_SPEED * 1.15)
		s.vel *= 0.08
		if w.record_events:
			t.cause = {"owner": s.owner, "part": "finger_touch"}
		_ev(w, t.pos, s.owner, "finger_touch", "닿았다!", true)


## 모든 충돌 직후: 감독 의자 · 눈빛 액자의 정면 맞이
static func post_collision(w, a, b, imp: float) -> void:
	if not on(w):
		return
	for pair in [[a, b], [b, a]]:
		var x = pair[0]
		var y = pair[1]
		if x.status.has("chair") and imp > 60.0:
			x.status.erase("chair")
			_ev(w, x.pos, x.owner, "director_chair", "의자로 막았다")
		if int(x.status.get("eyes_guard", -1)) == y.id:
			x.status.erase("eyes_guard")
			var away: Vector2 = (y.pos - x.pos).normalized()
			C.push(w, y, away, 1.0, x.owner, "follow_eyes")
			x.vel *= 0.4
			_ev(w, x.pos, x.owner, "follow_eyes", "정면으로 맞이함")


## 탄환이 알에 닿을 때. true 면 밀지 않는다 (우산이 튕겨 냄)
static func on_bullet(w, s, p) -> bool:
	if not on(w):
		return false
	if s.status.has("umbrella") and s.id != p.ignore_id:
		var pd: Vector2 = p.vel.normalized()
		var face := Vector2.from_angle(s.facing)
		var frontal: bool = absf(pd.dot(face)) >= FRONT_DOT
		if not frontal or bool(s.status["umbrella"]):
			var out: Vector2 = -pd.rotated(0.35)
			p.vel = out * p.vel.length()
			p.pos = s.pos + out * (R + p.radius + 2.0)
			p.ignore_id = s.id
			p.age = 0.0
			p.source = "reflect"
			w.emit({"t": "reflect", "pos": s.pos, "owner": s.owner})
			_film(w, s.pos, s.owner, "rain_umbrella", "빗속의 빙글 우산")
			return true
	if p.source == "venus" and s.id != p.ignore_id:
		var sh = w.shooter()
		var both: bool = sh != null and P.up(sh, "venus_arms")
		seal(w, s, ["aux", "weapon"] if both else ["aux"], w.round_no + 1)
		_ev(w, s.pos, p.owner, "venus_arms", "부품 봉인!", true)
	return false


## 부품 봉인: 슬롯을 비우고 넣어 둔다. until 바퀴가 끝나면 돌아온다 (그 사이 새 부품을 달면 새 것이 남는다).
static func seal(w, s, slots: Array, until: int) -> void:
	var box: Dictionary = s.status.get("m_seal", {})
	for slot in slots:
		var part: String = s.parts.get(slot, "")
		if part == "":
			continue
		box[slot] = {"part": part, "up": bool(s.ups.get(slot, false)), "until": until}
		s.parts[slot] = ""
		s.ups.erase(slot)
	if not box.is_empty():
		s.status["m_seal"] = box


static func _unseal(w, round_no: int) -> void:
	for s in w.stones:
		if not s.status.has("m_seal"):
			continue
		var box: Dictionary = s.status["m_seal"]
		for slot in box.keys():
			if int(box[slot]["until"]) <= round_no:
				if s.parts.get(slot, "") == "":
					s.parts[slot] = box[slot]["part"]
					if bool(box[slot]["up"]):
						s.ups[slot] = true
				box.erase(slot)
		if box.is_empty():
			s.status.erase("m_seal")


## 쏜 알이 멈췄을 때
static func on_stop(w, s) -> void:
	if not on(w):
		return
	var face := Vector2.from_angle(s.facing)
	if _has(s, "aux", "gleaner_broom"):
		var n := sweep_installs(w, s.pos, (3.0 if P.up(s, "gleaner_broom") else 2.0) * CELL)
		w.emit({"t": "m_sweep", "pos": s.pos, "radius": (3.0 if P.up(s, "gleaner_broom") else 2.0) * CELL, "owner": s.owner})
		_ev(w, s.pos, s.owner, "gleaner_broom", "싹싹 · 설치물 %d개" % n if n > 0 else "싹싹", true)
	if _has(s, "aux", "laser_glove"):
		var segs: Array = []
		if P.up(s, "laser_glove"):
			for ang in [PI / 4.0, -PI / 4.0]:
				var d: Vector2 = face.rotated(ang)
				segs.append([s.pos - d * LASER_LEN * 0.5, s.pos + d * LASER_LEN * 0.5])
		else:
			var side: Vector2 = face.orthogonal() * float(s.magnet_side)
			segs.append([s.pos + side * R, s.pos + side * (R + LASER_LEN)])
		for sg in segs:
			var inside := {}
			for o in w.stones:
				if o.alive and o.pos.distance_to(Geometry2D.get_closest_point_to_segment(o.pos, sg[0], sg[1])) < w.radius_of(o):
					inside[o.id] = true
			w.museum["lasers"].append({"a": sg[0], "b": sg[1], "until": w.round_no + 1, "owner": s.owner, "inside": inside})
		_film(w, s.pos, s.owner, "laser_glove", "금고털이 레이저")
	if _has(s, "aux", "rain_umbrella"):
		s.status["umbrella"] = P.up(s, "rain_umbrella")
		_ev(w, s.pos, s.owner, "rain_umbrella", "우산을 폈다")
	if _has(s, "aux", "director_chair"):
		s.status["chair"] = true
		_ev(w, s.pos, s.owner, "director_chair", "감독 의자")
	if _has(s, "prop", "shark_fin"):
		var spot: Vector2 = s.pos - face * (R + FIN_R + 6.0)
		if not w.is_inside(spot):
			spot = s.pos + face.orthogonal() * (R + FIN_R + 6.0)
		w.museum["fins"].append({"pos": spot, "left": 5 if P.up(s, "shark_fin") else 3, "owner": s.owner})
		if P.up(s, "shark_fin"):
			w.museum["fins"].append({"pos": s.pos + face.orthogonal() * (R + FIN_R + 6.0), "left": 5, "owner": s.owner})
		_film(w, spot, s.owner, "shark_fin", "다가오는 등지느러미")


## 설치물 청소: 판 위 설치물 중 범위 안의 것을 지운다. 지운 개수.
static func sweep_installs(w, c: Vector2, r: float) -> int:
	var n := 0
	for d in w.devices.duplicate():
		if d.pos.distance_to(c) < r:
			w.devices.erase(d)
			w.emit({"t": "expire", "kind": d.kind, "pos": d.pos, "owner": d.owner})
			n += 1
	if not w.pirate.is_empty():
		for key in ["holes", "ramps", "chests"]:
			var before: int = w.pirate[key].size()
			w.pirate[key] = w.pirate[key].filter(func(x): return (x["pos"] as Vector2).distance_to(c) >= r)
			n += before - w.pirate[key].size()
	if not w.clock.is_empty() and w.clock.has("alarms"):
		var b0: int = w.clock["alarms"].size()
		w.clock["alarms"] = w.clock["alarms"].filter(func(x): return (x["pos"] as Vector2).distance_to(c) >= r)
		n += b0 - w.clock["alarms"].size()
	if on(w):
		var ms: Dictionary = w.museum
		var b1: int = ms["marks"].size()
		ms["marks"] = ms["marks"].filter(func(x): return (x["pos"] as Vector2).distance_to(c) >= r)
		if b1 != ms["marks"].size():
			n += 1
		var b2: int = ms["lasers"].size()
		ms["lasers"] = ms["lasers"].filter(func(x): return Geometry2D.get_closest_point_to_segment(c, x["a"], x["b"]).distance_to(c) >= r)
		n += b2 - ms["lasers"].size()
		var b3: int = ms["fins"].size()
		ms["fins"] = ms["fins"].filter(func(x): return (x["pos"] as Vector2).distance_to(c) >= r)
		n += b3 - ms["fins"].size()
	for g in w.gimmicks:
		if g["kind"] == "paint":
			var b4: int = g["items"].size()
			g["items"] = g["items"].filter(func(x): return (x["pos"] as Vector2).distance_to(c) >= r + float(x["r"]) * 0.5)
			n += b4 - g["items"].size()
	return n


static func end_shot(w) -> void:
	if not on(w):
		return
	for s in w.stones:
		s.status.erase("eyes_guard")


# ── 차례 이벤트 ──────────────────────────────────────────

## 차례 시작: 내 우산 · 의자는 접는다
static func turn_start(w, pid: int) -> bool:
	if not on(w):
		return false
	for s in w.stones:
		if s.owner == pid:
			s.status.erase("umbrella")
			s.status.erase("chair")
	return false


## 차례 종료: 등지느러미 · 벨벳 차단줄 · 촬영 레일 수레가 움직인다
static func turn_end(w, _pid: int) -> bool:
	if not on(w):
		return false
	var moved := false
	var keep: Array = []
	for f in w.museum["fins"]:
		var fp: Vector2 = f["pos"]
		var tgt = null
		var bd := 99999.0
		for s in w.stones:
			if s.alive and s.owner != int(f["owner"]) and s.pos.distance_to(fp) < bd:
				bd = s.pos.distance_to(fp)
				tgt = s
		if tgt != null:
			var dir: Vector2 = (tgt.pos - fp).normalized()
			var stop_at: float = R + FIN_R + 2.0
			var step := minf(CELL, maxf(0.0, bd - stop_at))
			var to: Vector2 = fp + dir * step
			w.emit({"t": "walker", "kind": "fin", "a": fp, "b": to, "owner": int(f["owner"])})
			f["pos"] = to
			if bd - step <= stop_at + 1.0:
				C.push(w, tgt, dir, 1.0, int(f["owner"]), "shark_fin")
				_ev(w, tgt.pos, int(f["owner"]), "shark_fin", "덥석!")
				moved = true
		f["left"] = int(f["left"]) - 1
		if int(f["left"]) > 0:
			keep.append(f)
	w.museum["fins"] = keep
	for g in w.gimmicks:
		match str(g["kind"]):
			"velvet":
				var it: Dictionary = g["items"][0]
				var c0: Vector2 = it["pos"]
				var mv: Vector2 = it["move"]
				var nxt: Vector2 = c0 + mv * CELL
				for p in velvet_posts(it, nxt):
					if (p as Vector2).length() > w.size - 1.4 * CELL:
						mv = -mv
						it["move"] = mv
						nxt = c0 + mv * CELL
						break
				var olds := velvet_posts(it, c0)
				var news := velvet_posts(it, nxt)
				for i in olds.size():
					if C._sweep_path(w, [olds[i], news[i]], -1, "gm_velvet", -1, POST_R):
						moved = true
				it["pos"] = nxt
				w.emit({"t": "walker", "kind": "velvet", "a": c0, "b": nxt, "owner": -1})
			"dolly":
				var it2: Dictionary = g["items"][0]
				var t0 := float(it2["t"])
				var dt0: float = float(it2["dir"]) * DOLLY_STEP / maxf(1.0, dolly_len(it2))
				var t1 := t0 + dt0
				if t1 > 1.0 or t1 < 0.0:
					it2["dir"] = -float(it2["dir"])
					t1 = clampf(t1, 0.0, 1.0)
				var path: Array = []
				for k in 7:
					path.append(dolly_point(it2, lerpf(t0, t1, k / 6.0)))
				if C._sweep_path(w, path, -1, "gm_dolly", -1, CART_R):
					moved = true
				it2["t"] = t1
				w.emit({"t": "walker", "kind": "dolly", "a": path[0], "b": path[path.size() - 1], "owner": -1})
	return moved


## 바퀴 끝: 1바퀴짜리 자국 · 레이저를 걷고 봉인을 푼다
static func round_end(w, round_no: int) -> void:
	if not on(w):
		return
	var ms: Dictionary = w.museum
	for key in ["marks", "lasers"]:
		ms[key] = ms[key].filter(func(x): return int(x["until"]) > round_no)
	_unseal(w, round_no)


# ── 기믹 ─────────────────────────────────────────────────

static func velvet_posts(it: Dictionary, c: Vector2) -> Array:
	var ax: Vector2 = it["axis"]
	return [c - ax * VELVET_GAP, c, c + ax * VELVET_GAP]


static func dolly_point(it: Dictionary, t: float) -> Vector2:
	var a: Vector2 = it["a"]
	var b: Vector2 = it["b"]
	var m: Vector2 = it["m"]
	return a.lerp(m, t).lerp(m.lerp(b, t), t)


static func dolly_len(it: Dictionary) -> float:
	var L := 0.0
	var prev := dolly_point(it, 0.0)
	for k in range(1, 17):
		var q := dolly_point(it, k / 16.0)
		L += prev.distance_to(q)
		prev = q
	return L


static func cart_pos(it: Dictionary) -> Vector2:
	return dolly_point(it, float(it["t"]))


## 샷 도중: 벨벳 기둥 · 줄, 카메라 수레는 단단한 장애물
static func collide(w) -> void:
	if not on(w):
		return
	for g in w.gimmicks:
		match str(g["kind"]):
			"velvet":
				var it: Dictionary = g["items"][0]
				var posts := velvet_posts(it, it["pos"])
				for p in posts:
					_solid(w, p, POST_R, 0.75, "velvet")
				for i in 2:
					_wall(w, posts[i], posts[i + 1], 5.0, 0.55)
			"dolly":
				_solid(w, cart_pos(g["items"][0]), CART_R, 0.6, "dolly")


static func _solid(w, bp: Vector2, rad: float, keep: float, kind: String) -> void:
	for s in w.stones:
		if not s.alive:
			continue
		var rr: float = w.radius_of(s) + rad
		var d: Vector2 = s.pos - bp
		if d.length() < rr and d.length() > 0.001:
			var nrm := d.normalized()
			s.pos = bp + nrm * rr
			var vn: float = s.vel.dot(nrm)
			if vn < 0.0:
				s.vel = (s.vel - 2.0 * vn * nrm) * keep
				w.emit({"t": "hit", "pos": bp + nrm * rad, "strength": -vn, "a": s.id, "b": s.id, "n": nrm, "gimmick": kind})


static func _wall(w, a: Vector2, b: Vector2, half: float, keep: float) -> void:
	for s in w.stones:
		if not s.alive:
			continue
		var q := Geometry2D.get_closest_point_to_segment(s.pos, a, b)
		var d: Vector2 = s.pos - q
		var rr: float = w.radius_of(s) + half
		if d.length() < rr and d.length() > 0.001:
			var nrm := d.normalized()
			s.pos = q + nrm * rr
			var vn: float = s.vel.dot(nrm)
			if vn < 0.0:
				s.vel = (s.vel - 2.0 * vn * nrm) * keep
				w.emit({"t": "hit", "pos": q, "strength": -vn, "a": s.id, "b": s.id, "n": nrm, "gimmick": "velvet"})


## 알을 놓을 수 있는지 (기둥 · 수레와 0.5칸 이상)
static func blocks(w, p: Vector2, margin: float) -> bool:
	for g in w.gimmicks:
		if g["kind"] == "velvet":
			for q in velvet_posts(g["items"][0], g["items"][0]["pos"]):
				if p.distance_to(q) < R + POST_R + margin:
					return true
		if g["kind"] == "dolly":
			if p.distance_to(cart_pos(g["items"][0])) < R + CART_R + margin:
				return true
	return false
