// Ported from godot/scripts/meta/billing_ios.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §3): App Store purchases, with the same face as billing.gd (Google
    // Play) so the shop and the app don't care which store they talk to (scripts/meta/store_billing.gd picks one). The
    // StoreKit 2 side is GodotApplePlugins' StoreKitManager (addons/GodotApplePluginsStoreKit, a GDExtension in the iOS build
    // only; reached through ClassDB, so this script parses and stays inactive everywhere else).
    //
    // A purchase mirrors Play's exactly: Apple's sheet (the purchase carries appAccountToken = UUIDv5 of our account id,
    // scripts/meta/apple_token.gd) -> the signed transaction (JWS) -> the Siege server checks it with Apple
    // (server/iap_verify_apple.gd, message "iap" with "store":"apple") -> granted to the account once -> only THEN the
    // transaction is finished. Anything not finished (no network, server not set up yet, app killed) comes back from
    // StoreKit on the next start or resume (Transaction.unfinished), like Play's query_purchases. A gem pack's ledger token
    // is "apple:<transactionId>", the starter pack's (bought once per Apple ID) "apple:<originalTransactionId>".
    // RESTORE PURCHASES (the App Store requires one for the starter pack): AppStore.sync, then the current entitlements go
    // through the same path (the server says whether this account already has it).
    public class BillingIos : Node, IStoreBilling
    {
        public const string OPTION_CLASS = "StoreProductPurchaseOption";
        public const int OK = 0;                         // StoreKitManager.StoreKitStatus
        public const int INVALID_PRODUCT = 1;
        public const int CANCELLED = 2;                  // (StoreKit threw: no network, not allowed, ...)
        public const int UNVERIFIED = 3;
        public const int USER_CANCELLED = 4;
        public const int PENDING = 5;                    // Ask to Buy / Strong Customer Authentication: arrives later as an update
        public const double VERIFY_TIMEOUT = 20.0;
        public const string TOKEN_PREFIX = "apple:";

        public event Action Changed;                     // prices / readiness / busy changed: the shop redraws
        public event Action<string, GDict> Granted;
        public event Action<string, bool> Note;

        public Profile profile;
        public Action<GDict> on_server_grant;            // (granted dict with "profile") -- the app's EcoSync takes the account
        public object client = null;                     // GodotApplePlugins' StoreKitManager, or a test double with the same calls and signals
        public Action<string, string, string, Action<GDict>> verify_fn;   // (product, jws, token, cb(res)) -> void; default: ask the Siege server
        public string url = OS.HasEnvironment("SIEGE_URL") ? OS.GetEnvironment("SIEGE_URL") : Net.DEFAULT_URL;
        public bool ready_ = false;                      // Apple answered with the products
        public GDict prices = new GDict();               // product id -> "0,99 €" from Apple (the player's currency)
        public GDict products = new GDict();             // product id -> StoreProduct (the sheet needs it)
        public string busy = "";                         // the product whose sheet is open
        public bool restoring = false;                   // RESTORE PURCHASES is running
        public string last_token = "";                   // the appAccountToken of the last purchase (tests)
        public bool _restore_asked = false;
        public GDict _checking = new GDict();            // ledger token -> true while the server is asked
        public GArray _reqs = new GArray();              // open verification sockets [{ws, sent, msg, cb, t0}]

        public static bool Supported()
        {
            return Platform.HasClass(Platform.STOREKIT_CLASS);
        }

        public void Setup(Profile p, object c = null)
        {
            profile = p;
            if (verify_fn == null)
                verify_fn = _VerifyServer;
            client = c;
            if (client == null && Supported())
                client = ClassDB.Instantiate(Platform.STOREKIT_CLASS);
            if (client == null)
                return;
            GObject.Connect(client, "products_request_completed", (Action<GArray, int>)_OnProducts);
            GObject.Connect(client, "purchase_completed", (Action<Var, int, string>)_OnPurchase);
            GObject.Connect(client, "transaction_updated", (Action<Var>)_Handle);
            GObject.Connect(client, "unverified_transaction_updated", (Action<Var, int>)_OnUnverified);
            GObject.Connect(client, "restore_completed", (Action<int, string>)_OnRestored);
            GObject.Connect(client, "current_entitlements_fetch_completed", (Action<GArray>)_OnEntitlements);
            GObject.Call(client, "start");                        // listens for updates and hands back what wasn't finished
            _AskProducts();
        }

        public bool Active()
        {
            return client != null;
        }

        public string Price(string product)
        {
            // Apple's price in the player's currency once known, else the US price from the table
            return GD.Str(prices.Get(product, "$" + GD.Str(Net.IAP.Get(product, new GDict()).D.Get("usd", "?"))));
        }

        public bool CanBuy(string product)
        {
            if (!ready_ || busy != "" || restoring || !Net.IAP.Has(product) || !products.Has(product))
                return false;
            if ((bool)Net.IAP[product].D.Get("once", false) && (bool)profile.d["iap"]["starter"])
                return false;
            return true;
        }

        public void Buy(string product)
        {
            if (!Active())
            {
                Note?.Invoke("Gem packs are sold in the App Store version of Fatebound", false);
                return;
            }
            if (!ready_)
            {
                Note?.Invoke("The App Store isn't connected yet. Try again in a moment", false);
                _AskProducts();
                return;
            }
            if (!CanBuy(product))
                return;
            busy = product;
            Changed?.Invoke();
            last_token = AccountToken();
            var opts = _Options(last_token);
            if (opts.IsEmpty())
                GObject.Call(client, "purchase", products[product]);
            else
                GObject.Call(client, "purchase_with_options", products[product], opts);
        }

        public void Restore()
        {
            // RESTORE PURCHASES: Apple syncs (it may ask for the Apple ID password), then what this Apple ID owns is checked
            if (!Active() || restoring)
                return;
            restoring = true;
            _restore_asked = true;
            Changed?.Invoke();
            GObject.Call(client, "restore_purchases");
        }

        public void Resume()
        {
            // the app is opened again (or the server is reachable again): what StoreKit hasn't finished comes back
            if (client == null)
                return;
            if (!ready_)
                _AskProducts();
            GObject.Call(client, "fetch_unfinished_transactions");
        }

        public string AccountToken()
        {
            // the purchase is tied to the server account only when the phone uses one (billing.gd sends the account then too)
            if (profile == null || !profile.server_mode)
                return "";
            return AppleToken.ForAccount(GD.Str(profile.d["account"].Get("id", "")));
        }

        public static string TokenOf(string product, Var txn)
        {
            // the ledger token (the server works out the same one from the verified transaction)
            var once = (bool)Net.IAP.Get(product, new GDict()).D.Get("once", false);
            Var n = once ? GObject.Get(txn, "original_id") : GObject.Get(txn, "transaction_id");
            return GD.Long(n) > 0 ? TOKEN_PREFIX + GD.Str(GD.Long(n)) : "";
        }

        // ---------------- Apple's answers ----------------
        public void _AskProducts()
        {
            GObject.Call(client, "request_products", Var.Of(Net.IAP.Keys().ToStrings().ToArray()));
        }

        public void _OnProducts(GArray list, int status)
        {
            if (status != OK)
                return;
            foreach (var pr in list)
            {
                if (pr.IsNull)
                    continue;
                var id = GD.Str(GObject.Get(pr, "product_id"));
                if (Net.IAP.Has(id))
                {
                    products[id] = pr;
                    prices[id] = GD.Str(GObject.Get(pr, "display_price"));
                }
            }
            ready_ = true;
            Changed?.Invoke();
        }

        public void _OnPurchase(Var txn, int status, string _msg)
        {
            busy = "";
            Changed?.Invoke();
            switch (status)
            {
                case OK:
                    if (!txn.IsNull)
                        _Handle(txn);
                    break;
                case USER_CANCELLED:
                    break;
                case PENDING:
                    Note?.Invoke("Payment pending. Your gems arrive when Apple confirms it", true);
                    break;
                case UNVERIFIED:
                    Note?.Invoke("The App Store couldn't confirm that purchase, so nothing was added", false);
                    break;
                case INVALID_PRODUCT:
                    Note?.Invoke("That pack isn't on sale right now", false);
                    break;
                default:
                    Note?.Invoke("The purchase didn't go through. Try again in a moment", false);
                    break;
            }
        }

        public void _OnUnverified(Var txn, int err)
        {
            // StoreKit couldn't verify Apple's signature on this device: never granted (and never finished)
            GD.Print(GD.Fmt("billing_ios: unverified transaction %s (%d)", !txn.IsNull ? GD.Str(GObject.Get(txn, "product_id")) : "?", err));
        }

        public void _Handle(Var txn)
        {
            if (txn.IsNull)
                return;
            var product = GD.Str(GObject.Get(txn, "product_id"));
            if (!Net.IAP.Has(product))
                return;
            var token = TokenOf(product, txn);
            if (token == "" || _checking.Has(token))
                return;
            if ((double)GObject.Get(txn, "revocation_date") > 0.0)
            {
                GObject.Call(txn, "finish");                                    // refunded: nothing to deliver
                return;
            }
            if (profile.IapGranted(token))
            {
                if (_restore_asked && (bool)Net.IAP[product].Get("once", false))
                {
                    _restore_asked = false;
                    Note?.Invoke("Your Starter Pack is already on this account", true);
                }
                GObject.Call(txn, "finish");
                return;
            }
            _checking[token] = true;
            verify_fn(product, GD.Str(GObject.Get(txn, "jws_representation")), token, (GDict v) => _Verified(product, token, txn, v));
        }

        public void _Verified(string product, string token, Var txn, GDict v)
        {
            _checking.Erase(token);
            if (v.Get("granted", Var.Nil).IsDict)
            {
                // the server granted it to the account itself (or had already): take the account, then finish it
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
                    GObject.Call(txn, "finish");
                    return;
                }
                if (GD.Str(sg.Get("why", "")) == "used")
                {
                    if (_restore_asked && (bool)Net.IAP[product].Get("once", false))
                    {
                        _restore_asked = false;
                        Note?.Invoke("That Starter Pack belongs to another Fatebound account", false);
                    }
                    GObject.Call(txn, "finish");                                // granted to an account before: nothing more to do
                    return;
                }
            }
            if ((bool)v.Get("ok", false))
            {
                GDict g = profile.GrantIap(product, token);
                if ((bool)g.Get("ok", false))
                {
                    Granted?.Invoke(product, g);
                    GObject.Call(txn, "finish");
                }
                return;
            }
            switch (GD.Str(v.Get("why", "")))
            {
                case "pending":
                    Note?.Invoke("Payment pending. Your gems arrive when Apple confirms it", true);
                    break;
                case "bad":
                    Note?.Invoke("Apple couldn't confirm that purchase, so nothing was added", false);
                    break;
                case "used":
                    GObject.Call(txn, "finish");
                    break;
                default:
                    Note?.Invoke("Purchase received. It will be added as soon as the server can confirm it", true);
                    break;
            }
        }

        public void _OnRestored(int status, string _msg)
        {
            if (status != OK)
            {
                restoring = false;
                _restore_asked = false;
                Changed?.Invoke();
                Note?.Invoke("Couldn't reach the App Store to restore purchases. Try again in a moment", false);
                return;
            }
            GObject.Call(client, "fetch_current_entitlements");               // each one comes through _handle, then the list
        }

        public void _OnEntitlements(GArray list)
        {
            var ours = 0;
            foreach (var e in list)
            {
                if (!e.IsNull && Net.IAP.Has(GD.Str(GObject.Get(e, "product_id"))))
                    ours += 1;
            }
            if (restoring && ours == 0)
            {
                _restore_asked = false;
                Note?.Invoke("Nothing to restore on this Apple ID. Gems stay with the Fatebound account that bought them", true);
            }
            restoring = false;
            Changed?.Invoke();
        }

        public GArray _Options(string token)
        {
            // [appAccountToken] for purchase_with_options (a typed array of the plugin's option class), or [] without one
            if (token == "" || !ClassDB.ClassExists(OPTION_CLASS))
                return new GArray();
            Var o = ClassDB.ClassCallStatic(OPTION_CLASS, "app_account_token", token);
            if (o.IsNull)
                return new GArray();
            var opts = new GArray();          // (GDScript: Array([], TYPE_OBJECT, OPTION_CLASS, null) -- the port's arrays aren't typed)
            opts.Append(o);
            return opts;
        }

        // ---------------- the server's check ----------------
        public void _VerifyServer(string product, string jws, string _token, Action<GDict> cb)
        {
            var ws = new WebSocketPeer();
            ws.InboundBufferSize = 1 << 21;                       // (the answer can carry the account)
            if (ws.ConnectToUrl(url) != GD.OK)
            {
                cb(new GDict { { "ok", false }, { "why", "unreachable" } });
                return;
            }
            var msg = new GDict { { "t", "iap" }, { "v", Net.VERSION }, { "store", "apple" }, { "product", product }, { "jws", jws }, { "pkg", Net.IAP_PACKAGE } };
            if (profile != null && profile.server_mode)
            {
                msg["acct"] = GD.Str(profile.d["account"]["id"]);             // the server grants it to this account
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
