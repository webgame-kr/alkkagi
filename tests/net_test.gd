extends SceneTree
## 온라인 대전 동기화 테스트: 게임 둘(호스트·손님)을 가짜 연결로 이어 한 판을 끝까지 두고,
## 두 기기의 퍽 위치·승자가 똑같은지 본다.
##   godot --headless --path . -s res://tests/net_test.gd


class FakeNet:
	extends Node
	var available := true
	var me := ""
	var peers := {}      # id -> FakeNet
	var inbox: Array = []
	var st := "idle"

	func status() -> String:
		return st

	func error_text() -> String:
		return ""

	func code() -> String:
		return "test01"

	func my_id() -> String:
		return me

	func host() -> String:
		st = "hosting"
		return "test01"

	func join(_c: String) -> void:
		st = "joined"

	func close() -> void:
		st = "idle"

	func send_to(peer: String, msg: Dictionary) -> void:
		if peers.has(peer):
			peers[peer].inbox.append({"from": me, "data": JSON.parse_string(JSON.stringify(msg))})

	func broadcast(msg: Dictionary, except := "") -> void:
		for p in peers:
			if p != except:
				send_to(p, msg)

	func poll() -> Array:
		var out := inbox
		inbox = []
		return out

	func room_param() -> String:
		return ""

	func invite_url(_c: String) -> String:
		return ""

	func copy(_t: String) -> void:
		pass


var host
var guest
var frames := 0
var started := false


func _initialize() -> void:
	var scene = load("res://scenes/main.tscn")
	host = scene.instantiate()
	guest = scene.instantiate()
	root.add_child(host)
	root.add_child(guest)


func _wire() -> void:
	var hn := FakeNet.new()
	hn.me = "host"
	var gn := FakeNet.new()
	gn.me = "guest"
	hn.peers = {"guest": gn}
	gn.peers = {"host": hn}
	host.remove_child(host.net)
	host.net = hn
	host.add_child(hn)
	guest.remove_child(guest.net)
	guest.net = gn
	guest.add_child(gn)
	host.settings["speed"] = 2
	host.settings["n"] = 4
	host.settings["cpu"] = [false, false, true, true, true, true, true, true]
	host.settings["friend"] = [false, true, false, false, false, false, false, false]
	host.online = "host"
	hn.st = "hosting"
	guest.online = "guest"
	gn.st = "joined"
	guest.host_peer = "host"
	host.friend_peer[1] = "guest"
	host._host_broadcast_lobby()


func _drive(g) -> void:
	if g.state != "play" or g.m == null or g.turn_hold > 0.0 or g.waiting_req:
		return
	if g.m.phase != "draft" and not g.net_queue.is_empty():
		return
	var m = g.m
	if m.phase == "draft":
		# 동시 선택: 내 자리면 내 차례가 아니어도 바로 고른다
		for pid in m.draft_queue:
			if g._is_mine(pid) and g.picked_round.get(pid, -1) != m.round_no:
				var part: String = m.offers[pid][0]
				var st = m.world.alive_stones_of(pid)[0]
				g._apply_equip(pid, part, st.id, 1, "")
	elif m.phase == "aim":
		var pid2: int = m.current_player()
		if g._is_mine(pid2) and not g.has_meta("acted_%d" % m.shots):
			g.set_meta("acted_%d" % m.shots, true)
			var mine: Array = m.world.alive_stones_of(pid2)
			var s = mine[frames % mine.size()]
			var dir: Vector2 = (-s.pos).normalized().rotated(0.3 * sin(frames))
			g._act({"k": "shot", "pid": pid2, "stone": s.id, "dir": [dir.x, dir.y], "power": 0.75, "charged": true})


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_wire()
	if frames == 5:
		host._start_match()
		started = true
	if started:
		for i in 4:
			for g in [host, guest]:
				_drive(g)
				if g.state == "play":
					g._update_play(0.05)
	if started and host.state == "result" and guest.state == "result":
		var ok := true
		for i in host.m.world.stones.size():
			var a = host.m.world.stones[i]
			var b = guest.m.world.stones[i]
			if a.alive != b.alive or a.pos.distance_to(b.pos) > 0.001:
				ok = false
				print("  mismatch stone %d: %s %s vs %s %s" % [i, a.alive, a.pos, b.alive, b.pos])
		ok = ok and str(host.m.winners) == str(guest.m.winners)
		print("NET %s rounds=%d shots=%d winners=%s/%s frames=%d" % ["OK" if ok else "DESYNC", host.m.round_no, host.m.shots, host.m.winners, guest.m.winners, frames])
		quit(0 if ok else 1)
	elif frames > 120000:
		print("NET TIMEOUT host=%s/%s guest=%s/%s" % [host.state, host.m.phase if host.m else "-", guest.state, guest.m.phase if guest.m else "-"])
		quit(1)
	return false
