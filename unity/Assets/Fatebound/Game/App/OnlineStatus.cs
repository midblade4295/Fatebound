// Ported from godot/scripts/app/online_status.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // 0.31.82 (Kevin: "Add a players online in main menu"): asks the Siege server how many players are on it. A WebSocket
    // that sends {"t":"status"} (no hello, so it never counts as a player), reads the answer and closes -- every POLL_EVERY
    // seconds while Home shows (siege_app sets `active`). `info` is the last answer, {} while unknown: before the first
    // one, when the server can't be reached, or a server older than 0.31.82 (it never answers a status).
    public class OnlineStatus : Node
    {
        public const double POLL_EVERY = 15.0;
        public const double TIMEOUT = 8.0;

        public event Action Changed;

        public string url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public bool active = false;
        public GDict info = new GDict();
        public WebSocketPeer _ws = null;
        public bool _sent = false;
        public double _started = 0.0;
        public double _next = 0.0;
        public double _last_ok = -100.0;

        public void SetActive(bool on)
        {
            active = on;
            if (on && _Now() - _last_ok > 5.0)
                _next = 0.0;                                  // Home again: ask now unless the answer is fresh
        }

        public int Online()
        {
            return !info.IsEmpty() ? (int)info.Get("online", -1) : -1;
        }

        public double _Now()
        {
            return Time.GetTicksMsec() / 1000.0;
        }

        protected override void _Process(double _delta)
        {
            if (_ws == null)
            {
                if (active && _Now() >= _next)
                    _Begin();
                return;
            }
            _ws.Poll();
            var st = _ws.GetReadyState();
            if (st == WebSocketPeer.STATE_OPEN && !_sent)
            {
                _ws.PutPacket(Net.Encode(GDict.Of("t", "status")));
                _sent = true;
            }
            while (_ws.GetAvailablePacketCount() > 0)      // (read before the state: the answer comes with the close)
            {
                GDict m = Net.Decode(_ws.GetPacket());
                if (GD.Str(m.Get("t", "")) == "status")
                {
                    _Finish(m);
                    return;
                }
            }
            if (st == WebSocketPeer.STATE_CLOSED || _Now() - _started > TIMEOUT)
                _Finish(new GDict());
        }

        public void _Begin()
        {
            _ws = new WebSocketPeer();
            _sent = false;
            _started = _Now();
            if (_ws.ConnectToUrl(url) != GD.OK)
                _Finish(new GDict());
        }

        public void _Finish(GDict m)
        {
            if (_ws != null && _ws.GetReadyState() != WebSocketPeer.STATE_CLOSED)
                _ws.Close();
            _ws = null;
            _next = _Now() + POLL_EVERY;
            if (!m.IsEmpty())
                _last_ok = _Now();
            if ((Var)m != (Var)info)
            {
                info = m;
                Changed?.Invoke();
            }
        }
    }
}
