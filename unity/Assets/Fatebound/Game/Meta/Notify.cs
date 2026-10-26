// Ported from godot/scripts/meta/notify.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Eco = Fatebound.Game.Economy;

namespace Fatebound.Game
{
    // 0.31.119 (Kevin: "Do all" -- 5. "your chest is ready" notifications). The game's side of the FateboundNotify Android
    // plugin (godot/android_plugins/fatebound_notify; only in the Play Store build -- the preview APK has no plugin, and then
    // nothing here does anything).
    //   - going to the background: one notification per chest that is unlocking, at the moment it's ready ("Your Silver
    //     Chest is ready!"); coming back: they're all cancelled (you can see your chests then)
    //   - Settings > NOTIFICATIONS > "Chest ready" (settings.notify, on by default)
    //   - Android 13+ asks for permission: the first time a chest starts unlocking the game asks first in its own words
    //     ("Want a notification when your chest is ready?") and only on YES shows Android's dialog (settings.notify_asked)
    // Nothing leaves the phone: the notifications are scheduled on it.
    // 0.31.131 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §6): on iOS the same four calls come from FateboundNotifyIOS
    // (godot/ios_plugins/fatebound_notify, UNUserNotificationCenter; a GDExtension in the iOS build only), so everything
    // here -- the question, the toggle, the scheduling -- is the same on both phones.
    public class Notify
    {
        public const string SINGLETON = "FateboundNotify";
        public const string IOS_CLASS = "FateboundNotifyIOS";
        public const int ID_BASE = 1000;

        public object plugin = null;                  // the Android singleton, the iOS extension's object, or a test's fake

        public Notify(object fake = null)
        {
            if (fake != null)
                plugin = fake;
            else if (Engine.HasSingleton(SINGLETON))
                plugin = Engine.GetSingleton(SINGLETON);
            else if (Platform.IsIos() && Platform.HasClass(IOS_CLASS))
                plugin = ClassDB.Instantiate(IOS_CLASS);
        }

        public bool Available()
        {
            return plugin != null;
        }

        public static bool Enabled(Profile profile)
        {
            return profile != null && (bool)profile.d["settings"].Get("notify", true);
        }

        public bool HasPermission()
        {
            return Available() && (bool)GObject.Call(plugin, "hasPermission");
        }

        public void RequestPermission()
        {
            if (Available())
                GObject.Call(plugin, "requestPermission");
        }

        public bool ShouldAsk(Profile profile)
        {
            // the game's own question, once: the first time a chest starts unlocking, when Android would need permission
            return Available() && Enabled(profile) && !HasPermission() && !(bool)profile.d["settings"].Get("notify_asked", false);
        }

        public static GArray Plan(Profile profile)
        {
            // -> [{id, title, body, delay}] for every chest that is unlocking and not yet ready
            var out_ = new GArray();
            foreach (var c in profile.d["chests"]["slots"])
            {
                if ((int)c["start"] < 0)
                    continue;
                int left = profile.ChestLeft(c.D);
                if (left <= 0)
                    continue;
                var name = GD.Str(Eco.CHESTS[GD.Str(c["kind"])]["name"]);
                out_.Append(new GDict { { "id", ID_BASE + (int)c["id"] }, { "title", GD.Fmt("Your %s is ready!", name) },
                    { "body", "Open it in Fatebound for your rewards." }, { "delay", left } });
            }
            return out_;
        }

        public int OnBackground(Profile profile)
        {
            // -> how many were scheduled
            if (!Available())
                return 0;
            GObject.Call(plugin, "cancelAll");
            if (!Enabled(profile) || !HasPermission())
                return 0;
            var n = 0;
            foreach (var it in Plan(profile))
            {
                GObject.Call(plugin, "schedule", (int)it["id"], GD.Str(it["title"]), GD.Str(it["body"]), (int)it["delay"]);
                n += 1;
            }
            return n;
        }

        public void OnForeground()
        {
            if (Available())
                GObject.Call(plugin, "cancelAll");
        }
    }
}
