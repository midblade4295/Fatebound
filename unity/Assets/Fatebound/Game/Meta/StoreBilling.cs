// Ported from godot/scripts/meta/store_billing.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;

namespace Fatebound.Game
{
    // 0.31.130 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §1): which store's purchases the app uses. Both have one face
    // (signals changed / granted / note; prices, busy, ready_; active, price, can_buy, buy, resume; setup(profile)), so the
    // shop and the app only ever talk to what this hands back:
    //   Android (and the desktop, where nothing is active)  scripts/meta/billing.gd       Google Play, unchanged
    //   iOS                                                 scripts/meta/billing_ios.gd   the App Store (StoreKit 2)
    // The App Store one also has restore() (RESTORE PURCHASES) and `restoring`.
    public static class StoreBilling
    {
        public static Type ScriptFor(string store = "")
        {
            return (store != "" ? store : Platform.Store()) == "appstore" ? typeof(BillingIos) : typeof(Billing);
        }

        public static Node Make(string store = "")
        {
            return ScriptFor(store) == typeof(BillingIos) ? (Node)new BillingIos() : new Billing();
        }

        public static bool CanRestore(Node b)
        {
            // the shop shows RESTORE PURCHASES for a store that has it (the App Store)
            return b != null && b is BillingIos bi && bi.Active();
        }
    }

    /// <summary>(The port: the "one face" above as a C# interface -- GDScript calls it duck-typed. Billing and BillingIos
    /// implement it; a caller holding the Node that Make() returns casts to it.)</summary>
    public interface IStoreBilling
    {
        event Action Changed;
        event Action<string, GDict> Granted;
        event Action<string, bool> Note;
        GDict prices { get; }
        string busy { get; }
        bool ready_ { get; }
        Action<GDict> on_server_grant { get; set; }
        void Setup(Profile p);
        bool Active();
        string Price(string product);
        bool CanBuy(string product);
        void Buy(string product);
        void Resume();
    }
}
