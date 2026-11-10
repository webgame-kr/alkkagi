extends SceneTree
## 화면 스크립트를 실제로 띄워 CPU끼리 한 판을 끝까지 돌린다 (그리기·UI 코드 경로 점검).
##   godot --headless --path . -s res://tests/smoke_game.gd -- 4

var game
var frames := 0
var n := 4


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		n = int(args[0])
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		game.settings["n"] = n
		for i in 8:
			game.settings["cpu"][i] = true
		game.settings["timed"] = n >= 5
		if OS.get_cmdline_user_args().has("derby"):
			game.settings["mode"] = "derby"
		if OS.get_cmdline_user_args().has("toon"):
			game.settings["workshop"] = "toon"
		if OS.get_cmdline_user_args().has("magic"):
			game.settings["workshop"] = "magic"
		game._start_match()
	if frames > 2:
		# 빠르게: 한 프레임에 여러 번 진행
		for i in 6:
			if game.state == "play":
				game._update_play(0.05)
		if frames % 20 == 0:
			game._show_catalog(false)
			game._clear_overlay()
	if game.state == "result":
		print("RESULT n=%d round=%d shots=%d winners=%s reason=%s frames=%d" % [n, game.m.round_no, game.m.shots, str(game.m.winners), game.m.end_reason, frames])
		quit(0)
	elif frames > 60000:
		print("TIMEOUT phase=%s round=%d" % [game.m.phase, game.m.round_no])
		quit(1)
	return false
