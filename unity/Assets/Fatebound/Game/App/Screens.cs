// Ported from godot/scripts/app/screens.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector2i = Fatebound.Sim.Vec2i;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using Eco = Fatebound.Game.Economy;
using View = Fatebound.Game.SiegeView;
using Diag = Fatebound.Game.SiegeDiag;
using Net = Fatebound.Game.SiegeNet;
using Platform = Fatebound.Game.Platform;          // 0.31.130: Google Play or the App Store
using Champions = Fatebound.Game.Champions;       // 0.31.187: who the eighteen are (the Locker)
using Kits = Fatebound.Sim.MobaKits;              // (screens.gd loads moba_kits.gd inside skin_grid / market_heroes / locker_champions)

namespace Fatebound.Game
{
    // Screens for the Siege app shell. Each builds into `root` from app.profile; the shell rebuilds
    // the current screen after every change (buy, claim, equip...).
    public static class Screens
    {
        public const string PRIVACY_URL = "https://136-113-125-3.sslip.io/fatebound/privacy.html";

        // ---------------- shared bits ----------------
        public static int GridCols(SiegeApp app, double card_w, double gap = 10.0)
        {
            // 0.31.216 (landscape): a grid of cards as many across as the screen area takes (3 to 7)
            return GD.Clampi((int)(((double)app.ContentW() + gap) / (card_w + gap)), 3, 7);
        }

        public static void Section(Node root, string text, string right = "", string icon = "")
        {
            var r = UI.Row(root, 8);
            if (icon != "")
                UI.Icon(r, icon, 18, UI.GOLD);
            UI.Grow(UI.Label(r, text, 15, UI.GOLD, UI.TITLE_FONT, true));
            if (right != "")
            {
                var l = UI.Label(r, right, 12, UI.MUTED);
                l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            }
        }

        public static string ItemIcon(GDict it)
        {
            return GD.Str(it.Get("kind", "")) == "title" ? "title" : "star";
        }

        public static Color Rarity(GDict it)
        {
            return Color.FromCode(GD.Str(Eco.RARITY_COLOR.Get(GD.Str(it.Get("rarity", "common")), "#b8c4c9")));
        }

        public static string ChestIcon(string kind)
        {
            return UI2.V2 + GD.Fmt("chests/%s_icon.png", GD.Str(GDict.Of("wooden", "wood").Get(kind, kind)));
        }

        public static readonly GDict HERO_NAMES = GDict.Of("golem", "Golem", "dragoon", "Dragoon", "duelist", "Duelist", "stormcaller", "Stormcaller", "musketeer", "Musketeer",
            "druid", "Druid");                     // (moba.gd HEROES' names for the sold ones -- this file doesn't load the sim)

        public static GArray RewardText(GDict r)
        {
            // -> [glyph kind, text, colour, texture path or ""]
            if (r.Has("chest"))                                   // (0.31.79: chests used to read "0 gold" here)
            {
                var ck = GD.Str(r["chest"]);
                return GArray.Of("chest", GD.Str(Eco.CHESTS.Get(ck, new GDict()).Get("name", "Chest")), Color.FromCode(GD.Str(Eco.CHESTS.Get(ck, new GDict()).Get("color", "#ffcf4a"))), ChestIcon(ck));
            }
            if (r.Has("gems"))
                return GArray.Of("gem", GD.Fmt("%d gems", (int)r["gems"]), UI.CYAN, "res://assets/ui/currency/gem.png");
            // 0.31.185 (League's way): a hero shard (which hero, once it's known) and the premium pass's Hero Token
            if (r.Has("shard"))
            {
                var sh = GD.Str(r["shard"]);
                if (sh != "")
                    return GArray.Of("star", GD.Fmt("%s Shard", GD.Str(HERO_NAMES.Get(sh, sh.Capitalize()))), new Color("#9dff8a"), GD.Fmt("res://assets/ui/skins/default_%s.png", sh));
                return GArray.Of("star", "Hero Shard", new Color("#9dff8a"), UI2.V2 + "icons/helmet.png");
            }
            if (r.Has("token"))
                return GArray.Of("star", "Hero Token", new Color("#e2b8ff"), UI2.V2 + "icons/helmet.png");
            var g = (int)r.Get("gold", 0);
            return GArray.Of("coin", GD.Fmt("%d gold", g), UI.GOLD, GD.Fmt("res://assets/ui/currency/%s.png", g >= 300 ? "coins_s" : "coin"));
        }

        public static string _RarPanel(string rar)
        {
            return GD.Str(GDict.Of("common", "night", "rare", "royal", "epic", "purple", "legendary", "ember").Get(rar, "night"));
        }

        public static string _RarRim(string rar)
        {
            return GD.Str(GDict.Of("common", "silver", "rare", "blue", "epic", "purple", "legendary", "orange").Get(rar, "gold"));
        }

        public static Color _RarTint(string rar)
        {
            return (Color)GDict.Of("common", new Color(0.85, 0.88, 1.0), "rare", new Color(0.55, 0.78, 1.0), "epic", new Color(0.85, 0.6, 1.0), "legendary", new Color(1.0, 0.78, 0.35)).Get(rar, new Color(1, 0.9, 0.6));
        }

        // ---------------- HOME ----------------
        // 0.31.79 (Kevin: the concepts, "build it"): the painted backdrop with the heroes (the app's hero layer), one big PLAY
        // (always the server), the chests in 3D. The top is laid out by hand in content pixels (the hero layer lines up with it).
        // 0.31.112 (Kevin: "for home screen I don't want it to scroll down, just have the chests at bottom and move the orders and
        // stuff to its own popup menu"): Home fills the screen and doesn't scroll, the chests on the bottom edge; on a screen too
        // short for it, Home scrolls the little that's left.
        // 0.31.194 (Kevin: "Now let's design a new home screen" -- he picked B2, the champions' camp, keeping the chest slots, the
        // chat bar and the Discord / server pill): top to bottom -- the 5v5 pill (or your party) and JOIN OUR DISCORD in one row
        // under the top bar; the camp (camp_scene.gd: six champions round their fire); PLAY, an orange enamel plaque in a gold
        // frame with a blue gem at each end, the first win of the day as a tab under it; the four chests, each on a dark wood
        // panel with its name, the chest in 3D and its button; then the chat line and the tabs (siege_app). The side buttons
        // are gone: PASS has its tab, and ORDERS, QUESTS, RANKS and the TUTORIAL are in the top bar's menu (siege_app
        // open_home_menu). (0.31.114-0.31.193: medallion columns down both sides -- PASS, ORDERS, QUESTS; RANKS, TUTORIAL.)
        public const double ROW_Y = 2.0;             // the top row: the 5v5 pill (or your party) and JOIN OUR DISCORD
        public const double ROW_H = 40.0;
        public const double DISCORD_W = 118.0;
        public const string SALE = "res://assets/ui/v2/sale/";       // 0.31.203: the weekly sale's art (ElevenLabs): stage, ribbon, starburst
        public const double SALE_FEET = 0.78;        // where the showcase stands him (of the stage's height): the pedestal goes under his feet
        public const string PLAQUE = "res://assets/ui/v2/play_plaque.webp";
        public const double PLAQUE_W = 250.0;
        public const double PLAQUE_H = 84.0;         // (760 x 255 art: tools/home_camp.py; 0.31.139-0.31.193 a plaque with a crown and swords)
        public static readonly Rect2 PLAQUE_FACE = new Rect2(0.13, 0.18, 0.74, 0.7);    // the enamel face, as fractions of the plaque
        public const double FW_H = 26.0;             // the FIRST WIN tab under PLAY ...
        public const double FW_HANG = 14.0;          // ... hanging this far below the plaque
        public const double PLAY_GAP = 6.0;          // between PLAY (its tab) and the chests
        public const double PLAY_MIN = 186.0;        // (on a short screen the chests go no higher: Home scrolls a little instead; 260 for PLAY in portrait)
        public const double CHEST_H = 104.0;         // a chest's panel: its name, the chest in 3D, its button
        public static readonly GArray CHEST_FILL = GArray.Of(new Color("#3b2717"), new Color("#140b05"));     // the panels' dark wood (top, bottom)

        public static void DiscordPress(SiegeApp app)
        {
            // 0.31.124/125: Settings' and Home's JOIN OUR DISCORD -- open the invite; the first time, the gift (once per account)
            app.open_url(Eco.DISCORD_URL);              // (the app's link opener; tests put their own)
            if ((bool)app.profile.d.Get("discord", false))
            {
                app.Sfx("tap");
                return;
            }
            GDict r = app.profile.ClaimDiscord();
            if ((bool)r.Get("ok", false))
            {
                app.Sfx("purchase");
                app.Toast(GD.Fmt("Thanks for joining! +%d gems", Eco.DISCORD_GEMS), UI.GOLD);
                app.RefreshTop();
                app.Rebuild();                                // (Home's button goes; Settings' loses its +100)
            }
        }

        public static GDict HomeLayout(double h)
        {
            // 0.31.216 (landscape, Honor of Kings' lobby): the chests along the bottom on the left, PLAY at the bottom right (its
            // FIRST WIN tab over it), the camp's heroes over the chests in the middle; on a short screen the chests go no higher
            // than PLAY_MIN and Home scrolls a little. (Portrait until then: the chests on the bottom edge, PLAY over them.)
            var chest_y = GD.Maxf(PLAY_MIN, h - CHEST_H - 4.0);
            var play = chest_y + CHEST_H - PLAQUE_H - 2.0;
            return GDict.Of("play", play, "chests", chest_y, "needed", chest_y + CHEST_H + 4.0);
        }

        public static GDict MenuCounts(SiegeApp app)
        {
            // 0.31.194: what's waiting in the top bar's menu -- the orders ready to claim (the daily login reward counts: 0.31.119)
            // and the quest steps ready (0.31.97); whether the tutorial's been played
            var p = app.profile;
            GDict d = p.d;
            var orders = p.LoginReady() ? 1 : 0;
            foreach (var span in new[] { "daily", "weekly" })
            {
                foreach (var ch in (span == "daily" ? d["challenges"]["daily"] : d["challenges"]["weekly"]))
                {
                    if (!(bool)ch["claimed"] && Eco.CHALLENGES.Has(GD.Str(ch["id"])) && (int)ch["progress"] >= (int)Eco.CHALLENGES[ch["id"]]["goal"])
                        orders += 1;
                }
            }
            return GDict.Of("orders", orders, "quests", (int)p.QuestsReady(), "tutorial_done", (bool)d.Get("tutorial_done", false));
        }

        public static void Home(SiegeApp app, VBoxContainer root)
        {
            var p = app.profile;
            GDict d = p.d;
            app.HeroShow();
            double w = GD.Maxf(300.0, app.ContentW());
            double avail = app.HomeHeight();
            var lay = HomeLayout(avail);
            app.home_fixed = (double)lay["needed"] <= avail + 1.0;
            var top = new Control();
            top.CustomMinimumSize = new Vector2(0, GD.Maxf(avail, (double)lay["needed"]));
            top.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            root.AddChild(top);
            if (d.Has("title_note"))                               // 0.31.87: titles earned from the stats you already had
            {
                GArray tn = d["title_note"].A;
                app.Toast(GD.Fmt("You've earned %d title%s for what you've already done -- see the Armory", tn.Size(), tn.Size() == 1 ? "" : "s"), UI.GOLD);
                d.Erase("title_note");
                p.Save();
            }
            if (d.Has("refund_note"))                              // 0.31.39: skins removed -- tell them once what came back
            {
                GDict rn = d["refund_note"].D;
                app.Toast(GD.Fmt("Skins have been retired -- refunded %s", GStr.Join(", ", GArray.Of((int)rn["gold"] > 0 ? GD.Fmt("%d gold", (int)rn["gold"]) : "", (int)rn["gems"] > 0 ? GD.Fmt("%d gems", (int)rn["gems"]) : "").Filter(x => x != ""))), UI.GOLD);
                d.Erase("refund_note");
                p.Save();
            }
            var soc = app.social;          // (app.get("social"))
            var fw_open = GD.Str(d["first_win_day"]) != Eco.DayKey(p.Now());
            // --- the top row: the 5v5 pill (or your party) on the left, JOIN OUR DISCORD on the right until it's claimed
            // (0.31.125, Kevin: "Put a discord button on front page that goes away after they claim it")
            var discord = !(bool)d.Get("discord", false);
            var left_w = w - (discord ? DISCORD_W + 8.0 : 0.0);
            if (soc != null && soc.Online() && soc.InParty())
            {
                // in a party: who's in it (the leader first, with a crown)
                var names = new GArray();
                foreach (var m in soc.party.Get("members", new GArray()))
                    names.Append((GD.Str(m["pid"]) == GD.Str(soc.party["leader"]) ? "♛ " : "") + GD.Str(m["n"]));
                var pb = UI2.Button(top, GD.Fmt("PARTY %d/%d  ·  %s", soc.PartySize(), (int)soc.party.Get("max", 4), GStr.Join("  ·  ", names)), "green", () =>
                {
                    app.Sfx("menuOpen");
                    app.OpenFriends();
                }, "party_pill", 12, ROW_H, 17.0);
                pb.Position = new Vector2(0, ROW_Y);
                pb.Size = new Vector2(left_w, ROW_H);
                pb.ClipText = true;
                app.online_refs = new GDict();
            }
            else
                _OnlinePill(app, top, new Rect2(0, ROW_Y, left_w, ROW_H), !discord);
            if (discord)
                _DiscordButton(app, top, new Rect2(w - DISCORD_W, ROW_Y, DISCORD_W, ROW_H));
            // --- 0.31.214: the Starter Pack, until it's bought, on the camp's left under the top row
            if (!(bool)p.d["iap"]["starter"])
            {
                // (0.31.216: landscape -- between the top row and the chests, smaller on a short screen)
                var st_y = ROW_Y + ROW_H + 8.0;
                var st = StarterTile(app, top, new Vector2(0.0, st_y));
                var st_k = GD.Clampf(((double)lay["chests"] - 4.0 - st_y) / STARTER_H, 0.72, 1.0);
                st.Scale = new Vector2(st_k, st_k);
            }
            // --- PLAY: always the Siege server (0.31.79); the bots fill any empty slots. 0.31.145: it opens the 5v5's heroes.
            double py = (double)lay["play"];
            var px = w - PLAQUE_W;                        // (0.31.216: bottom right; centred over the chests in portrait)
            UI2.Glow(top, new Rect2(px - 34, py - 12, PLAQUE_W + 68, PLAQUE_H + 30), new Color(1.0, 0.55, 0.15, 0.5));
            var play = new Button();
            play.Flat = true;
            play.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed", "disabled" })
                play.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            play.Position = new Vector2(px, py);
            play.Size = new Vector2(PLAQUE_W, PLAQUE_H);
            play.SetMeta("action_key", "play");
            play.Pressed += () => app.Play();
            top.AddChild(play);
            var art = new TextureRect();
            art.Name = "Plaque";
            art.Texture = UI2.Tex(PLAQUE);
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_SCALE;
            art.TextureFilter = TextureFilterMode.LinearWithMipmaps;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            play.AddChild(art);
            if (art.Texture == null)                         // (without the ui pack's art: an orange button's colours)
                UI2.Plate(art, "orange", 18.0, "gold");
            var word = "PLAY";                            // (0.31.164-169: the 5v5 offline, no party count)
            if (soc != null && soc.Online() && soc.InParty() && soc.IsLeader() && soc.PartySize() > 1)
                word = GD.Fmt("PLAY ×%d", soc.PartySize());       // 0.31.170: the online 5v5 -- the party goes in together
            var face = new Rect2(PLAQUE_FACE.position * play.Size, PLAQUE_FACE.size * play.Size);
            var pl = UI2.Text(play, word, word.Length <= 5 ? 42 : 34, Color.WHITE, new Color("#6a1a04"), 11);
            pl.Name = "PlayWord";
            pl.HorizontalAlignment = HorizontalAlignment.Center;
            pl.VerticalAlignment = VerticalAlignment.Center;
            pl.Position = face.position + new Vector2(0, 1);
            pl.Size = face.size;
            pl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            // (0.31.213, Kevin's screenshot: the shine, clipped only to the button's box, showed as a pale box past the plaque's
            // right end at the end of each pass -- now only on the plaque itself)
            if (art.Texture != null)
                UI2.Sweep(art, 3.4, 60.0, 0.4, true);
            else
                UI2.Sweep(play, 3.4, 60.0, 0.4);
            UI2.Pulse(play, 0.022, 1.1);
            if (fw_open)
            {
                // 0.31.119: the first win of the day (it was the FIRST WIN medallion); 0.31.194 a dark tab hanging under PLAY
                var tag = _FirstWinTab(top);
                tag.Position = new Vector2(px + (PLAQUE_W - tag.Size.x) * 0.5, py - FW_H + 6.0);      // (0.31.216: over PLAY)
                top.MoveChild(tag, 0);
            }
            // --- chests, on the bottom edge
            ChestsRow(app, top, GD.Minf(w - PLAQUE_W - 14.0, 4.0 * 118.0), (double)lay["chests"]);     // (0.31.216: left of PLAY)
            if (app.safe_boot && !(bool)Var.Of(app.GetMeta("safe_note", false)))
            {
                // 0.31.70: the last start never reached the menu, so this one skipped the background loading
                app.SetMeta("safe_note", true);
                app.Toast("The game got stuck starting last time -- please tap Settings > SEND TO DEVELOPER", UI.GOLD);
            }
        }

        // 0.31.214 (Kevin: "Show the starter pack on the front page and make sure it's eye-catching and has pretty graphics that
        // doesn't look like AI made it"): its picture is a 3D render (tools/render_starter_pack.gd) -- the game's own gold chest
        // thrown open on a heap of gold coins and blue gems, a Hero Token leaning on it: what's in the pack
        public const string STARTER_ART = "res://assets/ui/v2/offer/starter_pack.webp";
        public const double STARTER_W = 112.0;
        public const double STARTER_H = 152.0;

        public static Control StarterTile(SiegeApp app, Control top, Vector2 at)
        {
            // Home's offer: a warm card under a breathing glow, light turning behind the chest as it bobs out of the card's top,
            // sparkles winking on it, STARTER PACK on a red ribbon, a shine passing; the price under it, beating
            // (buys at once); anywhere else on it: the offer's window (siege_app.open_starter)
            var t = new Control();
            t.Name = "StarterTile";
            t.Position = at;
            t.Size = new Vector2(STARTER_W, STARTER_H);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            top.AddChild(t);
            UI2.Glow(t, new Rect2(-30, -10, STARTER_W + 60, STARTER_H + 30), new Color(1.0, 0.58, 0.18, 0.6));
            var card = new Button();                       // (the whole card is the button to the window)
            card.Name = "StarterCard";
            card.Flat = true;
            card.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus", "hover_pressed", "disabled" })
                card.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            card.Position = new Vector2(0, 30);
            card.Size = new Vector2(STARTER_W, STARTER_H - 30);
            card.SetMeta("action_key", "home_starter");
            card.Pressed += () =>
            {
                app.Sfx("menuOpen");
                app.OpenStarter();
            };
            t.AddChild(card);
            UI2.Plate(card, "ember", 16.0, "gold");
            var clip = new Control();                      // (the light stays inside the card)
            clip.ClipContents = true;
            clip.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            clip.Position = new Vector2(4, 4);
            clip.Size = card.Size - new Vector2(8, 8);
            card.AddChild(clip);
            var ry = UI2.Rays(clip, 210.0, new Color(1.0, 0.86, 0.5), 22.0, 0.5);
            ry.Position = new Vector2(clip.Size.x * 0.5 - 105.0, 20.0 - 105.0);
            UI2.Sweep(card, 3.8, 50.0, 0.35);
            var art = new TextureRect();                   // (out of the card's top: the chest is bigger than its box)
            art.Name = "StarterArt";
            art.Texture = UI2.Tex(STARTER_ART);
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            art.TextureFilter = TextureFilterMode.LinearWithMipmaps;
            art.Size = new Vector2(STARTER_W + 24.0, 108.0);
            art.Position = new Vector2(-12.0, -8.0);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            t.AddChild(art);
            UI2.Bob(art, 3.0, 1.6);
            var tw_box = new Control();
            tw_box.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tw_box.Position = new Vector2(4, 4);
            tw_box.Size = new Vector2(STARTER_W - 8, 92);
            t.AddChild(tw_box);
            _Twinkles(tw_box, 4, new Color(1.0, 0.95, 0.75), new Rect2(0.12, 0.25, 0.76, 0.6), 16.0);
            var rb = UI2.Ribbon(t, "STARTER PACK", "", STARTER_W + 22.0, 24.0, GArray.Of(new Color("#f0503c"), new Color("#7c120b")));
            rb.Position = new Vector2(-11.0, 92.0);
            var b = _IapButton(app, t, "starter_pack", new Vector2(7.0, STARTER_H - 37.0), new Vector2(STARTER_W - 14.0, 31.0));
            b.Name = "StarterBuy";
            UI2.Pulse(b, 0.045, 0.8);
            return t;
        }

        public static Control _FirstWinTab(Control parent)
        {
            // 0.31.194: FIRST WIN +150 and a coin, white and gold on a dark tab with a gold rim (B2's)
            var tab = new Control();
            tab.Name = "FirstWinTag";
            tab.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(tab);
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 5);
            r.Alignment = BoxContainer.ALIGNMENT_CENTER;
            r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tab.AddChild(r);
            var a = UI2.Text(r, "FIRST WIN", 13, Color.WHITE, UI2.INK, 4);
            a.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var b = UI2.Text(r, GD.Fmt("+%d", (int)Eco.FIRST_WIN["gold"]), 14, UI2.GOLD, UI2.INK, 4);
            b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            UI2.Img(r, "res://assets/ui/currency/coin.png", 18.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var tw = (double)UI2.LG.GetStringSize("FIRST WIN", HorizontalAlignment.Left, -1, 13).x
                + (double)UI2.LG.GetStringSize(GD.Fmt("+%d", (int)Eco.FIRST_WIN["gold"]), HorizontalAlignment.Left, -1, 14).x + 18.0 + 10.0 + 30.0;
            tab.Size = new Vector2(tw, FW_H);
            r.Position = Vector2.ZERO;
            r.Size = tab.Size;
            UI2.Plate(tab, "night", 11.0, "gold", GDict.Of("fill_top", new Color("#3a2414"), "fill_bottom", new Color("#160c05"), "rim", 2.0,
                "shadow_y", 3.0));
            UI2.Bob(tab, 1.5, 1.4);
            return tab;
        }

        public static void _DiscordButton(SiegeApp app, Control top, Rect2 at)
        {
            // 0.31.125: JOIN OUR DISCORD, its gift as a tag on its corner, until it's claimed (0.31.194: on the top row's right,
            // two lines, as B2 has it)
            var db = UI2.Button(top, "JOIN OUR\nDISCORD", "discord", () => DiscordPress(app), "home_discord", 11, at.size.y, 14.0);
            db.Name = "HomeDiscord";
            db.Position = at.position;
            db.Size = at.size;
            db.AddThemeConstantOverride("line_spacing", -4);
            UI2.Bob(db, 2.0, 1.8);
            var gt = new PanelContainer();
            gt.Name = "DiscordGift";
            var gs = new StyleBoxFlat();
            gs.BgColor = new Color("#ffc94d");
            gs.BorderColor = new Color("#3a1c02");
            gs.SetBorderWidthAll(2);
            gs.SetCornerRadiusAll(10);
            gs.ContentMarginLeft = 6;
            gs.ContentMarginRight = 8;
            gs.ShadowColor = new Color(0, 0, 0, 0.35);
            gs.ShadowSize = 4;
            gt.AddThemeStyleboxOverride("panel", gs);
            gt.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            db.AddChild(gt);
            var gr = new HBoxContainer();
            gr.AddThemeConstantOverride("separation", 3);
            gr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            gt.AddChild(gr);
            UI2.Img(gr, "res://assets/ui/currency/gem.png", 16.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var gl = new Label();                          // (a plain Label: a wrapping one sizes the tag a letter wide)
            gl.Text = GD.Fmt("+%d", Eco.DISCORD_GEMS);
            gl.AddThemeFontOverride("font", UI.HEAVY_FONT);
            gl.AddThemeFontSizeOverride("font_size", 12);
            gl.AddThemeColorOverride("font_color", new Color("#3a1c02"));
            gl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            gr.AddChild(gl);
            gt.ResetSize();
            gt.Position = new Vector2(at.size.x - gt.GetCombinedMinimumSize().x + 10.0, at.size.y - 5.0);   // (off the words)
        }

        public static PanelContainer _Tag(Control parent, string text, int font = 12)
        {
            // a gold tag with dark text (the tutorial's gold in the menu)
            var tag = new PanelContainer();
            var ts = new StyleBoxFlat();
            ts.BgColor = new Color("#ffc94d");
            ts.BorderColor = new Color("#3a1c02");
            ts.SetBorderWidthAll(2);
            ts.SetCornerRadiusAll(10);
            ts.ContentMarginLeft = 8;
            ts.ContentMarginRight = 8;
            ts.ContentMarginTop = 1;
            ts.ContentMarginBottom = 1;
            ts.ShadowColor = new Color(0, 0, 0, 0.35);
            ts.ShadowSize = 4;
            tag.AddThemeStyleboxOverride("panel", ts);
            tag.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(tag);
            var tl = new Label();                          // (not UI.label: a wrapping label sizes the tag a letter wide first)
            tl.Text = text;
            tl.AddThemeFontOverride("font", UI.HEAVY_FONT);
            tl.AddThemeFontSizeOverride("font_size", font);
            tl.AddThemeColorOverride("font_color", new Color("#3a1c02"));
            tl.HorizontalAlignment = HorizontalAlignment.Center;
            tl.VerticalAlignment = VerticalAlignment.Center;
            tl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tag.AddChild(tl);
            var tw = (double)UI.HEAVY_FONT.GetStringSize(text, HorizontalAlignment.Left, -1, font).x + 22.0;
            tag.CustomMinimumSize = new Vector2(tw, 22);
            tag.Size = tag.CustomMinimumSize;
            return tag;
        }

        public static void _OnlinePill(SiegeApp app, Control top, Rect2 at, bool centred)
        {
            // --- players online (0.31.82, Kevin: "Add a players online in main menu"), painted by app.paint_online() from the
            // server's status answer (FATEBOUND / 5 vs 5 until one comes). 0.31.194: B2's green pill with a gold rim -- crossed
            // swords, the line and the live dot -- on the top row's left (in the middle once JOIN OUR DISCORD has gone)
            var pill = new Control();
            pill.Name = "OnlinePill";
            pill.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            top.AddChild(pill);
            var r = new HBoxContainer();
            r.AddThemeConstantOverride("separation", 7);
            r.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            pill.AddChild(r);
            var sw = UI2.Icon(r, "swords", 28.0);
            sw.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var col = new VBoxContainer();
            col.AddThemeConstantOverride("separation", -3);
            col.Alignment = BoxContainer.ALIGNMENT_CENTER;
            col.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            r.AddChild(col);
            var om = UI2.Text(col, "FATEBOUND", 14, Color.WHITE, new Color("#0b2a14"), 5);
            om.ClipText = true;
            var osub = UI2.Text(col, "5 vs 5", 11, new Color("#d9ffcf"), new Color("#0b2a14"), 4);
            var dot = new Panel();                                // the live dot breathes
            var ds = new StyleBoxFlat();
            ds.BgColor = new Color("#b9ff7a");
            ds.SetCornerRadiusAll(4);
            ds.ShadowColor = new Color(0.7, 1.0, 0.4, 0.7);
            ds.ShadowSize = 4;
            dot.AddThemeStyleboxOverride("panel", ds);
            dot.CustomMinimumSize = new Vector2(8, 8);
            dot.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            dot.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            r.AddChild(dot);
            UI2.WhenReady(dot, () =>
            {
                var dtw = dot.CreateTween().SetLoops();
                dtw.TweenProperty(dot, "modulate:a", 0.3, 0.8).SetTrans(Tween.TRANS_SINE);
                dtw.TweenProperty(dot, "modulate:a", 1.0, 0.8).SetTrans(Tween.TRANS_SINE);
            });
            // (as wide as its longest line can be -- "12 PLAYERS ONLINE" -- up to the room there is)
            var tw = (double)UI2.LG.GetStringSize("123 PLAYERS ONLINE", HorizontalAlignment.Left, -1, 14).x + 10.0 + 28.0 + 8.0 + 14.0 + 20.0;
            var pw = GD.Minf(at.size.x, tw);
            pill.Size = new Vector2(pw, at.size.y);
            pill.Position = new Vector2(at.position.x + (centred ? (at.size.x - pw) * 0.5 : 0.0), at.position.y);
            r.Position = new Vector2(10, 0);
            r.Size = new Vector2(pw - 20, at.size.y);
            col.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            UI2.Plate(pill, "green", at.size.y * 0.5, "gold", GDict.Of("rim", 2.5, "shadow_y", 3.0));
            app.online_refs = GDict.Of("main", om, "sub", osub);
            if (true /* app.has_method("paint_online") */)
                app.PaintOnline();
        }

        // ---------- chests (0.31.37; 0.31.79 in 3D; 0.31.194 on B2's panels) ----------
        public static void ChestsRow(SiegeApp app, Control parent, double w, double y)
        {
            // each slot a dark wood panel: the chest's name on top, the chest in 3D in the middle (all four in one view, over the
            // panels), and under it what you can do -- OPEN, the time left and SKIP for gems, UNLOCK, or how long it'll take once
            // it's its turn (QUEUED); an empty one shows a dim chest to come
            var p = app.profile;
            GDict busy = p.Unlocking();
            var gap = 8.0;
            var sw = (w - gap * 3.0) / 4.0;
            var sh = CHEST_H;
            var slots = new GArray();
            for (int i = 0; i < Eco.CHEST_SLOTS; i++)                           // the panels (under the chests)
            {
                var x = i * (sw + gap);
                var plate = new Control();
                plate.Position = new Vector2(x, y);
                plate.Size = new Vector2(sw, sh);
                plate.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                plate.SetMeta("chest_plate", i);                // (0.31.198: the Herald's tour shows the row)
                parent.AddChild(plate);
                if (i >= p.Chests().Size())
                {
                    UI2.Plate(plate, "glass", 12.0, "brown", GDict.Of("fill_top", new Color((Color)CHEST_FILL[0], 0.55), "fill_bottom", new Color((Color)CHEST_FILL[1], 0.7),
                        "outline_color", new Color(0.85, 0.62, 0.32, 0.5)));
                    continue;
                }
                GDict ch = p.Chests()[i].D;
                var k = GD.Str(ch["kind"]);
                bool ready = p.ChestReady(ch);
                if (ready)
                    UI2.Glow(plate, new Rect2(-14, -14, sw + 28, sh + 28), new Color(0.55, 1.0, 0.6, 0.5));
                UI2.Plate(plate, "night", 12.0, ready ? "green" : "brown", GDict.Of("fill_top", CHEST_FILL[0], "fill_bottom", CHEST_FILL[1]));
                slots.Append(GDict.Of("kind", k, "mode", ready ? "tease" : "idle", "x", x + sw * 0.5));
            }
            var row = new ChestRow();                           // the chests themselves, in 3D
            row.slots = slots;
            row.Position = new Vector2(0, y + 12.0);
            row.Size = new Vector2(w, 66.0);
            row.chest_px = GD.Minf(66.0, sw - 12.0);
            row.base_y = 0.9;
            parent.AddChild(row);
            int waiting = p.ChestsWaiting();
            if (waiting > 0)                                     // 0.31.108: reward chests waiting for a free slot (over the row)
            {
                var wc = UI2.Chip(parent, GD.Fmt("+%d WAITING", waiting), new Color(0.03, 0.02, 0.1, 0.92), UI2.GOLD, new Color(UI2.GOLD, 0.8));
                wc.Position = new Vector2(w - 108, y - 26);
                wc.SetMeta("action_key", "chests_waiting");
            }
            for (int i = 0; i < Eco.CHEST_SLOTS; i++)                           // and what's on each panel (over the chests)
            {
                var x = i * (sw + gap);
                var cell = new Control();
                cell.Position = new Vector2(x, y);
                cell.Size = new Vector2(sw, sh);
                cell.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                parent.AddChild(cell);
                if (i >= p.Chests().Size())
                {
                    var ghost = UI2.Img(cell, UI2.V2 + "chests/wood_icon.png", 48.0);
                    ghost.Position = new Vector2((sw - 48.0) * 0.5, 20.0);
                    ghost.Modulate = new Color(0.85, 0.75, 0.62, 0.45);           // (a dim silhouette of the chest to come)
                    ghost.SetMeta("empty_slot", true);
                    bool first_empty = i == p.Chests().Size();
                    var e = UI2.Text(cell, first_empty ? "WIN TO EARN" : "EMPTY", 11, first_empty ? new Color(1.0, 0.93, 0.8, 0.85) : new Color(0.9, 0.82, 0.7, 0.55), UI2.INK, 3);
                    e.HorizontalAlignment = HorizontalAlignment.Center;
                    e.Position = new Vector2(0, sh - 26);
                    e.Size = new Vector2(sw, 16);
                    e.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                    continue;
                }
                GDict ch = p.Chests()[i].D;
                var k = GD.Str(ch["kind"]);
                bool ready = p.ChestReady(ch);
                var idx = i;
                _ChestName(cell, k, sw, ready ? new Color("#c9ffb8") : UI2.CREAM);
                if (ready)
                {
                    var ob = UI2.Button(cell, "OPEN", "green", () => OpenChest(app, idx), GD.Fmt("chest_open_%d", i), 15, 28.0, 9.0);
                    ob.Position = new Vector2(6, sh - 33);
                    ob.Size = new Vector2(sw - 12, 28);
                    UI2.Sweep(ob, 2.2, 30.0, 0.6);
                }
                else if ((int)ch["start"] >= 0)
                {
                    _SlotTag(cell, UI.Duration(p.ChestLeft(ch)), UI2.GOLD);
                    var frac = 1.0 - (double)p.ChestLeft(ch) / (double)Eco.CHESTS[k]["unlock"];
                    var pb = UI2.Bar(cell, frac, 1.0, new Color("#fff1a6"), new Color("#f0a024"), 6.0);
                    pb.Position = new Vector2(8, sh - 40);
                    pb.Size = new Vector2(sw - 16, 6);
                    var sb = UI2.Button(cell, GD.Fmt("%d", Eco.SkipCost(p.ChestLeft(ch))), "purple", () => SkipChest(app, idx), GD.Fmt("chest_skip_%d", i), 14, 28.0, 9.0, "res://assets/ui/currency/gem.png");
                    sb.Position = new Vector2(6, sh - 33);
                    sb.Size = new Vector2(sw - 12, 28);
                }
                else if (busy.IsEmpty())
                {
                    _SlotTag(cell, UI.Duration(p.ChestLeft(ch)), Color.WHITE);
                    var ub = UI2.Button(cell, "UNLOCK", "blue", () =>
                    {
                        p.StartUnlock(idx);
                        app.Sfx("unlock");                  // 0.31.110: a key turns, ka-chunk
                        app.Rebuild();
                        if (true /* app.has_method("chest_started") */)
                            app.ChestStarted();
                    }, GD.Fmt("chest_unlock_%d", i), 13, 28.0, 9.0);
                    ub.Position = new Vector2(6, sh - 33);
                    ub.Size = new Vector2(sw - 12, 28);
                }
                else
                {
                    // waiting its turn: how long it'll take, under a dark QUEUED pill (B2's); tapping it opens it now for gems
                    var q = new PanelContainer();
                    var qs = new StyleBoxFlat();
                    qs.BgColor = new Color(0.0, 0.0, 0.0, 0.45);
                    qs.BorderColor = new Color(0.85, 0.62, 0.32, 0.45);
                    qs.SetBorderWidthAll(1);
                    qs.SetCornerRadiusAll(9);
                    q.AddThemeStyleboxOverride("panel", qs);
                    q.Position = new Vector2(6, sh - 33);
                    q.Size = new Vector2(sw - 12, 28);
                    q.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                    cell.AddChild(q);
                    var tr = new HBoxContainer();
                    tr.Alignment = BoxContainer.ALIGNMENT_CENTER;
                    tr.AddThemeConstantOverride("separation", 3);
                    tr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                    q.AddChild(tr);
                    UI2.Icon(tr, "hourglass", 18.0);
                    UI2.Text(tr, UI.Duration(p.ChestLeft(ch)), 14, Color.WHITE, new Color("#1a0d04"), 4);
                    _SlotTag(cell, "QUEUED", UI2.MUTED);
                    var skip = UI2.Button(cell, "", "ghost", () => SkipChest(app, idx), GD.Fmt("chest_skip_%d", i), 10, 20.0, 8.0);
                    skip.Position = new Vector2(4, 18);
                    skip.Size = new Vector2(sw - 8, sh - 22);
                    skip.Modulate = new Color(1, 1, 1, 0);            // (unseen: its skin too -- self_modulate left that over the chest)
                }
            }
        }

        public static void _ChestName(Control cell, string kind, double sw, Color col)
        {
            // the chest's name along the top of its panel ("SILVER CHEST"; just "SILVER" where the whole name won't fit)
            var n = GD.Str(Eco.CHESTS[kind]["name"]).ToUpperInvariant();
            if (UI2.LG.GetStringSize(n, HorizontalAlignment.Left, -1, 10).x > sw - 8.0)
                n = n.GetSlice(" ", 0);
            var l = UI2.Text(cell, n, 10, col, UI2.INK, 3);
            l.Name = "ChestName";
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.Position = new Vector2(0, 4);
            l.Size = new Vector2(sw, 14);
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
        }

        public static void _SlotTag(Control cell, string s, Color col)
        {
            // the time on a chest (or QUEUED), a chip over the chest's foot
            var c = UI2.Chip(cell, s, new Color(0.01, 0.02, 0.08, 0.85), col, new Color(col, 0.7));
            c.AnchorLeft = 0.5;
            c.AnchorRight = 0.5;
            c.GrowHorizontal = Control.GROW_DIRECTION_BOTH;
            c.OffsetLeft = -30;
            c.OffsetRight = 30;
            c.OffsetTop = 46;
            c.OffsetBottom = 62;
        }

        public static void SkipChest(SiegeApp app, int idx)
        {
            GDict r = app.profile.SkipChest(idx);
            if ((bool)r.Get("ok", false))
                OpenChest(app, idx);                   // (its sound: the chest's window opening)
            else
            {
                app.Sfx("error");
                app.Toast(GD.Fmt("Not enough gems (%d needed)", (int)r.Get("cost", 0)), UI.RED);
            }
        }

        public static void OpenChest(SiegeApp app, int idx)
        {
            // 0.31.79: the 3D opening (chest_open.gd); the roll happens when the chest is tapped open.
            GArray chs = app.profile.Chests();
            if (idx < 0 || idx >= chs.Size() || !app.profile.ChestReady(chs[idx].D))
                return;
            app.Sfx("menuOpen");
            app.CloseModal();
            var m = new ChestOpen();
            m.app = app;
            m.index = idx;
            m.kind = GD.Str(chs[idx]["kind"]);
            app.AddChild(m);
            app.modal = m;
        }

        public static void ChestOdds(SiegeApp app)
        {
            var lines = new GArray();
            foreach (var k in new[] { "wooden", "silver", "gold", "royal" })
                lines.Append(GD.Fmt("%s (%s): %s", GD.Str(Eco.CHESTS[k]["name"]), UI.Duration((int)Eco.CHESTS[k]["unlock"]), Eco.ChestOdds(k)));
            app.Toast(GStr.Join("\n", lines), UI.TEXT);
        }

        public static Control ChallengesCard(SiegeApp app, Node root, string span)
        {
            // 0.31.79: the orders on a parchment sheet
            var p = app.profile;
            GArray list = span == "daily" ? p.d["challenges"]["daily"].A : p.d["challenges"]["weekly"].A;
            var c = UI2.Frame(root, "parch", 12, 14.0, "brown");
            int now = p.Now();
            int reset = span == "daily" ? ((int)Math.Floor(now / 86400.0) + 1) * 86400 - now : 0;
            if (span == "weekly")
            {
                var days = (int)Math.Floor(now / 86400.0);
                var monday = days - ((days + 3) % 7);
                reset = (monday + 7) * 86400 - now;
            }
            var ink = new Color("#3b2412");
            var h = UI.Row(c, 8);
            UI2.Icon(h, span == "daily" ? "scroll" : "hourglass", 30.0);
            UI.Grow(UI2.Text(h, span == "daily" ? "DAILY ORDERS" : "WEEKLY ORDERS", 19, ink, ink, 0, false));
            var rl = UI.Label(h, "resets in " + UI.Duration(reset), 11, new Color("#7a5530"), UI.HEAVY_FONT);
            rl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            for (int i = 0; i < list.Size(); i++)
            {
                GDict ch = list[i].D;
                if (!Eco.CHALLENGES.Has(GD.Str(ch["id"])))
                    continue;                                   // (0.31.164: a retired Siege one, before the profile swapped it)
                GDict def = Eco.CHALLENGES[ch["id"]].D;
                var row = UI.Row(c, 10);
                var v = new VBoxContainer();
                v.AddThemeConstantOverride("separation", 3);
                UI.Grow(v);
                row.AddChild(v);
                UI.Label(v, GD.Str(def["text"]), 13, ink, UI.HEAVY_FONT);
                var reward = GD.Fmt("+%d pass XP", (int)def["pass"]);
                var order_gold = (int)def.Get("gold", 0) + (span == "daily" ? Eco.DAILY_GOLD : 0);     // (0.31.184: a daily's Embers are gold)
                if (order_gold > 0)
                    reward += GD.Fmt(" · +%d gold", order_gold);
                if (def.Has("gems"))
                    reward += GD.Fmt(" · +%d gems", (int)def["gems"]);
                var pr = UI.Row(v, 6);
                UI2.Bar(pr, (int)ch["progress"], (int)def["goal"], !(bool)ch["claimed"] ? new Color("#a8e4ff") : new Color("#b4f7a4"), !(bool)ch["claimed"] ? new Color("#2b8fd6") : new Color("#25a248"), 10.0);
                UI.Label(pr, GD.Fmt("%d/%d", GD.Mini((int)ch["progress"], (int)def["goal"]), (int)def["goal"]), 11, ink, UI.HEAVY_FONT).AutowrapMode = TextServer.AUTOWRAP_OFF;
                UI.Label(v, reward, 11, new Color("#8a5a0a"), UI.HEAVY_FONT);
                bool done = (int)ch["progress"] >= (int)def["goal"];
                var ii = i;
                if ((bool)ch["claimed"])
                    UI.Icon(row, "check", 28, new Color("#2f8a4f"));
                else if (done)
                {
                    var cb = UI2.Button(row, "CLAIM", "green", () =>
                    {
                        GDict r = p.ClaimChallenge(span, ii);
                        if (r["ok"])
                        {
                            app.Sfx("claim");
                            app.Toast("Order complete!" + (!r["tiers"].IsEmpty() ? GD.Fmt(" Pass tier %d reached", (int)r["tiers"][-1]) : ""), UI.GREEN);
                        }
                        app.Rebuild();
                    }, GD.Fmt("claim_%s_%d", span, i), 15, 38.0, 10.0);
                    var cm = cb.CustomMinimumSize;
                    cm.x = 84;
                    cb.CustomMinimumSize = cm;
                    UI2.Sweep(cb, 2.2, 30.0);
                }
                else if (span == "daily" && !(bool)p.d["challenges"]["rerolled"])
                {
                    var rb = UI2.Button(row, "↻", "blue", () =>
                    {
                        if (p.RerollDaily(ii))
                            app.Sfx("flip");
                        app.Rebuild();
                    }, GD.Fmt("reroll_%d", i), 18, 36.0, 10.0);
                    var rm = rb.CustomMinimumSize;
                    rm.x = 40;
                    rb.CustomMinimumSize = rm;
                    rb.AddThemeFontOverride("font", UI.HEAVY_FONT);
                }
            }
            return c.GetParent() as Control;
        }

        public static void PassCard(SiegeApp app, Node root)
        {
            // Home's Siege Pass summary: the tier medallion, the XP bar and CLAIM / VIEW.
            var p = app.profile;
            GDict d = p.d;
            var pc = UI2.Frame(root, "purple", 12, 18.0, "gold");
            int tier = p.PassTier();
            var r = UI.Row(pc, 12);
            var med = new Control();
            med.CustomMinimumSize = new Vector2(58, 66);
            r.AddChild(med);
            var mt = new TextureRect();
            mt.Texture = UI2.Tex(UI2.V2 + "shield_pass.svg");
            mt.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            mt.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            mt.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            med.AddChild(mt);
            var tn = UI2.Text(med, GD.Str(tier), 26, Color.WHITE, new Color("#1e0a45"), 6);
            tn.HorizontalAlignment = HorizontalAlignment.Center;
            tn.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tn.OffsetBottom = -8;
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 4);
            UI.Grow(v);
            r.AddChild(v);
            UI2.Text(v, "SIEGE PASS", 20, UI2.GOLD, UI2.INK, 5);
            int ends = Eco.SeasonEnds((int)d["pass"]["season"]) - p.Now();
            UI2.Body(v, GD.Fmt("%s  ·  %s left", Eco.SeasonName((int)d["pass"]["season"]), UI.Duration(ends)), 11, new Color("#e6d6ff"), false);
            int in_tier = (int)d["pass"]["xp"] - tier * Eco.TIER_XP;
            UI2.Bar(v, tier < Eco.PASS_TIERS ? in_tier : 1, tier < Eco.PASS_TIERS ? Eco.TIER_XP : 1, new Color("#fff3a8"), new Color("#e08a12"), 12.0);
            var claimable = 0;
            for (int t = 1; t < tier + 1; t++)
            {
                foreach (var prem in new[] { false, true })
                {
                    if (p.CanClaim(t, prem))
                        claimable += 1;
                }
            }
            var b = UI2.Button(pc, claimable > 0 ? GD.Fmt("CLAIM %d REWARD%s", claimable, claimable == 1 ? "" : "S") : "VIEW PASS", claimable > 0 ? "green" : "blue", () => app.ShowTab("pass"), "go_pass", 18, 46.0);
            if (claimable > 0)
                UI2.Sweep(b);
        }

        // ---------------- PASS ----------------
        public const double BANNER_MAX = 124.0;      // 0.31.216: landscape -- a banner no taller than this (210 and so in portrait)

        public static Control Banner(Node root, string art, string title, double h = 210.0, Color? title_color = null)
        {
            title_color ??= UI2.GOLD;
            // 0.31.79: a gold-framed painted banner at the top of a tab, its title over the bottom of the art.
            h = GD.Minf(h, BANNER_MAX);
            var c = new Control();
            c.CustomMinimumSize = new Vector2(0, h);
            c.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            root.AddChild(c);
            var clip = new Control();
            clip.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            clip.ClipContents = true;
            clip.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(clip);
            var t = new TextureRect();
            t.Texture = UI2.Tex(art);
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            t.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            clip.AddChild(t);
            var shade = new TextureRect();
            var g = new Gradient();
            g.SetColor(0, new Color(0.03, 0.02, 0.1, 0.0));
            g.SetColor(1, new Color(0.03, 0.02, 0.1, 0.85));
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.FillFrom = new Vector2(0.5, 0.35);
            gt.FillTo = new Vector2(0.5, 1.0);
            gt.Width = 4;
            gt.Height = 64;
            shade.Texture = gt;
            shade.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            shade.StretchMode = TextureRect.STRETCH_SCALE;
            shade.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            shade.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            clip.AddChild(shade);
            // the frame: rim and outline only, over the art
            UI2.Plate(c, "royal", 20.0, "gold", GDict.Of("fill_top", new Color(0, 0, 0, 0), "fill_bottom", new Color(0, 0, 0, 0), "pattern_mix", 0.0, "rim", 4.0, "bevel", 0.0));
            (c.GetChild(0) as Node2D).ShowBehindParent = false;
            c.MoveChild(c.GetChild(0), c.GetChildCount() - 1);
            clip.OffsetLeft = 4;
            clip.OffsetTop = 4;
            clip.OffsetRight = -4;
            clip.OffsetBottom = -4;
            var tl = UI2.Text(c, title, 36, title_color, UI2.INK, 9);
            tl.HorizontalAlignment = HorizontalAlignment.Center;
            tl.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            tl.OffsetTop = -80;                           // (0.31.216: higher on the shorter banner: a ribbon fits under it)
            tl.OffsetBottom = -36;
            for (int i = 0; i < 3; i++)
            {
                var sx = GD.RandfRange(20, 360);
                var sy = GD.RandfRange(14, GD.Maxf(16.0, h - 90));
                var sp = UI2.Glow(c, new Rect2(sx, sy, 12, 12), new Color(1, 0.95, 0.8, 0.9));
                sp.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            return c;
        }

        public static void PassScreen(SiegeApp app, VBoxContainer root)
        {
            // 0.31.42 (Kevin): a richer Siege Pass; 0.31.79: the painted banner, the tier medallion in a sunburst, the premium
            // offer, then the track -- free on the left, premium on the right, a gold spine. (0.31.79-0.31.187: the season's best
            // weapon turning in 3D under the offer -- 0.31.188 the pass gives no cosmetics: outfits are bought.)
            var p = app.profile;
            GDict d = p.d;
            int sid = (int)d["pass"]["season"];
            int tier = p.PassTier();

            // --- banner
            var ban = Banner(root, UI2.V2 + "art_pass.webp", "SIEGE PASS", 214.0);
            var rib = UI2.Ribbon(ban, GD.Fmt("SEASON %d  ·  %s", sid, GD.Str(Eco.SeasonName(sid)).ToUpperInvariant()), "", 300.0, 30.0, GArray.Of(new Color("#b37bff"), new Color("#4a1a96")));
            rib.SetAnchorsPreset(Control.PRESET_CENTER_BOTTOM);
            ban.Resized += () => rib.Position = new Vector2((ban.Size.x - 300.0) * 0.5, ban.Size.y - 34.0);
            var ends = UI2.IconChip(ban, UI2.IconPath("hourglass"), GD.Fmt("ENDS IN %s", UI.Duration(Eco.SeasonEnds(sid) - p.Now()).ToUpperInvariant()), new Color(0.03, 0.02, 0.1, 0.82), UI2.GOLD, new Color(UI2.GOLD, 0.7));
            ends.Position = new Vector2(12, 12);

            // --- tier card
            var tc = UI2.Frame(root, "royal", 12, 18.0, "gold");
            var tr = UI.Row(tc, 12);
            var med = new Control();
            med.CustomMinimumSize = new Vector2(72, 82);
            tr.AddChild(med);
            var mr = UI2.Rays(med, 150.0, new Color(1, 0.86, 0.45), 16.0, 0.6);
            mr.Position = new Vector2(-39, -34);
            var mt = new TextureRect();
            mt.Texture = UI2.Tex(UI2.V2 + "shield_pass.svg");
            mt.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            mt.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            mt.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            mt.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            med.AddChild(mt);
            var tn = UI2.Text(med, GD.Str(tier), 32, Color.WHITE, new Color("#1e0a45"), 7);
            tn.HorizontalAlignment = HorizontalAlignment.Center;
            tn.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tn.OffsetBottom = -10;
            var xv = new VBoxContainer();
            xv.AddThemeConstantOverride("separation", 5);
            xv.Alignment = BoxContainer.ALIGNMENT_CENTER;
            UI.Grow(xv);
            tr.AddChild(xv);
            var hr = UI.Row(xv, 6);
            UI.Grow(UI2.Text(hr, GD.Fmt("TIER %d", tier), 24, Color.WHITE));
            if (tier < Eco.PASS_TIERS)
            {
                UI2.Body(hr, GD.Fmt("NEXT: TIER %d", tier + 1), 11, UI2.SOFT, false);
                int xp_in = (int)d["pass"]["xp"] - tier * Eco.TIER_XP;
                var bh = UI2.Bar(xv, xp_in, Eco.TIER_XP, new Color("#fff3a8"), new Color("#e08a12"), 18.0);
                var xl = UI2.Body(bh, GD.Fmt("%d / %d XP", xp_in, Eco.TIER_XP), 11, Color.WHITE, false);
                xl.HorizontalAlignment = HorizontalAlignment.Center;
                xl.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                xl.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.8));
                xl.AddThemeConstantOverride("outline_size", 3);
            }
            else
                UI2.Text(xv, "PASS COMPLETE", 18, UI2.GOLD);
            UI2.Body(xv, "Earn pass XP from every match and order", 11, UI2.MUTED);

            // --- tier skip (0.31.107)
            GDict so = p.SkipOffer();
            if ((int)so["tiers"] > 0)
            {
                var kc = UI2.Frame(root, "night", 10, 16.0, "gold");
                var kr = UI.Row(kc, 10);
                var ki = UI2.Img(kr, "res://assets/ui/v2/shield_pass.svg", 46.0);
                var kn = UI2.Text(ki, GD.Fmt("+%d", (int)so["tiers"]), 16, Color.WHITE, new Color("#1e0a45"), 5);
                kn.HorizontalAlignment = HorizontalAlignment.Center;
                kn.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                kn.OffsetTop = 9;
                UI2.Wiggle(ki, 4.0);
                var kv = new VBoxContainer();
                kv.AddThemeConstantOverride("separation", 1);
                UI.Grow(kv);
                kr.AddChild(kv);
                UI2.Text(kv, GD.Fmt("SKIP %d TIER%s", (int)so["tiers"], (int)so["tiers"] == 1 ? "" : "S"), 18, UI2.GOLD);
                UI2.Body(kv, GD.Fmt("Jump to tier %d  ·  claim every reward on the way", tier + (int)so["tiers"]), 11, new Color("#dfe6ff"));
                var kb = UI2.Button(kr, GD.Str((int)so["gems"]), "purple", () => _SkipTiers(app), "skip_tiers", 17, 44.0, 12.0, "res://assets/ui/currency/gem.png");
                var km = kb.CustomMinimumSize;
                km.x = 112;
                kb.CustomMinimumSize = km;
                kb.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                kb.Disabled = (int)d["gems"] < (int)so["gems"];
            }

            // --- premium
            if ((bool)d["pass"]["premium"])
            {
                var pa = UI2.Frame(root, "purple", 10, 16.0, "gold");
                var pr = UI.Row(pa, 10);
                UI2.Icon(pr, "crown", 40.0);
                UI.Grow(UI2.Body(pr, GD.Fmt("PREMIUM ACTIVE -- all %d premium rewards are yours to claim", Eco.PASS_TIERS), 13, new Color("#f3e6ff")));
            }
            else
            {
                var pc = UI2.Frame(root, "purple", 12, 18.0, "purple");
                var ph = UI.Row(pc, 10);
                var cr = UI2.Icon(ph, "crown", 52.0);
                UI2.Wiggle(cr, 3.2);
                var pt = new VBoxContainer();
                pt.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                ph.AddChild(pt);
                UI2.Text(pt, "UNLOCK PREMIUM", 20, UI2.GOLD);
                UI2.Body(pt, PremiumSummary(sid), 12, new Color("#efe2ff"));
                var b = UI2.Button(pc, GD.Fmt("UNLOCK  %d", Eco.PREMIUM_COST), "purple", () => _BuyPremium(app), "buy_premium", 20, 52.0, 16.0, "res://assets/ui/currency/gem.png");
                b.Disabled = (int)d["gems"] < Eco.PREMIUM_COST;
                UI2.Sweep(b);
                UI2.Center(UI2.Body(pc, GD.Fmt("You have %d gems", (int)d["gems"]), 11, new Color("#d8c6ff")));
            }

            // --- claim all
            var claimable = 0;
            for (int t = 1; t < tier + 1; t++)
            {
                foreach (var prem in new[] { false, true })
                {
                    if (p.CanClaim(t, prem))
                        claimable += 1;
                }
            }
            if (claimable > 0)
            {
                var ca = UI2.Button(root, GD.Fmt("CLAIM ALL  (%d)", claimable), "green", () =>
                {
                    GArray got = p.ClaimAll();
                    app.Sfx("claim");
                    app.Toast(GD.Fmt("Claimed %d reward%s", got.Size(), got.Size() == 1 ? "" : "s"), UI.GREEN);
                    app.Rebuild();
                }, "claim_all", 24, 58.0, 18.0);
                UI2.Sweep(ca);
                UI2.Pulse(ca, 0.02);
            }

            // --- the track
            var head = UI.Row(root, 0);
            foreach (var side in new[] { false, true })
            {
                if (side)
                {
                    var gap = new Control();
                    gap.CustomMinimumSize = new Vector2(50, 0);
                    head.AddChild(gap);
                }
                var hp = new PanelContainer();
                var hs = new StyleBoxEmpty();
                hs.ContentMarginTop = 5;
                hs.ContentMarginBottom = 3;
                hp.AddThemeStyleboxOverride("panel", hs);
                hp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                head.AddChild(hp);
                UI2.Skin(hp, UI2.ButtonParams(side ? "purple" : "blue", 12.0, 4.0));
                var hl = UI2.Text(hp, side ? "PREMIUM" : "FREE", 16, Color.WHITE, side ? new Color("#1e0a45") : new Color("#0a1238"), 4);
                hl.HorizontalAlignment = HorizontalAlignment.Center;
            }
            for (int t = 1; t < Eco.PASS_TIERS + 1; t++)
            {
                var row = new HBoxContainer();
                row.AddThemeConstantOverride("separation", 6);
                root.AddChild(row);
                PassCell(app, row, sid, t, false);
                _Spine(row, t, tier);
                PassCell(app, row, sid, t, true);
            }
        }

        public static string PremiumSummary(int sid)
        {
            // what the premium track holds, counted from the season's rewards: "A Hero Token (any hero) · 3 hero shards · ..."
            var n = GDict.Of("token", 0, "shard", 0, "royal", 0, "gold", 0, "gems", 0);
            for (int t = 1; t < Eco.PASS_TIERS + 1; t++)
            {
                var r = Eco.PassReward(sid, t, true);
                n["token"] += (int)r.Get("token", 0);
                n["shard"] += r.Has("shard") ? 1 : 0;
                n["gems"] += (int)r.Get("gems", 0);
                if (r.Has("chest"))
                {
                    var key = GArray.Of("royal", "gold").Has(GD.Str(r["chest"])) ? GD.Str(r["chest"]) : "gold";
                    n[key] += 1;
                }
            }
            var bits = new GArray();
            if ((int)n["token"] > 0)
                bits.Append("A Hero Token (any hero)");
            if ((int)n["shard"] > 0)
                bits.Append(GD.Fmt("%d hero shards", (int)n["shard"]));
            bits.Append(GD.Fmt("%d Royal and %d Gold chests", (int)n["royal"], (int)n["gold"]));
            if ((int)n["gems"] > 0)
                bits.Append(GD.Fmt("%s gems", UI.Grouped((int)n["gems"])));
            bits.Append("more gold on every tier");
            return GStr.Join(" · ", bits);
        }

        public static readonly Color PASS_GOLD = new Color("#ffcf5a");
        public static readonly Color PASS_PURPLE = new Color("#b77cff");

        public static PanelContainer _Panel(Node parent, Color fill, Color edge, int radius, Color glow, int pad)
        {
            var pc = new PanelContainer();
            var sb = new StyleBoxFlat();
            sb.BgColor = fill;
            sb.BorderColor = edge;
            sb.SetBorderWidthAll(2);
            sb.SetCornerRadiusAll(radius);
            sb.ShadowColor = glow;
            sb.ShadowSize = 10;
            foreach (var side in new[] { "left", "right", "top", "bottom" })
                PropertyPath.Set(sb, "content_margin_" + side, (double)pad);
            pc.AddThemeStyleboxOverride("panel", sb);
            parent.AddChild(pc);
            return pc;
        }

        public static PanelContainer _Chip(Node parent, string text, Color fill, Color ink)
        {
            var pc = new PanelContainer();
            var sb = new StyleBoxFlat();
            sb.BgColor = fill;
            sb.SetCornerRadiusAll(10);
            sb.ContentMarginLeft = 8;
            sb.ContentMarginRight = 8;
            sb.ContentMarginTop = 2;
            sb.ContentMarginBottom = 2;
            pc.AddThemeStyleboxOverride("panel", sb);
            pc.SizeFlagsHorizontal = Control.SIZE_SHRINK_BEGIN;
            pc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(pc);
            var l = UI.Label(pc, text, 10, ink, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            return pc;
        }

        public static void _Spine(Node row, int t, int tier)
        {
            // the centre column: a gold line through the reached tiers, the tier number in a medal
            var col = new Control();
            col.CustomMinimumSize = new Vector2(44, 0);
            row.AddChild(col);
            var reached = t <= tier;
            var line_top = new ColorRect();
            var line_bot = new ColorRect();
            foreach (var ln in new[] { line_top, line_bot })
            {
                ln.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                col.AddChild(ln);
            }
            line_top.Color = reached ? PASS_GOLD : new Color(1, 1, 1, 0.1);
            line_bot.Color = t < tier ? PASS_GOLD : new Color(1, 1, 1, 0.1);
            var m = new Control();
            m.Size = t != tier ? new Vector2(40, 40) : new Vector2(46, 46);
            m.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            col.AddChild(m);
            if (reached)
                UI2.Plate(m, "royal", 23.0, "gold", GDict.Of("fill_top", new Color("#fff2b0"), "fill_bottom", new Color("#d98516"), "pattern_mix", 0.0, "rim", 0.0, "outline", 2.5,
                    "glow", t == tier ? 8.0 : 0.0, "glow_color", new Color(1.0, 0.84, 0.35, 0.8), "shadow_y", 3.0));
            else
                UI2.Plate(m, "night", 20.0, "gold", GDict.Of("rim", 0.0, "outline", 2.0, "outline_color", new Color(1, 0.84, 0.35, 0.35), "shadow_y", 3.0));
            var l = UI2.Text(m, GD.Str(t), t != tier ? 17 : 20, reached ? new Color("#3a1c02") : new Color("#c8bfe8"), reached ? new Color("#fff1b8") : new Color("#0b0620"), reached ? 0 : 3, false);
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            l.OffsetTop = 2;
            col.Resized += () =>
            {
                var cx = col.Size.x * 0.5;
                line_top.Position = new Vector2(cx - 3, 0);
                line_top.Size = new Vector2(6, col.Size.y * 0.5);
                line_bot.Position = new Vector2(cx - 3, col.Size.y * 0.5);
                line_bot.Size = new Vector2(6, col.Size.y * 0.5 + 8);
                m.Position = new Vector2(cx, col.Size.y * 0.5) - m.Size * 0.5;
            };
            if (t == tier && GD.IsInstanceValid(m))
                UI2.Pulse(m, 0.08, 0.8);
        }

        public static void PassCell(SiegeApp app, Node parent, int sid, int t, bool prem)
        {
            var p = app.profile;
            GDict r = p.PassRewardFor(t, prem);          // (a shard: the hero it is for this player)
            GArray rt = RewardText(r);
            bool claimed = (prem ? p.d["pass"]["prem"] : p.d["pass"]["free"]).Has(t);
            bool ready = p.CanClaim(t, prem);
            bool locked_prem = prem && !(bool)p.d["pass"]["premium"];
            bool locked = t > p.PassTier();
            var kind = prem ? "purple" : "royal";
            var rim = prem ? "purple" : "gold";
            if (ready)
            {
                kind = "green";
                rim = "green";
            }
            var cell = new Control();
            cell.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            cell.CustomMinimumSize = new Vector2(0, ready ? 116 : 104);
            parent.AddChild(cell);
            if (ready)
            {
                var g = UI2.Glow(cell, new Rect2(-16, -16, 10, 10), new Color(0.55, 1.0, 0.6, 0.5));
                cell.Resized += () => g.Size = cell.Size + new Vector2(32, 32);
            }
            UI2.Plate(cell, kind, 16.0, rim, GDict.Of("dim", (claimed || locked_prem) ? 0.45 : 0.0));
            if (r.Has("chest") && GD.Str(r["chest"]) == "royal" && !claimed)
            {
                var rays = UI2.Rays(cell, 150.0, new Color(0.85, 0.6, 1.0), 20.0, 0.35);       // (a Royal chest stands out)
                cell.Resized += () => rays.Position = new Vector2(cell.Size.x * 0.5 - 75.0, 4.0);
                cell.ClipContents = false;
            }
            var v = new VBoxContainer();
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.OffsetTop = 6;
            v.OffsetBottom = ready ? -30 : -6;
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.AddThemeConstantOverride("separation", 1);
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            cell.AddChild(v);
            var ic = new CenterContainer();
            ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            v.AddChild(ic);
            if (r.Has("chest"))
            {
                var ci = UI2.Img(ic, ChestIcon(GD.Str(r["chest"])), 58.0);
                if (ready)
                    UI2.Bob(ci, 3.0, 0.9);
            }
            else if (GD.Str(rt[3]) != "")
            {
                var ti = UI2.Img(ic, GD.Str(rt[3]), 54.0);
                if (ready)
                    UI2.Bob(ti, 3.0, 0.9);
            }
            else
                UI.Icon(ic, GD.Str(rt[0]), 34, (Color)rt[2]);
            var nm = UI2.Text(v, GD.Str(rt[1]).ToUpperInvariant(), 13, Color.WHITE, UI2.INK, 4, false);
            nm.HorizontalAlignment = HorizontalAlignment.Center;
            nm.ClipText = true;
            nm.TextOverrunBehavior = TextServer.OVERRUN_TRIM_ELLIPSIS;
            if (claimed || locked || locked_prem)
            {
                var badge = new Control();
                badge.Size = new Vector2(28, 28);
                badge.Position = new Vector2(-4, -4);
                badge.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                cell.AddChild(badge);
                if (claimed)
                {
                    UI2.Plate(badge, "green", 14.0, "green", GDict.Of("rim", 0.0, "fill_top", new Color("#8ff09a"), "fill_bottom", new Color("#27a248"), "pattern_mix", 0.0));
                    var ck = UI.Icon(badge, "check", 18, Color.WHITE);
                    ck.Position = new Vector2(5, 5);
                }
                else
                {
                    UI2.Plate(badge, "night", 14.0, "gold", GDict.Of("rim", 0.0, "outline", 2.0, "outline_color", locked_prem ? PASS_PURPLE : new Color(1, 1, 1, 0.3)));
                    var lk = UI.Icon(badge, "lock", 16, locked_prem ? PASS_PURPLE : UI.MUTED);
                    lk.Position = new Vector2(6, 5);
                }
            }
            var tap = new Button();
            tap.Flat = true;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                tap.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            tap.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tap.Pressed += () => OpenPassItem(app, sid, t, prem);
            cell.AddChild(tap);
            if (ready)
            {
                var gb = UI2.Button(cell, "CLAIM", "green", () => _ClaimTier(app, t, prem), GD.Fmt("claim_%s_%d", prem ? "prem" : "free", t), 14, 28.0, 9.0);
                gb.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
                gb.OffsetTop = -36;
                gb.OffsetBottom = -7;
                gb.OffsetLeft = 10;
                gb.OffsetRight = -10;
                UI2.Sweep(gb, 2.0, 30.0);
            }
        }

        public static void _ClaimTier(SiegeApp app, int t, bool prem)
        {
            GDict res = app.profile.ClaimTier(t, prem);
            if (res["ok"])
            {
                app.Sfx("claim");
                GArray got = RewardText(res["reward"].D);
                app.Toast("+ " + GD.Str(got[1]), UI.GREEN);
            }
            app.CloseModal();
            app.Rebuild();
        }

        public static void _SkipTiers(SiegeApp app)
        {
            var p = app.profile;
            GDict so = p.SkipOffer();
            int to = p.PassTier() + (int)so["tiers"];
            app.Confirm(GD.Fmt("SKIP %d TIERS?", (int)so["tiers"]), GD.Fmt("Jump straight to tier %d of the Siege Pass. Costs %d gems.", to, (int)so["gems"]), "SKIP", "premium", () =>
            {
                GDict r = p.SkipTiers();
                if (r["ok"])
                {
                    app.Sfx("tierUp");                  // 0.31.110: a bright rising chime
                    app.Toast(GD.Fmt("Tier %d reached! Claim your rewards", p.PassTier()), UI.GOLD);
                }
                else
                {
                    app.Sfx("error");
                    app.Toast(GD.Str(r["error"]), UI.RED);
                }
                app.Rebuild();
            });
        }

        public static void _BuyPremium(SiegeApp app)
        {
            var p = app.profile;
            var psid = (int)app.profile.d["pass"]["season"];
            app.Confirm("UNLOCK PREMIUM?", GD.Fmt("%s this season. Costs %d gems.", PremiumSummary(psid), Eco.PREMIUM_COST), "UNLOCK", "premium", () =>
            {
                GDict r = p.BuyPremium();
                if (r["ok"])
                {
                    app.Sfx("premium");                 // 0.31.110: a rich golden chord
                    app.Toast("Premium pass unlocked!", UI.PURPLE);
                }
                else
                {
                    app.Sfx("error");
                    app.Toast(GD.Str(r["error"]), UI.RED);
                }
                app.Rebuild();
            });
        }

        public static void OpenPassItem(SiegeApp app, int sid, int t, bool prem)
        {
            // the detail view: the reward big (0.31.42-0.31.187: a weapon in its class's hands, turning with your finger)
            var p = app.profile;
            GDict r = p.PassRewardFor(t, prem);
            GArray rt = RewardText(r);
            app.Sfx("menuOpen");
            app.CloseModal();
            var m = new Control();
            m.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            app.AddChild(m);
            app.modal = m;
            var dim = new ColorRect();
            dim.Color = new Color(0.02, 0.01, 0.05, 0.82);
            dim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            m.AddChild(dim);
            var margin = new MarginContainer();
            margin.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            foreach (var side in new[] { "left", "right" })
                margin.AddThemeConstantOverride("margin_" + side, 14);
            margin.AddThemeConstantOverride("margin_top", 60);
            margin.AddThemeConstantOverride("margin_bottom", 40);
            m.AddChild(margin);
            Color edge = prem ? PASS_PURPLE : PASS_GOLD;
            var sheet = _Panel(margin, new Color("#140d26"), edge, 22, new Color(edge.r, edge.g, edge.b, 0.45), 14);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 8);
            sheet.AddChild(v);
            var hr = UI.Row(v, 8);
            _Chip(hr, (prem ? "PREMIUM" : "FREE") + GD.Fmt("  ·  TIER %d", t), prem ? PASS_PURPLE : new Color("#2b3a55"), Color.WHITE);
            var sp = new Control();
            sp.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            hr.AddChild(sp);
            UI.Button(hr, "✕", "ghost", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, "pass_detail_close", 16, 12);
            var stage = new Control();
            stage.ClipContents = true;
            stage.CustomMinimumSize = new Vector2(0, 340);
            stage.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            v.AddChild(stage);
            Showcase.Backdrop(stage);
            var cc = new CenterContainer();
            cc.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            stage.AddChild(cc);
            var icc = new CenterContainer();
            cc.AddChild(icc);
            if (GD.Str(rt[3]) != "")
                UI.TexIcon(icc, GD.Str(rt[3]), 120);
            else
                UI.Icon(icc, GD.Str(rt[0]), 96, (Color)rt[2]);
            var nm = UI.Label(v, GD.Str(rt[1]), 24, Color.WHITE, UI.TITLE_FONT, true);
            nm.HorizontalAlignment = HorizontalAlignment.Center;
            if (r.Has("chest"))
            {
                var cd = UI.Label(v, Eco.ChestOdds(GD.Str(r["chest"])), 11, UI.MUTED);
                cd.HorizontalAlignment = HorizontalAlignment.Center;
                cd.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            }
            bool claimed = (prem ? p.d["pass"]["prem"] : p.d["pass"]["free"]).Has(t);
            if (claimed)
                UI.Button(v, "CLAIMED ✓", "secondary", () => { }, "pass_detail_claimed", 15).Disabled = true;
            else if (p.CanClaim(t, prem))
                UI.Button(v, "CLAIM", "claim", () => _ClaimTier(app, t, prem), "pass_detail_claim", 16);
            else if (prem && !(bool)p.d["pass"]["premium"])
            {
                UI.Button(v, GD.Fmt("UNLOCK PREMIUM  ·  %d GEMS", Eco.PREMIUM_COST), "premium", () =>
                {
                    app.CloseModal();
                    _BuyPremium(app);
                }, "pass_detail_premium", 15);
            }
            else
                UI.Button(v, GD.Fmt("REACH TIER %d TO UNLOCK", t), "secondary", () => { }, "pass_detail_locked", 14).Disabled = true;
        }

        // ---------------- SHOP ----------------
        public static void Shop(SiegeApp app, VBoxContainer root)
        {
            // 0.31.79: the market stall banner, the week's featured, the daily deals, the Arsenals and the gems. 0.31.188 (Kevin:
            // "I only want the cosmetics to be an entire outfit"): the outfits -- this week's three big (the hero in it, in his
            // own place), then every outfit by hero -- and the gems; tap an outfit to see it on him in his window.
            // 0.31.202 (Kevin: "Let's spruce up and beautify the shop menu"): gems twinkling over the banner; a bar that jumps to
            // FEATURED / OUTFITS / GEMS; the week's outfit with rays of its rarity behind him; the outfits by role (TANK ... SUPPORT,
            // a coin each that jumps to its row; each role's sets on top, its Frostbound line under) on new cards -- his own place
            // painted behind him (frosted for the Frostbound line), a glow of the rarity, OWNED / WORN; the starter pack shining.
            var p = app.profile;
            int now = p.Now();
            var ban = Banner(root, UI2.V2 + "art_shop.webp", "MARKET", 196.0);
            var note = UI2.Chip(ban, "EVERYTHING HERE IS COSMETIC", new Color(0.03, 0.02, 0.1, 0.8), UI2.CREAM, new Color(UI2.GOLD, 0.6));
            note.Position = new Vector2(12, 12);
            _Twinkles(ban, 9, new Color(0.75, 0.9, 1.0), new Rect2(0.12, 0.12, 0.8, 0.5));
            UI2.Sweep(ban, 5.0, 90.0, 0.28);
            // 0.31.204 (Kevin: "put a hero tab in the market that shows heroes that player doesn't own and that's where they will
            // purchase them"): the Market in three tabs -- OUTFITS (the weekly sale on top, then every outfit; a red SALE tag on
            // it), HEROES (market_heroes: the ones you don't own, to unlock) and GEMS (the packs). (0.31.202-0.31.203 a bar that
            // jumped down one long page: SALE / OUTFITS / GEMS.)
            if (!GArray.Of("outfits", "heroes", "gems").Has(GD.Str(app.shop_tab)))
                app.shop_tab = "outfits";
            var tabs = new HBoxContainer();
            tabs.AddThemeConstantOverride("separation", 8);
            root.AddChild(tabs);
            var locked = Champions.ORDER.Filter(h => !p.OwnsHero(GD.Str(h))).Size();
            foreach (var tb in GArray.Of(GArray.Of("outfits", "OUTFITS", UI2.IconPath("helmet")), GArray.Of("heroes", "HEROES", UI2.IconPath("crown")),
                    GArray.Of("gems", "GEMS", "res://assets/ui/currency/gem.png")))
            {
                string tid = GD.Str(tb[0]);
                bool on = GD.Str(app.shop_tab) == tid;
                var b = UI2.Button(tabs, GD.Str(tb[1]), on ? "gold" : "blue", () =>
                {
                    if (GD.Str(app.shop_tab) == tid)
                        return;
                    app.Sfx("tab");
                    app.shop_tab = tid;
                    app.content_scroll.ScrollVertical = 0;
                    app.Rebuild();
                }, "shop_tab_" + tid, 14, 40.0, 12.0, GD.Str(tb[2]));
                b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                var tag = "";
                if (tid == "outfits" && !Eco.FeaturedOutfits(now).IsEmpty())
                    tag = "SALE";
                else if (tid == "heroes" && locked > 0)
                    tag = GD.Str(locked);
                if (tag != "")
                {
                    var tc = _CardTag(b, tag, new Color("#d6372b"), new Color("#3a0805"));
                    tc.AnchorLeft = 1.0;
                    tc.AnchorRight = 1.0;
                    tc.GrowHorizontal = Control.GROW_DIRECTION_BEGIN;
                    tc.OffsetRight = 4;
                    tc.OffsetLeft = -30;
                    tc.OffsetTop = -7;
                    tc.OffsetBottom = 9;
                }
            }
            switch (GD.Str(app.shop_tab))
            {
                case "heroes":
                    MarketHeroes(app, root);
                    break;
                case "gems":
                {
                    GemPacks(app, root);
                    // (0.31.106-0.31.184 "GEMS -> GOLD": five gold packs for gems. 0.31.185, Kevin: "I want the same IAP system as
                    // league of legends" -- League never turns its paid currency into the earned one: gold is earned only, gems buy
                    // heroes outright)
                    var fn = UI2.IconChip(root, "res://assets/ui/v2/chests/gold_icon.png", "CHESTS ARE EARNED BY PLAYING  ·  NEVER SOLD",
                        new Color(0.05, 0.04, 0.16, 0.7), new Color("#e8d6b0"), new Color(UI2.GOLD, 0.35));
                    fn.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
                    break;
                }
                default:
                {
                    GArray feat = Eco.FeaturedOutfits(now);
                    if (!feat.IsEmpty())
                    {
                        _SaleHeader(app, root, feat, now);
                        var sel = GD.Clampi((int)Var.Of(app.GetMeta("shop_feat", 0)), 0, feat.Size() - 1);
                        FeaturedOutfit(app, root, GD.Str(feat[sel]));
                        var thumbs = new HBoxContainer();
                        thumbs.Alignment = BoxContainer.ALIGNMENT_CENTER;
                        thumbs.AddThemeConstantOverride("separation", 24);      // (0.31.203: room for their sale badges)
                        root.AddChild(thumbs);
                        for (int i = 0; i < feat.Size(); i++)
                            _FeatThumb(app, thumbs, GD.Str(feat[i]), i, i == sel);
                    }
                    UI2.Divider(root, "OUTFITS", 22, "a whole new look and weapon  ·  his hero comes with it");      // 0.31.186 (0.31.188: whole outfits)
                    SkinGrid(app, root);
                    break;
                }
            }
        }

        public static Control _SaleHeader(SiegeApp app, Node root, GArray feat, int now)
        {
            // 0.31.203 (Kevin: "make the graphic of the features look very eye catching"): WEEKLY SALE on a red silk ribbon with
            // gold trim (ElevenLabs art), a shine running along it, stars winking round it; under it the time left, ticking, and
            // how deep the sale goes
            var low = ViewLow(app);
            var hold = new Control();
            hold.CustomMinimumSize = new Vector2(0, 92);
            hold.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            root.AddChild(hold);
            var rb = new TextureRect();
            rb.Texture = UI2.Tex(SALE + "sale_ribbon.webp");
            rb.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            rb.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            rb.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rb.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;          // (the shine stays on the silk)
            rb.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            hold.AddChild(rb);
            var tl = UI2.Text(rb, "WEEKLY SALE", 30, new Color("#fff4cf"), new Color("#4a0306"), 7);
            tl.HorizontalAlignment = HorizontalAlignment.Center;
            tl.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tl.OffsetBottom = -12;
            if (!low)
            {
                UI2.Sweep(rb, 2.4, 70.0, 0.55);
                _Twinkles(hold, 6, new Color(1.0, 0.86, 0.45), new Rect2(0.04, 0.02, 0.92, 0.9), 20.0);
                UI2.Pulse(rb, 0.025, 0.9);
            }
            var row = new HBoxContainer();
            row.Alignment = BoxContainer.ALIGNMENT_CENTER;
            row.AddThemeConstantOverride("separation", 8);
            row.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            root.AddChild(row);
            var end = Eco.WeekStart(now) + 7 * 86400;
            var tc = UI2.IconChip(row, UI2.IconPath("hourglass"), "ENDS IN " + _SaleClock(end - now), new Color("#7a0c12"), new Color("#ffe3c4"),
                new Color("#ffcf6a", 0.7));
            Label tlbl = tc.GetChild(0).GetChild(1) as Label;
            var tm = new Timer();                                 // (it ticks)
            tm.WaitTime = 1.0;
            tm.Autostart = true;
            tm.Timeout += () =>
            {
                if (GD.IsInstanceValid(tlbl))
                    tlbl.Text = "ENDS IN " + _SaleClock(end - (int)app.profile.Now());
            };
            tc.AddChild(tm);
            var most = 0;
            foreach (var id in feat)
                most = GD.Maxi(most, Eco.SaleOff(GD.Str(id), now));
            UI2.Chip(row, GD.Fmt("UP TO %d%% OFF", most), new Color("#ffcf4a"), new Color("#3a1402"), new Color("#fff1b0"));
            return hold;
        }

        public static string _SaleClock(int left)
        {
            // the sale's time left: 2D 04:13:52, or 04:13:52 on its last day
            left = GD.Maxi(0, left);
            var hms = GD.Fmt("%02d:%02d:%02d", (left / 3600) % 24, (left / 60) % 60, left % 60);
            return left >= 86400 ? GD.Fmt("%dD %s", left / 86400, hms) : hms;
        }

        public static Control _SaleBadge(Control parent, int off, double px, bool still = false)
        {
            // 0.31.203: the weekly sale's red-and-gold starburst (ElevenLabs art) with its discount on it, tilted; it beats
            var b = new Control();
            b.Size = new Vector2(px, px);
            b.PivotOffset = b.Size * 0.5;
            b.Rotation = GD.DegToRad(-12.0);
            b.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(b);
            if (px >= 80.0)
                UI2.Glow(b, new Rect2(-px * 0.3, -px * 0.3, px * 1.6, px * 1.6), new Color(1.0, 0.72, 0.2, 0.75));
            var t = new TextureRect();
            t.Texture = UI2.Tex(SALE + "sale_badge.webp");
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            t.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(t);
            var v = new VBoxContainer();
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            v.Alignment = BoxContainer.ALIGNMENT_CENTER;
            v.AddThemeConstantOverride("separation", -(int)(px * 0.07));
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(v);
            var big = UI2.Text(v, GD.Fmt("-%d%%", off), GD.Maxi(9, (int)(px * 0.27)), Color.WHITE, new Color("#4a0306"), GD.Maxi(3, (int)(px * 0.05)), px >= 60.0);
            big.HorizontalAlignment = HorizontalAlignment.Center;
            if (px >= 60.0)
            {
                var ol = UI2.Text(v, "OFF", (int)(px * 0.14), new Color("#ffe9a8"), new Color("#4a0306"), 3, false);
                ol.HorizontalAlignment = HorizontalAlignment.Center;
            }
            if (!still)
            {
                UI2.WhenReady(b, () =>
                {
                    var tw = b.CreateTween().SetLoops();
                    tw.TweenProperty(b, "scale", Vector2.ONE * 1.12, 0.12).SetTrans(Tween.TRANS_SINE);
                    tw.TweenProperty(b, "scale", Vector2.ONE, 0.16).SetTrans(Tween.TRANS_SINE);
                    tw.TweenProperty(b, "scale", Vector2.ONE * 1.06, 0.1).SetTrans(Tween.TRANS_SINE);
                    tw.TweenProperty(b, "scale", Vector2.ONE, 0.18).SetTrans(Tween.TRANS_SINE);
                    tw.TweenInterval(1.1);
                });
            }
            return b;
        }

        public static ImageTexture _confetti_tex;

        public static CPUParticles2D _Confetti(Control parent, int n = 28)
        {
            // 0.31.203: confetti drifting down over the sale's stage -- little gold, red, white and pale gold slips, turning
            if (_confetti_tex == null)
            {
                var im = Image.Create(2, 4, false, ImageFormat.RGBA8);
                im.Fill(Color.WHITE);
                _confetti_tex = ImageTexture.CreateFromImage(im);
            }
            var cp = new CPUParticles2D();
            cp.Texture = _confetti_tex;
            cp.Amount = n;
            cp.Lifetime = 5.0;
            cp.Preprocess = 5.0;
            cp.EmissionShape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE;
            cp.Direction = new Vector2(0, 1);
            cp.Spread = 25.0;
            cp.Gravity = new Vector2(0, 18);
            cp.InitialVelocityMin = 18.0;
            cp.InitialVelocityMax = 40.0;
            cp.AngleMin = 0.0;
            cp.AngleMax = 360.0;
            cp.AngularVelocityMin = -220.0;
            cp.AngularVelocityMax = 220.0;
            cp.ScaleAmountMin = 1.4;
            cp.ScaleAmountMax = 2.4;
            var g = new Gradient();
            g.InterpolationMode = Gradient.InterpolationModeEnum.Constant;
            g.SetOffsets(new[] { 0.0, 0.3, 0.55, 0.75 });
            g.SetColors(new[] { new Color("#ffd04a"), new Color("#ff4a3d"), new Color("#fff6dc"), new Color("#ffb21e") });
            cp.ColorInitialRamp = g;
            var fade = new Gradient();
            fade.SetOffsets(new[] { 0.0, 0.8, 1.0 });
            fade.SetColors(new[] { Color.WHITE, Color.WHITE, new Color(1, 1, 1, 0) });
            cp.ColorRamp = fade;
            parent.AddChild(cp);
            Action place = () =>
            {
                cp.Position = new Vector2(parent.Size.x * 0.5, -6.0);
                cp.EmissionRectExtents = new Vector2(parent.Size.x * 0.5, 4.0);
            };
            parent.Resized += place;
            UI2.WhenReady(cp, place);
            return cp;
        }

        public static Label _Struck(Node parent, string s, int size, Color color)
        {
            // a price no longer asked: greyed, a red line through it
            var l = UI.Label(parent, s, size, color, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.8));
            l.AddThemeConstantOverride("outline_size", 3);
            var line = new ColorRect();
            line.Color = new Color("#ff3b30");
            line.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            line.AnchorRight = 1.0;
            line.AnchorTop = 0.5;
            line.AnchorBottom = 0.5;
            line.OffsetLeft = -2.0;
            line.OffsetRight = 2.0;
            line.OffsetTop = -1.0;
            line.OffsetBottom = 1.5;
            line.Rotation = GD.DegToRad(-10.0);
            line.Resized += () => line.PivotOffset = line.Size * 0.5;
            l.AddChild(line);
            return l;
        }

        public static void _ScrollTo(SiegeApp app, Node node)
        {
            // glide the page so `node` sits at the top (the shop's jump bar and role coins)
            ScrollContainer sc = app.content_scroll;
            if (!GD.IsInstanceValid(sc) || node == null || !GD.IsInstanceValid(node))
                return;
            var to = GD.Maxi(0, sc.ScrollVertical + (int)((double)(node as Control).GlobalPosition.y - sc.GlobalPosition.y) - 8);
            var tw = sc.CreateTween();
            tw.TweenProperty(sc, "scroll_vertical", to, 0.45).SetTrans(Tween.TRANS_CUBIC).SetEase(Tween.EASE_OUT);
        }

        public static void _Twinkles(Control parent, int n, Color col, Rect2 area, double px = 22.0)
        {
            // little four-point stars winking on and off over a picture (area: fractions of the parent), each on its own beat
            for (int i = 0; i < n; i++)
            {
                var t = new TextureRect();
                t.Texture = UI2.Tex("res://assets/vfx/spell/sparkle.png");
                t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                double sz = px * GD.RandfRange(0.6, 1.2);
                t.Size = new Vector2(sz, sz);
                t.PivotOffset = t.Size * 0.5;
                t.Modulate = new Color(col, 0.0);
                t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                var mat = new CanvasItemMaterial();
                mat.BlendMode = CanvasBlendMode.Add;
                t.Material = mat;
                parent.AddChild(t);
                double fx = GD.RandfRange(area.position.x, area.position.x + area.size.x);
                double fy = GD.RandfRange(area.position.y, area.position.y + area.size.y);
                Action place = () => t.Position = new Vector2(parent.Size.x * fx, parent.Size.y * fy) - t.Size * 0.5;
                parent.Resized += place;
                UI2.WhenReady(t, () =>
                {
                    place();
                    var tw = t.CreateTween().SetLoops();
                    tw.TweenInterval(GD.RandfRange(0.2, 3.0));
                    tw.TweenProperty(t, "modulate:a", 1.0, 0.35).SetTrans(Tween.TRANS_SINE);
                    tw.Parallel().TweenProperty(t, "rotation", GD.DegToRad(45.0), 0.7);
                    tw.TweenProperty(t, "modulate:a", 0.0, 0.45).SetTrans(Tween.TRANS_SINE);
                    tw.TweenProperty(t, "rotation", 0.0, 0.01);
                    tw.TweenInterval(GD.RandfRange(1.5, 3.5));
                });
            }
        }

        public static void _FeatThumb(SiegeApp app, Node row, string id, int i, bool on)
        {
            // one of the week's three: him in it over his own place, a gold frame on the one showing
            GDict sk = Eco.SKINS[id].D;
            var hid = GD.Str(sk["hero"]);
            var rc = Color.FromCode(GD.Str(Eco.RARITY_COLOR.Get(GD.Str(sk["rarity"]), "#c47bff")));
            var tb = new Button();
            tb.Flat = true;
            tb.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                tb.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            tb.CustomMinimumSize = new Vector2(76, 76);
            tb.SetMeta("action_key", GD.Fmt("feat_%d", i));
            tb.Pressed += () =>
            {
                app.Sfx("tap");
                app.SetMeta("shop_feat", i);
                app.Rebuild();
            };
            row.AddChild(tb);
            var pane = new Panel();
            var sb = new StyleBoxFlat();
            sb.BgColor = Champions.Accent(hid).Darkened(0.75);
            sb.SetCornerRadiusAll(16);
            pane.AddThemeStyleboxOverride("panel", sb);
            pane.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            pane.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            pane.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tb.AddChild(pane);
            var art = new TextureRect();
            art.Texture = UI2.Tex(Champions.CardArt(hid));
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.Modulate = on ? new Color(1, 1, 1) : new Color(0.55, 0.55, 0.65);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            pane.AddChild(art);
            var ti = UI2.Img(pane, GD.Fmt("res://assets/ui/skins/%s.png", id), 70.0);
            ti.Position = new Vector2(3, 6);
            if (!on)
                ti.Modulate = new Color(0.75, 0.75, 0.82);
            var rim = new Panel();
            var rs = new StyleBoxFlat();
            rs.DrawCenter = false;
            rs.BorderColor = on ? UI2.GOLD : new Color(rc, 0.8);
            rs.SetBorderWidthAll(on ? 3 : 2);
            rs.SetCornerRadiusAll(16);
            if (on)
            {
                rs.ShadowColor = new Color(1.0, 0.82, 0.3, 0.6);
                rs.ShadowSize = 8;
            }
            rim.AddThemeStyleboxOverride("panel", rs);
            rim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            tb.AddChild(rim);
            var off = Eco.SaleOff(id, (int)app.profile.Now());        // 0.31.203: its discount on the corner
            if (off > 0)
            {
                var bd = _SaleBadge(tb, off, 42.0, true);
                bd.Position = new Vector2(46, -14);
            }
        }

        public static Control GemPacks(SiegeApp app, Node root)
        {
            // 0.31.90 (Kevin: in-app purchases): gems for real money, Google Play only. The starter pack first while it can still
            // be bought, then the five packs, priced in the player's currency once Google has answered. (0.31.202: returns its
            // heading -- the shop's GEMS jump)
            // (app.billing is billing.gd or billing_ios.gd -- one face: StoreBilling's IStoreBilling)
            var bl = app.billing as IStoreBilling;
            bool live = bl != null && bl.Active();
            // (0.31.130: the App Store on iOS; the same words otherwise)
            var head = UI2.Divider(root, "GEM PACKS", 22, GD.Fmt(live ? "%s  ·  gems never change damage" : "in the %s version", Platform.StoreShort()));
            var p = app.profile;
            if (!(bool)p.d["iap"]["starter"])
            {
                var sc = new Control();
                sc.CustomMinimumSize = new Vector2(0, 132);
                root.AddChild(sc);
                UI2.Plate(sc, "ember", 18.0, "orange");
                var ry = UI2.Rays(sc, 200.0, new Color(1.0, 0.8, 0.4), 26.0, 0.35);
                ry.Position = new Vector2(-40, -40);
                var gi = UI2.Img(sc, STARTER_ART, 110.0);           // (0.31.214: the pack's own picture, as on Home)
                gi.Position = new Vector2(4, 18);
                UI2.Bob(gi, 4.0, 1.4);                                       // (0.31.202: it floats, it shines, it says once)
                _Twinkles(sc, 5, new Color(0.8, 0.95, 1.0), new Rect2(0.04, 0.1, 0.24, 0.7), 18.0);
                UI2.Sweep(sc, 3.6, 80.0, 0.3);
                var once = UI2.Chip(sc, "ONE-TIME OFFER", new Color("#e8443a"), Color.WHITE, new Color("#3a0805"));
                once.AnchorLeft = 1.0;
                once.AnchorRight = 1.0;
                once.GrowHorizontal = Control.GROW_DIRECTION_BEGIN;
                once.OffsetRight = -10;
                once.OffsetLeft = -120;
                once.OffsetTop = -9;
                once.OffsetBottom = 9;
                var v = new VBoxContainer();
                v.AddThemeConstantOverride("separation", 2);
                v.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                v.OffsetLeft = 120;
                v.OffsetRight = -12;
                v.OffsetTop = 10;
                v.OffsetBottom = -52;
                v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                sc.AddChild(v);
                UI2.Text(v, "STARTER PACK", 20, UI2.GOLD, UI2.INK, 5);
                GDict sp = Net.IAP["starter_pack"].D;
                UI2.Body(v, GD.Fmt("%d gems  ·  %s gold  ·  a Hero Token (any hero)  ·  once per player", (int)sp["gems"], UI.Grouped((int)sp.Get("gold", 0))),
                    12, new Color("#ffe9c7"));            // (0.31.108-0.31.187: an epic weapon)
                var sb = _IapButton(app, sc, "starter_pack", Vector2.ZERO, Vector2.ZERO);
                sb.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
                sb.OffsetLeft = 120;
                sb.OffsetRight = -12;
                sb.OffsetTop = -48;
                sb.OffsetBottom = -10;
            }
            // 0.31.108: a "play_only" pack (gems_14000) shows once Google Play knows its price; then it is the best value
            var shown = new GArray();
            foreach (var pid in Net.IAP)
            {
                GDict pk0 = Net.IAP[pid].D;
                if ((bool)pk0.Get("once", false))
                    continue;
                if ((bool)pk0.Get("play_only", false) && !(app.billing != null && (app.billing as IStoreBilling).prices.Has(pid)))
                    continue;
                shown.Append(pid);
            }
            var grids = new List<GridContainer>();
            foreach (var cols in new[] { 3, GD.Maxi(2, shown.Size() - 3) })
            {
                var grid = new GridContainer();
                grid.Columns = cols;
                grid.AddThemeConstantOverride("h_separation", 8);
                grid.AddThemeConstantOverride("v_separation", 10);
                root.AddChild(grid);
                grids.Add(grid);
            }
            var size_ix = 0;
            foreach (var pid0 in shown)
            {
                string pid = GD.Str(pid0);
                GDict pk = Net.IAP[pid].D;
                GridContainer grid = grids[size_ix < 3 ? 0 : 1];
                var c = new Control();
                var big = size_ix >= 3;
                UI.Grow(c);
                grid.AddChild(c);
                UI2.Plate(c, big ? "purple" : "royal", 18.0, big ? "gold" : "blue");
                var art_px = PackArt(c, GD.Fmt("res://assets/ui/packs/gem_pack_%d.png", GD.Mini(size_ix + 1, 6)), GD.Mini(size_ix + 1, 5), big,
                    new Color(0.55, 0.85, 1.0));
                var gl = UI2.Text(c, UI.Compact((int)pk["gems"]), big ? 21 : 19, Color.WHITE, UI2.INK, 5);
                gl.HorizontalAlignment = HorizontalAlignment.Center;
                gl.SetAnchorsAndOffsetsPreset(Control.PRESET_TOP_WIDE);
                gl.OffsetTop = art_px + 8.0;
                gl.OffsetBottom = art_px + 32.0;
                var b = _IapButton(app, c, pid, Vector2.ZERO, Vector2.ZERO);
                b.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
                b.OffsetLeft = 6;
                b.OffsetRight = -6;
                b.OffsetTop = -40;
                b.OffsetBottom = -6;
                var tag = GD.Str(pk.Get("tag", ""));
                if (tag == "BEST VALUE" && pid != shown[shown.Size() - 1])
                    tag = "";                                    // (a bigger pack is the best value)
                if (tag == "BEST VALUE")
                    UI2.Sweep(c, 3.0, 70.0, 0.32);                          // (0.31.202: the best value shines)
                if (tag != "")
                {
                    var tg = UI2.Chip(c, tag, tag == "BEST VALUE" ? new Color("#e8443a") : new Color("#2f7de1"), Color.WHITE, new Color("#170a05"));
                    tg.AnchorLeft = 0.5;
                    tg.AnchorRight = 0.5;
                    tg.OffsetLeft = -46;
                    tg.OffsetRight = 46;
                    tg.OffsetTop = -10;
                    tg.OffsetBottom = 8;
                }
                size_ix += 1;
            }
            if (StoreBilling.CanRestore(bl as Node))
            {
                // 0.31.130: the App Store requires a way to get a bought-once item (the starter pack) back on a new phone
                // (only billing_ios.gd has restore() and `restoring`: can_restore says it's that one)
                var rb = UI2.Button(root, (bl as BillingIos).restoring ? "…" : "RESTORE PURCHASES", "grey", () =>
                {
                    app.Sfx("tap");
                    (bl as BillingIos).Restore();
                }, "iap_restore", 14, 38.0);
                rb.Disabled = (bl as BillingIos).restoring || GD.Str(bl.busy) != "";
            }
            return head;
        }

        public static double PackArt(Control c, string path, int tier, bool big, Color shine)
        {
            // 0.31.106 (Kevin: "Make new art for the higher tier packs so it shows more the higher the pack is. Add fun things
            // to art for higher packs"): each tier its own picture, bigger as it goes (a gem, a heap, a pouch, a chest, a royal
            // hoard with a crown and a baby dragon; a stack ... a barrel, a mine cart with a grinning mimic). The top two shine
            // (a soft glow); the top one also has turning rays and bobs. Sets the tile's height; returns the art's size.
            var px = !big ? 104.0 : 132.0;
            c.CustomMinimumSize = new Vector2(0, px + 84.0);
            if (tier >= 4)
            {
                var gw = UI2.Glow(c, new Rect2(0, 0, 10, 10), new Color(shine, tier == 5 ? 0.5 : 0.32));
                c.Resized += () =>
                {
                    gw.Size = new Vector2(px, px) * 1.25;
                    gw.Position = new Vector2(((double)c.Size.x - gw.Size.x) * 0.5, 6.0 + (px - gw.Size.y) * 0.5);
                };
            }
            if (tier >= 5)
            {
                var ry = UI2.Rays(c, px * 1.6, shine.Lerp(Color.WHITE, 0.4), 22.0, 0.42);
                c.Resized += () => ry.Position = new Vector2(((double)c.Size.x - ry.Size.x) * 0.5, 6.0 + (px - ry.Size.y) * 0.5);
            }
            var gi = UI2.Img(c, path, px);
            c.Resized += () => gi.Position = new Vector2((c.Size.x - px) * 0.5, 6.0);
            if (tier >= 5)
            {
                UI2.WhenReady(gi, () =>
                {
                    var tw = gi.CreateTween().SetLoops();
                    tw.TweenProperty(gi, "position:y", 1.0, 1.3).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                    tw.TweenProperty(gi, "position:y", 9.0, 1.3).SetTrans(Tween.TRANS_SINE).SetEase(Tween.EASE_IN_OUT);
                });
            }
            return px;
        }

        public static Button _IapButton(SiegeApp app, Control parent, string pid, Vector2 at, Vector2 sz)
        {
            var bl = app.billing as IStoreBilling;
            bool live = bl != null && bl.Active();
            var label = Platform.StoreButton();                // "PLAY STORE" (0.31.130: "APP STORE" on iOS)
            if (live)
                label = GD.Str(bl.busy) == pid ? "…" : GD.Str(bl.Price(pid));
            var b = UI2.Button(parent, label, live ? "green" : "grey", () =>
            {
                app.Sfx("tap");
                if (bl != null)
                    bl.Buy(pid);
                else
                    app.Toast(GD.Fmt("Gem packs are sold in the %s version of Fatebound", Platform.StoreShort()), UI.RED);
            }, "iap_" + pid, 15, 34.0, 11.0);
            if (sz != Vector2.ZERO)
            {
                b.Position = at;
                b.Size = sz;
            }
            if (live)
                b.Disabled = !bl.CanBuy(pid);
            return b;
        }

        // ---------------- hero skins (0.31.186, League's way) ----------------
        // Every skin (Eco.SKINS): the hero in it (assets/ui/skins/<id>.png, tools/render_skin_icons.gd), its name, its gems --
        // BUY asks first (a skin of a locked hero brings him: "+ HERO" on the card); one you own WEAR / WORN (tap WORN: his own
        // look again). The hero window has the same choice beside the hero.
        public static void FeaturedOutfit(SiegeApp app, Node root, string id)
        {
            // 0.31.188: one of the week's outfits big -- the hero in it, turning, in front of his own place (Champions.art), its
            // name, his name, its price; tap: his window with it on (preview, buy, wear)
            // 0.31.203 (Kevin: "For featured outfits, let's make them discounted ... make the graphic of the features look very
            // eye catching"): the WEEKLY SALE's stage -- a treasure hall, its curtains drawn back (ElevenLabs art), him on its
            // pedestal under the light, rays of his rarity turning behind him, confetti falling, the red-and-gold starburst with
            // the discount beating on the corner, the full price struck through and the sale's on a shining button
            var p = app.profile;
            GDict sk = Eco.SKINS[id].D;
            var hid = GD.Str(sk["hero"]);
            var offer = Eco.SkinOffer(id, p.Now());
            var off = (int)offer["off"];
            bool owned = p.OwnsSkin(id);
            var low = ViewLow(app);
            var fc = new Control();
            fc.CustomMinimumSize = new Vector2(0, 300);
            root.AddChild(fc);
            var stage = new Panel();
            var sb = new StyleBoxFlat();
            sb.BgColor = new Color(0.12, 0.02, 0.03);
            sb.SetCornerRadiusAll(20);
            stage.AddThemeStyleboxOverride("panel", sb);
            stage.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            stage.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            stage.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            fc.AddChild(stage);
            var art = new TextureRect();
            art.Texture = UI2.Tex(SALE + "sale_stage.webp");
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_SCALE;
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            stage.AddChild(art);
            var rcol = Color.FromCode(GD.Str(Eco.RARITY_COLOR.Get(GD.Str(sk["rarity"]), "#c47bff")));
            var warm = rcol.Lerp(new Color(1.0, 0.8, 0.35), 0.45);
            // a dark wash on the right for the words (0.31.202), deeper now the hall behind is bright
            var wash = new TextureRect();
            var wg = new Gradient();
            wg.SetColor(0, new Color(0.1, 0.0, 0.02, 0.0));
            wg.SetColor(1, new Color(0.1, 0.0, 0.02, 0.82));
            var wt = new GradientTexture2D();
            wt.Gradient = wg;
            wt.FillFrom = new Vector2(0.4, 0.5);
            wt.FillTo = new Vector2(0.75, 0.5);
            wt.Width = 64;
            wt.Height = 4;
            wash.Texture = wt;
            wash.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            wash.StretchMode = TextureRect.STRETCH_SCALE;
            wash.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            wash.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            stage.AddChild(wash);
            var rays = UI2.Rays(stage, 340.0, warm, 24.0, 0.5);
            var halo = UI2.Glow(stage, new Rect2(0, 0, 240, 240), new Color(warm, 0.5));
            var pool = UI2.Glow(stage, new Rect2(0, 0, 210, 48), new Color(1.0, 0.86, 0.5, 0.65), false);
            fc.Resized += () =>
            {
                // the hall sized and slid so its pedestal (at 30.5 % across, 63.5 % down the picture) is under his feet
                double cx = fc.Size.x * 0.31;
                double feet = fc.Size.y * SALE_FEET;
                var ah = GD.Maxf(GD.Maxf(fc.Size.y, feet / 0.635), fc.Size.x * 9.0 / 16.0);   // (0.31.216: and as wide as a landscape card)
                var aw = ah * 16.0 / 9.0;
                art.Size = new Vector2(aw, ah);
                art.Position = new Vector2(GD.Clampf(cx - 0.305 * aw, fc.Size.x - aw, 0.0), GD.Minf(0.0, feet - 0.635 * ah));
                rays.Position = new Vector2(cx - 170.0, fc.Size.y * 0.42 - 170.0);
                halo.Position = new Vector2(cx - 120.0, fc.Size.y * 0.42 - 120.0);
                pool.Position = new Vector2(cx - 105.0, feet - 24.0);
            };
            var sh = new Showcase();
            sh.plinth = false;
            sh.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            sh.AnchorRight = 0.62;
            sh.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            stage.AddChild(sh);
            sh.ShowLook(hid, GDict.Of("skin", id));
            if (!low)
            {
                _Confetti(stage);
                _Twinkles(stage, 7, rcol.Lerp(Color.WHITE, 0.6), new Rect2(0.05, 0.1, 0.5, 0.75), 20.0);
            }
            var rim = new Panel();
            var rs = new StyleBoxFlat();
            rs.DrawCenter = false;
            rs.BorderColor = UI2.GOLD;                                // (0.31.203: the sale's gold; 0.31.202 its rarity)
            rs.SetBorderWidthAll(3);
            rs.SetCornerRadiusAll(20);
            rs.ShadowColor = new Color(1.0, 0.55, 0.15, 0.55);
            rs.ShadowSize = 12;
            rim.AddThemeStyleboxOverride("panel", rs);
            rim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            fc.AddChild(rim);
            var cap = new VBoxContainer();
            cap.AddThemeConstantOverride("separation", 3);
            cap.AnchorLeft = 0.56;
            cap.AnchorRight = 1.0;
            cap.OffsetTop = 16;
            cap.OffsetRight = -12;
            cap.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            fc.AddChild(cap);
            UI2.IconChip(cap, UI2.IconPath("crown"), GD.Str(sk["rarity"]).ToUpperInvariant() + "  ·  " + GD.Str(Eco.SKIN_HEROES.Get(hid, hid)).ToUpperInvariant(),
                rcol, new Color("#120a02"));
            var nl = UI2.Text(cap, GD.Str(sk["set"]).ToUpperInvariant(), 24, Color.WHITE, new Color("#3a0306"), 6);
            nl.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            UI2.Body(cap, GD.Fmt("%s, the %s", Champions.NameOf(hid), GD.Str(Eco.SKIN_HEROES.Get(hid, hid))), 11, Champions.Accent(hid).Lightened(0.45));
            if (!owned && off > 0)
            {
                // the full price struck through, and what you keep
                var was = new HBoxContainer();
                was.AddThemeConstantOverride("separation", 5);
                was.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                cap.AddChild(was);
                UI2.Img(was, "res://assets/ui/currency/gem.png", 16.0);
                _Struck(was, UI.Grouped((int)offer["was_gems"]), 15, new Color(0.82, 0.8, 0.88));
                UI2.Chip(was, GD.Fmt("SAVE %s", UI.Grouped((int)offer["was_gems"] - (int)offer["gems"])), new Color("#1f7a34"), Color.WHITE, new Color("#9dff8a", 0.6));
            }
            if (!owned && (int)offer["gold"] > 0)                    // 0.31.189: a rare outfit -- or gold (0.31.203: on sale too)
            {
                var gr = new HBoxContainer();
                gr.AddThemeConstantOverride("separation", 4);
                gr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                cap.AddChild(gr);
                UI2.Body(gr, "or", 11, new Color("#ffd86b"), false);
                if (off > 0)
                    _Struck(gr, UI.Grouped((int)offer["was_gold"]), 11, new Color(0.8, 0.78, 0.7));
                UI2.Body(gr, GD.Fmt("%s gold", UI.Grouped((int)offer["gold"])), 11, new Color("#ffd86b"), false);
            }
            UI2.Body(cap, "Tap to see it on him", 10, new Color(1, 1, 1, 0.65));
            var tap = new Button();
            tap.Flat = true;
            tap.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                tap.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            tap.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            tap.SetMeta("action_key", "feat_open");
            tap.Pressed += () => app.OpenChampion(hid, id);
            fc.AddChild(tap);
            Button b;
            if (owned)
            {
                bool worn = p.WornSkin(hid) == id;
                b = UI2.Button(fc, worn ? "WORN" : "WEAR", worn ? "grey" : "blue", () =>
                {
                    p.WearSkin(hid, p.WornSkin(hid) == id ? "" : id);
                    app.Sfx("equip");
                    app.Rebuild();
                }, "feat_wear", 16, 44.0, 12.0);
            }
            else
            {
                b = UI2.Button(fc, UI.Grouped((int)offer["gems"]), "purple", () => BuySkin(app, id), "feat_buy", 19, 48.0, 13.0,
                    "res://assets/ui/currency/gem.png");
                b.Disabled = !CanBuySkin(p, id);
                if (!b.Disabled)
                {
                    UI2.Sweep(b, 2.0, 50.0, 0.5);
                    if (!low)
                        UI2.Pulse(b, 0.035, 0.7);
                }
            }
            b.AnchorLeft = 0.58;
            b.AnchorRight = 1.0;
            b.AnchorTop = 1.0;
            b.AnchorBottom = 1.0;
            b.OffsetRight = -12;
            b.OffsetTop = -62;
            b.OffsetBottom = -12;
            if (off > 0)
            {
                var bd = _SaleBadge(fc, off, 104.0, low);
                bd.Position = new Vector2(-12, -16);
            }
        }

        public static void SkinGrid(SiegeApp app, Node root)
        {
            // 0.31.202: the outfits by role, the Locker's order (TANK ... SUPPORT) -- a row of the six roles' coins first, each
            // jumping to its own; a role: its name, its heroes, then three to a row: their sets on top, the Frostbound line under
            // (Kits = Fatebound.Sim.MobaKits: the .gd loads moba_kits.gd here, not at boot: the 5v5's)
            var heads = new GDict();
            var coins = new HBoxContainer();
            coins.Alignment = BoxContainer.ALIGNMENT_CENTER;
            coins.AddThemeConstantOverride("separation", 6);
            root.AddChild(coins);
            foreach (var role in ROLE_ORDER)
            {
                string rl = GD.Str(role);
                _RoleCoin(coins, rl, GD.Str(Kits.ROLE_NAMES.GetValueOrDefault(rl, rl)), () =>
                {
                    app.Sfx("tap");
                    _ScrollTo(app, heads.Get(rl).As<Node>());
                });
            }
            foreach (var role in ROLE_ORDER)
            {
                GArray heroes = Champions.ORDER.Filter(h => Kits.RoleOf(GD.Str(h)) == role && !Eco.SkinsOf(GD.Str(h)).IsEmpty());
                if (heroes.IsEmpty())
                    continue;
                var rh = new HBoxContainer();
                rh.AddThemeConstantOverride("separation", 8);
                root.AddChild(rh);
                heads[role] = Var.Of(rh);
                var bp = GD.Fmt("res://assets/ui/roles/%s.png", role);
                if (ResourceLoader.Exists(bp))
                {
                    var bi = UI2.Img(rh, bp, 30.0);
                    bi.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                }
                var rt = UI2.Text(rh, GD.Str(Kits.ROLE_NAMES.GetValueOrDefault(GD.Str(role), GD.Str(role))), 19, UI2.GOLD, UI2.INK, 5);
                rt.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var names = heroes.Map(h => GD.Str(Eco.SKIN_HEROES.Get(GD.Str(h), h)));
                var rs = UI2.Body(rh, GStr.Join("  ·  ", names), 10, UI2.SOFT, true);
                rs.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                rs.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var rsm = rs.CustomMinimumSize;
                rsm.x = 10;
                rs.CustomMinimumSize = rsm;
                var grid = new GridContainer();
                grid.Columns = GridCols(app, 128.0);          // (0.31.216: as many as the landscape screen takes; 3 in portrait)
                grid.AddThemeConstantOverride("h_separation", 10);
                grid.AddThemeConstantOverride("v_separation", 12);
                root.AddChild(grid);
                var ids = new GArray();
                foreach (var frost in new[] { false, true })
                {
                    foreach (var h in heroes)
                    {
                        foreach (var id in Eco.SkinsOf(GD.Str(h)))
                        {
                            if (Eco.SKIN_LINES.Has(GD.Str(Eco.SKINS[id].D.Get("line", ""))) == frost)
                                ids.Append(GD.Str(id));
                        }
                    }
                }
                foreach (var id in ids)
                    OutfitCard(app, grid, GD.Str(id));
            }
        }

        public static Button _RoleCoin(Node row, string role, string label, Action on_press)
        {
            // a round button with the role's emblem and its name under it (the shop's jump to that role)
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            b.CustomMinimumSize = new Vector2(58, 64);
            b.SetMeta("action_key", "shop_role_" + role);
            b.Pressed += on_press;
            row.AddChild(b);
            var disc = new Control();
            disc.Position = new Vector2(6, 0);
            disc.Size = new Vector2(46, 46);
            disc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(disc);
            UI2.Plate(disc, "royal", 23.0, "gold", GDict.Of("rim", 2.0));
            var ic = UI2.Img(disc, GD.Fmt("res://assets/ui/roles/%s.png", role), 34.0);
            ic.Position = new Vector2(6, 6);
            var l = UI.Label(b, label, 9, UI2.CREAM, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.HorizontalAlignment = HorizontalAlignment.Center;
            l.AddThemeColorOverride("font_outline_color", UI2.INK);
            l.AddThemeConstantOverride("outline_size", 3);
            l.Position = new Vector2(-4, 48);
            l.Size = new Vector2(66, 14);
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            return b;
        }

        public static TextureRect _GradRect(Control parent, GArray stops, Vector2? from = null, Vector2? to = null)
        {
            // a full-size gradient over the parent: stops = [[offset, Color], ...]
            var from_ = from ?? new Vector2(0, 0);
            var to_ = to ?? new Vector2(0, 1);
            var g = new Gradient();
            var offs = new List<double>();
            var cols = new List<Color>();
            foreach (var st in stops)
            {
                offs.Add((float)(double)st[0]);
                cols.Add((Color)st[1]);
            }
            g.SetOffsets(offs);
            g.SetColors(cols);
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.FillFrom = from_;
            gt.FillTo = to_;
            gt.Width = 4;
            gt.Height = 64;
            var t = new TextureRect();
            t.Texture = gt;
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_SCALE;
            t.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(t);
            return t;
        }

        public static Control OutfitCard(SiegeApp app, Node grid, string id, bool armory = false)
        {
            // 0.31.202: one outfit -- the hero in it standing in his own place (Champions.card_art; the Frostbound line's
            // frosted over), a glow of its rarity behind him (a set: turning rays too), its rarity and whether you own it or wear
            // it, the set's name and the hero's, "or 40K" gold for the Frostbound line; tap the picture: his window with it on;
            // the button: its gems (BUY asks first), WEAR, WORN
            var p = app.profile;
            GDict sk = Eco.SKINS[id].D;
            var hid = GD.Str(sk["hero"]);
            var rar = GD.Str(sk["rarity"]);
            bool frost = Eco.SKIN_LINES.Has(GD.Str(sk.Get("line", "")));
            var rc = Color.FromCode(GD.Str(Eco.RARITY_COLOR.Get(rar, "#c47bff")));
            bool owned = p.OwnsSkin(id);
            bool worn = owned && p.WornSkin(hid) == id;
            Color acc = Champions.Accent(hid);
            var offer = Eco.SkinOffer(id, p.Now());                 // 0.31.203: the weekly sale's price when it's on it
            bool sale = (int)offer["off"] > 0 && !owned;
            var c = new Control();
            c.CustomMinimumSize = new Vector2(0, 226);
            UI.Grow(c);
            grid.AddChild(c);
            var pane = new Panel();
            var sb = new StyleBoxFlat();
            sb.BgColor = rc.Darkened(0.82);
            sb.SetCornerRadiusAll(16);
            pane.AddThemeStyleboxOverride("panel", sb);
            pane.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            pane.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            pane.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(pane);
            var art = new TextureRect();
            art.Texture = UI2.Tex(Champions.CardArt(hid));
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.OffsetBottom = -52;
            art.Modulate = frost ? new Color(0.62, 0.8, 1.0) : new Color(0.92, 0.88, 1.0);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            pane.AddChild(art);
            if (frost)
                _GradRect(pane, GArray.Of(GArray.Of(0.0, new Color(0.85, 0.95, 1.0, 0.45)), GArray.Of(0.35, new Color(0.7, 0.88, 1.0, 0.0))));       // (a frost glaze)
            TextureRect rays = null;
            if (!frost)
                rays = UI2.Rays(pane, 190.0, rc.Lerp(Color.WHITE, 0.3), 28.0, 0.38);
            var halo = UI2.Glow(pane, new Rect2(0, 0, 150, 150), new Color(rc, !frost ? 0.55 : 0.42), false);
            var pool = UI2.Glow(pane, new Rect2(0, 0, 110, 26), new Color(0, 0, 0, 0.55), false);        // (his shadow)
            var ti = UI2.Img(pane, GD.Fmt("res://assets/ui/skins/%s.png", id), 128.0);
            _GradRect(pane, GArray.Of(GArray.Of(0.0, new Color(0, 0, 0, 0)), GArray.Of(0.48, new Color(0, 0, 0, 0)), GArray.Of(0.7, new Color(rc.Darkened(0.85), 0.9)),
                GArray.Of(1.0, new Color(rc.Darkened(0.88), 1.0))));
            c.Resized += () =>
            {
                double cx = c.Size.x * 0.5;
                ti.Position = new Vector2(cx - 64.0, 14.0);
                halo.Position = new Vector2(cx - 75.0, 4.0);
                pool.Position = new Vector2(cx - 55.0, 128.0);
                if (rays != null)
                    rays.Position = new Vector2(cx - 95.0, 78.0 - 95.0);
            };
            if (frost && !ViewLow(app))
                _Twinkles(pane, 3, new Color(0.85, 0.95, 1.0), new Rect2(0.1, 0.08, 0.8, 0.5), 14.0);
            var rim = new Panel();
            var rs = new StyleBoxFlat();
            rs.DrawCenter = false;
            rs.BorderColor = worn ? UI2.GOLD : rc;
            rs.SetBorderWidthAll(worn ? 3 : 2);
            rs.SetCornerRadiusAll(16);
            rs.ShadowColor = worn ? new Color(UI2.GOLD, 0.55) : new Color(rc, 0.3);
            rs.ShadowSize = worn ? 7 : 4;
            rim.AddThemeStyleboxOverride("panel", rs);
            rim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(rim);
            // its rarity (left), and the hero coming with it / owned / worn (right)
            var tag = _CardTag(c, rar.ToUpperInvariant(), rc.Darkened(0.15), rc.Darkened(0.7));
            tag.Position = new Vector2(6, 6);
            var right = "";
            var rfill = new Color("#2f8a3e");
            if (worn)
            {
                right = "WORN";
                rfill = new Color("#b8861c");
            }
            else if (owned && !armory)                     // (0.31.204: in the Armory everything is yours)
                right = "OWNED ✓";
            else if (!p.OwnsHero(hid))
                right = "+ HERO";
            if (right != "" && sale)
            {
                var hc = _CardTag(c, right, rfill, rfill.Darkened(0.7));       // (the corner is the sale's: under the rarity)
                hc.Position = new Vector2(6, 24);
            }
            else if (right != "")
            {
                var hc = _CardTag(c, right, rfill, rfill.Darkened(0.7));
                hc.AnchorLeft = 1.0;
                hc.AnchorRight = 1.0;
                hc.GrowHorizontal = Control.GROW_DIRECTION_BEGIN;
                hc.OffsetRight = -6;
                hc.OffsetLeft = -60;
                hc.OffsetTop = 6;
                hc.OffsetBottom = 22;
            }
            // the names over the foot of the picture
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            v.OffsetTop = -100;
            v.OffsetBottom = -46;
            v.OffsetLeft = 4;
            v.OffsetRight = -4;
            v.Alignment = BoxContainer.ALIGNMENT_END;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(v);
            var set_name = GD.Str(sk["set"]).ToUpperInvariant();
            var nl = UI2.Text(v, set_name, set_name.Length <= 10 ? 14 : (set_name.Length <= 12 ? 12 : 11), Color.WHITE, UI2.INK, 4);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            nl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            nl.ClipText = true;
            var hl = UI.Label(v, GD.Str(Eco.SKIN_HEROES.Get(hid, hid)).ToUpperInvariant(), 10, acc.Lerp(Color.WHITE, 0.45), UI.HEAVY_FONT);
            hl.HorizontalAlignment = HorizontalAlignment.Center;
            hl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            hl.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.8));
            hl.AddThemeConstantOverride("outline_size", 3);
            if (!owned && (int)offer["gold"] > 0)                 // 0.31.189: or gold (0.31.203: the sale's)
            {
                var gc = UI2.IconChip(v, "res://assets/ui/currency/coin.png", GD.Fmt("or %dK", (int)offer["gold"] / 1000), new Color(0.18, 0.12, 0.02, 0.85),
                    new Color("#ffd86b"), new Color("#ffd86b", 0.5));
                gc.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            }
            else if (sale)                                            // what it was, struck through
            {
                var wr = new HBoxContainer();
                wr.Alignment = BoxContainer.ALIGNMENT_CENTER;
                wr.AddThemeConstantOverride("separation", 3);
                wr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                v.AddChild(wr);
                UI2.Img(wr, "res://assets/ui/currency/gem.png", 12.0);
                _Struck(wr, GD.Str((int)offer["was_gems"]), 11, new Color(0.8, 0.78, 0.86));
            }
            var look = new Button();                         // 0.31.188: tap the card -- his window with it on
            look.Flat = true;
            look.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                look.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            look.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            look.OffsetBottom = -46;
            look.SetMeta("action_key", "skin_look_" + id);
            look.Pressed += () => app.OpenChampion(hid, id, armory);
            c.AddChild(look);
            Button b;
            if (owned)
            {
                b = UI2.Button(c, worn ? "WORN" : "WEAR", worn ? "gold" : "blue", () =>
                {
                    p.WearSkin(hid, p.WornSkin(hid) == id ? "" : id);
                    app.Sfx("equip");
                    app.Rebuild();
                }, "skin_wear_" + id, 13, 34.0, 11.0);
            }
            else
            {
                b = UI2.Button(c, GD.Str((int)offer["gems"]), "purple", () => BuySkin(app, id), "skin_buy_" + id, 14, 34.0, 11.0,
                    "res://assets/ui/currency/gem.png");
                b.Disabled = !CanBuySkin(p, id);
            }
            b.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            b.OffsetLeft = 7;
            b.OffsetRight = -7;
            b.OffsetTop = -42;
            b.OffsetBottom = -7;
            if (sale)
            {
                rs.BorderColor = new Color("#ffcf4a");                   // (a sale: a gold frame, glowing warm)
                rs.ShadowColor = new Color(1.0, 0.5, 0.15, 0.5);
                rs.ShadowSize = 7;
                var bd = _SaleBadge(c, (int)offer["off"], 50.0, ViewLow(app));
                c.Resized += () => bd.Position = new Vector2(c.Size.x - 40.0, -10.0);
            }
            return c;
        }

        // ---------------- the Market's HEROES (0.31.204) ----------------
        public static void MarketHeroes(SiegeApp app, VBoxContainer root)
        {
            // 0.31.204 (Kevin: "put a hero tab in the market that shows heroes that player doesn't own and that's where they will
            // purchase them"): every hero you don't own, by role (TANK ... SUPPORT), on cards like the outfits' -- him in his
            // own place, FREE THIS WEEK / NEW / a shard of him, his gold and gem price, UNLOCK (gold, gems, a shard, a Hero Token;
            // asked first); tap the picture: his window (story, kit, outfits). Once he's yours he's in the Armory. The 5v5
            // picker's GET IN MARKET lands here with his card lit (app.open_market("heroes", hid)).
            var p = app.profile;
            // (Kits = Fatebound.Sim.MobaKits: the .gd loads moba_kits.gd here, not at boot: the 5v5's)
            GArray locked = Champions.ORDER.Filter(h => !p.OwnsHero(GD.Str(h)));
            UI2.Divider(root, "HEROES", 22, "yours for good  ·  gold or gems  ·  then he's in your Armory");
            var inv = "";
            if ((int)p.d.Get("tokens", 0) > 0)
                inv = GD.Fmt("HERO TOKEN x%d", (int)p.d["tokens"]);
            var nsh = p.d.Get("shards", new GArray()).A.Size();
            if (nsh > 0)
                inv += (inv != "" ? "  ·  " : "") + GD.Fmt("◆ SHARD%s %d", nsh > 1 ? "S" : "", nsh);
            if (inv != "" && !locked.IsEmpty())
            {
                var ic = UI2.Chip(root, inv, new Color("#173a1e"), new Color("#c9f7bd"), new Color("#6be07c"));
                ic.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            }
            if (locked.IsEmpty())
            {
                // every hero is yours
                var box = UI2.Frame(root, "night", 16, 18.0, "gold");
                box.AddThemeConstantOverride("separation", 6);
                var cr = UI2.Img(box, UI2.IconPath("crown"), 64.0);
                cr.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
                UI2.Center(UI2.Text(box, "EVERY HERO IS YOURS", 22, Color.WHITE));
                UI2.Center(UI2.Body(box, GD.Fmt("All %d of them -- they're waiting in your Armory.", Champions.ORDER.Size()), 12, UI2.SOFT));
                var ab = UI2.Button(box, "OPEN THE ARMORY", "gold", () =>
                {
                    app.Sfx("tab");
                    app.locker_tab = "heroes";
                    app.ShowTab("locker");
                }, "market_to_armory", 15, 42.0, 12.0);
                ab.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
                return;
            }
            GArray free = Eco.FreeHeroes(p.Now()).Filter(h => !p.OwnsHero(GD.Str(h)));
            if (!free.IsEmpty())
            {
                var fc = UI2.Chip(root, GD.Fmt("FREE THIS WEEK: %s  ·  play them in battle, own them here", GStr.Join(", ", free.Map(h => Champions.ShortOf(GD.Str(h)).ToUpperInvariant()))),
                    new Color("#1f6a2e"), Color.WHITE, new Color("#9dff8a", 0.6));
                fc.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            }
            var focus = GD.Str(Var.Of(app.GetMeta("shop_hero_focus", "")));
            if (app.HasMeta("shop_hero_focus"))
                app.RemoveMeta("shop_hero_focus");
            Control lit = null;
            foreach (var role in ROLE_ORDER)
            {
                GArray hs = locked.Filter(h => Kits.RoleOf(GD.Str(h)) == role);
                if (hs.IsEmpty())
                    continue;
                var rh = new HBoxContainer();
                rh.AddThemeConstantOverride("separation", 8);
                root.AddChild(rh);
                var bp = GD.Fmt("res://assets/ui/roles/%s.png", role);
                if (ResourceLoader.Exists(bp))
                    UI2.Img(rh, bp, 30.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                UI2.Text(rh, GD.Str(Kits.ROLE_NAMES.GetValueOrDefault(GD.Str(role), GD.Str(role))), 19, UI2.GOLD, UI2.INK, 5).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var rs = UI2.Body(rh, GD.Str(Kits.ROLE_TEXT.GetValueOrDefault(GD.Str(role), "")), 10, UI2.SOFT, true);
                rs.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                rs.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var rsm = rs.CustomMinimumSize;
                rsm.x = 10;
                rs.CustomMinimumSize = rsm;
                var grid = new GridContainer();
                grid.Columns = GridCols(app, 128.0);          // (0.31.216: as many as the landscape screen takes; 3 in portrait)
                grid.AddThemeConstantOverride("h_separation", 10);
                grid.AddThemeConstantOverride("v_separation", 12);
                root.AddChild(grid);
                foreach (var hid in hs)
                {
                    var c = HeroOfferCard(app, grid, GD.Str(hid));
                    if (GD.Str(hid) == focus)
                        lit = c;
                }
                if (hs.Size() < 3)                                  // (keep the cards a third wide)
                {
                    for (int i = 0; i < 3 - hs.Size(); i++)
                    {
                        var gap = new Control();
                        UI.Grow(gap);
                        grid.AddChild(gap);
                    }
                }
            }
            if (lit != null)
            {
                // from the 5v5 picker: glide to his card and light it up
                var ring = new Panel();
                var rs2 = new StyleBoxFlat();
                rs2.DrawCenter = false;
                rs2.BorderColor = new Color("#fff3ad");
                rs2.SetBorderWidthAll(4);
                rs2.SetCornerRadiusAll(18);
                rs2.ShadowColor = new Color(1.0, 0.8, 0.3, 0.8);
                rs2.ShadowSize = 14;
                ring.AddThemeStyleboxOverride("panel", rs2);
                ring.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
                ring.OffsetLeft = -3;
                ring.OffsetTop = -3;
                ring.OffsetRight = 3;
                ring.OffsetBottom = 3;
                ring.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                ring.SetMeta("hero_focus_ring", true);
                lit.AddChild(ring);
                UI2.WhenReady(ring, () =>
                {
                    var tw = ring.CreateTween().SetLoops(4);
                    tw.TweenProperty(ring, "modulate:a", 0.25, 0.4).SetTrans(Tween.TRANS_SINE);
                    tw.TweenProperty(ring, "modulate:a", 1.0, 0.4).SetTrans(Tween.TRANS_SINE);
                    var glide = ring.CreateTween();               // (bound to the ring: gone with the page if you leave first)
                    glide.TweenInterval(0.12);
                    glide.TweenCallback(() =>
                    {
                        ScrollContainer sc = app.content_scroll;
                        if (GD.IsInstanceValid(lit) && GD.IsInstanceValid(sc))
                        {
                            var to = GD.Maxi(0, sc.ScrollVertical + (int)((double)lit.GlobalPosition.y - sc.GlobalPosition.y) - 90);
                            sc.CreateTween().TweenProperty(sc, "scroll_vertical", to, 0.45).SetTrans(Tween.TRANS_CUBIC).SetEase(Tween.EASE_OUT);
                        }
                    });
                });
            }
        }

        public static Control HeroOfferCard(SiegeApp app, Node grid, string hid)
        {
            // 0.31.204: one hero for sale -- him (in his own look) in his own place (Champions.card_art), a glow of his colour, his
            // name and class, FREE THIS WEEK / NEW / ◆ shard tags, his price in gold and in gems, UNLOCK (asked first: each way);
            // tap the picture: his window
            var p = app.profile;
            Color acc = Champions.Accent(hid);
            GDict pr = p.HeroPrice(hid);
            bool plays = p.CanPlayHero(hid);
            var c = new Control();
            c.CustomMinimumSize = new Vector2(0, 244);
            UI.Grow(c);
            grid.AddChild(c);
            var pane = new Panel();
            var sb = new StyleBoxFlat();
            sb.BgColor = acc.Darkened(0.82);
            sb.SetCornerRadiusAll(16);
            pane.AddThemeStyleboxOverride("panel", sb);
            pane.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            pane.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            pane.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(pane);
            var art = new TextureRect();
            art.Texture = UI2.Tex(Champions.CardArt(hid));
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.OffsetBottom = -70;
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            pane.AddChild(art);
            var rays = UI2.Rays(pane, 190.0, acc.Lerp(new Color(1.0, 0.9, 0.6), 0.4), 30.0, 0.32);
            var halo = UI2.Glow(pane, new Rect2(0, 0, 150, 150), new Color(acc.Lerp(Color.WHITE, 0.2), 0.5), false);
            var pool = UI2.Glow(pane, new Rect2(0, 0, 110, 26), new Color(0, 0, 0, 0.55), false);
            var ti = UI2.Img(pane, GD.Fmt("res://assets/ui/skins/default_%s.png", hid), 128.0);
            _GradRect(pane, GArray.Of(GArray.Of(0.0, new Color(0, 0, 0, 0)), GArray.Of(0.42, new Color(0, 0, 0, 0)), GArray.Of(0.62, new Color(acc.Darkened(0.85), 0.92)),
                GArray.Of(1.0, new Color(acc.Darkened(0.9), 1.0))));
            c.Resized += () =>
            {
                double cx = c.Size.x * 0.5;
                ti.Position = new Vector2(cx - 64.0, 14.0);
                halo.Position = new Vector2(cx - 75.0, 4.0);
                pool.Position = new Vector2(cx - 55.0, 128.0);
                rays.Position = new Vector2(cx - 95.0, 78.0 - 95.0);
            };
            var rim = new Panel();
            var rs = new StyleBoxFlat();
            rs.DrawCenter = false;
            rs.BorderColor = acc.Lerp(Color.WHITE, 0.15);
            rs.SetBorderWidthAll(2);
            rs.SetCornerRadiusAll(16);
            rs.ShadowColor = new Color(acc, 0.35);
            rs.ShadowSize = 5;
            rim.AddThemeStyleboxOverride("panel", rs);
            rim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(rim);
            // tags down the left: FREE this week, NEW (at his launch price), ◆ a shard of him
            var tags = new VBoxContainer();
            tags.AddThemeConstantOverride("separation", 3);
            tags.Position = new Vector2(6, 6);
            tags.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(tags);
            if (plays)
                _CardTag(tags, "FREE", new Color("#2f8a3e"), new Color("#0a2006"));          // (this week's: the chip over the list says so)
            if (Eco.Launching(hid, p.Now()))
                _CardTag(tags, "NEW", new Color("#d9682a"), new Color("#3a1402"));
            if (p.ShardsOf(hid) > 0)
                _CardTag(tags, "◆ SHARD", new Color("#1f6a2e"), new Color("#6be07c"));
            var nsk = Eco.SkinsOf(hid).Size();
            if (nsk > 0)
            {
                var oc = _CardTag(c, GD.Fmt("%d OUTFIT%s", nsk, nsk == 1 ? "" : "S"), new Color(0.08, 0.04, 0.16, 0.85), new Color("#c47bff"));
                oc.AnchorLeft = 1.0;
                oc.AnchorRight = 1.0;
                oc.GrowHorizontal = Control.GROW_DIRECTION_BEGIN;
                oc.OffsetRight = -6;
                oc.OffsetLeft = -60;
                oc.OffsetTop = 6;
                oc.OffsetBottom = 22;
            }
            // his name, his class, his prices
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 0);
            v.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            v.OffsetTop = -118;
            v.OffsetBottom = -44;
            v.OffsetLeft = 4;
            v.OffsetRight = -4;
            v.Alignment = BoxContainer.ALIGNMENT_END;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(v);
            var nm = Champions.ShortOf(hid).ToUpperInvariant();
            var nl = UI2.Text(v, nm, nm.Length <= 8 ? 16 : 13, Color.WHITE, acc.Darkened(0.75), 5);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            nl.ClipText = true;
            var cl = UI.Label(v, GD.Str(Eco.SKIN_HEROES.Get(hid, hid)).ToUpperInvariant(), 10, acc.Lerp(Color.WHITE, 0.5), UI.HEAVY_FONT);
            cl.HorizontalAlignment = HorizontalAlignment.Center;
            cl.AddThemeColorOverride("font_outline_color", new Color(0, 0, 0, 0.8));
            cl.AddThemeConstantOverride("outline_size", 3);
            if (!pr.IsEmpty())
            {
                var prow = new HBoxContainer();
                prow.Alignment = BoxContainer.ALIGNMENT_CENTER;
                prow.AddThemeConstantOverride("separation", 3);
                prow.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                v.AddChild(prow);
                UI2.Img(prow, "res://assets/ui/currency/coin.png", 15.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                UI2.Text(prow, _ShortGold((int)pr["gold"]), 13, UI2.GOLD, new Color("#201002"), 3);
                UI2.Body(prow, "or", 9, UI2.SOFT, false).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                UI2.Img(prow, "res://assets/ui/currency/gem.png", 15.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                UI2.Text(prow, GD.Str((int)pr["gems"]), 13, new Color("#cfe9ff"), new Color("#0a1238"), 3);
            }
            var look = new Button();                         // tap the picture: his window
            look.Flat = true;
            look.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                look.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            look.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            look.OffsetBottom = -46;
            look.SetMeta("action_key", "hero_look_" + hid);
            look.Pressed += () => app.OpenChampion(hid);
            c.AddChild(look);
            var b = UI2.Button(c, "UNLOCK", "gold", () => BuyHero(app, hid), "hero_unlock_" + hid, 14, 36.0, 11.0);
            b.Disabled = !CanUnlockHero(p, hid);
            if (!b.Disabled)
                UI2.Sweep(b, 3.0, 40.0, 0.4);
            b.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            b.OffsetLeft = 7;
            b.OffsetRight = -7;
            b.OffsetTop = -42;
            b.OffsetBottom = -7;
            return c;
        }

        public static string _ShortGold(int n)
        {
            // 6,300 / 50K / 1.5K
            if (n >= 10000)
                return n % 1000 == 0 ? GD.Fmt("%dK", n / 1000) : GD.Fmt("%.1fK", n / 1000.0);
            return UI.Grouped(n);
        }

        public static bool CanUnlockHero(Profile p, string hid)
        {
            // any of the ways: his gold, his gems, a shard of him and its gold, a Hero Token
            GDict pr = p.HeroPrice(hid);
            if (pr.IsEmpty() || p.OwnsHero(hid))
                return false;
            return (int)p.d["gold"] >= (int)pr["gold"] || (int)p.d["gems"] >= (int)pr["gems"] || (int)p.d.Get("tokens", 0) > 0
                || (p.ShardsOf(hid) > 0 && (int)p.d["gold"] >= Eco.ShardUnlockGold(hid, p.Now()));
        }

        public static void BuyHero(SiegeApp app, string hid)
        {
            // 0.31.204: UNLOCK <NAME>? -- each way (the 5v5 window's chooser, 0.31.185), those you can't pay dimmed; CANCEL
            var p = app.profile;
            GDict pr = p.HeroPrice(hid);
            if (pr.IsEmpty() || p.OwnsHero(hid))
                return;
            Action<GDict> done = (GDict r) =>
            {
                if ((bool)r.Get("ok", false))
                {
                    app.Sfx("purchase");
                    app.Toast(GD.Fmt("%s joins you! He's in your Armory.", Champions.NameOf(hid)), UI2.GOLD);
                    app.RefreshTop();
                }
                else
                {
                    app.Sfx("error");
                    app.Toast(GD.Str(r.Get("error", "Can't unlock")), UI.RED);
                }
                app.Rebuild();
            };
            var opts = GArray.Of(
                new GDict { { "text", GD.Fmt("%s GOLD", UI.Grouped((int)pr["gold"])) }, { "style", "gold" }, { "key", "hero_buy_gold" }, { "enabled", (int)p.d["gold"] >= (int)pr["gold"] },
                    { "call", (Action)(() => done(p.BuyHero(hid))) } },
                new GDict { { "text", GD.Fmt("%s GEMS", UI.Grouped((int)pr["gems"])) }, { "style", "premium" }, { "key", "hero_buy_gems" }, { "enabled", (int)p.d["gems"] >= (int)pr["gems"] },
                    { "call", (Action)(() => done(p.BuyHeroGems(hid))) } });
            if (p.ShardsOf(hid) > 0)
            {
                var sg = Eco.ShardUnlockGold(hid, p.Now());
                opts.Append(new GDict { { "text", GD.Fmt("SHARD + %s GOLD", UI.Grouped(sg)) }, { "style", "claim" }, { "key", "hero_buy_shard" }, { "enabled", (int)p.d["gold"] >= sg },
                    { "call", (Action)(() => done(p.UseShard(hid))) } });
            }
            if ((int)p.d.Get("tokens", 0) > 0)
            {
                opts.Append(new GDict { { "text", "HERO TOKEN" }, { "style", "primary" }, { "key", "hero_buy_token" }, { "enabled", true },
                    { "call", (Action)(() => done(p.UseToken(hid))) } });
            }
            app.Choose(GD.Fmt("UNLOCK %s?", Champions.NameOf(hid).ToUpperInvariant()), GD.Fmt("The %s, yours for good.%s", GD.Str(Eco.SKIN_HEROES.Get(hid, hid)),
                Eco.Launching(hid, p.Now()) ? "  Launch price for now." : ""), opts);
        }

        public static PanelContainer _CardTag(Control parent, string s, Color fill, Color border)
        {
            // a small corner tag on a card (EPIC, RARE, + HERO, OWNED, WORN)
            var pc = new PanelContainer();
            var sb = new StyleBoxFlat();
            sb.BgColor = fill;
            sb.BorderColor = border;
            sb.SetBorderWidthAll(1);
            sb.SetCornerRadiusAll(7);
            sb.ContentMarginLeft = 5;
            sb.ContentMarginRight = 5;
            sb.ContentMarginTop = 0;
            sb.ContentMarginBottom = 1;
            pc.AddThemeStyleboxOverride("panel", sb);
            pc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(pc);
            var l = UI.Label(pc, s, 9, Color.WHITE, UI.HEAVY_FONT);
            l.AutowrapMode = TextServer.AUTOWRAP_OFF;
            l.HorizontalAlignment = HorizontalAlignment.Center;
            return pc;
        }

        public static bool ViewLow(SiegeApp app)
        {
            // fewer extras on "reduce motion" (Settings)
            return app.profile != null && (bool)app.profile.d.Get("settings", new GDict()).D.Get("reduce_motion", false);
        }

        public static bool CanBuySkin(Profile p, string id)
        {
            // the gems for it -- or (0.31.189: a rare outfit) the gold. 0.31.203: at the weekly sale's price when it's on it
            var o = Eco.SkinOffer(id, p.Now());
            return (int)p.d["gems"] >= (int)o["gems"] || ((int)o["gold"] > 0 && (int)p.d["gold"] >= (int)o["gold"]);
        }

        public static void BuySkin(SiegeApp app, string id)
        {
            // BUY asks first; Profile.buy_outfit takes the weekly sale's price when the outfit is on it (0.31.203)
            var p = app.profile;
            GDict sk = Eco.SKINS[id].D;
            var o = Eco.SkinOffer(id, p.Now());
            var hid = GD.Str(sk["hero"]);
            bool with_hero = !p.OwnsHero(hid);
            Action<GDict> bought = (GDict r) =>
            {
                if ((bool)r.Get("ok", false))
                {
                    app.Sfx("purchase");
                    app.Toast(GD.Fmt("%s is yours%s", GD.Str(sk["name"]), (bool)r.Get("hero", false) ? GD.Fmt(" -- and the %s", GD.Str(Eco.SKIN_HEROES.Get(hid, hid))) : ""), UI.GOLD);
                    app.RefreshTop();
                }
                else
                {
                    app.Sfx("error");
                    app.Toast(GD.Str(r.Get("error", "Can't buy")), UI.RED);
                }
                app.Rebuild();
            };
            var tail = GD.Fmt("%s Worn at once -- change it in the shop or the hero window.", with_hero ? GD.Fmt(" The %s comes with it.", GD.Str(Eco.SKIN_HEROES.Get(hid, hid))) : "");
            var sale = (int)o["off"] > 0 ? GD.Fmt("Weekly sale: %d%% off. ", (int)o["off"]) : "";
            if ((int)o["gold"] > 0)
            {
                // 0.31.189 (Kevin: "Frostbound for gold"): gems or gold
                app.Choose(GD.Fmt("BUY %s?", GD.Str(sk["name"]).ToUpperInvariant()), GD.Fmt("%s%s gems or %s gold.%s", sale, UI.Grouped((int)o["gems"]), UI.Grouped((int)o["gold"]), tail), GArray.Of(
                    new GDict { { "text", GD.Fmt("%s GEMS", UI.Grouped((int)o["gems"])) }, { "style", "premium" }, { "key", "modal_yes" }, { "enabled", (int)p.d["gems"] >= (int)o["gems"] },
                        { "call", (Action)(() => bought(p.BuyOutfit(id, false))) } },
                    new GDict { { "text", GD.Fmt("%s GOLD", UI.Grouped((int)o["gold"])) }, { "style", "gold" }, { "key", "modal_gold" }, { "enabled", (int)p.d["gold"] >= (int)o["gold"] },
                        { "call", (Action)(() => bought(p.BuyOutfit(id, true))) } }));
                return;
            }
            app.Confirm(GD.Fmt("BUY %s?", GD.Str(sk["name"]).ToUpperInvariant()), GD.Fmt("%s%d gems.%s", sale, (int)o["gems"], tail), "BUY", "premium", () =>
                bought(p.BuyOutfit(id, false)));
        }

        public static bool IsEquipped(Profile p, string id)
        {
            // a title worn (0.31.188: titles are all there is to equip)
            return Eco.Item(id).Get("kind", "") == "title" && GD.Str(p.d["title"]) == id;
        }

        public static void Equip(SiegeApp app, string id)
        {
            if (app.profile.Equip(id)["ok"])
            {
                app.Sfx("equip");
                app.Toast(GD.Fmt("Equipped %s", GD.Str(Eco.Item(id)["name"])), UI.CYAN);
            }
            app.Rebuild();
        }

        // ---------------- LOCKER ----------------
        public static Button _ClassCoin(Node parent, string cls, bool on, string key, Action on_press, string label = "", double px = 48.0)
        {
            // A round class button with the class's render in it (gold when selected).
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            b.CustomMinimumSize = new Vector2(px, px + (label != "" ? 14.0 : 0.0));
            b.SetMeta("action_key", key);
            b.Pressed += on_press;
            parent.AddChild(b);
            var disc = new Control();
            disc.Size = new Vector2(px, px);
            disc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(disc);
            if (on)
                UI2.Skin(disc, UI2.ButtonParams("gold", px * 0.5, 3.0).Merged(GDict.Of("glow", 7.0, "glow_color", new Color(1.0, 0.84, 0.35, 0.8)), true));
            else
                UI2.Plate(disc, "royal", px * 0.5, "gold", GDict.Of("rim", 2.0, "dim", 0.15));
            var clip = new Control();
            clip.Position = new Vector2(3, 3);
            clip.Size = new Vector2(px - 6, px - 6);
            clip.ClipContents = true;
            clip.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            disc.AddChild(clip);
            var t = new TextureRect();
            var portrait = GD.Fmt("res://assets/ui/skins/default_%s.png", cls);
            t.Texture = UI2.Tex(ResourceLoader.Exists(portrait) ? portrait : GD.Fmt("res://assets/ui/icons/default_%s.png", cls));
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            t.Position = new Vector2(-px * 0.1, -px * 0.04);
            t.Size = new Vector2(px * 1.1, px * 1.1);
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            clip.AddChild(t);
            if (label != "")
            {
                var l = UI2.Text(b, label, 9, on ? UI2.CYAN : Color.WHITE, UI2.INK, 3, false);
                l.HorizontalAlignment = HorizontalAlignment.Center;
                l.Position = new Vector2(-10, px + 1);
                l.Size = new Vector2(px + 20, 12);
            }
            return b;
        }

        public static void Locker(SiegeApp app, VBoxContainer root)
        {
            // 0.31.79: the vault -- the class picker, the hero on the vault's pedestal, the nameplate and the weapons as cards.
            // 0.31.187 (Kevin: "give every champion a unique name ... a short background story. Put all this in a revamped locker
            // tab"): CHAMPIONS first (the eighteen by role: tap one for his own window, champion_window.gd), then TITLES.
            // (0.31.187: ARMORY, the vault and its weapons -- gone with the weapons, 0.31.188: an outfit is his whole look.)
            // 0.31.204 (Kevin: "Now redo the locker menu. Change the name to armory and only put in there what the player owns"):
            // the ARMORY (the tab keeps its id "locker") -- a painted armory hall (ElevenLabs) with what you hold on it, then
            // three tabs: HEROES (yours, by role; tap one: his window with only his outfits you own), OUTFITS (yours: WEAR /
            // WORN) and TITLES (earned: EQUIP). Nothing to buy and nothing locked: the Market sells heroes and outfits (a way
            // there when there's more to get); a title you haven't earned isn't shown, only how many are left.
            var p = app.profile;
            GArray heroes = Champions.ORDER.Filter(h => p.OwnsHero(GD.Str(h)));
            GArray outfits = new GArray();
            foreach (var h in Champions.ORDER)
            {
                foreach (var id in Eco.SkinsOf(GD.Str(h)))
                {
                    if (p.OwnsSkin(GD.Str(id)))
                        outfits.Append(GD.Str(id));
                }
            }
            GArray titles = _EarnedTitles(p);
            var ban = Banner(root, UI2.V2 + "art_armory.webp", "ARMORY", 176.0);
            GArray free = Champions.ORDER.Filter(h => !p.OwnsHero(GD.Str(h)) && p.CanPlayHero(GD.Str(h)));   // 0.31.205
            var hold = UI2.Chip(ban, GD.Fmt("%d HEROES%s  ·  %d OUTFITS  ·  %d TITLES", heroes.Size(), !free.IsEmpty() ? GD.Fmt(" +%d FREE", free.Size()) : "",
                outfits.Size(), titles.Size()),
                new Color(0.03, 0.02, 0.1, 0.8), UI2.CREAM, new Color(UI2.GOLD, 0.6));
            hold.Position = new Vector2(12, 12);
            if (!ViewLow(app))
                _Twinkles(ban, 6, new Color(1.0, 0.86, 0.5), new Rect2(0.1, 0.1, 0.8, 0.5));
            if (GD.Str(app.locker_tab) == "champions")
                app.locker_tab = "heroes";                     // (0.31.187-0.31.203's name for it)
            if (!GArray.Of("heroes", "outfits", "titles").Has(GD.Str(app.locker_tab)))
                app.locker_tab = "heroes";
            var tabs = new HBoxContainer();
            tabs.AddThemeConstantOverride("separation", 8);
            root.AddChild(tabs);
            foreach (var t in GArray.Of(GArray.Of("heroes", "HEROES", heroes.Size() + free.Size(), UI2.IconPath("crown")), GArray.Of("outfits", "OUTFITS", outfits.Size(), UI2.IconPath("helmet")),
                    GArray.Of("titles", "TITLES", titles.Size(), UI2.IconPath("scroll"))))
            {
                string tid = GD.Str(t[0]);
                bool on = GD.Str(app.locker_tab) == tid;
                var tb0 = UI2.Button(tabs, GD.Fmt("%s %d", GD.Str(t[1]), (int)t[2]), on ? "gold" : "blue", () =>
                {
                    if (GD.Str(app.locker_tab) == tid)
                        return;
                    app.locker_tab = tid;
                    app.Sfx("tab");
                    app.content_scroll.ScrollVertical = 0;
                    app.Rebuild();
                }, "locker_tab_" + tid, 14, 40.0, 12.0, GD.Str(t[3]));
                tb0.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            }
            switch (GD.Str(app.locker_tab))
            {
                case "outfits":
                    ArmoryOutfits(app, root, outfits);
                    break;
                case "titles":
                    ArmoryTitles(app, root, titles);
                    break;
                default:
                    LockerChampions(app, root);
                    break;
            }
        }

        public static GArray _EarnedTitles(Profile p)
        {
            // the titles you hold, in the Locker's old order: for everyone, then each class's, then the leaderboard's
            var out_ = new GArray();
            var secs = GArray.Of("");
            secs.AppendArray(Eco.HERO_CLASSES);
            foreach (var sec in secs)
            {
                var ids = new GArray();
                foreach (var id in Eco.TITLE_GOALS)
                {
                    if (GD.Str(Eco.TITLE_GOALS[id]["cls"]) == GD.Str(sec) && p.Owns(GD.Str(id)))
                        ids.Append(id);
                }
                ids.SortCustom((a, b) => Eco.TITLE_RARITY_ORDER.Find(GD.Str(Eco.CATALOG[a]["rarity"])) < Eco.TITLE_RARITY_ORDER.Find(GD.Str(Eco.CATALOG[b]["rarity"])));
                out_.AppendArray(ids);
            }
            foreach (var id in Eco.PRIZE_TITLES)
            {
                if (p.Owns(GD.Str(id)))
                    out_.Append(id);
            }
            return out_;
        }

        public static void _ToMarket(SiegeApp app, Node root, string text, string tab_id, string key)
        {
            // a way from the Armory to what the Market has (0.31.204)
            var b = UI2.Button(root, text, "purple", () =>
            {
                app.Sfx("tab");
                app.OpenMarket(tab_id);
            }, key, 13, 38.0, 12.0, UI2.IconPath("stall"));
            b.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
        }

        public static void _ArmoryEmpty(Node root, string icon, string head, string line)
        {
            var box = UI2.Frame(root, "night", 16, 18.0, "gold");
            box.AddThemeConstantOverride("separation", 6);
            var ic = UI2.Img(box, UI2.IconPath(icon), 56.0);
            ic.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            UI2.Center(UI2.Text(box, head, 20, Color.WHITE));
            var l = UI2.Center(UI2.Body(box, line, 12, UI2.SOFT));
            var lm = l.CustomMinimumSize;
            lm.x = 10;
            l.CustomMinimumSize = lm;
        }

        public static void ArmoryOutfits(SiegeApp app, VBoxContainer root, GArray outfits)
        {
            // 0.31.204: the outfits you own, his heroes' order -- WEAR / WORN on each (tap WORN: his own look again); tap the
            // picture: his window in it
            var p = app.profile;
            var more = Eco.SKINS.Size() - outfits.Size();
            if (outfits.IsEmpty())
            {
                _ArmoryEmpty(root, "helmet", "NO OUTFITS YET", "A whole new look and weapon for a hero -- the Market has them, and a few are on sale this week.");
                _ToMarket(app, root, "BROWSE OUTFITS IN THE MARKET  ▸", "outfits", "armory_to_outfits");
                return;
            }
            var worn = 0;
            foreach (var id in outfits)
            {
                if (p.WornSkin(GD.Str(Eco.SKINS[id]["hero"])) == GD.Str(id))
                    worn += 1;
            }
            UI2.Center(UI2.Body(root, GD.Fmt("%d yours  ·  %d worn  ·  tap WORN for his own look again", outfits.Size(), worn), 11, UI2.SOFT));
            var grid = new GridContainer();
            grid.Columns = GridCols(app, 128.0);          // (0.31.216: as many as the landscape screen takes; 3 in portrait)
            grid.AddThemeConstantOverride("h_separation", 10);
            grid.AddThemeConstantOverride("v_separation", 12);
            root.AddChild(grid);
            foreach (var id in outfits)
                OutfitCard(app, grid, GD.Str(id), true);
            if (outfits.Size() % 3 != 0)
            {
                for (int i = 0; i < 3 - outfits.Size() % 3; i++)
                {
                    var gap = new Control();
                    UI.Grow(gap);
                    grid.AddChild(gap);
                }
            }
            if (more > 0)
                _ToMarket(app, root, GD.Fmt("%d MORE IN THE MARKET  ▸", more), "outfits", "armory_to_outfits");
        }

        public static void ArmoryTitles(SiegeApp app, VBoxContainer root, GArray titles)
        {
            // 0.31.204: NO TITLE, then every title you've earned (EQUIP / WORN); the ones still to earn aren't shown -- how many
            var p = app.profile;
            UI2.Divider(root, "TITLES", 20, "shown next to your name");
            var none = UI2.Frame(root, "night", 10, 14.0, "gold");
            var nr = UI.Row(none, 8);
            UI.Grow(UI2.Text(nr, "NO TITLE", 15, Color.WHITE));
            var ne = UI2.Button(nr, GD.Str(p.d["title"]) == "" ? "EQUIPPED" : "EQUIP", GD.Str(p.d["title"]) == "" ? "grey" : "blue", () =>
            {
                p.Unequip("", "title");
                app.Rebuild();
            }, "equip_default_title", 13, 34.0, 11.0);
            ne.Disabled = GD.Str(p.d["title"]) == "";
            var nem = ne.CustomMinimumSize;
            nem.x = 104;
            ne.CustomMinimumSize = nem;
            foreach (var id in titles)
                LockerRow(app, root, GD.Str(id));
            var left = 0;
            foreach (var id in Eco.TITLE_GOALS)
            {
                if (!p.Owns(GD.Str(id)) && !Eco.Retired(Eco.TITLE_GOALS[id].D))
                    left += 1;
            }
            foreach (var id in Eco.PRIZE_TITLES)
            {
                if (!p.Owns(GD.Str(id)))
                    left += 1;
            }
            if (titles.IsEmpty())
                _ArmoryEmpty(root, "scroll", "NO TITLES YET", "Titles are earned by playing -- win, take towers, climb the weekly leaderboard.");
            if (left > 0)
                UI2.Center(UI2.Body(root, GD.Fmt("%d more to earn by playing", left), 11, UI2.SOFT));
        }

        // ---------------- the Locker's CHAMPIONS (0.31.187) ----------------
        // The eighteen by role (League's six: a row of three each -- the class, its upgrade, the new hero), each a card: his own
        // place painted behind him (Champions.card_art), him in the skin he wears, his name and class, and where he stands with
        // you: yours (a tick), FREE this week, NEW at his launch price, or his price and a padlock; ◆ when you hold his shard, and
        // how many skins he has. Tap: his window (champion_window.gd).
        public static readonly GArray ROLE_ORDER = GArray.Of("tank", "fighter", "assassin", "mage", "marksman", "support");

        public static void LockerChampions(SiegeApp app, VBoxContainer root)
        {
            // 0.31.204: the Armory's HEROES -- the heroes you own, by role (a role with none of yours left out); the ones you
            // don't are in the Market's HEROES (a way there under them). 0.31.205 (Kevin: "Make the heros that are free for the
            // week show up in players armory"): and this week's free ones among them, FREE THIS WEEK on their cards (yours to
            // play until Monday; to keep, the Market)
            var p = app.profile;
            // (Kits = Fatebound.Sim.MobaKits: the .gd loads moba_kits.gd here, not at boot: the 5v5's)
            GArray order = Champions.ORDER;
            GArray mine = order.Filter(h => p.OwnsHero(GD.Str(h)));
            GArray free = order.Filter(h => !p.OwnsHero(GD.Str(h)) && p.CanPlayHero(GD.Str(h)));
            GArray shown = order.Filter(h => p.CanPlayHero(GD.Str(h)));
            var top = UI2.Center(UI2.Body(root, GD.Fmt("%d of %d heroes yours%s  ·  tap one for his story, his outfits and a closer look", mine.Size(), order.Size(),
                !free.IsEmpty() ? GD.Fmt("  ·  %d free this week", free.Size()) : ""), 11, UI2.SOFT));
            var topm = top.CustomMinimumSize;
            topm.x = 10;
            top.CustomMinimumSize = topm;
            var inv = "";
            if ((int)p.d.Get("tokens", 0) > 0)
                inv = GD.Fmt("HERO TOKEN x%d", (int)p.d["tokens"]);
            var nsh = p.d.Get("shards", new GArray()).A.Size();
            if (nsh > 0)
                inv += (inv != "" ? "  ·  " : "") + GD.Fmt("◆ SHARD%s %d", nsh > 1 ? "S" : "", nsh);
            if (inv != "")
            {
                var ic = UI2.Chip(root, inv + "  ·  use them in the Market", new Color("#173a1e"), new Color("#c9f7bd"), new Color("#6be07c"));
                ic.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
            }
            foreach (var role in ROLE_ORDER)
            {
                GArray hs = shown.Filter(h => Kits.RoleOf(GD.Str(h)) == role);
                if (hs.IsEmpty())
                    continue;
                var rh = new HBoxContainer();
                rh.AddThemeConstantOverride("separation", 8);
                root.AddChild(rh);
                var bp = GD.Fmt("res://assets/ui/roles/%s.png", role);
                if (ResourceLoader.Exists(bp))
                {
                    var bi = UI2.Img(rh, bp, 30.0);
                    bi.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                }
                var rt = UI2.Text(rh, GD.Str(Kits.ROLE_NAMES.GetValueOrDefault(GD.Str(role), GD.Str(role))), 19, UI2.GOLD, UI2.INK, 5);
                rt.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var rs = UI2.Body(rh, GD.Str(Kits.ROLE_TEXT.GetValueOrDefault(GD.Str(role), "")), 10, UI2.SOFT, true);
                rs.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                rs.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var rsm = rs.CustomMinimumSize;
                rsm.x = 10;
                rs.CustomMinimumSize = rsm;
                var grid = new GridContainer();
                grid.Columns = GridCols(app, 128.0);          // (0.31.216: as many as the landscape screen takes; 3 in portrait)
                grid.AddThemeConstantOverride("h_separation", 8);
                grid.AddThemeConstantOverride("v_separation", 8);
                root.AddChild(grid);
                foreach (var hid in hs)
                    ChampionCard(app, grid, GD.Str(hid));
                if (hs.Size() < 3)                                  // (keep the cards a third wide)
                {
                    for (int i = 0; i < 3 - hs.Size(); i++)
                    {
                        var gap = new Control();
                        gap.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                        grid.AddChild(gap);
                    }
                }
            }
            var more = order.Size() - mine.Size();
            if (more > 0)
                _ToMarket(app, root, GD.Fmt("%d MORE HERO%s IN THE MARKET  ▸", more, more == 1 ? "" : "ES"), "heroes", "armory_to_heroes");
        }

        public static Button ChampionCard(SiegeApp app, Node grid, string hid)
        {
            var p = app.profile;
            Color acc = Champions.Accent(hid);
            bool owned = p.OwnsHero(hid);
            bool plays = p.CanPlayHero(hid);
            var b = new Button();
            b.Flat = true;
            b.FocusMode = Control.FOCUS_NONE;
            foreach (var st_name in new[] { "normal", "hover", "pressed", "focus" })
                b.AddThemeStyleboxOverride(st_name, new StyleBoxEmpty());
            b.CustomMinimumSize = new Vector2(0, 196);
            b.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            b.SetMeta("action_key", "champ_" + hid);
            b.Pressed += () => app.OpenChampion(hid, "__worn", true);     // (0.31.204: the Armory's -- his outfits you own)
            grid.AddChild(b);
            // the card: his place (cover), clipped to the rounded frame, darker toward the bottom for the name
            var card = new Panel();
            card.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            card.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            card.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            var sb = new StyleBoxFlat();
            sb.BgColor = acc.Darkened(0.8);
            sb.SetCornerRadiusAll(14);
            card.AddThemeStyleboxOverride("panel", sb);
            b.AddChild(card);
            var art = new TextureRect();
            var ap = Champions.CardArt(hid);
            art.Texture = ResourceLoader.Exists(ap) ? ResourceLoader.Load<Texture2D>(ap) : null;
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (!plays)
                art.Modulate = new Color(0.62, 0.62, 0.7);
            card.AddChild(art);
            var g = new Gradient();
            g.SetOffsets(new[] { 0.0, 0.5, 1.0 });
            g.SetColors(new[] { new Color(0, 0, 0, 0.0), new Color(0, 0, 0, 0.1), new Color(acc.Darkened(0.85), 0.95) });
            var gt = new GradientTexture2D();
            gt.Gradient = g;
            gt.Width = 4;
            gt.Height = 64;
            gt.FillTo = new Vector2(0, 1);
            var shade = new TextureRect();
            shade.Texture = gt;
            shade.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            shade.StretchMode = TextureRect.STRETCH_SCALE;
            shade.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            shade.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            card.AddChild(shade);
            // him, in the skin he wears
            string worn = p.WornSkin(hid);
            var pp = worn != "" ? GD.Fmt("res://assets/ui/skins/%s.png", worn) : GD.Fmt("res://assets/ui/skins/default_%s.png", hid);
            var por = new TextureRect();
            por.Texture = ResourceLoader.Exists(pp) ? ResourceLoader.Load<Texture2D>(pp) : null;
            por.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            por.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            por.AnchorRight = 1.0;
            por.OffsetLeft = 4;
            por.OffsetRight = -4;
            por.OffsetTop = 22;
            por.OffsetBottom = 142;
            por.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (!plays)
                por.Modulate = new Color(0.7, 0.7, 0.78);
            card.AddChild(por);
            var rim = new Panel();
            var rs = new StyleBoxFlat();
            rs.DrawCenter = false;
            rs.BorderColor = owned ? acc : new Color(acc.Darkened(0.25), 0.8);
            rs.SetBorderWidthAll(owned ? 3 : 2);
            rs.SetCornerRadiusAll(14);
            rim.AddThemeStyleboxOverride("panel", rs);
            rim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(rim);
            // his name and class
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", -2);
            v.AnchorTop = 1.0;
            v.AnchorBottom = 1.0;
            v.AnchorRight = 1.0;
            v.OffsetTop = -56;
            v.OffsetBottom = -6;
            v.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(v);
            var nl = UI2.Text(v, Champions.ShortOf(hid).ToUpperInvariant(), 17, Color.WHITE, acc.Darkened(0.75), 5);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            var cl = UI2.Body(v, GD.Str(Eco.SKIN_HEROES.Get(hid, hid)).ToUpperInvariant(), 9, acc.Lightened(0.5), false);
            cl.HorizontalAlignment = HorizontalAlignment.Center;
            // where he stands with you
            var st = new HBoxContainer();
            st.AddThemeConstantOverride("separation", 3);
            st.Alignment = BoxContainer.ALIGNMENT_CENTER;
            st.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            v.AddChild(st);
            // (0.31.204: the Armory has only yours -- the outfit he wears; 0.31.187-0.31.203 YOURS, or his price and a padlock)
            string wk = p.WornSkin(hid);
            if (!owned && plays)                          // 0.31.205: this week's free one
                UI2.Body(st, "FREE THIS WEEK", 9, new Color("#9dff8a"), false);
            else
                UI2.Body(st, (wk != "" ? GD.Str(Eco.SKINS[wk]["set"]).ToUpperInvariant() : "ORIGINAL LOOK"), 9, wk != "" ? new Color("#e8ccff") : new Color(1, 1, 1, 0.7), false);
            var chips = new VBoxContainer();                // (stacked down the left: the skins' count is on the right)
            chips.AddThemeConstantOverride("separation", 3);
            chips.Position = new Vector2(6, 6);
            chips.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(chips);
            if (!owned && plays)
                UI2.Chip(chips, "FREE", new Color("#2f8a3e"), Color.WHITE, new Color("#0a2006"));
            if (Eco.Launching(hid, p.Now()))
                UI2.Chip(chips, "NEW", new Color("#d9682a"), Color.WHITE, new Color("#3a1402"));
            if (!owned && p.ShardsOf(hid) > 0)
                UI2.Chip(chips, "◆", new Color("#173a1e"), new Color("#9dff8a"), new Color("#6be07c"));
            var nsk = Eco.SkinsOf(hid).Filter(id => p.OwnsSkin(GD.Str(id))).Size();     // (0.31.204: the ones you own)
            if (nsk > 0)
            {
                var sc = UI2.Chip(b, GD.Fmt("%d OUTFIT%s", nsk, nsk == 1 ? "" : "S"), new Color(0.05, 0.03, 0.12, 0.8), new Color("#e8ccff"), new Color("#c47bff"));
                sc.AnchorLeft = 1.0;
                sc.AnchorRight = 1.0;
                sc.OffsetLeft = -62;
                sc.OffsetRight = -6;
                sc.OffsetTop = 6;
                sc.OffsetBottom = 22;
                sc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            return b;
        }

        // + / − zoom buttons and the hint over an interactive showcase (the pass item view, 0.31.48; the locker, 0.31.64)
        public static void ZoomControls(Control stage, Showcase sh, string prefix)
        {
            var zc = new VBoxContainer();
            zc.AddThemeConstantOverride("separation", 10);
            zc.SetAnchorsAndOffsetsPreset(Control.PRESET_CENTER_RIGHT);
            zc.OffsetLeft = -58;
            zc.OffsetRight = -12;
            zc.OffsetTop = -50;
            zc.OffsetBottom = 50;
            stage.AddChild(zc);
            foreach (var zb in GArray.Of(GArray.Of("+", 1.3, prefix + "_zoom_in"), GArray.Of("−", 1.0 / 1.3, prefix + "_zoom_out")))
            {
                double zf = (double)zb[1];
                var b = UI2.Button(zc, GD.Str(zb[0]), "blue", () => sh.ZoomBy(zf), GD.Str(zb[2]), 24, 44.0, 22.0);
                b.CustomMinimumSize = new Vector2(44, 44);
                b.AddThemeFontOverride("font", UI.HEAVY_FONT);
            }
            var hint = UI2.Chip(stage, "DRAG TO TURN  ·  PINCH TO ZOOM", new Color(0.02, 0.03, 0.1, 0.75), new Color(1, 1, 1, 0.85), new Color(UI2.GOLD, 0.5));
            hint.AnchorLeft = 0.5;
            hint.AnchorRight = 0.5;
            hint.AnchorTop = 1.0;
            hint.AnchorBottom = 1.0;
            hint.OffsetLeft = -100;
            hint.OffsetRight = 100;
            hint.OffsetTop = -30;
            hint.OffsetBottom = -10;
        }

        public static void LockerRow(SiegeApp app, Node root, string id)
        {
            // A title card (0.31.87, Kevin picked the looks): the rarity's panel and rim, the name exactly as it shows over the
            // head (punctuated, the title in its rarity's colour), what earns it and how far along it is; EQUIP once earned.
            var p = app.profile;
            var it = Eco.Item(id);
            var rar = GD.Str(it["rarity"]);
            GDict goal = Eco.TITLE_GOALS.Get(id, Eco.PRIZE_TITLES.Get(id, new GDict())).D;     // (0.31.120: the leaderboard's titles)
            var c = UI2.Frame(root, _RarPanel(rar), 8, 16.0, _RarRim(rar), GDict.Of("pattern_mix", 0.0));
            var pc = c.GetParent() as Control;
            if (rar == "legendary")
                UI2.Sweep(pc, 2.6, 60.0, 0.3);
            var r = UI.Row(c, 10);
            var ic = new Control();
            ic.CustomMinimumSize = new Vector2(48, 48);
            ic.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            r.AddChild(ic);
            if (GArray.Of("epic", "legendary").Has(rar))
            {
                var rays = UI2.Rays(ic, 80.0, rar == "legendary" ? new Color(1, 0.85, 0.45) : new Color(0.8, 0.6, 1.0), 14.0, 0.5);
                rays.Position = new Vector2(24, 24) - new Vector2(40, 40);
            }
            var icn = UI2.Icon(ic, GD.Str(GDict.Of("common", "scroll", "rare", "banner", "epic", "trophy", "legendary", "crown").Get(rar, "scroll")), 46.0);
            icn.Position = new Vector2(1, 1);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 2);
            UI.Grow(v);
            r.AddChild(v);
            bool owned = p.Owns(id);
            var top = UI.Row(v, 6);
            UI2.Chip(top, rar.ToUpperInvariant(), Color.FromCode(GD.Str(Eco.RARITY_COLOR.Get(rar, "#b8c4c9"))), new Color("#120a02"));
            UI2.Body(top, owned ? "EARNED" : "LOCKED", 10, owned ? new Color("#8cf0a8") : new Color(1, 1, 1, 0.6), false);
            var nm = new HBoxContainer();
            nm.AddThemeConstantOverride("separation", 0);
            v.AddChild(nm);
            foreach (var part in Net.TitleParts(GD.Str(p.d["name"]), id))
                UI2.Text(nm, GD.Str(part[0]), 17, part[1] ? _RarTint(rar).Lightened(0.25) : Color.WHITE, new Color("#120a02"), 5);
            UI2.Body(v, GD.Str(goal.Get("task", "")), 11, new Color(1, 1, 1, 0.82), false);
            int n = (int)goal.Get("n", 1);
            int have = owned ? n : (Eco.PRIZE_TITLES.Has(id) ? 0 : GD.Mini(n, p.TitleProgress(id)));
            var pr = UI.Row(v, 6);
            var gold = rar == "legendary";
            UI2.Bar(pr, (double)have, (double)n, gold ? new Color("#fff3ad") : new Color("#b6f3ff"), gold ? new Color("#f0a024") : new Color("#36b9ea"), 10.0);
            UI2.Body(pr, GD.Fmt("%s / %s", _Thousands(have), _Thousands(n)), 11, Color.WHITE, false);
            if (owned)
            {
                bool eq = IsEquipped(p, id);
                var b = UI2.Button(r, eq ? "WORN" : "EQUIP", eq ? "grey" : "green", () => Equip(app, id), "equip_" + id, 13, 40.0, 12.0);
                b.Disabled = eq;
                var bm = b.CustomMinimumSize;
                bm.x = 74;
                b.CustomMinimumSize = bm;
                b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            }
        }

        public static string _Thousands(int n)
        {
            var s = GD.Str(GD.Absi(n));
            var out_ = "";
            while (s.Length > 3)
            {
                out_ = "," + s.Substr(s.Length - 3) + out_;
                s = s.Substr(0, s.Length - 3);
            }
            return (n < 0 ? "-" : "") + s + out_;
        }

        // ---------------- SETTINGS ----------------
        public static void PlayGamesCard(SiegeApp app, VBoxContainer root)
        {
            if (Platform.IsIos())
            {
                GameCenterCard(app, root);                       // 0.31.130
                return;
            }
            var gp = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(gp, "GOOGLE PLAY", 20);
            // (app.play_games is play_games.gd or game_center.gd -- one face: GameServices' IGameServices)
            var pg = app.play_games as IGameServices;
            var st = pg != null ? GD.Str(pg.state) : "off";
            var line = "";
            switch (st)
            {
                case "off":
                    line = "Sign in with Google Play to keep your progress in your Google account and take it to a new phone. Available in the Google Play version of Fatebound.";
                    break;
                case "out":
                    line = "Not signed in. Sign in to keep your progress in your Google account and take it to a new phone.";
                    break;
                case "signing":
                    line = "Signing in to Google Play...";
                    break;
                case "checking":
                    line = "Checking your Google Play save...";
                    break;
                case "synced":
                {
                    var who = GD.Str(pg.player);
                    line = GD.Fmt("Signed in%s. Your progress is backed up to your Google account%s.", who != "" ? " as " + who : "", _Ago(app, (int)pg.LastBackup()));
                    break;
                }
                case "ask":
                    line = "Google Play has different progress from this phone. Choose which one to keep.";
                    break;
                case "error":
                    line = (GD.Str(pg.why) != "" ? GD.Str(pg.why) : "Couldn't reach Google Play saves") + ". Your progress on this phone is safe.";
                    break;
            }
            UI2.Body(gp, line, 12, UI2.SOFT);
            switch (st)
            {
                case "out":
                    UI2.Button(gp, "SIGN IN WITH GOOGLE PLAY", "blue", () =>
                    {
                        app.Sfx("confirm");
                        pg.SignIn();
                    }, "play_sign_in", 15, 44.0);
                    break;
                case "synced":
                    UI2.Button(gp, "BACK UP NOW", "green", () =>
                    {
                        app.Sfx("confirm");
                        pg.BackUpNow();
                    }, "play_backup", 15, 44.0);
                    UI2.Button(gp, "ACHIEVEMENTS", "gold", () =>                // 0.31.119: Google Play Games' own screen
                    {
                        app.Sfx("menuOpen");
                        pg.ShowAchievements();
                    }, "play_achievements", 15, 44.0);
                    break;
                case "ask":
                    UI2.Button(gp, "CHOOSE", "gold", () =>
                    {
                        app.AskCloud();
                    }, "play_choose", 15, 44.0);
                    break;
                case "error":
                    UI2.Button(gp, "TRY AGAIN", "blue", () =>
                    {
                        app.Sfx("confirm");
                        pg.BackUpNow();
                    }, "play_retry", 15, 44.0);
                    break;
            }
        }

        public static void GameCenterCard(SiegeApp app, VBoxContainer root)
        {
            // 0.31.130 (the iOS port): Game Center -- signed in (achievements) or where to sign in. Apple allows no in-app sign-in
            // once a player has declined, so it points to iOS Settings. The progress itself is the Fatebound account's.
            var gp = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(gp, "GAME CENTER", 20);
            var pg = app.play_games as IGameServices;
            var st = pg != null ? GD.Str(pg.state) : "off";
            var line = "";
            switch (st)
            {
                case "off":
                    line = "Game Center isn't available in this build.";
                    break;
                case "signing":
                    line = "Signing in to Game Center...";
                    break;
                case "synced":
                {
                    var who = GD.Str(pg.player);
                    line = GD.Fmt("Game Center: signed in%s. Achievements are kept in Game Center.", who != "" ? " as " + who : "");
                    break;
                }
                default:
                    line = "Not signed in. Sign in from iOS Settings > Game Center to earn achievements.";
                    break;
            }
            UI2.Body(gp, line, 12, UI2.SOFT);
            if (st == "synced")
            {
                UI2.Button(gp, "ACHIEVEMENTS", "gold", () =>                    // Apple's own screen
                {
                    app.Sfx("menuOpen");
                    pg.ShowAchievements();
                }, "gc_achievements", 15, 44.0);
            }
        }

        public static void AccountCard(SiegeApp app, VBoxContainer root)
        {
            // 0.31.132 (the iOS port, IOS_PORT_SPEC_FOR_CLAUDE.md §4, §6): the Fatebound account -- the progress itself -- moved
            // between phones with a one-time code (Android and iPhone alike), and deleted from here (App Store 5.1.1(v)).
            var al = app.account_link;
            if (al == null)
                return;
            var ac = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(ac, "ACCOUNT", 20);
            bool has = al.HasAccount();
            UI2.Body(ac, has ? ("Your progress is kept in your Fatebound account on our server. Take it to another phone, Android or "
                + "iPhone, with a one-time code.") : "Your account is made the first time the game reaches our server.", 12, UI2.SOFT);
            var mv = UI2.Button(ac, "MOVE TO ANOTHER PHONE", "blue", () =>
            {
                app.Sfx("confirm");
                app.ShowMoveCode();
            }, "move_new", 15, 44.0);
            mv.Disabled = !has;
            UI2.Button(ac, "ENTER A CODE", "green", () =>
            {
                app.Sfx("confirm");
                app.EnterMoveCode();
            }, "move_enter", 15, 44.0);
            var dl = UI2.Button(ac, "DELETE ACCOUNT", "red", () =>
            {
                app.AskDeleteAccount();
            }, "account_delete", 13, 38.0);
            dl.Disabled = !has;
        }

        public static string _Ago(SiegeApp app, int at)
        {
            if (at <= 0)
                return "";
            int s = GD.Maxi(0, (int)app.profile.Now() - at);
            if (s < 60)
                return " (just now)";
            if (s < 3600)
                return GD.Fmt(" (%d min ago)", s / 60);
            if (s < 86400)
                return GD.Fmt(" (%d h ago)", s / 3600);
            return GD.Fmt(" (%d days ago)", s / 86400);
        }

        public static void Settings(SiegeApp app, VBoxContainer root)
        {
            // 0.31.79: a wooden sign with a turning gear, the profile on parchment, the career in tiles with the 3D icons, then
            // sound, graphics, the old game's progress and help.
            var p = app.profile;
            GDict d = p.d;
            var sign = new Control();
            sign.CustomMinimumSize = new Vector2(0, 66);
            root.AddChild(sign);
            var board = new HBoxContainer();
            board.Alignment = BoxContainer.ALIGNMENT_CENTER;
            board.AddThemeConstantOverride("separation", 10);
            board.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            sign.AddChild(board);
            sign.Resized += () =>
            {
                board.Size = new Vector2(260, 60);
                board.Position = new Vector2(((double)sign.Size.x - 260.0) * 0.5, 2);
            };
            UI2.Plate(board, "wood", 14.0, "gold", GDict.Of("rim", 4.0));
            var gear = UI2.Icon(board, "gear", 42.0);
            gear.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            UI2.Spin(gear, 14.0);
            UI2.Text(board, "SETTINGS", 30, UI2.GOLD).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            // Profile (parchment)
            var prof = UI2.Frame(root, "parch", 12, 16.0, "brown");
            var ink = new Color("#3b2412");
            var top = UI.Row(prof, 10);
            var shc = new Control();
            shc.CustomMinimumSize = new Vector2(48, 54);
            top.AddChild(shc);
            var sht = new TextureRect();
            sht.Texture = UI2.Tex(UI2.V2 + "shield.svg");
            sht.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            sht.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            sht.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            shc.AddChild(sht);
            var lvl = UI2.Text(shc, GD.Str((int)d["level"]), 22, Color.WHITE, new Color("#0e1433"), 5);
            lvl.HorizontalAlignment = HorizontalAlignment.Center;
            lvl.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            lvl.OffsetBottom = -6;
            var nv = new VBoxContainer();
            UI.Grow(nv);
            top.AddChild(nv);
            var yl = UI.Label(nv, "YOUR NAME", 10, new Color("#7a5530"), UI.HEAVY_FONT);
            yl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            var nr = UI.Row(nv, 8);
            var name_edit = new LineEdit();
            name_edit.Text = GD.Str(d["name"]);
            name_edit.MaxLength = 24;          // capped to 16 after trimming spaces (see SAVE)
            name_edit.PlaceholderText = "Your name";
            name_edit.AddThemeFontOverride("font", UI.HEAVY_FONT);
            name_edit.AddThemeFontSizeOverride("font_size", 16);
            name_edit.AddThemeColorOverride("font_color", ink);
            var es = new StyleBoxFlat();
            es.BgColor = new Color("#fffaf0");
            es.BorderColor = new Color("#5d3a1c");
            es.SetBorderWidthAll(3);
            es.SetCornerRadiusAll(10);
            es.ContentMarginLeft = 10;
            es.ContentMarginRight = 10;
            es.ContentMarginTop = 6;
            es.ContentMarginBottom = 6;
            name_edit.AddThemeStyleboxOverride("normal", es);
            name_edit.AddThemeStyleboxOverride("focus", es);
            UI.Grow(name_edit);
            nr.AddChild(name_edit);
            var sv = UI2.Button(nr, "SAVE", "green", () =>
            {
                var nm = name_edit.Text.StripEdges().Left(16);
                if (nm == "")
                    nm = "Player";
                p.SetName(nm);                             // (0.31.108: an op, so the server has it too)
                app.Sfx("confirm");
                app.Toast("Name saved", UI.CYAN);
                app.RefreshTop();
            }, "save_name", 16, 40.0, 11.0);
            var svm = sv.CustomMinimumSize;
            svm.x = 76;
            sv.CustomMinimumSize = svm;
            var xr = UI.Row(prof, 8);
            var xl = UI.Label(xr, GD.Fmt("LEVEL %d", (int)d["level"]), 11, ink, UI.HEAVY_FONT);
            xl.AutowrapMode = TextServer.AUTOWRAP_OFF;
            UI2.Bar(xr, (int)d["xp"], Eco.LevelXp((int)d["level"]), new Color("#b6f3ff"), new Color("#2b8fd6"), 12.0);
            var xv = UI.Label(xr, GD.Fmt("%d / %d XP", (int)d["xp"], Eco.LevelXp((int)d["level"])), 11, ink, UI.HEAVY_FONT);
            xv.AutowrapMode = TextServer.AUTOWRAP_OFF;
            // Google Play (0.31.102, Kevin: "Google play account linking to the game"): sign in, and the progress kept there
            PlayGamesCard(app, root);
            AccountCard(app, root);                               // 0.31.132: the account between phones
            // Career
            var car = UI2.Frame(root, "royal", 12, 18.0, "gold");
            UI2.Divider(car, "CAREER", 20);
            GDict st = d["stats"].D;
            var grid = new GridContainer();
            grid.Columns = app.ContentW() > 700.0 ? 8 : 6;          // (0.31.216: two rows across the landscape screen; 4 in portrait)
            grid.AddThemeConstantOverride("h_separation", 8);
            grid.AddThemeConstantOverride("v_separation", 8);
            car.AddChild(grid);
            var wins = (int)st["wins"];
            var matches = (int)st["matches"];
            // (0.31.164, 5v5 only: towers, last hits and jungle camps where King rescues, gathering and fish were)
            var tiles = GArray.Of(GArray.Of("swords", UI.Compact(matches), "MATCHES"), GArray.Of("trophy", UI.Compact(wins), "WINS"), GArray.Of("castle", UI.Compact((int)st.Get("towers", 0)), "TOWERS"),
                GArray.Of("skull", UI.Compact((int)st["kills"]), "KNOCKOUTS"), GArray.Of("anvil", UI.Compact((int)st["gates"] * 100), "TOWER DMG"), GArray.Of("helmet", UI.Compact((int)st.Get("lh", 0)), "LAST HITS"),
                GArray.Of("horn", UI.Compact((int)st.Get("camps", 0)), "CAMPS"), GArray.Of("banner", matches > 0 ? GD.Fmt("%d%%", (int)GD.Round(100.0 * wins / matches)) : "--", "WIN RATE"));
            var i = 0;
            foreach (var tdef in tiles)
            {
                var tc = new VBoxContainer();
                tc.AddThemeConstantOverride("separation", 0);
                tc.Alignment = BoxContainer.ALIGNMENT_CENTER;
                tc.CustomMinimumSize = new Vector2(0, 96);
                UI.Grow(tc);
                grid.AddChild(tc);
                UI2.Plate(tc, "glass", 14.0);
                var ic = UI2.Icon(tc, GD.Str(tdef[0]), 42.0);
                ic.SizeFlagsHorizontal = Control.SIZE_SHRINK_CENTER;
                UI2.Bob(ic, 2.5, 1.3 + (i % 3) * 0.2, i * 0.15);
                UI2.Center(UI2.Text(tc, GD.Str(tdef[1]), 19, Color.WHITE));
                UI2.Center(UI2.Body(tc, GD.Str(tdef[2]), 9, UI2.MUTED, false));
                i += 1;
            }
            // Sound
            var au = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(au, "SOUND", 20);
            foreach (var pair in GArray.Of(GArray.Of("master", "Master"), GArray.Of("sfx", "Effects"), GArray.Of("music", "Music")))
            {
                string key = GD.Str(pair[0]);
                var row = UI.Row(au, 10);
                var ll = UI2.Text(row, GD.Str(pair[1]).ToUpperInvariant(), 14, Color.WHITE);
                var llm = ll.CustomMinimumSize;
                llm.x = 76;
                ll.CustomMinimumSize = llm;
                var sl = new HSlider();
                sl.MinValue = 0.0;
                sl.MaxValue = 1.0;
                sl.Step = 0.05;
                sl.Value = (double)d["settings"].D.Get(key, 1.0);       // 0.31.110 (Kevin): every slider at 100% by default
                sl.SetMeta("action_key", "slider_" + key);
                sl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                UI2.StyleSlider(sl);
                UI.Grow(sl);
                row.AddChild(sl);
                var pv = UI2.Text(row, GD.Fmt("%d%%", (int)GD.Round(sl.Value * 100)), 14, UI2.GOLD);
                var pvm = pv.CustomMinimumSize;
                pvm.x = 44;
                pv.CustomMinimumSize = pvm;
                pv.HorizontalAlignment = HorizontalAlignment.Right;
                sl.ValueChanged += (double v) =>
                {
                    pv.Text = GD.Fmt("%d%%", (int)GD.Round(v * 100));
                    d["settings"].D[key] = v;
                    p.Save();
                    app._ApplyAudio();
                    app.Sfx("slider");                 // 0.31.110: a tiny tick a step, at the new level
                };
            }
            // 0.31.120 (Kevin: phone vibration): a buzz when you're hit, knock someone out, fall, or a King is rescued
            UI2.Toggle(au, "Vibration", "A buzz each time you knock out an enemy", (bool)d["settings"].D.Get("vibrate", true), "vibrate", (bool on) =>
            {
                app.Sfx("toggle");
                d["settings"].D["vibrate"] = on;
                p.Save();
                if (on)
                    Input.VibrateHandheld(60, 0.7);
            });
            // Social (0.31.111)
            var sx = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(sx, "SOCIAL", 20);
            UI2.Toggle(sx, "Global chat", "Everyone online; friends and party chat stay on", (bool)d["settings"].D.Get("chat_global", true), "chat_global", (bool on) =>
            {
                app.Sfx("toggle");
                d["settings"].D["chat_global"] = on;
                p.Save();
                if (app.social != null)
                    app.social.SetShowGlobal(on);
            });
            var soc2 = app.social;
            if (soc2 != null && soc2.Online())
            {
                var fc = UI.Row(sx, 8);
                var fcl = UI2.Body(fc, GD.Fmt("Your friend code: %s", Social.CodeOf(GD.Str(soc2.me.Get("pid", "")))), 13, UI2.SOFT, false);
                fcl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                fcl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var fb = UI2.Button(fc, "FRIENDS", "blue", () =>
                {
                    app.Sfx("menuOpen");
                    app.OpenFriends();
                }, "settings_friends", 13, 36.0, 11.0);
                var fbm = fb.CustomMinimumSize;
                fbm.x = 100;
                fb.CustomMinimumSize = fbm;
            }
            UI2.Body(sx, "Tap a name in the chat to add a friend, block or report them.", 11, UI2.MUTED);
            // 0.31.124 (Kevin: "Add the discord link to the game" + "give a reward for joining the discord")
            var cx = UI2.Frame(root, "night", 12, 18.0, "gold");
            cx.Name = "CommunityCard";
            UI2.Divider(cx, "COMMUNITY", 20);
            var claimed = (bool)d.Get("discord", false);
            UI2.Body(cx, "Join the Fatebound Discord: news, updates, events and other players to team up with." +
                (claimed ? "" : GD.Fmt(" Joining gives you %d gems, once.", Eco.DISCORD_GEMS)), 12, UI2.SOFT);
            var dlabel = claimed ? "JOIN OUR DISCORD" : GD.Fmt("JOIN OUR DISCORD  ·  +%d GEMS", Eco.DISCORD_GEMS);
            UI2.Button(cx, dlabel, "discord", () => DiscordPress(app), "discord", 15, 46.0);
            // 0.31.118 (Kevin's analytics spec): usage statistics to our own server, on by default, off here
            var px = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(px, "PRIVACY", 20);
            UI2.Toggle(px, "Share anonymous usage stats", "Sessions, matches and menu use -- never your name or chat", (bool)d["settings"].D.Get("analytics", true), "analytics", (bool on) =>
            {
                app.Sfx("toggle");
                d["settings"].D["analytics"] = on;
                p.Save();
                if (app.analytics != null)
                    app.analytics.SetEnabled(on);
            });
            UI2.Body(px, "Only to Fatebound's own server, tied to your game account's random id. Kept 90 days, never sold or shared.", 11, UI2.MUTED);
            // 0.31.119: notifications (the Play build's plugin; the preview APK has none)
            var nx = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(nx, "NOTIFICATIONS", 20);
            var nt = app.notify;
            bool can_notify = nt != null && nt.Available();
            var ntb = UI2.Toggle(nx, "Chest ready", can_notify ? "A notification when a chest has finished unlocking" : "Not in this version of the app",
                (bool)d["settings"].D.Get("notify", true) && can_notify, "notify", (bool on) =>
                {
                    app.Sfx("toggle");
                    d["settings"].D["notify"] = on;
                    d["settings"].D["notify_asked"] = true;
                    p.Save();
                    if (on && nt != null && !nt.HasPermission())
                        nt.RequestPermission();
                });
            ntb.Disabled = !can_notify;
            if (!can_notify)
                ntb.Modulate = new Color(1, 1, 1, 0.45);
            // Graphics
            var gx = UI2.Frame(root, "night", 12, 18.0, "gold");
            UI2.Divider(gx, "GRAPHICS", 20);
            // (0.31.163, Kevin: "Remove both": no High-quality graphics toggle -- always on, siege_app ignores a saved "off")
            UI2.Toggle(gx, "Reduce effects", "Smoother on older phones", (bool)d["settings"].D.Get("reduce_motion", false), "reduce_motion", (bool on) =>
            {
                app.Sfx("toggle");
                d["settings"].D["reduce_motion"] = on;
                p.Save();
            });
            // (0.31.123, Kevin: "Remove the progress from old version in the settings since Google play saves progress now":
            // the old version's paste-in import card is gone; a legacy save on the phone is still carried over by itself, once --
            // Profile.import_legacy at first launch)
            // Help
            // 0.31.120 (Kevin: SEND TO DEVELOPER): the log straight to the developer's server, asked every time
            UI2.Button(root, "SEND TO DEVELOPER", "orange", () => app.OpenSendDiag(), "send_diag", 15, 44.0);
            var help = new HBoxContainer();
            help.AddThemeConstantOverride("separation", 10);
            root.AddChild(help);
            if (Diag.HasLogs())
            {
                UI.Grow(UI2.Button(help, "COPY DIAGNOSTICS", "blue", () =>
                {
                    DisplayServer.ClipboardSet(Diag.ReadLogs());
                    app.Toast("Diagnostics copied", UI.CYAN);
                }, "copy_diag", 13, 40.0));
            }
            UI.Grow(UI2.Button(help, "PRIVACY POLICY", "blue", () => OS.ShellOpen(PRIVACY_URL), "privacy", 13, 40.0));
            // (0.31.112-0.31.163: HOW TO PLAY (TUTORIAL) -- Siege's walkthrough; gone with Siege, 0.31.164.) 0.31.181: the 5v5's
            UI2.Button(root, "HOW TO PLAY (TUTORIAL)", "blue", () =>
            {
                app.Sfx("confirm");
                app.StartTutorial();
            }, "settings_tutorial", 14, 44.0);
            var ver = UI2.Body(root, GD.Fmt("Fatebound %s", Diag.BUILD), 11, UI2.MUTED);
            ver.HorizontalAlignment = HorizontalAlignment.Center;
        }

        // ---------------- QUESTS (0.31.97, Kevin: "Build the quest system and I want quests for each class") ----------------
        // Every class has one quest (Eco.QUESTS): three steps claimed in order (0.31.188: the last pays gems and a Royal chest --
        // it gave the class's legendary weapon). The class picker shows a badge where a step is ready and a tick where the quest
        // is done; the hero stands in his own place in the outfit he wears (turn and zoom him); each step shows its task, how far
        // along it is, what it pays and CLAIM when it can be claimed.
        public const string QUEST_ICON = "res://assets/ui/v2/icons/quest.png";

        public static string QuestIconName()
        {
            return ResourceLoader.Exists(QUEST_ICON) ? "quest" : "crown";
        }

        public static HBoxContainer _RewardChips(Node parent, GDict r, Color? ink = null)
        {
            // the reward of a quest step as small pictures with their amounts
            var ink_ = ink ?? Color.WHITE;
            var row = new HBoxContainer();
            row.AddThemeConstantOverride("separation", 8);
            row.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(row);
            var parts = new GArray();
            foreach (var k in GArray.Of("gold", "gems", "chest"))
            {
                if (r.Has(k))
                    parts.Append(GDict.Of(k, r[k]));
            }
            foreach (var part0 in parts)
            {
                GDict part = part0.D;
                var rt = RewardText(part);
                var cell = new HBoxContainer();
                cell.AddThemeConstantOverride("separation", 3);
                row.AddChild(cell);
                if (GD.Str(rt[3]) != "")
                    UI2.Img(cell, GD.Str(rt[3]), 22.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                var t = GD.Str(rt[1]);
                if (part.Has("gold") || part.Has("gems"))
                    t = GD.Fmt("+%d", (int)part.Values()[0]);
                UI2.Body(cell, t, 11, ink_ == Color.WHITE ? (Color)rt[2] : ink_, false).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            }
            return row;
        }

        public static string QuestFirst(Profile p)
        {
            // the class to open the Quests screen on: one with a step ready, else the one played most, else the Knight
            foreach (var cls in Eco.QUESTS)
            {
                if (p.QuestReady(GD.Str(cls)) && GD.Str(cls) != "worker")
                    return GD.Str(cls);
            }
            var best = "knight";
            var most = 0;
            foreach (var cls in Eco.QUESTS)
            {
                if (GD.Str(cls) == "worker")
                    continue;
                var n = (int)p.d["stats"].D.Get(Eco.QuestKey(GD.Str(cls), "matches"), 0);
                if (n > most)
                {
                    most = n;
                    best = GD.Str(cls);
                }
            }
            return best;
        }

        public static void ClaimQuest(SiegeApp app, string cls)
        {
            var p = app.profile;
            GDict res = p.ClaimQuest(cls);
            if (!(bool)res.Get("ok", false))
                return;
            bool last = (int)res["step"] + 1 >= Eco.QUESTS[cls]["steps"].A.Size();
            app.Sfx(last ? "revealLegendary" : "claim");      // 0.31.110: the quest's end gets the golden choir
            app.RefreshTop();
            var bits = new GArray();
            foreach (var k in GArray.Of("gold", "gems"))
            {
                if ((int)res["reward"].D.Get(k, 0) > 0)
                    bits.Append(GD.Fmt("+%d %s", (int)res["reward"][k], GDict.Of("gold", "gold", "gems", "gems")[k]));
            }
            if (res["reward"].D.Has("chest"))
                bits.Append(GD.Fmt("a %s", GD.Str(Eco.CHESTS[GD.Str(res["reward"]["chest"])]["name"])));
            app.Toast(GD.Fmt(last ? "Quest complete! %s" : GD.Fmt("Quest step %d done: %s", (int)res["step"] + 1, "%s"), GStr.Join(", ", bits)), UI.GOLD);
            app.Rebuild();
        }

        public static void Quests(SiegeApp app, VBoxContainer root)
        {
            var p = app.profile;
            // the sign
            var sign = new Control();
            sign.CustomMinimumSize = new Vector2(0, 66);
            root.AddChild(sign);
            var board = new HBoxContainer();
            board.Alignment = BoxContainer.ALIGNMENT_CENTER;
            board.AddThemeConstantOverride("separation", 10);
            board.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            sign.AddChild(board);
            sign.Resized += () =>
            {
                board.Size = new Vector2(230, 60);
                board.Position = new Vector2(((double)sign.Size.x - 230.0) * 0.5, 2);
            };
            UI2.Plate(board, "wood", 14.0, "gold", GDict.Of("rim", 4.0));
            UI2.Icon(board, QuestIconName(), 46.0).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            UI2.Text(board, "QUESTS", 28, UI2.GOLD).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var back = UI2.Button(sign, "", "ghost", () =>
            {
                app.Sfx("menuClose");
                app.ShowTab("home");
            }, "quests_back", 14, 40.0, 12.0);
            back.Position = new Vector2(0, 12);
            back.Size = new Vector2(46, 40);
            UI.Icon(back, "home", 22, Color.WHITE).Position = new Vector2(12, 7);
            UI2.Center(UI2.Body(root, "Every class has a quest. Finish its three steps for gold, gems and a Royal chest.", 12, UI2.SOFT));
            // class picker: a badge where a step is ready, a tick where the quest is done
            string cls = Eco.QUESTS.Has(GD.Str(app.quest_cls)) && GD.Str(app.quest_cls) != "worker" ? app.quest_cls : QuestFirst(p);
            app.quest_cls = cls;
            var rail = UI2.Frame(root, "glass", 8, 18.0);
            foreach (var row_classes in new[] { Eco.HERO_CLASSES, Eco.UP_CLASSES })             // (0.31.164: no Worker -- Siege's)
            {
                var rr = new HBoxContainer();
                rr.Alignment = BoxContainer.ALIGNMENT_CENTER;
                rr.AddThemeConstantOverride("separation", 4);
                rail.AddChild(rr);
                foreach (var c0 in row_classes)
                {
                    string c = GD.Str(c0);
                    var cb = _ClassCoin(rr, c, cls == c, "quest_" + c, () =>
                    {
                        app.quest_cls = c;
                        app.Sfx("tap");
                        app.Rebuild();
                    }, "", 38.0);
                    if (p.QuestReady(c))
                        UI2.Badge(cb, "!", new Vector2(2, -4));
                    else if (p.QuestDone(c))
                    {
                        var tick = UI2.Chip(cb, "✔", new Color("#2f9e55"), Color.WHITE, new Color(1, 1, 1, 0.6));
                        tick.Position = new Vector2(16, -4);
                        tick.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                    }
                }
            }
            GDict q = Eco.QUESTS[cls].D;
            int step = p.QuestStep(cls);
            bool done = p.QuestDone(cls);
            // the hero, in his own place (0.31.188; it was the hero holding the legendary)
            var hero = new Control();
            hero.CustomMinimumSize = new Vector2(0, 300);
            root.AddChild(hero);
            var stage = new Control();
            stage.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            stage.OffsetLeft = 5;
            stage.OffsetTop = 5;
            stage.OffsetRight = -5;
            stage.OffsetBottom = -5;
            stage.ClipContents = true;
            hero.AddChild(stage);
            UI2.Plate(hero, "ember", 22.0, "orange", GDict.Of("rim", 4.0));
            var art = new TextureRect();
            var ap = Champions.Art(cls);
            art.Texture = ResourceLoader.Exists(ap) ? ResourceLoader.Load<Texture2D>(ap) : null;
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.OffsetTop = -110;
            art.OffsetBottom = 90;
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            stage.AddChild(art);
            var sh = new Showcase();
            sh.interactive = true;
            sh.plinth = false;
            sh.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            stage.AddChild(sh);
            sh.ShowLook(cls, p.LookFor(cls));
            ZoomControls(stage, sh, "quests");
            if (done)
            {
                var tag = UI2.Chip(stage, "QUEST COMPLETE", new Color("#2f9e55"), Color.WHITE, new Color(UI2.GOLD, 0.6));
                tag.Position = new Vector2(10, 8);
                tag.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            // the nameplate: who he is
            var np = UI2.Frame(root, "ember", 8, 16.0, "orange");
            var nm = UI2.Text(np, Champions.NameOf(cls).ToUpperInvariant(), 24, new Color("#ffd27a"), new Color("#3d1602"), 6);
            nm.HorizontalAlignment = HorizontalAlignment.Center;
            UI2.Sweep(np.GetParent() as Control, 2.6, 60.0, 0.3);
            var sub = GD.Fmt("%s  ·  QUEST %s", GD.Str(Eco.CLASS_NAMES[cls]).ToUpperInvariant(), done ? "COMPLETE" : GD.Fmt("STEP %d OF %d", step + 1, q["steps"].A.Size()));
            UI2.Center(UI2.Body(np, sub, 11, new Color("#ffe7c8"), false));
            var note = Eco.QuestNote(cls);
            if (note != "")
                UI2.Center(UI2.Body(np, note, 10, new Color(1, 1, 1, 0.7), false));
            // the steps
            for (int i = 0; i < q["steps"].A.Size(); i++)
                QuestStepCard(app, root, cls, i);
        }

        public static void QuestStepCard(SiegeApp app, Node root, string cls, int i)
        {
            var p = app.profile;
            GDict q = Eco.QUESTS[cls].D;
            GDict s = q["steps"][i].D;
            int step = p.QuestStep(cls);
            var claimed = i < step;
            var current = i == step;
            var n = (int)s["n"];
            int have = claimed ? n : GD.Mini(n, Eco.QuestProgress(p.d["stats"].D, cls, i));
            bool ready = current && have >= n;
            bool last = i == q["steps"].A.Size() - 1;
            var c = UI2.Frame(root, ready ? "royal" : (last && !claimed ? "ember" : "night"), 8, 16.0,
                ready ? "gold" : (last ? "orange" : "silver"), GDict.Of("pattern_mix", 0.0, "dim", claimed ? 0.3 : 0.0));
            if (ready)
                UI2.Sweep(c.GetParent() as Control, 2.2, 60.0, 0.35);
            var r = UI.Row(c, 10);
            // the step's number (a tick once claimed)
            var disc = new Control();
            disc.CustomMinimumSize = new Vector2(40, 40);
            disc.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            r.AddChild(disc);
            UI2.Plate(disc, !claimed ? "royal" : "night", 20.0, (current || claimed) ? "gold" : "silver", GDict.Of("rim", 2.0));
            var dl = UI2.Text(disc, claimed ? "✔" : GD.Str(i + 1), 18, current ? UI2.CYAN : Color.WHITE, UI2.INK, 4);
            dl.HorizontalAlignment = HorizontalAlignment.Center;
            dl.VerticalAlignment = VerticalAlignment.Center;
            dl.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 3);
            UI.Grow(v);
            r.AddChild(v);
            UI2.Text(v, GD.Str(s["task"]), 14, !claimed ? Color.WHITE : new Color(1, 1, 1, 0.65), UI2.INK, 4).AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            var pr = UI.Row(v, 6);
            bool gold = last;
            UI2.Bar(pr, (double)have, (double)n, gold ? new Color("#fff3ad") : new Color("#b6f3ff"), gold ? new Color("#f0a024") : new Color("#36b9ea"), 10.0);
            UI2.Body(pr, GD.Fmt("%s / %s", _Thousands(have), _Thousands(n)), 11, Color.WHITE, false);
            var rw = UI.Row(v, 6);
            UI2.Body(rw, claimed ? "CLAIMED" : (!last ? "REWARD" : "FINAL REWARD"), 9, claimed ? new Color("#8cf0a8") : new Color(1, 1, 1, 0.6), false);
            _RewardChips(rw, Eco.QuestReward(cls, i));
            if (ready)
            {
                var b = UI2.Button(r, "CLAIM", "gold", () => ClaimQuest(app, cls), "quest_claim_" + cls, 14, 42.0, 12.0);
                var bm = b.CustomMinimumSize;
                bm.x = 80;
                b.CustomMinimumSize = bm;
                b.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                UI2.Pulse(b, 0.03, 1.0);
            }
            else if (i > step)
                UI2.Body(r, GD.Fmt("after step %d", (i)), 10, new Color(1, 1, 1, 0.5), false).SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
        }
    }
}
