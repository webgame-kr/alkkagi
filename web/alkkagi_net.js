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
      { urls: "stun:stun.cloudflare.com:3478" }
      // 무료 중계(TURN) 서버들은 더 이상 동작하지 않아 뺐다. 직접 연결이 안 되면 아래 MQTT 중계로 넘어간다.
    ]
  };
  var JOIN_WAIT = 12000;   // 이만큼 지나도 안 이어지면 중계로 넘어간다
  var JOIN_TRIES = 1;
  // 직접 연결(WebRTC)이 안 되는 친구를 위한 중계: 공개 MQTT 서버(웹소켓)로 방장과 메시지를 주고받는다.
  var BROKERS = ["wss://broker.emqx.io:8084/mqtt", "wss://test.mosquitto.org:8081/mqtt"];
  var TOPIC = "alkkagi-v1/";
  function rid() { return Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 6); }
  var net = {
    ver: 6,
    relays: [],       // 연결된 중계 클라이언트
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
      net._relayHost(net.code);
      return net.code;
    },

    // 중계 가짜 연결: 게임 쪽에서는 보통 연결과 똑같이 보인다
    _relayConn: function (peerId, cli, topic, myId) {
      var c = {
        peer: peerId, open: true, relay: true,
        send: function (json) { if (c.open) cli.publish(topic, JSON.stringify({ f: myId, d: json })); },
        close: function () {
          if (!c.open) return;
          try { cli.publish(topic, JSON.stringify({ f: myId, d: '{"t":"_bye"}' })); } catch (e) {}
          c.open = false;
        }
      };
      return c;
    },

    // 중계로 받은 것 처리 (from: 보낸 쪽 이름, json: 문자열)
    _relayIn: function (from, json) {
      var msg;
      try { msg = typeof json === "string" ? JSON.parse(json) : json; } catch (e) { return; }
      var c = net.conns[from];
      net.seen[from] = Date.now();
      if (!msg) return;
      if (msg.t === "_ping") { if (c) c.send('{"t":"_pong"}'); return; }
      if (msg.t === "_pong") return;
      if (msg.t === "_bye") { if (c) { c.open = false; net._gone(c); } return; }
      net._push(from, msg);
    },

    _mqtt: function (url, onConnect, onFail) {
      if (typeof mqtt === "undefined") { onFail(); return null; }
      var done = false;
      var cli;
      try {
        cli = mqtt.connect(url, { connectTimeout: 7000, reconnectPeriod: 3000, clientId: "alk" + rid(), keepalive: 20 });
      } catch (e) { onFail(); return null; }
      var to = setTimeout(function () { if (!done) { done = true; try { cli.end(true); } catch (e) {} onFail(); } }, 8000);
      cli.on("connect", function () { if (done) return; done = true; clearTimeout(to); onConnect(cli); });
      cli.on("error", function () { if (done) return; done = true; clearTimeout(to); try { cli.end(true); } catch (e) {} onFail(); });
      return cli;
    },

    _relayHost: function (code) {
      var hostTopic = TOPIC + code + "/h";
      BROKERS.forEach(function (url) {
        net._mqtt(url, function (cli) {
          if (net.code !== code || net.status === "closed") { cli.end(true); return; }
          net.relays.push(cli);
          cli.subscribe(hostTopic);
          cli.on("message", function (topic, payload) {
            if (topic !== hostTopic) return;
            var m;
            try { m = JSON.parse(payload.toString()); } catch (e) { return; }
            if (!m || !m.f) return;
            var from = "relay-" + m.f;
            var inner;
            try { inner = JSON.parse(m.d); } catch (e) { return; }
            if (inner && inner.t === "_hi") {
              var old = net.conns[from];
              if (!old || !old.open) {
                var c = net._relayConn(from, cli, TOPIC + code + "/g/" + m.f, "h");
                net.conns[from] = c;
                net.seen[from] = Date.now();
                net._push(from, { t: "_joined" });
              }
              net.conns[from].send('{"t":"_welcome"}');
              return;
            }
            if (!net.conns[from]) return;
            net._relayIn(from, m.d);
          });
        }, function () {});
      });
    },

    // 손님: 직접 연결이 안 될 때 중계로 들어간다. 첫 서버가 안 되면 다음 서버.
    _relayJoin: function (code, bi) {
      bi = bi || 0;
      if (bi >= BROKERS.length) {
        net.status = "error";
        net.error = "방장 기기와 연결이 안 되고 중계 서버에도 닿지 못했어요 (와이파이를 바꾸거나 휴대폰 핫스팟으로 해 보세요)";
        return;
      }
      net.status = "joining";
      net.stage = "relay";
      net.tryNo = bi + 2;
      var me = rid();
      var hostId = PREFIX + code;
      var myTopic = TOPIC + code + "/g/" + me;
      var token = net._joinToken = rid();
      net._mqtt(BROKERS[bi], function (cli) {
        if (net._joinToken !== token) { cli.end(true); return; }
        net.relays.push(cli);
        var welcomed = false;
        cli.subscribe(myTopic, function () {
          cli.publish(TOPIC + code + "/h", JSON.stringify({ f: me, d: '{"t":"_hi"}' }));
        });
        var wt = setTimeout(function () {
          if (welcomed || net._joinToken !== token) return;
          try { cli.end(true); } catch (e) {}
          net.relays = net.relays.filter(function (x) { return x !== cli; });
          net._relayJoin(code, bi + 1);
        }, 9000);
        cli.on("message", function (topic, payload) {
          if (topic !== myTopic) return;
          var m;
          try { m = JSON.parse(payload.toString()); } catch (e) { return; }
          var inner;
          try { inner = JSON.parse(m.d); } catch (e) { return; }
          if (inner && inner.t === "_welcome") {
            if (welcomed) return;
            welcomed = true;
            clearTimeout(wt);
            net.conns[hostId] = net._relayConn(hostId, cli, TOPIC + code + "/h", me);
            net.seen[hostId] = Date.now();
            net.status = "joined";
            net.via = "relay";
            net._push(hostId, { t: "_open" });
            return;
          }
          if (welcomed) net._relayIn(hostId, m.d);
        });
      }, function () {
        if (net._joinToken !== token) return;
        net._relayJoin(code, bi + 1);
      });
    },

    join: function (code, tryNo) {
      tryNo = tryNo || 1;
      net.close();
      net.code = code;
      if (tryNo === 1) net.t0 = Date.now();
      // 직접 연결 라이브러리가 없거나 주소에 relay=1 이 있으면 바로 중계로
      if (typeof Peer === "undefined" || /[?&]relay=1/.test(location.search)) { net._relayJoin(code, 0); return; }
      net.status = "joining";
      net.tryNo = tryNo;
      net.stage = "signal";
      if (tryNo === 1) net.t0 = Date.now();
      net.via = "direct";
      net._joinToken = "";
      var mine = net.peer = new Peer({ config: ICE });
      clearTimeout(net._timer);
      net._timer = setTimeout(function () {
        if (net.peer !== mine || net.status !== "joining") return;
        if (tryNo < JOIN_TRIES) { net.join(code, tryNo + 1); return; }
        try { mine.destroy(); } catch (e) {}
        net.peer = null;
        net._relayJoin(code, 0);
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
        if (e && e.type === "peer-unavailable") {
          net.status = "error";
          net.error = "방을 찾을 수 없어요 (호스트가 닫았거나 코드가 틀려요)";
          return;
        }
        // 연결 서버가 막혀 있거나 다른 문제: 중계로 들어가 본다
        try { mine.destroy(); } catch (e2) {}
        net.peer = null;
        net._relayJoin(code, 0);
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

    // 그 친구와 어떻게 이어졌나: "relay" | "direct" | ""
    how: function (peer) {
      var c = net.conns[peer];
      return c ? (c.relay ? "relay" : "direct") : "";
    },

    close: function () {
      for (var k in net.conns) { try { net.conns[k].close(); } catch (e) {} }
      net.conns = {};
      net._joinToken = "";
      for (var i = 0; i < net.relays.length; i++) { try { net.relays[i].end(true); } catch (e) {} }
      net.relays = [];
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
