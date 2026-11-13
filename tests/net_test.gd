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

	var tok := ""

	func token() -> String:
		return tok

	func quiet(_p: String) -> int:
		return 0

	func detail() -> Array:
		return ["", 1, 0]


var host
var guest
var frames := 0
var started := false


var stale_hint := 0
var drop_mode := ""          # "draft": 손님이 첫 개조 중에 끊긴다 · "rejoin": 끊겼다가 다시 들어온다
var dropped := false
var drop_frame := -1
var rejoined := false


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
	for ws in ["magic", "toon", "lab", "clock", "pirate"]:
		if OS.get_cmdline_user_args().has(ws):
			host.settings["workshop"] = ws
	for md in ["derby", "crown", "parcel"]:
		if OS.get_cmdline_user_args().has(md):
			host.settings["mode"] = md
	host.settings["cpu"] = [false, false, true, true, true, true, true, true]
	host.settings["friend"] = [false, true, false, false, false, false, false, false]
	host.online = "host"
	hn.st = "hosting"
	guest.online = "guest"
	gn.st = "joined"
	guest.host_peer = "host"
	host.friend_peer[1] = "guest"
	gn.tok = "T1"
	host.room_tokens[1] = "T1"
	host._host_broadcast_lobby()


func _drive(g) -> void:
	if g.state != "play" or g.m == null or g.turn_hold > 0.0 or g.waiting_req or g.catchup:
		return
	if g.m.phase != "draft" and not g.net_queue.is_empty():
		return
	var m = g.m
	if m.phase == "place":
		for pid in g.my_seats:
			if not m.placements.has(pid) and not g.place_sent.has(pid):
				g._send_place(pid, m.preset(pid, "line"))
		return
	if m.phase == "draft":
		# 동시 선택: 내 자리면 내 차례가 아니어도 바로 고른다
		for pid in m.draft_queue:
			if g._is_mine(pid) and g.picked_round.get(pid, -1) != m.round_no:
				var part: String = m.offers[pid][0]
				var st = m.world.alive_stones_of(pid)[0]
				g._apply_equip(pid, part, st.id, 1, "")
	elif m.phase == "aim":
		# 개조가 끝나 쏘는 차례가 되면 「골랐어요」 안내가 남아 있으면 안 된다
		if g.overlay != null and _has_text(g.overlay, "골랐어요"):
			stale_hint += 1
			if stale_hint < 3:
				print("  stale: %s round=%d phase=%s q=%s picked=%s my=%s catch=%s" % ["guest" if g == guest else "host", m.round_no, m.phase, g.net_queue.size(), g.picked_round, g.my_seats, g.catchup])
		var pid2: int = m.current_player()
		if g._is_mine(pid2) and not g.has_meta("acted_%d" % m.shots):
			g.set_meta("acted_%d" % m.shots, true)
			var mine: Array = m.world.alive_stones_of(pid2)
			var s = mine[frames % mine.size()]
			var dir: Vector2 = (-s.pos).normalized().rotated(0.3 * sin(frames))
			g._act({"k": "shot", "pid": pid2, "stone": s.id, "dir": [dir.x, dir.y], "power": 0.75, "charged": true})


func _drop_guest() -> void:
	dropped = true
	drop_frame = frames
	host.net.peers.erase("guest")
	guest.net.peers.erase("host")
	host.net.inbox.append({"from": "guest", "data": {"t": "_left"}})


func _rejoin_guest() -> void:
	rejoined = true
	var gn = guest.net
	gn.me = "guest2"
	host.net.peers["guest2"] = gn
	gn.peers["host"] = host.net
	guest.net.inbox.append({"from": "host", "data": {"t": "_open"}})


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 1:
		for a in OS.get_cmdline_user_args():
			if a == "drop" or a == "rejoin":
				drop_mode = a
	if drop_mode != "" and started and not dropped and host.state == "play" and host.m != null and host.m.phase == "draft" and host.m.round_no >= 2:
		_drop_guest()
	if drop_mode == "rejoin" and dropped and not rejoined and frames > drop_frame + 40:
		_rejoin_guest()
	if drop_mode == "drop" and dropped and started and host.state == "result":
		print("NET OK drop: host finished alone rounds=%d frames=%d" % [host.m.round_no, frames])
		quit(0)
		return false
	if frames == 3:
		_wire()
	if frames == 4:
		guest._send_chat("  안녕하세요 반가워요  ")
	if frames == 5:
		var ok_chat: bool = not host.chat_log.is_empty() and str(host.chat_log[-1]["text"]) == "안녕하세요 반가워요"
		if not ok_chat:
			print("NET CHAT FAIL host=%s" % [host.chat_log])
			quit(1)
		host._start_match()
		started = true
	if started:
		for i in 4:
			for g in [host, guest]:
				if g == guest and dropped and not rejoined:
					continue
				_drive(g)
				if g.state == "play":
					if g.catchup:
						g._catch_up()
					else:
						g._update_play(0.05)
	if started and frames == 200 and host.state == "play" and not dropped:
		guest._send_chat("경기 중 채팅")
	if started and frames == 210 and host.state == "play" and not dropped:
		if host.chat_log.is_empty() or str(host.chat_log[-1]["text"]) != "경기 중 채팅" or guest.chat_log.is_empty() or str(guest.chat_log[-1]["text"]) != "경기 중 채팅":
			print("NET CHAT FAIL in play host=%s guest=%s" % [host.chat_log.back() if not host.chat_log.is_empty() else "-", guest.chat_log.back() if not guest.chat_log.is_empty() else "-"])
			quit(1)
	if started and host.state == "result" and guest.state == "result":
		var ok := true
		for i in host.m.world.stones.size():
			var a = host.m.world.stones[i]
			var b = guest.m.world.stones[i]
			if a.alive != b.alive or a.pos.distance_to(b.pos) > 0.001:
				ok = false
				print("  mismatch stone %d: %s %s vs %s %s" % [i, a.alive, a.pos, b.alive, b.pos])
		ok = ok and str(host.m.winners) == str(guest.m.winners)
		if stale_hint > 0:
			print("  '골랐어요' 안내가 쏘는 차례에도 남아 있음: %d프레임" % stale_hint)
			ok = false
		if drop_mode == "rejoin":
			print("  rejoined=%s" % rejoined)
			ok = ok and rejoined
		print("NET %s rounds=%d shots=%d winners=%s/%s frames=%d" % ["OK" if ok else "DESYNC", host.m.round_no, host.m.shots, host.m.winners, guest.m.winners, frames])
		quit(0 if ok else 1)
	elif frames > 120000:
		print("NET TIMEOUT host=%s/%s guest=%s/%s" % [host.state, host.m.phase if host.m else "-", guest.state, guest.m.phase if guest.m else "-"])
		quit(1)
	return false


func _has_text(n: Node, t: String) -> bool:
	if n is Label and (n as Label).text.begins_with(t):
		return true
	for c in n.get_children():
		if _has_text(c, t):
			return true
	return false
