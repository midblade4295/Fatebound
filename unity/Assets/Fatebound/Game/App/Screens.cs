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
            if ((bool)Var.Of(app.safe_boot) && !(bool)Var.Of(app.GetMeta("safe_note", false)))
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

        // @@CONTINUE@@
    }
}
