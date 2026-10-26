// Ported from godot/scripts/meta/lb_fetch.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // 0.31.119: asks the Siege server for the week's leaderboard ({"t":"lb", "acct", "key"} on its own socket, like eco_sync)
    // and hands the answer to `done` -- {} when there's no answer (no connection, an older server, a key it doesn't know).
    // Frees itself when done.
    // 0.31.120: ask() sends any one-socket request this way (the referral code: {"t":"ref", ...} -> {"t":"ref", ...}; a
    // diagnostics report, compressed: {"t":"diag", ...}).
    public class LbFetch : Node
    {
        public const double TIMEOUT = 10.0;

        public string url = "";
        public GDict msg = new GDict();
        public Action<GDict> done = _r => { };
        public string reply_t = "lb";
        public bool compress = false;            // 0.31.120: zstd (a diagnostics report)
        public WebSocketPeer _ws = new WebSocketPeer();
        public bool _sent = false;
        public double _t = 0.0;
        public bool _over = false;

        public static LbFetch Start(Node parent, string url_, string acct, string key, Action<GDict> cb)
        {
            var f = new LbFetch();
            f.url = url_;
            f.msg = new GDict { { "t", "lb" }, { "v", Net.VERSION }, { "acct", acct }, { "key", key } };
            f.done = cb;
            parent.AddChild(f);
            return f;
        }

        public static LbFetch Ask(Node parent, string url_, GDict msg_, Action<GDict> cb, bool zstd = false)
        {
            // the answer is the first message whose "t" is the request's
            var f = new LbFetch();
            f.url = url_;
            f.compress = zstd;
            f.msg = msg_.Duplicate();
            f.msg["v"] = Net.VERSION;
            f.reply_t = GD.Str(msg_.Get("t", ""));
            f.done = cb;
            parent.AddChild(f);
            return f;
        }

        protected override void _Ready()
        {
            _ws.InboundBufferSize = 1 << 18;
            if (_ws.ConnectToUrl(url) != GD.OK)
                _Finish(new GDict());
        }

        protected override void _Process(double delta)
        {
            if (_over)
                return;
            _t += delta;
            _ws.Poll();
            var st = _ws.GetReadyState();
            if (st == WebSocketPeer.STATE_OPEN && !_sent)
            {
                _ws.PutPacket(Net.Encode(msg, compress));
                _sent = true;
            }
            while (_ws.GetAvailablePacketCount() > 0)
            {
                var m = Net.Decode(_ws.GetPacket());
                if (GD.Str(m.Get("t", "")) == reply_t)
                {
                    _Finish(m);
                    return;
                }
            }
            if (st == WebSocketPeer.STATE_CLOSED || _t > TIMEOUT)
                _Finish(new GDict());
        }

        public void _Finish(GDict r)
        {
            if (_over)
                return;
            _over = true;
            if (_ws.GetReadyState() == WebSocketPeer.STATE_OPEN)
                _ws.Close();
            done(r);
            QueueFree();
        }
    }
}
