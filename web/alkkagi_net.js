// 개조 알까기 친구 초대: PeerJS(공개 시그널 서버 0.peerjs.com) 위의 아주 작은 중계.
// 게임(GDScript)은 JavaScriptBridge 로 window.AlkNet 을 부른다.
// 호스트가 방을 열면 친구들은 링크(?room=코드)로 들어와 호스트에 직접 연결된다 (별 모양).
// 받은 메시지는 inbox 에 쌓이고, 게임이 매 프레임 poll() 로 가져간다.
(function () {
  var PREFIX = "alkkagi-v1-";
  // 직접 연결이 막힌 네트워크(휴대폰 데이터, 회사·학교 와이파이)를 위해 주소 확인(STUN)과 중계(TURN) 서버를 여럿 둔다.
  var ICE = {
    iceServers: [
      { urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302", "stun:stun2.l.google.com:19302"] },
      { urls: "stun:stun.cloudflare.com:3478" },
      { urls: ["turn:eu-0.turn.peerjs.com:3478", "turn:us-0.turn.peerjs.com:3478"], username: "peerjs", credential: "peerjsp" },
      { urls: ["turn:openrelay.metered.ca:80", "turn:openrelay.metered.ca:443", "turn:openrelay.metered.ca:443?transport=tcp"], username: "openrelayproject", credential: "openrelayproject" }
    ]
  };
  var JOIN_WAIT = 12000;   // 이만큼 지나도 안 이어지면 한 번 더 시도
  var JOIN_TRIES = 3;
  var net = {
    ver: 5,
    peer: null,
    conns: {},        // peerId -> DataConnection
    inbox: [],
    status: "idle",   // idle | opening | hosting | joining | joined | error | closed
    error: "",
    code: "",
    myId: "",

    _push: function (from, data) {
      net.inbox.push({ from: from, data: data });
    },

    seen: {},         // peerId -> 마지막으로 무엇이든 받은 시각 (ms)

    _gone: function (conn) {
      if (conn._gone) return;
      conn._gone = true;
      if (net.conns[conn.peer] === conn) delete net.conns[conn.peer];
      delete net.seen[conn.peer];
      net._push(conn.peer, { t: "_left" });
    },

    _wire: function (conn) {
      conn.on("data", function (d) {
        net.seen[conn.peer] = Date.now();
        var msg = d;
        if (typeof d === "string") { try { msg = JSON.parse(d); } catch (e) { return; } }
        // 연결 확인은 게임이 멈춰 있어도(다른 탭) 여기서 바로 답한다
        if (msg && msg.t === "_ping") { try { conn.send('{"t":"_pong"}'); } catch (e) {} return; }
        if (msg && msg.t === "_pong") return;
        net._push(conn.peer, msg);
      });
      conn.on("open", function () { net.seen[conn.peer] = Date.now(); });
      conn.on("close", function () { net._gone(conn); });
      conn.on("error", function () { net._gone(conn); });
    },

    // 2초마다 연결 확인. 30초 동안 아무것도 못 받으면 끊긴 것으로 본다 (휴대폰이 잠깐 다른 앱에 가도 버티게).
    _tick: function () {
      var now = Date.now();
      for (var k in net.conns) {
        var c = net.conns[k];
        if (!c.open) continue;
        try { c.send('{"t":"_ping"}'); } catch (e) {}
        var last = net.seen[k] || now;
        if (!net.seen[k]) net.seen[k] = now;
        if (now - last > 30000) { try { c.close(); } catch (e) {} net._gone(c); }
      }
    },

    // 이 기기 표시 (다시 들어와도 같은 자리를 돌려받기 위해)
    token: function () {
      try {
        var t = localStorage.getItem("alk_token");
        if (!t) { t = Math.random().toString(36).slice(2) + Date.now().toString(36); localStorage.setItem("alk_token", t); }
        return t;
      } catch (e) {
        if (!net._tok) net._tok = Math.random().toString(36).slice(2);
        return net._tok;
      }
    },

    // 마지막 연락 뒤 지난 초 (손님: 방장)
    quiet: function (peer) {
      var t = net.seen[peer];
      return t ? Math.floor((Date.now() - t) / 1000) : -1;
    },

    randomCode: function () {
      var a = "abcdefghjkmnpqrstuvwxyz23456789", s = "";
      for (var i = 0; i < 6; i++) s += a[Math.floor(Math.random() * a.length)];
      return s;
    },

    host: function () {
      if (typeof Peer === "undefined") { net.status = "error"; net.error = "연결 라이브러리를 불러오지 못했어요"; return ""; }
      net.close();
      net.code = net.randomCode();
      net.status = "opening";
      net.peer = new Peer(PREFIX + net.code, { config: ICE });
      net.peer.on("open", function (id) { net.myId = id; net.status = "hosting"; });
      net.peer.on("connection", function (conn) {
        conn.on("open", function () {
          net.conns[conn.peer] = conn;
          net._push(conn.peer, { t: "_joined" });
        });
        net._wire(conn);
      });
      net.peer.on("error", function (e) {
        if (e && e.type === "unavailable-id") { net.host(); return; }
        net.status = "error"; net.error = String(e && e.type || e);
      });
      net.peer.on("disconnected", function () { if (net.peer && !net.peer.destroyed) net.peer.reconnect(); });
      return net.code;
    },

    join: function (code, tryNo) {
      if (typeof Peer === "undefined") { net.status = "error"; net.error = "연결 라이브러리를 불러오지 못했어요"; return; }
      tryNo = tryNo || 1;
      net.close();
      net.code = code;
      net.status = "joining";
      net.tryNo = tryNo;
      net.stage = "signal";
      if (tryNo === 1) net.t0 = Date.now();
      var mine = net.peer = new Peer({ config: ICE });
      clearTimeout(net._timer);
      net._timer = setTimeout(function () {
        if (net.peer !== mine || net.status !== "joining") return;
        if (tryNo < JOIN_TRIES) { net.join(code, tryNo + 1); return; }
        net.status = "error";
        net.error = net.stage === "signal"
          ? "연결 서버에 닿지 못했어요 (VPN · 광고 차단 · 회사/학교 네트워크가 막고 있을 수 있어요)"
          : "방장 기기와 직접 연결이 안 돼요 (와이파이를 바꾸거나 휴대폰 핫스팟으로 해 보세요)";
      }, JOIN_WAIT);
      net.peer.on("open", function (id) {
        net.myId = id;
        net.stage = "connect";
        var conn = net.peer.connect(PREFIX + code, { reliable: true });
        conn.on("open", function () {
          net.conns[conn.peer] = conn;
          net.status = "joined";
          net._push(conn.peer, { t: "_open" });
        });
        net._wire(conn);
      });
      net.peer.on("error", function (e) {
        if (net.peer !== mine) return;
        clearTimeout(net._timer);
        net.status = "error";
        net.error = (e && e.type === "peer-unavailable") ? "방을 찾을 수 없어요 (호스트가 닫았거나 코드가 틀려요)" : String(e && e.type || e);
      });
    },

    send: function (to, json) {
      var c = net.conns[to];
      if (c && c.open) c.send(json);
    },

    broadcast: function (json, except) {
      for (var k in net.conns) {
        if (k !== except && net.conns[k].open) net.conns[k].send(json);
      }
    },

    poll: function () {
      var out = JSON.stringify(net.inbox);
      net.inbox = [];
      return out;
    },

    // 연결이 어디까지 왔는지: "signal 2 14" = 연결 서버 접속 중 · 2번째 시도 · 14초째
    detail: function () {
      return (net.stage || "") + " " + (net.tryNo || 1) + " " + Math.floor((Date.now() - (net.t0 || Date.now())) / 1000);
    },

    peers: function () { return JSON.stringify(Object.keys(net.conns)); },

    close: function () {
      for (var k in net.conns) { try { net.conns[k].close(); } catch (e) {} }
      net.conns = {};
      if (net.peer) { try { net.peer.destroy(); } catch (e) {} }
      net.peer = null;
      net.status = "idle";
      net.error = "";
    },

    roomParam: function () {
      var m = /[?&]room=([a-z0-9]+)/.exec(location.search);
      return m ? m[1] : "";
    },

    inviteUrl: function (code) {
      return location.origin + location.pathname + "?room=" + code;
    },

    copy: function (text) {
      try { navigator.clipboard.writeText(text); return true; } catch (e) { return false; }
    }
  };
  setInterval(net._tick, 2000);
  // 방장이 다른 탭·앱으로 가면 게임이 멈춘다: 손님들에게 알린다
  document.addEventListener("visibilitychange", function () {
    if (net.status === "hosting") net.broadcast(JSON.stringify({ t: "_away", on: document.hidden }));
  });
  window.AlkNet = net;
})();
