// Ported from godot/scripts/meta/billing.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // 0.31.90: Google Play purchases (Kevin: "I want to incorporate IAP"). Only the Play app has the billing plugin
    // (addons/GodotGooglePlayBilling, packed by the Gradle preset); everywhere else `supported()` is false and the shop
    // says the packs are in the Play Store version.
    //
    // A purchase: Google's sheet -> on_purchase_updated -> the Siege server asks Google whether the token is real
    // (server/iap_verify.gd, message "iap") -> the profile grants it once per token (Profile.grant_iap) -> a gem pack is
    // consumed so it can be bought again; the starter pack is acknowledged (bought once). Anything not finished (no
    // network, server not set up yet, app killed) is picked up again on the next start from Google's own list
    // (query_purchases). Google refunds a purchase nobody acknowledges within 3 days, so nothing is acknowledged or
    // consumed before it has been granted.
    public class Billing : Node, IStoreBilling
    {
        public const string PLUGIN = "GodotGooglePlayBilling";
        public const int PURCHASED = 1;                  // BillingClient.PurchaseState
        public const int PENDING = 2;
        public const int OK = 0;                         // BillingClient.BillingResponseCode
        public const int USER_CANCELED = 1;
        public const int ITEM_ALREADY_OWNED = 7;
        public const double VERIFY_TIMEOUT = 20.0;

        public event Action Changed;                     // prices / readiness / busy changed: the shop redraws
        public event Action<string, GDict> Granted;
        public event Action<string, bool> Note;

        public Profile profile;
        public Action<GDict> on_server_grant;            // 0.31.108: (granted dict with "profile") -- the app's EcoSync takes the account
        public BillingClient client = null;              // the plugin's BillingClient, or a test double with the same calls and signals
        public Action<string, string, string, Action<GDict>> verify_fn;   // (product, token, order, cb(res)) -> void; default: ask the Siege server
        public string url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public bool ready_ = false;
        public GDict prices = new GDict();               // product id -> "$0.99" from Google (local currency)
        public string busy = "";                         // the product whose sheet is open
        public GDict _checking = new GDict();            // token -> true while the server is asked
        public GArray _reqs = new GArray();              // open verification sockets [{ws, sent, msg, cb, t0}]

        public static bool Supported()
        {
            return Engine.HasSingleton(PLUGIN);
        }

        public void Setup(Profile p, BillingClient c = null)
        {
            profile = p;
            if (verify_fn == null)
                verify_fn = _VerifyServer;
            client = c;
            if (client == null && Supported())
            {
                client = new BillingClient();
                AddChild(client);
            }
            if (client == null)
                return;
            client.Connected += _OnConnected;
            client.Disconnected += () =>
            {
                ready_ = false;
                Changed?.Invoke();
            };
            client.ConnectError += (_code, _msg) =>
            {
                ready_ = false;
                Changed?.Invoke();
            };
            client.QueryProductDetailsResponse += _OnDetails;
            client.QueryPurchasesResponse += _OnPurchases;
            client.OnPurchaseUpdated += _OnUpdated;
            client.ConsumePurchaseResponse += _r => { };
            client.AcknowledgePurchaseResponse += _r => { };
            client.StartConnection();
        }

        public bool Active()
        {
            return client != null;
        }

        public string Price(string product)
        {
            // Google's price in the player's currency once known, else the US price from the table
            return GD.Str(prices.Get(product, "$" + GD.Str(Net.IAP.Get(product, new GDict()).D.Get("usd", "?"))));
        }

        public bool CanBuy(string product)
        {
            if (!ready_ || busy != "" || !Net.IAP.Has(product))
                return false;
            if ((bool)Net.IAP[product].D.Get("once", false) && (bool)profile.d["iap"]["starter"])
                return false;
            return true;
        }

        public void Buy(string product)
        {
            if (!Active())
            {
                Note?.Invoke("Gem packs are sold in the Google Play version of Fatebound", false);
                return;
            }
            if (!ready_)
            {
                Note?.Invoke("The Play Store isn't connected yet. Try again in a moment", false);
                client.StartConnection();
                return;
            }
            if (!CanBuy(product))
                return;
            busy = product;
            Changed?.Invoke();
            GDict r = client.Purchase(product);
            if ((int)r.Get("response_code", OK) != OK)
            {
                busy = "";
                Changed?.Invoke();
                Note?.Invoke(_ErrorText((int)r.Get("response_code", -99)), false);
            }
        }

        public void Resume()
        {
            // Ask Google for purchases not finished yet (the app is opened again, or the server is reachable again).
            if (ready_ && client != null)
                client.QueryPurchases((BillingClient.ProductType)0);
        }

        // ---------------- Google's answers ----------------
        public void _OnConnected()
        {
            ready_ = true;
            client.QueryProductDetails(Net.IAP.Keys().ToStrings().ToArray(), (BillingClient.ProductType)0);
            client.QueryPurchases((BillingClient.ProductType)0);
            Changed?.Invoke();
        }

        public void _OnDetails(GDict res)
        {
            if ((int)res.Get("response_code", -1) != OK)
                return;
            foreach (var pd in res.Get("product_details", new GArray()))
            {
                Var offers = pd.D.Get("one_time_purchase_offer_details_list", Var.Nil);
                if (offers.IsArr && !offers.A.IsEmpty())
                    prices[GD.Str(pd["product_id"])] = GD.Str(offers[0].D.Get("formatted_price", ""));
            }
            Changed?.Invoke();
        }

        public void _OnPurchases(GDict res)
        {
            if ((int)res.Get("response_code", -1) == OK)
            {
                foreach (var pu in res.Get("purchases", new GArray()))
                    _Handle(pu.D);
            }
        }

        public void _OnUpdated(GDict res)
        {
            var code = (int)res.Get("response_code", -1);
            busy = "";
            Changed?.Invoke();
            if (code == OK)
            {
                foreach (var pu in res.Get("purchases", new GArray()))
                    _Handle(pu.D);
            }
            else if (code == ITEM_ALREADY_OWNED)
                Resume();                                       // an earlier purchase never finished: finish it now
            else if (code != USER_CANCELED)
                Note?.Invoke(_ErrorText(code), false);
        }

        // (GDScript's Array(x): an array as it is, a packed array's elements)
        static GArray ToArray(Var x)
        {
            if (x.IsArr)
                return x.A;
            if (x.Obj is System.Collections.IEnumerable e && !(x.Obj is string))
                return GArray.From(e);
            GD.PushError("Invalid type in Array constructor.");
            return new GArray();
        }

        public void _Handle(GDict pu)
        {
            GArray ids = ToArray(pu.Get("product_ids", new GArray()));
            var product = !ids.IsEmpty() ? GD.Str(ids[0]) : "";
            var token = GD.Str(pu.Get("purchase_token", ""));
            if (!Net.IAP.Has(product) || token == "" || _checking.Has(token))
                return;
            switch ((int)pu.Get("purchase_state", 0))
            {
                case PENDING:
                    Note?.Invoke("Payment pending. Your gems arrive when Google confirms it", true);
                    return;
                case PURCHASED:
                    break;
                default:
                    return;
            }
            if (profile.IapGranted(token))
            {
                _Finish(product, token, (bool)pu.Get("is_acknowledged", false));
                return;
            }
            _checking[token] = true;
            verify_fn(product, token, GD.Str(pu.Get("order_id", "")), (GDict v) => _Verified(product, token, pu, v));
        }

        public void _Verified(string product, string token, GDict pu, GDict v)
        {
            _checking.Erase(token);
            if (v.Get("granted", Var.Nil).IsDict)
            {
                // 0.31.108: the server granted it to the account itself (or had already): take the account, then finish it
                GDict sg = v["granted"].D;
                if ((bool)sg.Get("ok", false))
                {
                    if (!profile.IapGranted(token))
                        profile.d["iap"]["done"].Append(new GDict { { "t", token }, { "p", product }, { "at", profile.Now() } });
                    if ((bool)Net.IAP.Get(product, new GDict()).Get("once", false))
                        profile.d["iap"].D["starter"] = true;
                    if (on_server_grant != null)
                        on_server_grant(sg);
                    profile.Save();
                    Granted?.Invoke(product, sg);
                    _Finish(product, token, (bool)pu.Get("is_acknowledged", false));
                    return;
                }
                if (GD.Str(sg.Get("why", "")) == "used")
                {
                    _Finish(product, token, true);                 // granted to an account before: nothing more to do
                    return;
                }
            }
            if ((bool)v.Get("ok", false))
            {
                GDict g = profile.GrantIap(product, token);
                if ((bool)g.Get("ok", false))
                {
                    Granted?.Invoke(product, g);
                    _Finish(product, token, (bool)pu.Get("is_acknowledged", false));
                }
                return;
            }
            switch (GD.Str(v.Get("why", "")))
            {
                case "pending":
                    Note?.Invoke("Payment pending. Your gems arrive when Google confirms it", true);
                    break;
                case "bad":
                    Note?.Invoke("Google couldn't confirm that purchase, so nothing was added", false);
                    break;
                case "used":
                    _Finish(product, token, true);
                    break;
                default:
                    Note?.Invoke("Purchase received. It will be added as soon as the server can confirm it", true);
                    break;
            }
        }

        public void _Finish(string product, string token, bool acknowledged)
        {
            if ((bool)Net.IAP[product].D.Get("once", false))
            {
                if (!acknowledged)
                    client.AcknowledgePurchase(token);
            }
            else
                client.ConsumePurchase(token);
        }

        public static string _ErrorText(int code)
        {
            switch (code)
            {
                case 2:
                case 12:
                case -1:
                case -3:
                    return "Couldn't reach Google Play. Check your connection";
                case 3:
                    return "Google Play billing isn't available on this device";
                case 4:
                    return "That pack isn't on sale right now";
                default:
                    return GD.Fmt("The purchase didn't go through (code %d)", code);
            }
        }

        // ---------------- the server's check ----------------
        public void _VerifyServer(string product, string token, string order, Action<GDict> cb)
        {
            var ws = new WebSocketPeer();
            ws.InboundBufferSize = 1 << 21;                       // (0.31.108: the answer can carry the account)
            if (ws.ConnectToUrl(url) != GD.OK)
            {
                cb(new GDict { { "ok", false }, { "why", "unreachable" } });
                return;
            }
            var msg = new GDict { { "t", "iap" }, { "v", Net.VERSION }, { "product", product }, { "token", token }, { "order", order }, { "pkg", Net.IAP_PACKAGE } };
            if (profile != null && profile.server_mode)
            {
                msg["acct"] = GD.Str(profile.d["account"]["id"]);             // 0.31.108: the server grants it to this account
                msg["key"] = GD.Str(profile.d["account"]["key"]);
            }
            _reqs.Append(new GDict { { "ws", Var.Of(ws) }, { "sent", false }, { "cb", cb }, { "t0", Time.GetTicksMsec() / 1000.0 }, { "msg", msg } });
        }

        protected override void _Process(double _dt)
        {
            foreach (var r in _reqs.Duplicate())
            {
                WebSocketPeer ws = r["ws"].As<WebSocketPeer>();
                ws.Poll();
                var st = ws.GetReadyState();
                if (st == WebSocketPeer.STATE_OPEN && !(bool)r["sent"])
                {
                    ws.PutPacket(Net.Encode(r["msg"].D));
                    r.D["sent"] = true;
                }
                var answer = new GDict();
                while (ws.GetAvailablePacketCount() > 0)
                {
                    var m = Net.Decode(ws.GetPacket());
                    if (GD.Str(m.Get("t", "")) == "iap")
                        answer = m;
                }
                bool late = Time.GetTicksMsec() / 1000.0 - (double)r["t0"] > VERIFY_TIMEOUT;
                if (!answer.IsEmpty() || st == WebSocketPeer.STATE_CLOSED || late)
                {
                    _reqs.Erase(r);
                    if (st != WebSocketPeer.STATE_CLOSED)
                        ws.Close();
                    r["cb"].As<Action<GDict>>()(!answer.IsEmpty() ? answer : new GDict { { "ok", false }, { "why", "unreachable" } });
                }
            }
        }

        // ---- IStoreBilling (the face store_billing.gd describes)
        GDict IStoreBilling.prices => prices;
        string IStoreBilling.busy => busy;
        bool IStoreBilling.ready_ => ready_;
        Action<GDict> IStoreBilling.on_server_grant { get => on_server_grant; set => on_server_grant = value; }
        void IStoreBilling.Setup(Profile p) => Setup(p);
    }
}
