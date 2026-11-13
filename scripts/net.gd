extends Node
## 친구 초대(온라인) 연결. 웹 빌드에서만 동작한다: web/alkkagi_net.js (PeerJS) 를 JavaScriptBridge 로 부른다.
## 메시지는 사전(JSON). poll() 이 쌓인 메시지를 [{from, data}] 로 돌려준다.

var available := false
var _js = null


func _ready() -> void:
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("AlkNet")
		available = _js != null


func status() -> String:
	return str(_js.status) if available else "idle"


func error_text() -> String:
	return str(_js.error) if available else "웹에서만 친구 초대를 쓸 수 있어요"


## [단계(signal|connect), 시도 번호, 지난 초]
func detail() -> Array:
	if not available:
		return ["", 1, 0]
	var parts := str(_js.detail()).split(" ")
	return [parts[0] if parts.size() > 0 else "", int(parts[1]) if parts.size() > 1 else 1, int(parts[2]) if parts.size() > 2 else 0]


## 이 기기 표시 (다시 들어와도 같은 자리를 돌려받기 위해)
func token() -> String:
	return str(_js.token()) if available else "local"


## peer 에게서 마지막으로 받은 뒤 지난 초 (-1 = 모름)
func quiet(peer: String) -> int:
	return int(_js.quiet(peer)) if available else -1


func code() -> String:
	return str(_js.code) if available else ""


func my_id() -> String:
	return str(_js.myId) if available else ""


func host() -> String:
	return str(_js.host()) if available else ""


func join(room: String) -> void:
	if available:
		_js.join(room)


func close() -> void:
	if available:
		_js.close()


func send_to(peer: String, msg: Dictionary) -> void:
	if available:
		_js.send(peer, JSON.stringify(msg))


func broadcast(msg: Dictionary, except := "") -> void:
	if available:
		_js.broadcast(JSON.stringify(msg), except)


func poll() -> Array:
	if not available:
		return []
	var raw = JSON.parse_string(str(_js.poll()))
	return raw if raw is Array else []


func room_param() -> String:
	return str(_js.roomParam()) if available else ""


func invite_url(c: String) -> String:
	return str(_js.inviteUrl(c)) if available else ""


func copy(text: String) -> void:
	if available:
		_js.copy(text)
