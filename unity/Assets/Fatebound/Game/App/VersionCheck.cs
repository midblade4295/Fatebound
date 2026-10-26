// Ported from godot/scripts/app/version_check.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // Version check on the menu (0.31.73, Kevin: "when server has newer version than players installed game it'll force
    // them to update"). Opens a WebSocket to the Siege server, asks {"t":"ver"} and reads the protocol it speaks, without
    // joining a match. Emits `done(server_v)` once and frees itself:
    //   server_v >= 0  the server's protocol (compare with Net.version_verdict)
    //   -1             no answer: offline, server down, or a server older than 0.31.73 (it ignores "ver"); the connect
    //                  path (siege_mode.gd) still catches a mismatch when the player taps PLAY.
    public class VersionCheck : Node
    {
        public event Action<int> Done;
        public event Action<GDict> Answered;          // 0.31.118: the whole "ver" answer (what the server can do: "an":1 ...)

        public string url = Net.DEFAULT_URL;
        public double timeout = 6.0;
        public WebSocketPeer ws = null;
        public double _t = 0.0;
        public bool _sent = false;
        public GDict _bye = new GDict();
        public bool _finished = false;

        protected override void _Ready()
        {
            ws = new WebSocketPeer();
            ws.InboundBufferSize = 1 << 16;
            ws.OutboundBufferSize = 1 << 12;
            if (ws.ConnectToUrl(url) != GD.OK)
                _Finish(-1);
        }

        protected override void _Process(double delta)
        {
            if (_finished || ws == null)
                return;
            _t += delta;
            ws.Poll();
            var st = ws.GetReadyState();
            if (st == WebSocketPeer.STATE_OPEN && !_sent)
            {
                ws.PutPacket(Net.Encode(GDict.Of("t", "ver", "v", Net.VERSION)));
                _sent = true;
            }
            while (ws.GetAvailablePacketCount() > 0)
            {
                GDict m = Net.Decode(ws.GetPacket());
                switch (GD.Str(m.Get("t", "")))
                {
                    case "ver":
                        Answered?.Invoke(m);
                        _Finish((int)m.Get("v", -1));
                        return;
                    case "bye":
                    {
                        _bye = m;
                        var sv = Net.RefusedVersion(_bye, -1, "");
                        if (sv >= 0)
                        {
                            _Finish(sv);
                            return;
                        }
                        break;
                    }
                }
            }
            if (st == WebSocketPeer.STATE_CLOSED)
            {
                var sv2 = Net.RefusedVersion(_bye, ws.GetCloseCode(), ws.GetCloseReason());
                // A legacy server never answers "ver"; it closes with 4000 "no hello" after its timeout -> unknown.
                _Finish(sv2 > 0 ? sv2 : -1);
                return;
            }
            if (_t > timeout)
                _Finish(-1);
        }

        public void _Finish(int server_v)
        {
            if (_finished)
                return;
            _finished = true;
            if (ws != null && ws.GetReadyState() == WebSocketPeer.STATE_OPEN)
                ws.Close(1000, "done");
            Done?.Invoke(server_v);
            QueueFree();
        }
    }
}
