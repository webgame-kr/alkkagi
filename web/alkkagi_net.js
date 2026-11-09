// 개조 알까기 친구 초대: PeerJS(공개 시그널 서버 0.peerjs.com) 위의 아주 작은 중계.
// 게임(GDScript)은 JavaScriptBridge 로 window.AlkNet 을 부른다.
// 호스트가 방을 열면 친구들은 링크(?room=코드)로 들어와 호스트에 직접 연결된다 (별 모양).
// 받은 메시지는 inbox 에 쌓이고, 게임이 매 프레임 poll() 로 가져간다.
(function () {
  var PREFIX = "alkkagi-v1-";
  var net = {
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

    _wire: function (conn) {
      conn.on("data", function (d) {
        var msg = d;
        if (typeof d === "string") { try { msg = JSON.parse(d); } catch (e) { return; } }
        net._push(conn.peer, msg);
      });
      conn.on("close", function () {
        delete net.conns[conn.peer];
        net._push(conn.peer, { t: "_left" });
      });
      conn.on("error", function () {
        delete net.conns[conn.peer];
        net._push(conn.peer, { t: "_left" });
      });
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
      net.peer = new Peer(PREFIX + net.code);
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

    join: function (code) {
      if (typeof Peer === "undefined") { net.status = "error"; net.error = "연결 라이브러리를 불러오지 못했어요"; return; }
      net.close();
      net.code = code;
      net.status = "joining";
      net.peer = new Peer();
      net.peer.on("open", function (id) {
        net.myId = id;
        var conn = net.peer.connect(PREFIX + code, { reliable: true });
        conn.on("open", function () {
          net.conns[conn.peer] = conn;
          net.status = "joined";
          net._push(conn.peer, { t: "_open" });
        });
        net._wire(conn);
      });
      net.peer.on("error", function (e) {
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
  window.AlkNet = net;
})();
