// Ported from godot/scripts/meta/profile.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Eco = Fatebound.Game.Economy;
using Net = Fatebound.Game.SiegeNet;

namespace Fatebound.Game
{
    // The player's Siege profile: currencies, level, Siege Pass, challenges, owned/equipped cosmetics,
    // stats. Saved to user://siege_profile.json (atomic write). On first run it migrates once from the
    // dice-era save (user://fatebound-save.json), which is left untouched on disk.
    public class Profile
    {
        public const int SCHEMA = 1;
        public string path = "user://siege_profile.json";
        public string legacy_path = "user://fatebound-save.json";
        public GDict d = new GDict();
        public int now_override = -1;          // tests: fixed clock (unix seconds)
        public string last_error = "";
        public int saves = 0;                  // 0.31.102: saves this run (play_games.gd: did it change while an upload was out?)

        // ---------------- 0.31.108: the server owns the economy (Kevin: "make sure everything is verified by server so players
        // can't edit gems ect") ----------------
        // The Siege server keeps every player's profile (server/eco_accounts.gd) and is the only one whose copy counts. Every
        // change a player makes is an "op" -- the method's name and its arguments -- that the server replays with this same
        // code on its own copy (apply_op), with its own clock; what it answers replaces the phone's copy (the app's
        // eco_sync.gd), the phone's unsent ops re-applied on top. So the phone shows a change at once, and an edited save file
        // changes nothing: the next answer from the server puts it back. What only the server may do (grant a purchase, take a
        // match's result) is not an op the phone can send.
        public Action<string, GArray> on_op;   // the app's EcoSync: (op, args) after each change made here
        public bool replaying = false;         // applying ops (on the server, or the phone re-applying its unsent ones): not recorded
        public bool server_side = false;       // the server's own copy
        public bool server_mode = false;       // the phone, with the server's economy on: things only a local save allowed are off
        public int clock_offset = 0;           // the phone: server time - phone time (so a chest's timer agrees with the server's)
        public int ready_grace = 0;            // the server: a chest counts as unlocked this many seconds early (clocks differ a little)
        public static readonly GDict OPS = new GDict {
            // op -> argument types (JSON numbers arrive as floats; ints are converted)
            { "claim_tier", GArray.Of(GD.TYPE_INT, GD.TYPE_BOOL) }, { "claim_all", new GArray() }, { "skip_tiers", new GArray() }, { "buy_premium", new GArray() },
            // (0.31.106-0.31.184 "exchange": gold for gems; until 0.31.188 "buy" / "buy_pack": weapons and Arsenals)
            { "equip", GArray.Of(GD.TYPE_STRING) }, { "unequip", GArray.Of(GD.TYPE_STRING, GD.TYPE_STRING) }, // (0.31.188: titles only)
            { "reroll_daily", GArray.Of(GD.TYPE_INT) }, { "claim_challenge", GArray.Of(GD.TYPE_STRING, GD.TYPE_INT) },
            { "claim_quest", GArray.Of(GD.TYPE_STRING) }, // (0.31.93-0.31.187 "forge", "set_forge_element")
            { "start_unlock", GArray.Of(GD.TYPE_INT) }, { "skip_chest", GArray.Of(GD.TYPE_INT) }, { "open_chest", GArray.Of(GD.TYPE_INT) },
            { "set_name", GArray.Of(GD.TYPE_STRING) }, { "finish_tutorial", new GArray() },
            { "claim_login", new GArray() }, // 0.31.119: the daily login reward
            { "claim_discord", new GArray() }, // 0.31.124: JOIN OUR DISCORD, once
            { "buy_hero", GArray.Of(GD.TYPE_STRING) }, // 0.31.168: a 5v5 hero for gold
            // 0.31.185 (League's way): a hero for gems, a hero shard used (unlock at a discount) or melted, a Hero Token used
            { "buy_hero_gems", GArray.Of(GD.TYPE_STRING) }, { "use_shard", GArray.Of(GD.TYPE_STRING) }, { "melt_shard", GArray.Of(GD.TYPE_STRING) }, { "use_token", GArray.Of(GD.TYPE_STRING) },
            { "buy_skin", GArray.Of(GD.TYPE_STRING) }, { "wear_skin", GArray.Of(GD.TYPE_STRING, GD.TYPE_STRING) }, // 0.31.186: hero skins
            { "buy_skin_gold", GArray.Of(GD.TYPE_STRING) }, // 0.31.189: a rare outfit (Frostbound) for gold
            { "buy_sale", GArray.Of(GD.TYPE_STRING, GD.TYPE_INT, GD.TYPE_BOOL) }, // 0.31.203: an outfit on the weekly sale (id, week, gold)
        };

        public void _Rec(string op, GArray args)
        {
            if (!replaying && on_op != null)
                on_op(op, args);
        }

        public GDict ApplyOp(string op, Var args)
        {
            // Replay one op (the server's copy, or the phone's unsent ones over the server's answer). Chest ops carry the
            // chest's id, not its slot. -> the method's own result ({"ok": false, "error"} for an unknown or malformed op).
            if (!OPS.Has(op) || !args.IsArr)
                return new GDict { { "ok", false }, { "error", "unknown op" } };
            GArray types = OPS[op].A;
            GArray a = args.A;
            if (a.Size() != types.Size())
                return new GDict { { "ok", false }, { "error", "bad args" } };
            var v = new GArray();
            for (int i = 0; i < types.Size(); i++)
            {
                Var x = a[i];
                switch ((int)types[i])
                {
                    case GD.TYPE_INT:
                        if (!(x.IsInt || x.IsFloat) || !GD.IsFinite((double)x))
                            return new GDict { { "ok", false }, { "error", "bad args" } };
                        v.Append(GD.Long(x));
                        break;
                    case GD.TYPE_BOOL:
                        if (!x.IsBool)
                            return new GDict { { "ok", false }, { "error", "bad args" } };
                        v.Append(x);
                        break;
                    default:
                        if (!x.IsString || GStr.Length(x.AsString()) > 64)
                            return new GDict { { "ok", false }, { "error", "bad args" } };
                        v.Append(x);
                        break;
                }
            }
            var was = replaying;
            replaying = true;
            Var out_ = Var.Nil;
            switch (op)
            {
                case "start_unlock":
                case "skip_chest":
                case "open_chest":
                    {
                        var ix = ChestIndex((int)v[0]);
                        if (ix < 0)
                            out_ = new GDict { { "ok", false }, { "error", "no such chest" } };
                        else if (op == "start_unlock")
                            out_ = new GDict { { "ok", StartUnlock(ix) } };
                        else if (op == "skip_chest")
                            out_ = SkipChest(ix);
                        else
                            out_ = OpenChest(ix);
                        break;
                    }
                case "claim_all":
                    out_ = new GDict { { "ok", true }, { "got", ClaimAll() } };
                    break;
                case "reroll_daily":
                    out_ = new GDict { { "ok", RerollDaily((int)v[0]) } };
                    break;
                case "unequip":
                    Unequip(GD.Str(v[0]), GD.Str(v[1]));
                    out_ = new GDict { { "ok", true } };
                    break;
                default:
                    out_ = Callv(op, v);
                    break;
            }
            replaying = was;
            return out_.IsDict ? out_.D : new GDict { { "ok", (bool)out_ } };
        }

        // (GDScript's callv(op, v): the op's method by its name)
        Var Callv(string op, GArray v)
        {
            switch (op)
            {
                case "claim_tier": return ClaimTier((int)v[0], (bool)v[1]);
                case "skip_tiers": return SkipTiers();
                case "buy_premium": return BuyPremium();
                case "equip": return Equip(GD.Str(v[0]));
                case "claim_challenge": return ClaimChallenge(GD.Str(v[0]), (int)v[1]);
                case "claim_quest": return ClaimQuest(GD.Str(v[0]));
                case "set_name": return SetName(GD.Str(v[0]));
                case "finish_tutorial": return FinishTutorial();
                case "claim_login": return ClaimLogin();
                case "claim_discord": return ClaimDiscord();
                case "buy_hero": return BuyHero(GD.Str(v[0]));
                case "buy_hero_gems": return BuyHeroGems(GD.Str(v[0]));
                case "use_shard": return UseShard(GD.Str(v[0]));
                case "melt_shard": return MeltShard(GD.Str(v[0]));
                case "use_token": return UseToken(GD.Str(v[0]));
                case "buy_skin": return BuySkin(GD.Str(v[0]));
                case "wear_skin": return WearSkin(GD.Str(v[0]), GD.Str(v[1]));
                case "buy_skin_gold": return BuySkinGold(GD.Str(v[0]));
                case "buy_sale": return BuySale(GD.Str(v[0]), (int)v[1], (bool)v[2]);
            }
            GD.PushError("Invalid call. Nonexistent function '" + op + "' in base 'RefCounted (profile.gd)'.");
            return Var.Nil;
        }

        public int ChestIndex(int id)
        {
            for (int i = 0; i < d["chests"]["slots"].A.Size(); i++)
            {
                if ((int)d["chests"]["slots"][i]["id"] == id)
                    return i;
            }
            return -1;
        }

        public event Action Changed;

        public Profile(string save_path = "user://siege_profile.json", string legacy = "user://fatebound-save.json")
        {
            path = save_path;
            legacy_path = legacy;
        }

        public int Now()
        {
            return now_override >= 0 ? now_override : GD.Int(Time.GetUnixTimeFromSystem()) + clock_offset;
        }

        public static GDict Defaults()
        {
            return new GDict { { "schema", SCHEMA }, { "name", "Player" }, { "gold", 0 }, { "gems", 0 }, { "level", 1 }, { "xp", 0 },
                { "pass", new GDict { { "season", 0 }, { "xp", 0 }, { "premium", false }, { "free", new GArray() }, { "prem", new GArray() }, { "swaps", new GDict() } } },
                { "owned", new GArray() }, { "title", "" }, // (0.31.188: owned = titles; "equip" was the weapons)
                { "heroes", new GArray() }, // 0.31.168: the 5v5 heroes bought with gold (Eco.HERO_PRICES)
                { "shards", new GArray() }, // 0.31.185: hero shards (a hero id each; League's champion shards)
                { "tokens", 0 }, // 0.31.185: Hero Tokens (the premium pass's: any locked hero)
                { "skins", new GArray() }, // 0.31.186: hero skins owned (Eco.SKINS ids)
                { "skin_on", new GDict() }, // 0.31.186: hero -> the skin he wears ("" or none: his own)
                { "challenges", new GDict { { "day", "" }, { "daily", new GArray() }, { "week", "" }, { "weekly", new GArray() }, { "rerolled", false } } },
                { "stats", new GDict { { "matches", 0 }, { "wins", 0 }, { "rescues", 0 }, { "kills", 0 }, { "gates", 0 }, { "gathered", 0 }, { "fed", 0 },
                    { "lifts", 0 }, { "repaired", 0 }, { "healed", 0 }, { "best_multi", 0 }, { "streak", 0 }, { "best_streak", 0 } } }, // (0.31.87: for the titles)
                { "tutorial_done", false },
                { "first_win_day", "" }, { "history", new GArray() }, { "migration", new GDict() },
                { "login", new GDict { { "day", "" }, { "n", 0 } } }, // 0.31.119: the last day claimed, claims so far
                { "discord", false }, // 0.31.124: the Discord reward claimed
                { "prizes", new GArray() }, // 0.31.120: weekly leaderboard prizes paid (newest first)
                { "clan_rewards", new GArray() }, // 0.31.196: Clan Chests and League gems paid (newest first)
                { "gift_shards", new GArray() }, // 0.31.196: shards a clanmate gave (of "shards"; never given on)
                { "war_rewards", new GArray() }, // 0.31.151: the war's rewards paid (0.31.169: no more -- Crown War is gone; kept in saves)
                { "paid", new GArray() }, // 0.31.134: gold the server took (a clan), newest first
                { "referral", new GDict { { "by", "" }, { "notes", new GArray() } } }, // 0.31.120: whose code was entered; friend rewards (newest first)
                { "iap", new GDict { { "done", new GArray() }, { "starter", false } } }, // 0.31.90: purchase tokens already granted
                { "chests", new GDict { { "slots", new GArray() }, { "next", 1 }, { "queue", new GArray() }, { "salt", 0 } } }, // 0.31.108: queue (reward chests waiting), salt (the rolls' seed)
                { "quests", new GDict() }, // 0.31.97: class -> quest steps claimed (0-3)
                { "cloud", new GDict { { "stamp", "" }, { "dirty", false }, { "at", 0 } } }, // 0.31.102: the Google Play save this is in step with
                { "account", new GDict { { "id", "" }, { "key", "" } } }, // 0.31.108: the phone's key to its account on the server
                { "settings", new GDict { { "master", 1.0 }, { "music", 1.0 }, { "sfx", 1.0 }, { "reduce_motion", false }, { "audio_max", true } } } };      // (0.31.110: 100% by default)
        }

        // ---------------- load / save ----------------
        public void LoadOrCreate()
        {
            if (FileAccess.FileExists(path))
            {
                var txt = FileAccess.GetFileAsString(path);
                Var v = JSON.ParseString(txt);
                if (v.IsDict)
                {
                    d = _Normalized(v.D);
                    Refresh();
                    // 0.31.87: titles earned from the stats the profile already had (a veteran's first start with titles)
                    var got = CheckTitles();
                    if (!got.IsEmpty())
                    {
                        d["title_note"] = got;
                        Save();
                    }
                    return;
                }
                last_error = "Profile was unreadable; kept a copy as .corrupt and started fresh";
                DirAccess.CopyAbsolute(ProjectSettings.GlobalizePath(path), ProjectSettings.GlobalizePath(path + ".corrupt"));
            }
            d = Defaults();
            _MigrateLegacy();
            Refresh();
            Save();
        }

        public GDict _Normalized(GDict v)
        {
            var out_ = v.Duplicate(true);
            _MergeMissing(out_, Defaults());
            foreach (var k in GArray.Of("gold", "gems", "xp"))
                out_[k] = GD.Maxi(0, GD.Long(out_[k]));
            out_["level"] = GD.Maxi(1, GD.Long(out_["level"]));
            var owned = new GArray();
            foreach (var id in out_["owned"])
            {
                if (Eco.CATALOG.Has(GD.Str(id)) && !owned.Has(GD.Str(id)))
                    owned.Append(GD.Str(id));
            }
            out_["owned"] = owned;
            // 0.31.39: skins were removed -- give back what any bought ones cost, once
            if (!(bool)out_.Get("skins_refunded", false))
            {
                var back = new GDict { { "gold", 0 }, { "gems", 0 } };
                foreach (var sid in v.Get("owned", new GArray()))
                {
                    if (Eco.REMOVED_SKIN_REFUND.Has(GD.Str(sid)))
                    {
                        GDict pr = Eco.REMOVED_SKIN_REFUND[GD.Str(sid)].D;
                        back["gold"] += GD.Long(pr.Get("gold", 0));
                        back["gems"] += GD.Long(pr.Get("gems", 0));
                    }
                }
                out_["gold"] = GD.Long(out_["gold"]) + back["gold"];
                out_["gems"] = GD.Long(out_["gems"]) + back["gems"];
                out_["skins_refunded"] = true;
                if (back["gold"] + back["gems"] > 0)
                    out_["refund_note"] = back;
            }
            // 0.31.188 (Kevin: "Remove the forge and the individual weapon skins"): the weapons left owned above (they're not in
            // the catalog), and what was equipped and forged goes with them -- no refund (Kevin: "Remove, no refund")
            foreach (var k in GArray.Of("equip", "forge"))
                out_.Erase(k);
            if (out_.Get("chests").IsDict)
                out_["chests"].D.Erase("pity");
            if (out_["pass"].Get("swaps").IsDict)
            {
                var kept = new GDict();
                foreach (var k in out_["pass"]["swaps"])
                {
                    if (out_["pass"]["swaps"][k].IsDict && out_["pass"]["swaps"][k].D.Has("shard"))
                        kept[k] = out_["pass"]["swaps"][k];                 // (a claimed tier's shard: which hero it was)
                }
                out_["pass"].D["swaps"] = kept;
            }
            if (out_["title"] != "" && !owned.Has(GD.Str(out_["title"])))
                out_["title"] = "";
            // JSON numbers come back as floats: make tier lists and challenge progress ints again.
            foreach (var track in GArray.Of("free", "prem"))
            {
                var tiers = new GArray();
                foreach (var t in out_["pass"][track])
                {
                    if (_IsNum(t) && !tiers.Has(GD.Long(t)))
                        tiers.Append(GD.Long(t));
                }
                out_["pass"].D[track] = tiers;
            }
            out_["pass"].D["season"] = GD.Long(out_["pass"]["season"]);
            out_["pass"].D["xp"] = GD.Maxi(0, GD.Long(out_["pass"]["xp"]));
            foreach (var span in GArray.Of("daily", "weekly"))
            {
                foreach (var c in out_["challenges"][span])
                    c.D["progress"] = GD.Long(c.Get("progress", 0));
            }
            // 0.31.184 (Kevin: "Maybe let's have the two currency so it's more simple"): Embers (0.31.90-0.31.183, the Forge's
            // material) are gold now, Eco.EMBER_GOLD each -- a save from before is turned once (the key goes with it)
            if (out_.Has("embers"))
            {
                out_["gold"] = GD.Long(out_["gold"]) + (long)GD.Maxi(0, _IsNum(out_["embers"]) ? GD.Long(out_["embers"]) : 0) * Eco.EMBER_GOLD;
                out_.Erase("embers");
            }
            // 0.31.185: heroes, shards and tokens -- only real heroes, no negative tokens
            foreach (var k in GArray.Of("heroes", "shards"))
            {
                var keep = new GArray();
                if (out_.Get(k).IsArr)
                {
                    foreach (var h in out_[k])
                    {
                        if (Eco.HERO_PRICES.Has(GD.Str(h)) && (k == "shards" || !keep.Has(GD.Str(h))))
                            keep.Append(GD.Str(h));
                    }
                }
                out_[k] = keep;
            }
            // 0.31.196: the shards clanmates gave -- each one of "shards" (no more of a hero than there are shards of him)
            var gifts = new GArray();
            if (out_.Get("gift_shards").IsArr)
            {
                foreach (var h in out_["gift_shards"])
                {
                    if (Eco.HERO_PRICES.Has(GD.Str(h)) && gifts.Count(GD.Str(h)) < out_["shards"].A.Count(GD.Str(h)))
                        gifts.Append(GD.Str(h));
                }
            }
            out_["gift_shards"] = gifts;
            out_["tokens"] = GD.Maxi(0, _IsNum(out_.Get("tokens", 0)) ? GD.Long(out_.Get("tokens", 0)) : 0);
            // 0.31.186: skins -- only real ones, each worn by its own hero and owned
            var sk = new GArray();
            if (out_.Get("skins").IsArr)
            {
                foreach (var id in out_["skins"])
                {
                    if (Eco.SKINS.Has(GD.Str(id)) && !sk.Has(GD.Str(id)))
                        sk.Append(GD.Str(id));
                }
            }
            out_["skins"] = sk;
            var on = new GDict();
            if (out_.Get("skin_on").IsDict)
            {
                foreach (var h in out_["skin_on"])
                {
                    var id = GD.Str(out_["skin_on"][h]);
                    if (sk.Has(id) && GD.Str(Eco.SKINS[id]["hero"]) == GD.Str(h))
                        on[GD.Str(h)] = id;
                }
            }
            out_["skin_on"] = on;
            // 0.31.110 (Kevin: "make it so the audio sliders are max by default"): once, each slider still on its old default
            // (master 80%, effects 80%, music 60%) goes to 100%; one someone moved stays where they put it
            // (asked of the saved settings: the defaults merged in above carry the mark)
            GDict st = out_["settings"].D;
            Var saved_st = v.Get("settings");
            if (!(saved_st.IsDict && (bool)saved_st.Get("audio_max", false)))
            {
                foreach (var k in GArray.Of("master", "sfx", "music"))
                {
                    if (GD.IsEqualApprox((double)st.Get(k, 1.0), k == "music" ? 0.6 : 0.8))
                        st[k] = 1.0;
                }
                st["audio_max"] = true;
            }
            // 0.31.97: quest steps claimed -- known classes, 0..3
            var qs = new GDict();
            foreach (var c in out_["quests"].Keys())
            {
                if (Eco.QUESTS.Has(GD.Str(c)))
                    qs[GD.Str(c)] = GD.Clampi(GD.Long(out_["quests"][c]), 0, Eco.QUESTS[GD.Str(c)]["steps"].Size());
            }
            out_["quests"] = qs;
            return out_;
        }

        public static bool _IsNum(Var v)
        {
            return v.IsInt || v.IsFloat;
        }

        public static void _MergeMissing(GDict target, GDict base_)
        {
            // JSON loads every number as a float, so int/float count as the same type here (treating
            // them as different reset every saved number to its default on load).
            foreach (var k in base_)
            {
                Var bv = base_[k];
                bool same_type = target.Has(k) && (GD.TypeOf(target[k]) == GD.TypeOf(bv) || (_IsNum(target[k]) && _IsNum(bv)));
                if (!same_type)
                    target[k] = (bv.IsDict || bv.IsArr) ? bv.Duplicate(true) : bv;
                else if (bv.IsDict)
                    _MergeMissing(target[k].D, bv.D);
            }
        }

        public bool Save(bool changed_here = true)
        {
            // Write to a temp file then rename, so a crash mid-write can't corrupt the profile.
            // 0.31.102: every save but the cloud sync's own marks the profile as changed since the Google Play copy
            // (play_games.gd uploads it); kept in the file, so a change made just before the app is killed still goes up.
            if (changed_here)
            {
                d["cloud"].D["dirty"] = true;
                saves += 1;
            }
            var tmp = path + ".tmp";
            var f = FileAccess.Open(tmp, FileAccess.WRITE);
            if (f == null)
            {
                last_error = GD.Fmt("Could not write profile (%s)", GD.ErrorString(FileAccess.GetOpenError()));
                return false;
            }
            f.StoreString(JSON.Stringify(d));
            f.Close();
            var err = DirAccess.RenameAbsolute(ProjectSettings.GlobalizePath(tmp), ProjectSettings.GlobalizePath(path));
            if (err != GD.OK)
            {
                last_error = GD.Fmt("Could not replace profile (%s)", GD.ErrorString(err));
                return false;
            }
            Changed?.Invoke();
            return true;
        }

        // ---------------- the Google Play copy (0.31.102, scripts/meta/play_games.gd) ----------------
        public const int CLOUD_VERSION = 1;

        public GDict Summary()
        {
            // what the "which progress to keep?" choice shows of each side
            return new GDict { { "level", (int)d["level"] }, { "wins", (int)d["stats"]["wins"] }, { "matches", (int)d["stats"]["matches"] }, { "gold", (int)d["gold"] },
                { "gems", (int)d["gems"] }, { "items", d["owned"].A.Size() }, { "name", GD.Str(d["name"]) } };
        }

        public bool IsFresh()
        {
            // a new install: nothing played, bought or earned -- Google Play's copy simply replaces it
            return (int)d["stats"]["matches"] == 0 && d["owned"].A.IsEmpty() && d["iap"]["done"].A.IsEmpty()
                && (int)d["level"] <= 1 && (int)d["xp"] == 0 && (int)d["pass"]["xp"] == 0;
        }

        public GDict CloudPayload(string stamp, string device = "")
        {
            var prof = d.Duplicate(true);
            prof.Erase("cloud");
            return new GDict { { "v", CLOUD_VERSION }, { "stamp", stamp }, { "at", Now() }, { "device", device }, { "sum", Summary() }, { "profile", prof } };
        }

        public bool RestoreCloud(Var prof, string stamp)
        {
            // Google Play's copy replaces this phone's progress; this phone's sound and graphics settings stay
            if (!prof.IsDict || !prof.D.Has("stats"))
                return false;
            GDict keep = d["settings"].D.Duplicate(true);
            d = _Normalized(prof.D);
            d["settings"] = keep;
            d["cloud"] = new GDict { { "stamp", stamp }, { "dirty", false }, { "at", Now() } };
            Refresh();
            return Save(false);
        }

        public void _MigrateLegacy()
        {
            if (!FileAccess.FileExists(legacy_path))
            {
                d["migration"] = new GDict { { "from", "none" } };
                return;
            }
            Var v = JSON.ParseString(FileAccess.GetFileAsString(legacy_path));
            if (!v.IsDict)
            {
                d["migration"] = new GDict { { "from", "unreadable" } };
                return;
            }
            ImportLegacy(v.D);
        }

        public GDict ImportLegacy(GDict old)
        {
            // One-time conversion of a dice-era save (at first launch; 0.31.123: Settings no longer has a paste-in import).
            if (!d["migration"].IsEmpty() && GD.Str(d["migration"].Get("from", "")) == "legacy")
                return new GDict { { "ok", false }, { "error", "Old progress was already imported" } };
            if (server_mode || server_side)
                return new GDict { { "ok", false }, { "error", "Old progress can't be imported any more" } };     // (0.31.108: unverifiable)
            var conv = Eco.LegacyConversion(old);
            d["gold"] += (int)conv["gold"];
            d["gems"] += (int)conv["gems"];
            d["level"] = GD.Maxi((int)d["level"], (int)conv["level"]);
            d["migration"] = new GDict { { "from", "legacy" }, { "at", Now() }, { "gold", conv["gold"] }, { "gems", conv["gems"] }, { "level", conv["level"] },
                { "weapons", conv["weapons"] }, { "chests", conv["chests"] } };
            return new GDict { { "ok", true }, { "summary", conv } };
        }

        // ---------------- time-based state ----------------
        public void Refresh()
        {
            // New season -> reset pass progress; new day/week -> new challenges.
            var t = Now();
            var sid = Eco.SeasonId(t);
            if ((int)d["pass"]["season"] != sid)
                d["pass"] = new GDict { { "season", sid }, { "xp", 0 }, { "premium", false }, { "free", new GArray() }, { "prem", new GArray() }, { "swaps", new GDict() } };
            var day = Eco.DayKey(t);
            var week = Eco.WeekKey(t);
            GDict ch = d["challenges"].D;
            if (ch["day"] != day)
            {
                ch["day"] = day;
                ch["daily"] = Eco.RollChallenges("daily", day, Eco.DAILY_COUNT);
                ch["rerolled"] = false;
            }
            if (ch["week"] != week)
            {
                ch["week"] = week;
                ch["weekly"] = Eco.RollChallenges("weekly", week, Eco.WEEKLY_COUNT);
            }
            _RetireChallenges(ch["daily"].A, "daily", GD.Str(ch["day"]));
            _RetireChallenges(ch["weekly"].A, "weekly", GD.Str(ch["week"]));
        }

        public void _RetireChallenges(GArray list, string span, string key)
        {
            // 0.31.164 (Kevin: "5v5 only"): a saved Siege challenge (King rescues, fish, gathering, King lifts) is swapped in place
            // for a 5v5 one -- the same slot (the server replays claims by index) and the same claimed state; the same rolls on
            // the phone and the server
            var keep = new GArray();
            foreach (var c in list)
            {
                if (c.IsDict && Eco.CHALLENGES.Has(GD.Str(c.Get("id", ""))))
                    keep.Append(GD.Str(c["id"]));
            }
            if (keep.Size() == list.Size())
                return;
            var fresh = Eco.RollChallenges(span, key + "-5v5", list.Size() - keep.Size(), keep);
            var fi = 0;
            int n_ = list.Size();
            for (int i = 0; i < n_; i++)
            {
                Var c = list[i];
                if (c.IsDict && Eco.CHALLENGES.Has(GD.Str(c.Get("id", ""))))
                    continue;
                if (fi >= fresh.Size())
                    break;
                GDict nc = fresh[fi].D;
                fi += 1;
                if (c.IsDict && (bool)c.Get("claimed", false))
                {
                    nc["claimed"] = true;
                    nc["progress"] = (int)Eco.CHALLENGES[nc["id"]]["goal"];
                }
                list[i] = nc;
            }
            for (int i = list.Size() - 1; i > -1; i--)
            {
                if (!list[i].IsDict || !Eco.CHALLENGES.Has(GD.Str(list[i].Get("id", ""))))
                    list.RemoveAt(i);                          // (nothing left to swap in: dropped)
            }
        }

        // ---------------- level / pass ----------------
        public int PassTier()
        {
            return GD.Mini(Eco.PASS_TIERS, (int)d["pass"]["xp"] / Eco.TIER_XP);
        }

        public void _AddXp(int amount, GDict out_)
        {
            d["xp"] += amount;
            while (d["xp"] >= Eco.LevelXp((int)d["level"]))
            {
                d["xp"] -= Eco.LevelXp((int)d["level"]);
                d["level"] += 1;
                var r = Eco.LevelReward((int)d["level"]);
                d["gold"] += (int)r.Get("gold", 0);
                d["gems"] += (int)r.Get("gems", 0);
                if (r.Has("chest"))
                    AddChest(GD.Str(r["chest"]), out_, true);
                out_["levels"].Append(new GDict { { "level", d["level"] }, { "reward", r } });
            }
        }

        public void _AddPassXp(int amount, GDict out_)
        {
            var before = PassTier();
            d["pass"].D["xp"] = GD.Mini((int)d["pass"]["xp"] + amount, Eco.PASS_TIERS * Eco.TIER_XP);
            int end = PassTier() + 1;
            for (int tier = before + 1; tier < end; tier++)
                out_["tiers"].Append(tier);
        }

        public bool CanClaim(int tier, bool premium)
        {
            if (tier < 1 || tier > PassTier())
                return false;
            if (premium && !(bool)d["pass"]["premium"])
                return false;
            return !(premium ? d["pass"]["prem"] : d["pass"]["free"]).Has(tier);
        }

        public GDict PassRewardFor(int tier, bool premium)
        {
            // what this tier gives this player -- the season's reward, a shard's hero picked for him (a claimed tier: what it
            // gave). (0.31.108-0.31.187: an owned weapon's swap.)
            var key = GD.Fmt(premium ? "p%d" : "f%d", tier);
            GDict sw = d["pass"].Get("swaps", new GDict()).D;
            if (sw.Has(key) && (premium ? d["pass"]["prem"] : d["pass"]["free"]).Has(tier))
                return sw[key].D;
            var r = Eco.PassReward((int)d["pass"]["season"], tier, premium);
            if (r.Has("shard") && GD.Str(r["shard"]) == "")
            {
                // 0.31.185: which hero's shard -- one not owned yet (the same on the phone and the server); kept once claimed
                var hs = new GDict { { "shard", Eco.PickShard(GD.Fmt("pass-shard-%d-%d%s", (int)d["pass"]["season"], tier, premium ? "p" : ""), d.Get("heroes", new GArray()).A) } };
                hs.Merge(r, false);
                return hs;
            }
            return r;
        }

        public GDict _Claim(int tier, bool premium)
        {
            var r = PassRewardFor(tier, premium);
            if (r.Has("shard"))
            {
                if (!d["pass"].D.Has("swaps"))
                    d["pass"].D["swaps"] = new GDict();
                d["pass"]["swaps"].D[GD.Fmt(premium ? "p%d" : "f%d", tier)] = r;
            }
            _Grant(r);
            (premium ? d["pass"]["prem"] : d["pass"]["free"]).Append(tier);
            return r;
        }

        public GDict ClaimTier(int tier, bool premium)
        {
            if (!CanClaim(tier, premium))
                return new GDict { { "ok", false } };
            var r = _Claim(tier, premium);
            Save();
            _Rec("claim_tier", GArray.Of(tier, premium));
            return new GDict { { "ok", true }, { "reward", r } };
        }

        public GArray ClaimAll()
        {
            var got = new GArray();
            int end = PassTier() + 1;
            for (int tier = 1; tier < end; tier++)
            {
                foreach (var prem in new[] { false, true })
                {
                    if (CanClaim(tier, prem))
                        got.Append(_Claim(tier, prem));
                }
            }
            if (!got.IsEmpty())
            {
                Save();
                _Rec("claim_all", new GArray());
            }
            return got;
        }

        public GDict SkipOffer()
        {
            // the pass's tier skip as it stands: {tiers, gems} (tiers 0 when the pass is complete)
            var n = GD.Mini(Eco.TIER_SKIP, Eco.PASS_TIERS - PassTier());
            return new GDict { { "tiers", GD.Maxi(n, 0) }, { "gems", GD.Maxi(n, 0) * Eco.TIER_SKIP_GEMS } };
        }

        public GDict SkipTiers()
        {
            // 0.31.107: buy the next (up to) 10 tiers -- the pass XP for them, the progress into the current tier kept; their
            // rewards wait to be claimed like any others
            var o = SkipOffer();
            if ((int)o["tiers"] <= 0)
                return new GDict { { "ok", false }, { "error", "The pass is already complete" } };
            if ((int)d["gems"] < (int)o["gems"])
                return new GDict { { "ok", false }, { "error", "Not enough gems" } };
            d["gems"] -= (int)o["gems"];
            var out_ = new GDict { { "tiers", new GArray() } };
            _AddPassXp((int)o["tiers"] * Eco.TIER_XP, out_);
            d["pass"].D["skipped"] = (int)d["pass"].Get("skipped", 0) + (int)o["tiers"];
            Save();
            _Rec("skip_tiers", new GArray());
            return new GDict { { "ok", true }, { "tiers", out_["tiers"] }, { "gems", (int)o["gems"] } };
        }

        public GDict BuyPremium()
        {
            if ((bool)d["pass"]["premium"])
                return new GDict { { "ok", false }, { "error", "You already own this season's premium pass" } };
            if ((int)d["gems"] < Eco.PREMIUM_COST)
                return new GDict { { "ok", false }, { "error", "Not enough gems" } };
            d["gems"] -= Eco.PREMIUM_COST;
            d["pass"].D["premium"] = true;
            Save();
            _Rec("buy_premium", new GArray());
            return new GDict { { "ok", true } };
        }

        public void _Grant(GDict r)
        {
            d["gold"] += (int)r.Get("gold", 0);
            d["gems"] += (int)r.Get("gems", 0);
            if (GD.Str(r.Get("shard", "")) != "")                            // 0.31.185: a hero shard, a Hero Token
                d["shards"].Append(GD.Str(r["shard"]));
            d["tokens"] = (int)d.Get("tokens", 0) + (int)r.Get("token", 0);
            if (r.Has("chest"))
                AddChest(GD.Str(r["chest"]), new GDict(), true);
        }

        // ---------------- shop / locker ----------------
        public bool Owns(string id)
        {
            return d["owned"].Has(id);
        }

        public bool CanAfford(GDict price)
        {
            return (int)d["gold"] >= (int)price.Get("gold", 0) && (int)d["gems"] >= (int)price.Get("gems", 0);
        }

        // 0.31.168 (Kevin: "Unlock with gold"): the 5v5's six new heroes are bought with gold, once; the rest are everyone's.
        // 0.31.185 (Kevin: "I want the same IAP system as league of legends"): or with gems, a hero shard or a Hero Token; and
        // this week's free ones are everyone's to play (Eco.free_heroes) -- see economy.gd HERO_GEMS.
        public bool OwnsHero(string hid)
        {
            return !Eco.HERO_PRICES.Has(hid) || d.Get("heroes", new GArray()).A.Has(hid);
        }

        public bool CanPlayHero(string hid)
        {
            return OwnsHero(hid) || Eco.FreeHeroes(Now()).Has(hid);
        }

        public GDict HeroPrice(string hid)
        {
            return Eco.HeroPrice(hid, Now());
        }

        public void _OwnHero(string hid)
        {
            if (!d.Has("heroes"))
                d["heroes"] = new GArray();
            d["heroes"].Append(hid);
        }

        public string _CanUnlock(string hid)
        {
            // "" when hid can be unlocked, else why not
            if (!Eco.HERO_PRICES.Has(hid))
                return "Not for sale";
            if (OwnsHero(hid))
                return "Already yours";
            return "";
        }

        public GDict BuyHero(string hid)
        {
            var why = _CanUnlock(hid);
            if (why != "")
                return new GDict { { "ok", false }, { "error", why } };
            var price = new GDict { { "gold", (int)HeroPrice(hid)["gold"] } };
            if (!CanAfford(price))
                return new GDict { { "ok", false }, { "error", "Not enough gold" } };
            d["gold"] -= (int)price["gold"];
            _OwnHero(hid);
            Save();
            _Rec("buy_hero", GArray.Of(hid));
            return new GDict { { "ok", true } };
        }

        public GDict BuyHeroGems(string hid)
        {
            var why = _CanUnlock(hid);
            if (why != "")
                return new GDict { { "ok", false }, { "error", why } };
            var price = new GDict { { "gems", (int)HeroPrice(hid)["gems"] } };
            if (!CanAfford(price))
                return new GDict { { "ok", false }, { "error", "Not enough gems" } };
            d["gems"] -= (int)price["gems"];
            _OwnHero(hid);
            Save();
            _Rec("buy_hero_gems", GArray.Of(hid));
            return new GDict { { "ok", true } };
        }

        public int ShardsOf(string hid)
        {
            return d.Get("shards", new GArray()).A.Count(hid);
        }

        public int GiftableShards(string hid)
        {
            // 0.31.196: the shards of hid this player may give a clanmate -- not the ones a clanmate gave him (a shard given back
            // and forth would pay its melt gold every time)
            return GD.Maxi(0, ShardsOf(hid) - d.Get("gift_shards", new GArray()).A.Count(hid));
        }

        public void _ShardGone(string hid)
        {
            // a shard of hid used or melted: a gifted one goes first
            d["shards"].Erase(hid);
            if (d.Get("gift_shards", Var.Nil).IsArr && d["gift_shards"].A.Count(hid) > ShardsOf(hid))
                d["gift_shards"].Erase(hid);
        }

        public GDict UseShard(string hid)
        {
            // a shard of a locked hero: the hero for Eco.SHARD_UNLOCK of his gold price
            var why = _CanUnlock(hid);
            if (why != "")
                return new GDict { { "ok", false }, { "error", why } };
            if (ShardsOf(hid) <= 0)
                return new GDict { { "ok", false }, { "error", "No shard of that hero" } };
            var g = Eco.ShardUnlockGold(hid, Now());
            if ((int)d["gold"] < g)
                return new GDict { { "ok", false }, { "error", "Not enough gold" } };
            d["gold"] -= g;
            _ShardGone(hid);
            _OwnHero(hid);
            Save();
            _Rec("use_shard", GArray.Of(hid));
            return new GDict { { "ok", true }, { "gold", g } };
        }

        public GDict MeltShard(string hid)
        {
            // a shard melted down: Eco.SHARD_MELT of the hero's gold price
            if (ShardsOf(hid) <= 0)
                return new GDict { { "ok", false }, { "error", "No shard of that hero" } };
            var g = Eco.ShardMeltGold(hid, Now());
            _ShardGone(hid);
            d["gold"] += g;
            Save();
            _Rec("melt_shard", GArray.Of(hid));
            return new GDict { { "ok", true }, { "gold", g } };
        }

        // ---------------- hero skins (0.31.186) ----------------
        public bool OwnsSkin(string id)
        {
            return d.Get("skins", new GArray()).A.Has(id);
        }

        public string WornSkin(string hid)
        {
            return GD.Str(d.Get("skin_on", new GDict()).D.Get(hid, ""));
        }

        public GDict BuySkin(string id)
        {
            // a skin for its gems -- and, League's way, his hero too if he's still locked; worn at once
            if (!Eco.SKINS.Has(id))
                return new GDict { { "ok", false }, { "error", "Not for sale" } };
            if (OwnsSkin(id))
                return new GDict { { "ok", false }, { "error", "Already yours" } };
            var gems = (int)Eco.SKINS[id]["gems"];
            if ((int)d["gems"] < gems)
                return new GDict { { "ok", false }, { "error", "Not enough gems" } };
            d["gems"] -= gems;
            var with_hero = _GotSkin(id);
            Save();
            _Rec("buy_skin", GArray.Of(id));
            return new GDict { { "ok", true }, { "hero", with_hero } };
        }

        public bool _GotSkin(string id)
        {
            // an outfit bought: his, worn at once, and (League's way) his hero too if still locked -> whether the hero came with it
            d["skins"].Append(id);
            var hid = GD.Str(Eco.SKINS[id]["hero"]);
            var with_hero = !OwnsHero(hid);
            if (with_hero)
                _OwnHero(hid);
            d["skin_on"].D[hid] = id;
            return with_hero;
        }

        public GDict BuyOutfit(string id, bool gold = false)
        {
            // 0.31.203: what every BUY button calls -- the weekly sale's price when the outfit is on it, else the full price
            var o = Eco.SkinOffer(id, Now());
            if ((int)o["off"] > 0)
                return BuySale(id, (int)o["week"], gold);
            return gold ? BuySkinGold(id) : BuySkin(id);
        }

        public GDict BuySale(string id, int week, bool gold)
        {
            // 0.31.203 (Kevin: "For featured outfits, let's make them discounted"): an outfit at its weekly-sale price. `week`
            // is the sale the buyer saw (Eco.week_index): this week's, or last week's for Eco.SALE_GRACE after it ended (a buy
            // still on its way, or made offline just before midnight). Gems, or (gold) the rare line's gold price, discounted.
            if (!Eco.SKINS.Has(id))
                return new GDict { { "ok", false }, { "error", "Not for sale" } };
            if (OwnsSkin(id))
                return new GDict { { "ok", false }, { "error", "Already yours" } };
            var t = Now();
            var cur = Eco.WeekIndex(t);
            if (week != cur && !(week == cur - 1 && t < Eco.WeekStart(t) + Eco.SALE_GRACE))
                return new GDict { { "ok", false }, { "error", "That sale has ended" } };
            var off = Eco.SaleOffWeek(id, week);
            if (off <= 0)
                return new GDict { { "ok", false }, { "error", "Not on sale" } };
            GDict sk = Eco.SKINS[id].D;
            var price = 0;
            if (gold)
            {
                if ((int)sk.Get("gold", 0) <= 0)
                    return new GDict { { "ok", false }, { "error", "Not for gold" } };
                price = Eco.SalePrice((int)sk["gold"], off, Eco.SALE_GOLD_STEP);
                if ((int)d["gold"] < price)
                    return new GDict { { "ok", false }, { "error", "Not enough gold" } };
                d["gold"] -= price;
            }
            else
            {
                price = Eco.SalePrice((int)sk["gems"], off, Eco.SALE_GEM_STEP);
                if ((int)d["gems"] < price)
                    return new GDict { { "ok", false }, { "error", "Not enough gems" } };
                d["gems"] -= price;
            }
            var with_hero = _GotSkin(id);
            Save();
            _Rec("buy_sale", GArray.Of(id, week, gold));
            return new GDict { { "ok", true }, { "hero", with_hero }, { "off", off }, { "price", price }, { "gold", gold } };
        }

        public GDict BuySkinGold(string id)
        {
            // 0.31.189 (Kevin: "Frostbound for gold"): an outfit that has a gold price (Eco.SKINS "gold": the rare line) for gold --
            // as with gems, a locked hero's outfit brings him; worn at once
            if (!Eco.SKINS.Has(id) || (int)Eco.SKINS[id].Get("gold", 0) <= 0)
                return new GDict { { "ok", false }, { "error", "Not for gold" } };
            if (OwnsSkin(id))
                return new GDict { { "ok", false }, { "error", "Already yours" } };
            var gold = (int)Eco.SKINS[id]["gold"];
            if ((int)d["gold"] < gold)
                return new GDict { { "ok", false }, { "error", "Not enough gold" } };
            d["gold"] -= gold;
            var with_hero = _GotSkin(id);
            Save();
            _Rec("buy_skin_gold", GArray.Of(id));
            return new GDict { { "ok", true }, { "hero", with_hero } };
        }

        public GDict WearSkin(string hid, string id)
        {
            // id "" -> the hero's own look
            if (id == "")
                d["skin_on"].D.Erase(hid);
            else if (!OwnsSkin(id) || GD.Str(Eco.SKINS[id]["hero"]) != hid)
                return new GDict { { "ok", false } };
            else
                d["skin_on"].D[hid] = id;
            Save();
            _Rec("wear_skin", GArray.Of(hid, id));
            return new GDict { { "ok", true } };
        }

        public GDict UseToken(string hid)
        {
            // the premium pass's Hero Token: any locked hero (kept until there is one)
            var why = _CanUnlock(hid);
            if (why != "")
                return new GDict { { "ok", false }, { "error", why } };
            if ((int)d.Get("tokens", 0) <= 0)
                return new GDict { { "ok", false }, { "error", "No Hero Token" } };
            d["tokens"] = (int)d["tokens"] - 1;
            _OwnHero(hid);
            Save();
            _Rec("use_token", GArray.Of(hid));
            return new GDict { { "ok", true } };
        }

        // ---------------- in-app purchases (0.31.90) ----------------
        public bool IapGranted(string token)
        {
            foreach (var e in d["iap"]["done"])
            {
                if (GD.Str(e.D.Get("t", "")) == token)
                    return true;
            }
            return false;
        }

        public GDict GrantIap(string product, string token)
        {
            // A purchase Google and the server have confirmed: add what it holds. Idempotent per token (a retry after a crash,
            // or the same purchase seen again on the next start, grants nothing twice). -> {ok, gems, gold, token, again}
            GDict pk = Net.IAP.Get(product, new GDict()).D;
            if (pk.IsEmpty() || token == "")
                return new GDict { { "ok", false }, { "error", "Unknown purchase" } };
            if (server_mode)
                return new GDict { { "ok", false }, { "error", "The server grants purchases" } };       // (0.31.108: eco_accounts.gd does)
            if (IapGranted(token))
                return new GDict { { "ok", true }, { "again", true }, { "gems", 0 }, { "gold", 0 }, { "token", 0 } };
            var out_ = new GDict { { "ok", true }, { "again", false }, { "gems", (int)pk.Get("gems", 0) }, { "gold", (int)pk.Get("gold", 0) }, { "token", (int)pk.Get("token", 0) } };
            d["gems"] = (int)d["gems"] + (int)out_["gems"];
            d["gold"] = (int)d["gold"] + (int)out_["gold"];
            d["tokens"] = (int)d.Get("tokens", 0) + (int)out_["token"];      // 0.31.188: the starter pack's Hero Token (it held an epic weapon)
            if ((bool)pk.Get("once", false))
                d["iap"].D["starter"] = true;
            d["iap"]["done"].Append(new GDict { { "t", token }, { "p", product }, { "at", Now() } });
            while (d["iap"]["done"].Size() > 300)
                d["iap"]["done"].A.PopFront();
            Save();
            return out_;
        }

        public GDict Equip(string id)
        {
            // Wear an earned title (id "" not allowed; use unequip). (0.31.188: titles are all there is to equip.)
            var it = Eco.Item(id);
            if (it.IsEmpty() || !Owns(id) || GD.Str(it.Get("kind", "")) != "title")
                return new GDict { { "ok", false } };
            d["title"] = id;
            Save();
            _Rec("equip", GArray.Of(id));
            return new GDict { { "ok", true } };
        }

        public void Unequip(string cls, string slot)
        {
            if (slot == "title")
                d["title"] = "";
            else
                return;
            Save();
            _Rec("unequip", GArray.Of(cls, slot));
        }

        public GDict LookFor(string hid)
        {
            // What the battle view (and every hero on a menu) shows for this hero: {"skin": the outfit he wears} -- the outfit
            // carries its own weapon (0.31.188); {} his own look. (0.31.39-0.31.187: the equipped weapon and its Forge stars.)
            var worn = WornSkin(hid);
            return worn != "" ? new GDict { { "skin", worn } } : new GDict();
        }

        public GDict WireLooks()
        {
            // what I wear, for my hello ("lk"), so the other players see it (0.31.101; 0.31.188: outfits only -- the weapons'
            // "<class>": "weapon id|stars|element" entries are gone)
            var out_ = new GDict();
            // 0.31.186: the skins worn, one a hero ("_sk": "knight_frost,golem_frost"): each app shows the one for the hero played
            var worn = new GArray();
            foreach (var h in d.Get("skin_on", new GDict()))
                worn.Append(GD.Str(d["skin_on"][h]));
            worn.Sort();
            if (!worn.IsEmpty())
                out_["_sk"] = GStr.Join(",", worn);
            return out_;
        }

        // ---------------- challenges ----------------
        public bool RerollDaily(int index)
        {
            GDict ch = d["challenges"].D;
            if ((bool)ch["rerolled"] || index < 0 || index >= ch["daily"].Size() || (bool)ch["daily"][index]["claimed"])
                return false;
            var used = new GArray();
            foreach (var c in ch["daily"])
                used.Append(c["id"]);
            var fresh = Eco.RollChallenges("daily", GD.Str(ch["day"]) + "-reroll", 1, used);
            if (fresh.IsEmpty())
                return false;
            ch["daily"].A[index] = fresh[0];
            ch["rerolled"] = true;
            Save();
            _Rec("reroll_daily", GArray.Of(index));
            return true;
        }

        public GDict ClaimChallenge(string span, int index)
        {
            if (!GArray.Of("daily", "weekly").Has(span))
                return new GDict { { "ok", false } };
            GArray list = span == "daily" ? d["challenges"]["daily"].A : d["challenges"]["weekly"].A;
            if (index < 0 || index >= list.Size())
                return new GDict { { "ok", false } };
            GDict c = list[index].D;
            GDict def = Eco.CHALLENGES[c["id"]].D;
            if ((bool)c["claimed"] || (int)c["progress"] < (int)def["goal"])
                return new GDict { { "ok", false } };
            c["claimed"] = true;
            var out_ = new GDict { { "levels", new GArray() }, { "tiers", new GArray() }, { "chests", new GArray() } };
            _AddPassXp((int)def.Get("pass", 0), out_);
            d["gold"] += (int)def.Get("gold", 0);
            d["gems"] += (int)def.Get("gems", 0);
            var bonus = span == "daily" ? Eco.DAILY_GOLD : 0;      // 0.31.184 (0.31.93-0.31.183: Embers)
            d["gold"] += bonus;
            // 0.31.37: the whole day's challenges done -> a Silver chest; the whole week's -> a Gold chest
            if (list.All(x => (bool)x["claimed"]))
                AddChest(span == "daily" ? "silver" : "gold", out_, true);
            Save();
            _Rec("claim_challenge", GArray.Of(span, index));
            return new GDict { { "ok", true }, { "tiers", out_["tiers"] }, { "chests", out_["chests"] }, { "gold", (int)def.Get("gold", 0) + bonus } };
        }

        // ---------------- weekly leaderboard prizes (0.31.120) ----------------
        public GDict GrantPrize(string week, int rank, GDict prize)
        {
            // the server only (server/eco_accounts.gd, when a week ends): never an op a phone can send
            foreach (var x in d["prizes"])
            {
                if (GD.Str(x.Get("week", "")) == week)
                    return new GDict { { "ok", false }, { "error", "paid" } };
            }
            var out_ = new GDict { { "chests", new GArray() } };
            d["gems"] = (int)d["gems"] + (int)prize.Get("gems", 0);
            if (GD.Str(prize.Get("chest", "")) != "")
                AddChest(GD.Str(prize["chest"]), out_, true);
            var t = GD.Str(prize.Get("title", ""));
            if (t != "" && !d["owned"].A.Has(t))
                d["owned"].Append(t);
            d["prizes"].A.PushFront(new GDict { { "week", week }, { "rank", rank }, { "gems", (int)prize.Get("gems", 0) }, { "chest", GD.Str(prize.Get("chest", "")) }, { "title", t } });
            if (d["prizes"].A.Size() > 12)
                d["prizes"].A.Resize(12);
            Save();
            return new GDict { { "ok", true }, { "chests", out_["chests"] } };
        }

        // ---------------- gold the server takes (0.31.134) ----------------
        public GDict PayGold(int amount, string why)
        {
            // the server only (server/clans.gd: starting a clan): gold taken from the account, never below zero; the phone sees
            // it with its next answer from the server (eco_sync pull)
            if (amount <= 0 || (int)d["gold"] < amount)
                return new GDict { { "ok", false }, { "error", "gold" } };
            d["gold"] = (int)d["gold"] - amount;
            if (!d.Get("paid", Var.Nil).IsArr)
                d["paid"] = new GArray();
            d["paid"].A.PushFront(new GDict { { "at", Now() }, { "gold", amount }, { "why", why.Left(16) } });
            if (d["paid"].A.Size() > 12)
                d["paid"].A.Resize(12);
            Save();
            return new GDict { { "ok", true } };
        }

        // ---------------- referrals (0.31.120) ----------------
        public GDict GrantReferral(string kind, string name)
        {
            // the server only (server/referrals.gd): a Gold chest -- "joined" (you reached level 5 with a friend's code) or
            // "friend" (a player who entered your code did)
            var out_ = new GDict { { "chests", new GArray() } };
            AddChest(Eco.REF_CHEST, out_, true);
            d["referral"]["notes"].A.PushFront(new GDict { { "kind", kind }, { "name", name.Left(24) }, { "at", Now() } });
            if (d["referral"]["notes"].A.Size() > 20)
                d["referral"]["notes"].A.Resize(20);
            Save();
            return new GDict { { "ok", true }, { "chests", out_["chests"] } };
        }

        // ---------------- clans (0.31.196) ----------------
        public GDict GrantClanReward(string week, GDict r)
        {
            // the server only (server/clans.gd, when a week ends): the clan's Clan Chest (r.chest, a reward chest) and its League
            // gems (r.gems) -- once a week; never an op a phone can send
            if (!d.Get("clan_rewards", Var.Nil).IsArr)
                d["clan_rewards"] = new GArray();
            foreach (var x in d["clan_rewards"])
            {
                if (GD.Str(x.Get("week", "")) == week)
                    return new GDict { { "ok", false }, { "error", "paid" } };
            }
            var out_ = new GDict { { "chests", new GArray() } };
            var chest = GD.Str(r.Get("chest", ""));
            if (chest != "" && Eco.CHESTS.Has(chest))
                AddChest(chest, out_, true);
            else
                chest = "";
            var gems = GD.Maxi(0, (int)r.Get("gems", 0));
            d["gems"] = (int)d["gems"] + gems;
            d["clan_rewards"].A.PushFront(new GDict { { "week", week }, { "clan", GD.Str(r.Get("clan", "")).Left(24) }, { "tag", GD.Str(r.Get("tag", "")).Left(4) },
                { "chest", chest }, { "tier", (int)r.Get("tier", 0) }, { "rank", (int)r.Get("rank", 0) }, { "gems", gems }, { "pts", (int)r.Get("pts", 0) } });
            if (d["clan_rewards"].A.Size() > 12)
                d["clan_rewards"].A.Resize(12);
            Save();
            return new GDict { { "ok", true }, { "chests", out_["chests"] } };
        }

        public GDict GiveShard(string hid)
        {
            // the server only (server/clans.gd, a shard request answered): a shard of hid given to a clanmate -- gone from here,
            // and what melting it would have paid (melt_shard's gold) paid here
            if (ShardsOf(hid) <= 0)
                return new GDict { { "ok", false }, { "error", "No shard of that hero" } };
            if (GiftableShards(hid) <= 0)
                return new GDict { { "ok", false }, { "error", "gifted" } };            // (a clanmate's gift isn't given on)
            var g = Eco.ShardMeltGold(hid, Now());
            d["shards"].Erase(hid);
            d["gold"] = (int)d["gold"] + g;
            Save();
            return new GDict { { "ok", true }, { "gold", g } };
        }

        public GDict ReceiveShard(string hid)
        {
            // the server only: a clanmate's shard of hid, given to this account
            if (!Eco.HERO_PRICES.Has(hid))
                return new GDict { { "ok", false }, { "error", "Not a hero" } };
            if (!d.Get("shards", Var.Nil).IsArr)
                d["shards"] = new GArray();
            d["shards"].Append(hid);
            if (!d.Get("gift_shards", Var.Nil).IsArr)
                d["gift_shards"] = new GArray();
            d["gift_shards"].Append(hid);
            Save();
            return new GDict { { "ok", true } };
        }

        // ---------------- the daily login reward (0.31.119) ----------------
        public bool LoginReady()
        {
            return GD.Str(d["login"].Get("day", "")) != Eco.DayKey(Now());
        }

        public int LoginNext()
        {
            // the calendar day (0-6) the next claim gives
            return (int)GD.Posmod(GD.Long(d["login"].Get("n", 0)), Eco.LOGIN_REWARDS.Size());
        }

        public GDict ClaimLogin()
        {
            // one a day: the calendar's next reward (the server replays this with its own clock)
            if (!LoginReady())
                return new GDict { { "ok", false }, { "error", "claimed today" } };
            var i = LoginNext();
            GDict rw = Eco.LOGIN_REWARDS[i].D;
            var out_ = new GDict { { "chests", new GArray() } };
            d["gold"] = (int)d["gold"] + (int)rw.Get("gold", 0);
            d["gems"] = (int)d["gems"] + (int)rw.Get("gems", 0);
            if (rw.Has("chest"))
                AddChest(GD.Str(rw["chest"]), out_, true);
            d["login"].D["day"] = Eco.DayKey(Now());
            d["login"].D["n"] = (int)d["login"].Get("n", 0) + 1;
            Save();
            _Rec("claim_login", new GArray());
            return new GDict { { "ok", true }, { "day", i + 1 }, { "reward", rw }, { "chests", out_["chests"] } };
        }

        // ---------------- matches ----------------
        public GDict ApplyMatch(GDict me, bool won, bool draw, bool online)
        {
            // Called once per finished match. Returns the itemised rewards plus level-ups, pass tiers
            // and challenge progress for the results screen.
            Refresh();
            var stats = Eco.MatchStats(me, won, draw);
            var today = Eco.DayKey(Now());
            var first_win = won && GD.Str(d["first_win_day"]) != today;
            if (first_win)
                d["first_win_day"] = today;
            var r = Eco.MatchRewards(stats, won, draw, online, first_win);
            var out_ = new GDict { { "rewards", r }, { "levels", new GArray() }, { "tiers", new GArray() }, { "challenges", new GArray() }, { "first_win", first_win }, { "chests", new GArray() } };
            d["gold"] += (int)r["gold"];
            // 0.31.37: chests -- every win a Wooden one (Silver for a rescue or a multi-kill); the first win of the day a Silver
            if (won)
                AddChest((int)stats.Get("rescues", 0) > 0 || (int)me.Get("best_multi", 0) >= 2 ? "silver" : "wooden", out_);
            if (first_win)
                AddChest("silver", out_);
            _AddXp((int)r["xp"], out_);
            _AddPassXp((int)r["pass"], out_);
            var keys = GArray.Of("matches", "wins", "rescues", "kills", "gates", "gathered", "fed", "lifts", "repaired", "healed");
            keys.AppendArray(Eco.FIVE_STATS);
            foreach (var key in keys)
                d["stats"].D[key] = (int)d["stats"].Get(key, 0) + (int)stats.Get(key, 0);
            _TitleStats(stats, won);
            out_["quests"] = _QuestStats(stats, won);
            foreach (var span in GArray.Of("daily", "weekly"))
            {
                foreach (var c in (span == "daily" ? d["challenges"]["daily"] : d["challenges"]["weekly"]))
                {
                    GDict def = Eco.CHALLENGES[c["id"]].D;
                    if ((bool)c["claimed"])
                        continue;
                    var before = (int)c["progress"];
                    c.D["progress"] = GD.Mini((int)def["goal"], before + (int)stats.Get(def["stat"], 0));
                    if ((int)c["progress"] != before)
                        out_["challenges"].Append(new GDict { { "id", c["id"] }, { "text", def["text"] }, { "progress", c["progress"] }, { "goal", def["goal"] },
                            { "done", (int)c["progress"] >= (int)def["goal"] }, { "span", span } });
                }
            }
            out_["titles"] = CheckTitles();
            d["history"].A.PushFront(new GDict { { "at", Now() }, { "won", won }, { "draw", draw }, { "online", online }, { "gold", r["gold"] }, { "cls", GD.Str(me.Get("cls", "")) } });
            if (d["history"].A.Size() > 20)
                d["history"].A.Resize(20);
            Save();
            if (!online)
                _Rec("match", GArray.Of(SlimMe(me), won, draw));     // 0.31.108: (an online match's result the server takes from its own match)
            return out_;
        }

        public static GDict SlimMe(GDict me)
        {
            // what a match's result needs of the unit (the op that carries it goes to the server; the unit has much more)
            var out_ = new GDict();
            var ks = GArray.Of("kills", "rescues", "gate_dmg", "gathered", "fed", "lifts", "repaired", "healed", "best_multi", "cls", "cls_main",
                    "kills_cls", "q");
            ks.AppendArray(Eco.FIVE_STATS);
            foreach (var k in ks)
            {
                if (me.Has(k))
                {
                    Var v = me[k];
                    out_[k] = v.IsDict ? (Var)v.D.Duplicate(true) : v;
                }
            }
            return out_;
        }

        public void _TitleStats(GDict stats, bool won)
        {
            // 0.31.87: the lifetime numbers the titles read (Eco.TITLE_GOALS), from one match's stats
            var main = GD.Str(stats.Get("main", ""));
            if (main != "")
            {
                d["stats"].D["main_" + main] = (int)d["stats"].Get("main_" + main, 0) + 1;
                if (won)
                    d["stats"].D["win_" + main] = (int)d["stats"].Get("win_" + main, 0) + 1;
            }
            foreach (var key in stats)
            {
                if (GD.Str(key).BeginsWith("kills_"))
                    d["stats"].D[key] = (int)d["stats"].Get(key, 0) + (int)stats[key];
            }
            d["stats"].D["best_multi"] = GD.Maxi((int)d["stats"].Get("best_multi", 0), (int)stats.Get("best_multi", 0));
            d["stats"].D["streak"] = won ? (int)d["stats"].Get("streak", 0) + 1 : 0;          // (a draw or a loss ends the run)
            d["stats"].D["best_streak"] = GD.Maxi((int)d["stats"].Get("best_streak", 0), (int)d["stats"]["streak"]);
        }

        public GDict ClaimDiscord()
        {
            // 0.31.124: the gift for opening the Discord invite (Settings > COMMUNITY) -- once per account; the server replays it
            // on its own copy, so a phone can't take it twice
            if ((bool)d.Get("discord", false))
                return new GDict { { "ok", false }, { "error", "claimed" } };
            d["discord"] = true;
            d["gems"] = (int)d["gems"] + Eco.DISCORD_GEMS;
            Save();
            _Rec("claim_discord", new GArray());
            return new GDict { { "ok", true }, { "gems", Eco.DISCORD_GEMS } };
        }

        public GDict FinishTutorial()
        {
            // the Herald's last line: the recruit's pay, once (0.31.108: here, so the server pays it too)
            if ((bool)d.Get("tutorial_done", false))
                return new GDict { { "ok", false } };
            d["gold"] = (int)d["gold"] + Eco.TUTORIAL_GOLD;
            d["tutorial_done"] = true;
            Save();
            _Rec("finish_tutorial", new GArray());
            return new GDict { { "ok", true } };
        }

        public static string CleanName(string s)
        {
            var out_ = "";
            foreach (var chv in (Var)s)
            {
                string ch = chv.AsString();
                if (ch.UnicodeAt(0) >= 32 && ch.UnicodeAt(0) != 127)
                    out_ += ch;
            }
            return out_.StripEdges().Left(20);
        }

        public GDict SetName(string nm)
        {
            var n = CleanName(nm);
            if (n == "" || n == GD.Str(d["name"]))
                return new GDict { { "ok", false } };
            d["name"] = n;
            Save();
            _Rec("set_name", GArray.Of(n));
            return new GDict { { "ok", true } };
        }

        // ---------------- class quests (0.31.97) ----------------
        public GArray _QuestStats(GDict stats, bool won)
        {
            // Add one match to every class quest's counters (Eco.QUESTS: a base class counts its upgrade too). -> the lines the
            // results screen shows: each quest whose current step moved, with whether it is now ready to claim.
            GDict q = stats.Get("q", new GDict()).D;
            var before = new GDict();
            foreach (var cls in Eco.QUESTS)
                before[cls] = QuestHave(GD.Str(cls));
            foreach (var cls in Eco.QUESTS)
            {
                var t = 0.0;
                var add = new GDict();
                var multi = 0;
                foreach (var c in Eco.QuestFamily(GD.Str(cls)))
                {
                    Var e = q.Get(c, new GDict());
                    if (!e.IsDict)
                        continue;
                    t += (double)e.Get("t", 0.0);
                    foreach (var st in Eco.QUEST_COUNTS)
                        add[st] = (int)add.Get(st, 0) + (int)e.Get(st, 0);
                    multi = GD.Maxi(multi, (int)e.Get("best_multi", 0));
                }
                if (t >= Eco.QUEST_MIN_TIME)
                {
                    add["matches"] = 1;
                    if (won)
                        add["wins"] = 1;
                }
                foreach (var st in add)
                {
                    if ((int)add[st] > 0)
                    {
                        var k = Eco.QuestKey(GD.Str(cls), GD.Str(st));
                        d["stats"].D[k] = (int)d["stats"].Get(k, 0) + (int)add[st];
                    }
                }
                var mk = Eco.QuestKey(GD.Str(cls), "best_multi");
                if (multi > (int)d["stats"].Get(mk, 0))
                    d["stats"].D[mk] = multi;
            }
            var lines = new GArray();
            foreach (var cls in Eco.QUESTS)
            {
                var step = QuestStep(GD.Str(cls));
                if (step >= Eco.QUESTS[cls]["steps"].Size())
                    continue;
                var have = QuestHave(GD.Str(cls));
                if (have != (int)before[cls])
                {
                    GDict s = Eco.QUESTS[cls]["steps"][step].D;
                    lines.Append(new GDict { { "cls", cls }, { "step", step }, { "text", GD.Str(s["task"]) }, { "progress", GD.Mini(have, (int)s["n"]) }, { "goal", (int)s["n"] },
                        { "done", have >= (int)s["n"] } });
                }
            }
            return lines;
        }

        public int QuestStep(string cls)
        {
            // the steps of cls's quest already claimed (= the index of the one being worked on)
            return (int)d["quests"].Get(cls, 0);
        }

        public int QuestHave(string cls)
        {
            // progress on cls's current step (its stat's lifetime count)
            return Eco.QuestProgress(d["stats"].D, cls, QuestStep(cls));
        }

        public bool QuestReady(string cls)
        {
            GDict q = Eco.QUESTS.Get(cls, new GDict()).D;
            var step = QuestStep(cls);
            return !q.IsEmpty() && step < q["steps"].Size() && QuestHave(cls) >= (int)q["steps"][step]["n"];
        }

        public int QuestsReady()
        {
            var n = 0;
            foreach (var cls in Eco.QUESTS)
            {
                if (QuestReady(GD.Str(cls)) && GD.Str(cls) != "worker")          // (0.31.164: the Worker's is Siege's, not shown)
                    n += 1;
            }
            return n;
        }

        public bool QuestDone(string cls)
        {
            return Eco.QUESTS.Has(cls) && QuestStep(cls) >= Eco.QUESTS[cls]["steps"].Size();
        }

        public GDict ClaimQuest(string cls)
        {
            // Claim cls's current step: its reward (gold / gems / a chest; 0.31.188: the last gave the class's legendary weapon).
            // -> {ok, step (the one claimed, 0-based), reward, chests}
            if (!QuestReady(cls))
                return new GDict { { "ok", false } };
            var step = QuestStep(cls);
            var r = Eco.QuestReward(cls, step);
            var out_ = new GDict { { "ok", true }, { "step", step }, { "reward", r }, { "chests", new GArray() } };
            d["gold"] = (int)d["gold"] + (int)r.Get("gold", 0);
            d["gems"] = (int)d["gems"] + (int)r.Get("gems", 0);
            if (r.Has("chest"))
                AddChest(GD.Str(r["chest"]), out_, true);
            d["quests"].D[cls] = step + 1;
            Save();
            _Rec("claim_quest", GArray.Of(cls));
            return out_;
        }

        public int TitleProgress(string id)
        {
            return Eco.TitleProgress(d["stats"].D, id);
        }

        public GArray CheckTitles()
        {
            // Titles whose goal is reached and that aren't owned yet: owned now. -> their ids (rarest first).
            var got = new GArray();
            foreach (var id in Eco.TITLE_GOALS)
            {
                if (!d["owned"].Has(id) && TitleProgress(GD.Str(id)) >= (int)Eco.TITLE_GOALS[id]["n"])
                {
                    d["owned"].Append(id);
                    got.Append(id);
                }
            }
            got.SortCustom((a, b) => Eco.TITLE_RARITY_ORDER.Find(GD.Str(Eco.CATALOG[a]["rarity"])) > Eco.TITLE_RARITY_ORDER.Find(GD.Str(Eco.CATALOG[b]["rarity"])));
            return got;
        }

        // ---------------- chests (0.31.37) ----------------
        public GArray Chests()
        {
            return d["chests"]["slots"].A;
        }

        public void AddChest(string kind, GDict out_, bool reward = false)
        {
            // a new chest takes a free slot; with all CHEST_SLOTS full a match's chest is turned into gold at once, while a
            // reward chest (a level, the pass, a quest, a whole day's / week's orders -- 0.31.108) waits for a slot
            if (!out_.Has("chests"))
                out_["chests"] = new GArray();
            if (d["chests"]["slots"].Size() >= Eco.CHEST_SLOTS)
            {
                if (reward && d["chests"]["queue"].A.Size() < Eco.CHEST_QUEUE_MAX)
                {
                    d["chests"]["queue"].Append(kind);
                    out_["chests"].Append(new GDict { { "kind", kind }, { "full", false }, { "queued", true } });
                    return;
                }
                int g = (int)Eco.CHEST_FULL_GOLD[kind];
                d["gold"] += g;
                out_["chests"].Append(new GDict { { "kind", kind }, { "full", true }, { "gold", g } });
                return;
            }
            _NewChest(kind);
            out_["chests"].Append(new GDict { { "kind", kind }, { "full", false } });
        }

        public void _NewChest(string kind)
        {
            var c = new GDict { { "id", (int)d["chests"]["next"] }, { "kind", kind }, { "got", Now() }, { "start", -1 } };
            d["chests"].D["next"] = (int)d["chests"]["next"] + 1;
            d["chests"]["slots"].Append(c);
        }

        public void _FillSlots()
        {
            // the waiting reward chests move into the slots that are free
            while (d["chests"]["slots"].Size() < Eco.CHEST_SLOTS && !d["chests"]["queue"].A.IsEmpty())
                _NewChest(GD.Str(d["chests"]["queue"].A.PopFront()));
        }

        public int ChestsWaiting()
        {
            return d["chests"].Get("queue", new GArray()).A.Size();
        }

        public int ChestLeft(GDict c)
        {
            // seconds until it's unlocked (its full time if not started)
            int t = (int)Eco.CHESTS[c["kind"]]["unlock"];
            if ((int)c["start"] < 0)
                return t;
            return GD.Maxi(0, (int)c["start"] + t - Now());
        }

        public bool ChestReady(GDict c)
        {
            return (int)c["start"] >= 0 && ChestLeft(c) <= ready_grace;
        }

        public GDict Unlocking()
        {
            foreach (var c in d["chests"]["slots"])
            {
                if ((int)c["start"] >= 0 && ChestLeft(c.D) > 0)
                    return c.D;
            }
            return new GDict();
        }

        public bool StartUnlock(int index)
        {
            if (index < 0 || index >= d["chests"]["slots"].Size() || !Unlocking().IsEmpty())
                return false;
            GDict c = d["chests"]["slots"][index].D;
            if ((int)c["start"] >= 0)
                return false;
            c["start"] = Now();
            Save();
            _Rec("start_unlock", GArray.Of((int)c["id"]));
            return true;
        }

        public GDict SkipChest(int index)
        {
            if (index < 0 || index >= d["chests"]["slots"].Size())
                return new GDict { { "ok", false } };
            GDict c = d["chests"]["slots"][index].D;
            var cost = Eco.SkipCost(ChestLeft(c));
            if (ChestReady(c) || (int)d["gems"] < cost)
                return new GDict { { "ok", false }, { "cost", cost } };
            d["gems"] = (int)d["gems"] - cost;
            c["start"] = Now() - (int)Eco.CHESTS[c["kind"]]["unlock"];
            Save();
            _Rec("skip_chest", GArray.Of((int)c["id"]));
            return new GDict { { "ok", true }, { "cost", cost } };
        }

        public GDict OpenChest(int index)
        {
            if (index < 0 || index >= d["chests"]["slots"].Size())
                return new GDict { { "ok", false } };
            GDict c = d["chests"]["slots"][index].D;
            if (!ChestReady(c))
                return new GDict { { "ok", false } };
            // 0.31.108: the roll's seed is the account's salt and the chest's id and kind -- the phone and the server roll the
            // same (it was the name and the time it was got, which the two may not agree on)
            var roll = Eco.RollChest(GD.Str(c["kind"]), GD.Hash(GArray.Of(GD.Long(d["chests"].Get("salt", 0)), GD.Long(c["id"]), GD.Str(c["kind"]))));
            d["gold"] += (int)roll["gold"];
            if (GD.Str(roll.Get("shard", "")) != "")
                d["shards"].Append(GD.Str(roll["shard"]));              // 0.31.185: a hero shard
            d["gems"] += (int)roll["gems"];
            d["chests"]["slots"].A.RemoveAt(index);
            _FillSlots();
            Save();
            _Rec("open_chest", GArray.Of((int)c["id"]));
            roll["ok"] = true;
            roll["kind"] = c["kind"];
            return roll;
        }
    }
}
