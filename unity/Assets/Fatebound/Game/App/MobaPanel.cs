// Ported from godot/scripts/app/moba_panel.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Color = Fatebound.GUI.Col;
using UI = Fatebound.Game.Ui;
using UI2 = Fatebound.Game.Ui2;
using SocialUI = Fatebound.Game.SocialUi;
using Moba = Fatebound.Sim.Moba;
using Kits = Fatebound.Sim.MobaKits;      // 0.31.167: roles and kits
using Eco = Fatebound.Game.Economy;
using Hud = Fatebound.Game.SiegeHud;         // 0.31.171: the ability icons

namespace Fatebound.Game
{
    // 0.31.155 5V5 (the test; scripts/siege/moba.gd): pick your hero, then BATTLE -- an offline 5v5 with bots on both sides
    // (siege_app.start_moba). Twelve heroes: the six classes and their six upgrades. The last pick is kept on the phone
    // (settings.moba_hero). 0.31.167: by role, each card's role on it, and the picked hero's role and kit (Q W E R) under
    // the grid. 0.31.168 (Kevin: six new heroes, "Unlock with gold"): eighteen, as a table of League's six roles -- a column
    // each, three heroes in it (the class, its upgrade, the new one); the new six cost gold (economy.gd HERO_PRICES, the
    // profile's "heroes"): a locked card shows its price, and picking one turns BATTLE into UNLOCK.
    // 0.31.185 (Kevin: "I want the same IAP system as league of legends"): this week's two free heroes play like your own
    // (FREE on the card); UNLOCK opens a chooser over the window (League's "unlock with Blue Essence or RP"): the gold, the
    // gems, a hero shard (at Eco.SHARD_UNLOCK of the gold) or a Hero Token; beside BATTLE, UNLOCK for a free one and MELT for
    // a shard of a hero you own. Your Hero Tokens and shards beside PICK YOUR HERO (a ◆ on a card: a shard of him).
    // 0.31.204 (Kevin: "put a hero tab in the market ... that's where they will purchase them"; asked about this window: "Send
    // to Market"): heroes are bought in the Market's HEROES -- a locked hero's BATTLE is GET IN MARKET, and beside BATTLE a
    // free one has MARKET; both open the Market's HEROES with his card lit (siege_app.open_market). The chooser is gone from
    // here (screens.gd buy_hero has it); MELT stays (a shard of a hero you own, for gold).
    public class MobaPanel : Control
    {
        public static readonly GDict ROLE_COL = new GDict { { "tank", "#6fa8dc" }, { "fighter", "#e06666" }, { "assassin", "#a48ae0" }, { "mage", "#f6a24b" }, { "marksman", "#8fd16f" },
            { "support", "#ffd966" } };
        public const string COIN = "res://assets/ui/currency/coin.png";
        public const string GEM = "res://assets/ui/currency/gem.png";
        // 0.31.175 (Kevin: "Use eleven or meshy to make these menus better looking and more high quality"): ElevenLabs paintings
        // (tools/build_menu_icons.py) -- the champions' hall the picked hero stands in, the six role badges over the columns,
        // the padlock on a hero still to unlock
        public const string HALL = "res://assets/ui/menu/hero_hall.webp";
        public const string LOCK = "res://assets/ui/menu/lock.png";
        public const double STAGE_H = 136.0;

        public const double CARD_W = 54.0;
        public const double CARD_H = 64.0;          // (72 in portrait)
        public static readonly GDict LOOK = new GDict { { "knight", "knight" }, { "barbarian", "barbarian" }, { "rogue", "rogue" }, { "ranger", "ranger" }, { "mage", "mage" }, { "priest", "priest" },
            { "crusader", "crusader" }, { "berserker", "berserker" }, { "assassin", "assassin" }, { "sniper", "sniper" }, { "archmage", "archmage" }, { "necromancer", "necromancer" },
            { "golem", "golem" }, { "dragoon", "dragoon" }, { "duelist", "duelist" }, { "stormcaller", "stormcaller" }, { "musketeer", "musketeer" }, { "druid", "druid" } };

        public SiegeApp app;
        public string hero = "knight";
        public GridContainer _grid;
        public Button _go;
        public Button _side;               // 0.31.185: beside BATTLE -- UNLOCK (one free this week); 0.31.204: MARKET
        public Button _melt;               // ... or MELT (a shard of one you own)
        public Label _inv;                  // 0.31.185: the Hero Tokens and shards you hold
        public VBoxContainer _kit;          // 0.31.171: the kit, a row per ability with its icon
        public Showcase _show;                        // 0.31.175: the stage -- the hero in 3D on the hall's dais, his name, role and price
        public Label _stage_name;
        public Label _stage_role;
        public TextureRect _stage_badge;
        public Label _stage_text;
        public HBoxContainer _stage_lock;
        public Label _stage_price;
        public Label _stage_free;           // 0.31.185: FREE THIS WEEK (the rotation)
        public Button _skin_btn;            // 0.31.186: the skin he wears -- tap for the next one you own (his own look among them)

        public static Texture2D RoleBadge(string role)
        {
            var p = GD.Fmt("res://assets/ui/roles/%s.png", role);
            return ResourceLoader.Exists(p) ? ResourceLoader.Load<Texture2D>(p) : null;
        }

        public static Texture2D _Tex(string p)
        {
            return ResourceLoader.Exists(p) ? ResourceLoader.Load<Texture2D>(p) : null;
        }

        public static string Portrait(string hid)
        {
            return GD.Fmt("res://assets/ui/skins/default_%s.png", GD.Str(LOOK.Get(hid, "knight")));
        }

        public bool _Owns(string hid)
        {
            return app.profile.OwnsHero(hid);
        }

        public bool _Plays(string hid)
        {
            // yours, or free this week (0.31.185)
            return app.profile.CanPlayHero(hid);
        }

        public void Open(SiegeApp a)
        {
            app = a;
            var saved = GD.Str(app.profile.d["settings"].Get("moba_hero", ""));
            hero = Moba.HEROES.ContainsKey(saved) && _Plays(saved) ? saved : "knight";
            var w = SocialUI.Window(this, "5V5", "swords", () =>
            {
                app.Sfx("menuClose");
                app.CloseModal();
            }, 6.0 + (double)app.safe_top, 8.0);       // (0.31.216: the whole screen, as Honor of Kings' hero select)
            VBoxContainer sheet = w["body"].As<VBoxContainer>();
            // 0.31.216 (landscape, Honor of Kings' hero select): the picked hero on his stage and his kit on the left, the heroes to
            // pick from and BATTLE on the right (one column in portrait)
            var cols = new HBoxContainer();
            cols.AddThemeConstantOverride("separation", 12);
            cols.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            sheet.AddChild(cols);
            var left = new VBoxContainer();
            left.AddThemeConstantOverride("separation", 6);
            left.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            left.SizeFlagsStretchRatio = 0.85;
            cols.AddChild(left);
            var body = new VBoxContainer();
            body.AddThemeConstantOverride("separation", 8);
            body.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            cols.AddChild(body);
            // (0.31.155-0.31.163: "TEST MODE" -- 0.31.164, Kevin: "5v5 only": it's the game's match now, PLAY opens this)
            // (0.31.165: the Rift -- three towers a lane, a keep with a gate at each lane's end and two King towers inside;
            // 0.31.166: the Grave Wyrm)
            // (0.31.170: online -- the players in the match and bots in the seats nobody has taken)
            _BuildStage(left);
            _kit = new VBoxContainer();
            _kit.AddThemeConstantOverride("separation", 3);
            left.AddChild(_kit);
            // (0.31.175: the match said shorter -- the stage took its room; 0.31.216 shorter still -- the kit's under the stage)
            UI2.Body(left, "Five a side, bots in the empty seats. Break a lane's three towers, then defeat their King.",     // (0.31.217)
                9, UI2.SOFT);
            var ph = UI.Row(body, 8);
            UI2.Text(ph, "PICK YOUR HERO", 16, UI2.GOLD);
            _inv = UI2.Body(ph, "", 10, Color.FromCode("#c9f7bd"));
            _inv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _inv.HorizontalAlignment = HorizontalAlignment.Right;
            _inv.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            var holder = new CenterContainer();
            holder.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            body.AddChild(holder);
            _grid = new GridContainer();
            _grid.Columns = Kits.ROLE_ORDER.Length;
            _grid.AddThemeConstantOverride("h_separation", 4);
            _grid.AddThemeConstantOverride("v_separation", 5);
            holder.AddChild(_grid);
            var gap = new Control();
            gap.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            gap.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            body.AddChild(gap);
            var foot = UI.Row(body, 8);
            _go = UI2.Button(foot, "BATTLE", "orange", _OnGo, "moba_battle", 22, 52.0, 16.0);
            _go.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            UI2.Sweep(_go);
            _side = UI2.Button(foot, "MARKET", "gold", _ToMarket, "moba_side_market", 16, 52.0, 16.0, "res://assets/ui/v2/icons/stall.png");
            { var cm = _side.CustomMinimumSize; cm.x = 120; _side.CustomMinimumSize = cm; }
            _melt = UI2.Button(foot, "MELT", "green", () => _UnlockBy("melt"), "moba_melt_shard", 15, 52.0, 16.0, COIN);
            { var cm = _melt.CustomMinimumSize; cm.x = 132; _melt.CustomMinimumSize = cm; }
            _Render();
        }

        public void _BuildStage(VBoxContainer body)
        {
            // (0.31.216: on the left of the window, as tall as it can be)
            // 0.31.175: the picked hero, in 3D and idling, on the dais of the painted champions' hall; his name, role badge,
            // what the role does, and the price while he's locked, on the hall's dark right side
            var st = new Panel();
            st.CustomMinimumSize = new Vector2(0, STAGE_H);
            st.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            st.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var sb = new StyleBoxFlat();
            sb.BgColor = new Color(0.04, 0.03, 0.06);
            sb.SetCornerRadiusAll(12);
            st.AddThemeStyleboxOverride("panel", sb);
            st.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            body.AddChild(st);
            var hall = new TextureRect();
            hall.Texture = _Tex(HALL);
            hall.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            hall.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            hall.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            hall.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            st.AddChild(hall);
            var rim = new Panel();                 // (a thin gold rim over the painting's edge)
            var rs = new StyleBoxFlat();
            rs.DrawCenter = false;
            rs.BorderColor = Color.FromCode("#c99a3a");
            rs.SetBorderWidthAll(2);
            rs.SetCornerRadiusAll(12);
            rim.AddThemeStyleboxOverride("panel", rs);
            rim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            _show = new Showcase();
            _show.plinth = false;
            _show.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            st.AddChild(_show);
            var info = new VBoxContainer();
            info.AddThemeConstantOverride("separation", 3);
            info.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            st.AddChild(info);
            _stage_name = UI2.Text(info, "", 24, Color.WHITE, Color.FromCode("#120a20"));
            var rr = new HBoxContainer();
            rr.AddThemeConstantOverride("separation", 5);
            rr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            info.AddChild(rr);
            _stage_badge = new TextureRect();
            _stage_badge.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            _stage_badge.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            _stage_badge.CustomMinimumSize = new Vector2(26, 26);
            _stage_badge.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            rr.AddChild(_stage_badge);
            _stage_role = UI2.Text(rr, "", 15, Color.WHITE, Color.FromCode("#120a20"));
            _stage_text = UI2.Body(info, "", 10, Color.FromCode("#e8dcc8"));
            _stage_text.CustomMinimumSize = new Vector2(150, 0);
            _stage_lock = new HBoxContainer();
            _stage_lock.AddThemeConstantOverride("separation", 4);
            _stage_lock.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            info.AddChild(_stage_lock);
            foreach (var t in new[] { LOCK, COIN })
            {
                var ic = new TextureRect();
                ic.Texture = _Tex(t);
                ic.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                ic.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
                ic.CustomMinimumSize = new Vector2(20, 20);
                ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                _stage_lock.AddChild(ic);
                if (t == LOCK)
                    _stage_lock.MoveChild(ic, 0);
            }
            _stage_price = UI2.Text(_stage_lock, "", 15, Color.FromCode("#ffd65a"), Color.FromCode("#201002"));
            _stage_lock.MoveChild(_stage_price, 2);
            _stage_free = UI2.Text(info, "FREE THIS WEEK", 13, Color.FromCode("#9dff8a"), Color.FromCode("#0a2006"));
            st.AddChild(rim);
            _skin_btn = UI2.Button(st, "", "blue", _NextSkin, "moba_skin", 10, 26.0, 9.0);
            st.Resized += () =>
            {
                // the hall's dais is at ~23 % across, its top ~76 % down the painting (cover-scaled to the stage's width): the
                // hero's feet (78 % down his frame) on it
                double w = st.Size.x;
                var hh = w * 0.5;
                var dais = new Vector2(w * 0.235, hh * 0.755 - (hh - st.Size.y) * 0.5);
                var fh = 176.0;
                _show.Size = new Vector2(150, fh);
                _show.Position = new Vector2(dais.x - 75.0, dais.y - fh * 0.78);
                info.Position = new Vector2(w * 0.47, 14);
                { var cm = _stage_text.CustomMinimumSize; cm.x = (float)(w * 0.53 - 14); _stage_text.CustomMinimumSize = cm; }
                info.Size = new Vector2(w * 0.53 - 10, 0);
                _skin_btn.Size = new Vector2(GD.Minf(150.0, w * 0.42), 26);
                _skin_btn.Position = new Vector2(8, st.Size.y - 32);
            };
        }

        public void _RenderStage()
        {
            var role = Kits.RoleOf(hero);
            _stage_name.Text = Moba.HEROES[hero].name.ToUpperInvariant();
            _stage_role.Text = Kits.ROLE_NAMES.GetValueOrDefault(role, "");
            _stage_role.AddThemeColorOverride("font_color", Color.FromCode(GD.Str(ROLE_COL.Get(role, "#ffffff"))).Lightened(0.25));
            _stage_badge.Texture = RoleBadge(role);
            _stage_text.Text = Kits.ROLE_TEXT.GetValueOrDefault(role, "");
            var owned = _Owns(hero);
            _stage_free.Visible = !owned && _Plays(hero);       // (in the price's place: UNLOCK beside BATTLE has the prices)
            _stage_lock.Visible = !owned && !_stage_free.Visible;
            _stage_price.Text = UI.Grouped((int)app.profile.HeroPrice(hero).Get("gold", 0));
            if (_show != null)
            {
                _show.ShowLook(hero, app.profile.LookFor(hero));     // 0.31.186: in the outfit he wears (0.31.188: its weapon too)
                _show.Modulate = _Plays(hero) ? Color.WHITE : new Color(0.62, 0.62, 0.7);
            }
            // 0.31.186: SKIN -- shown when you own one of his
            GArray mine = Eco.SkinsOf(hero).Filter(id => app.profile.OwnsSkin(GD.Str(id)));
            _skin_btn.Visible = !mine.IsEmpty() && _Owns(hero);
            string w2 = app.profile.WornSkin(hero);
            _skin_btn.Text = "OUTFIT: " + (w2 != "" ? GD.Str(Eco.SKINS[w2]["set"]).ToUpperInvariant() : "DEFAULT") + "  ▸";
        }

        public void _OnGo()
        {
            if (!_Plays(hero))
            {
                // 0.31.168: UNLOCK (0.31.185: the chooser -- gold, gems, a shard or a Hero Token). 0.31.204: the Market sells him
                _ToMarket();
                return;
            }
            app.profile.d["settings"].D["moba_hero"] = hero;
            app.profile.Save();
            app.Sfx("confirm");
            app.CloseModal();
            app.StartMoba(hero);
        }

        public static GArray RoleTable()
        {
            // the grid's cells in reading order: a header per role, then the heroes row by row (each role's in HERO_ORDER)
            var cols = new List<List<string>>();
            foreach (var role in Kits.ROLE_ORDER)
                cols.Add(new List<string>(Array.FindAll(Moba.HERO_ORDER, h => Kits.RoleOf(GD.Str(h)) == role)));
            var @out = new GArray();
            foreach (var role in Kits.ROLE_ORDER)
                @out.Append("#" + role);
            var rows = 0;
            foreach (var c in cols)
                rows = GD.Maxi(rows, c.Count);
            for (int r = 0; r < rows; r++)
            {
                foreach (var c in cols)
                    @out.Append(r < c.Count ? GD.Str(c[r]) : "");
            }
            return @out;
        }

        public void _Render()
        {
            foreach (var c in _grid.GetChildren())
            {
                _grid.RemoveChild(c);
                c.QueueFree();
            }
            // 0.31.168: a column per role (TANK, FIGHTER, ASSASSIN, MAGE, MARKSMAN, SUPPORT) under its name
            foreach (var cell in RoleTable())
            {
                var id = GD.Str(cell);
                if (id.BeginsWith("#"))
                    _grid.AddChild(_RoleHead(id.Substr(1)));
                else if (id == "")
                {
                    var gap = new Control();
                    gap.CustomMinimumSize = new Vector2(CARD_W, CARD_H);
                    _grid.AddChild(gap);
                }
                else
                    _grid.AddChild(_Card(id));
            }
            var lines = KitLines(hero);
            _inv.Text = InventoryText(app.profile);
            _inv.Visible = _inv.Text != "";
            _RenderStage();
            foreach (var c in _kit.GetChildren())
            {
                _kit.RemoveChild(c);
                c.QueueFree();
            }
            for (int i = 0; i < 4; i++)
                _kit.AddChild(_KitRow(hero, new[] { "q", "w", "e", "r" }[i], GD.Str(lines[i + 1])));
            _go.Disabled = false;
            _go.Text = _Plays(hero) ? "BATTLE" : "GET IN MARKET";
            // 0.31.185: beside it, UNLOCK for one free this week (0.31.204: MARKET), MELT for a shard of one you own
            var p = app.profile;
            _side.Visible = _Plays(hero) && !_Owns(hero);
            _melt.Visible = _Owns(hero) && p.ShardsOf(hero) > 0;
            _melt.Text = GD.Fmt("MELT +%s", UI.Grouped(Eco.ShardMeltGold(hero, p.Now())));
        }

        public void _NextSkin()
        {
            // 0.31.186: his own look, then each skin of his you own, round and round
            var p = app.profile;
            GArray cycle = GArray.Of("");
            cycle.AppendArray(Eco.SkinsOf(hero).Filter(id => p.OwnsSkin(GD.Str(id))));
            var i = cycle.Find(p.WornSkin(hero));
            p.WearSkin(hero, GD.Str(cycle[(i + 1) % cycle.Size()]));
            app.Sfx("equip");
            _RenderStage();
        }

        public static string InventoryText(Profile p)
        {
            // "HERO TOKEN x1  ·  ◆ SHARDS 2" (which heroes: the ◆ on their cards; this week's free ones: FREE on theirs)
            var bits = new GArray();
            if ((int)p.d.Get("tokens", 0) > 0)
                bits.Append(GD.Fmt("HERO TOKEN x%d", (int)p.d["tokens"]));
            var n = p.d.Get("shards", new GArray()).Size();
            if (n > 0)
                bits.Append(GD.Fmt("◆ SHARD%s %d", n > 1 ? "S" : "", n));
            return GStr.Join("  ·  ", bits);
        }

        public void _ToMarket()
        {
            // 0.31.204: the Market's HEROES, his card lit -- heroes are bought there
            app.Sfx("tab");
            app.OpenMarket("heroes", hero);
        }

        public void _UnlockBy(string how)
        {
            // (0.31.204: only MELT is left here -- a shard of a hero you own, for gold)
            var p = app.profile;
            GDict r = how == "melt" ? p.MeltShard(hero) : new GDict { { "ok", false } };
            if ((bool)r.Get("ok", false))
            {
                app.Sfx("purchase");
                app.Toast(GD.Fmt("Shard melted: +%s gold", UI.Grouped((int)r.Get("gold", 0))), UI2.GOLD);
                app.RefreshTop();
            }
            else
            {
                app.Sfx("error");
                app.Toast(GD.Str(r.Get("error", "Can't unlock")), Color.FromCode("#ff8a7a"));
            }
            _Render();
        }

        public static string KitText(string hid)
        {
            return GStr.Join("\n", KitLines(hid));
        }

        public static GArray KitLines(string hid)
        {
            // the hero's role, then his kit: Q, W (level 2), E (level 3), R (level 6)
            var role = Kits.RoleOf(hid);
            var lines = GArray.Of(GD.Fmt("%s · %s -- %s", Moba.HEROES[hid].name.ToUpperInvariant(), Kits.ROLE_NAMES.GetValueOrDefault(role, ""),
                Kits.ROLE_TEXT.GetValueOrDefault(role, "")));
            var q = Kits.Kit(hid, "q");
            lines.Append(GD.Fmt("Q %s: %s", q != null && q.name != null ? q.name : "", q != null && q.text != null ? q.text : Moba.HERO_LINE.GetValueOrDefault(hid, "")));
            foreach (var slot in new[] { "w", "e" })
            {
                var k = Kits.Kit(hid, slot);
                lines.Append(GD.Fmt("%s %s (lv %d): %s", slot.ToUpperInvariant(), k != null && k.name != null ? k.name : "", Kits.UNLOCK[slot], k != null && k.text != null ? k.text : ""));
            }
            var u = Moba.ULTS.GetValueOrDefault(hid);
            lines.Append(GD.Fmt("R %s (lv %d): %s", u != null && u.name != null ? u.name : "", Moba.ULT_LEVEL, u != null && u.text != null ? u.text : ""));
            return lines;
        }

        public Control _KitRow(string hid, string slot, string line)
        {
            // 0.31.171: the ability's icon (the HUD's button) beside its line
            var row = new HBoxContainer();
            row.AddThemeConstantOverride("separation", 6);
            row.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var ic = new TextureRect();
            ic.Texture = Hud.AbilityIcon(hid, slot);
            ic.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            ic.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            ic.CustomMinimumSize = new Vector2(30, 30);
            ic.SizeFlagsVertical = Control.SIZE_SHRINK_BEGIN;
            ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            row.AddChild(ic);
            var l = UI2.Body(row, line, 10, Color.WHITE);
            l.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            l.CustomMinimumSize = new Vector2(10, 0);
            return row;
        }

        public Control _RoleHead(string role)
        {
            // 0.31.175: the role's painted badge and its name (was a coloured strip with the name in 5-8 px)
            var c = new Control();
            c.CustomMinimumSize = new Vector2(CARD_W, 33);
            c.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var b = new TextureRect();
            b.Texture = RoleBadge(role);
            b.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            b.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            b.Position = new Vector2((CARD_W - 22.0) * 0.5, 0);
            b.Size = new Vector2(22, 22);
            b.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            c.AddChild(b);
            var nm = Kits.ROLE_NAMES.GetValueOrDefault(role, "");
            var fs = 9;
            while (fs > 6 && UI2.LG.GetStringSize(nm, HorizontalAlignment.Left, -1, fs).x > CARD_W - 2.0)
                fs -= 1;
            var rl = UI2.Text(c, nm, fs, Color.FromCode(GD.Str(ROLE_COL.Get(role, "#ffffff"))).Lightened(0.2), Color.FromCode("#120a20"), 2, false);
            rl.HorizontalAlignment = HorizontalAlignment.Center;
            rl.Position = new Vector2(-2, 21);
            rl.Size = new Vector2(CARD_W + 4, 12);
            return c;
        }

        public static GDict _glows = new GDict();

        public static Texture2D _Glow(string role)
        {
            // a soft light behind a card's portrait in its role's colour
            if (!_glows.Has(role))
            {
                var g = new Gradient();
                var c = Color.FromCode(GD.Str(ROLE_COL.Get(role, "#ffffff")));
                g.SetColor(0, new Color(c, 0.75));
                g.SetColor(1, new Color(c.Darkened(0.6), 0.0));
                var gt = new GradientTexture2D();
                gt.Gradient = g;
                gt.Fill = GradientTexture2D.FillEnum.Radial;
                gt.FillFrom = new Vector2(0.5, 0.42);
                gt.FillTo = new Vector2(0.5, 1.05);
                gt.Width = 64;
                gt.Height = 96;
                _glows[role] = Var.Of(gt);
            }
            return _glows[role].As<Texture2D>();
        }

        public Control _Card(string hid)
        {
            // 0.31.175: on a dark ground in its role's colour with a glow behind the portrait; a hero to unlock dimmed, with
            // the padlock and his price in gold; the picked one in a gold frame with a tick
            var on = hid == hero;
            var owned = _Plays(hid);             // (0.31.185: a free one this week shows as playable, FREE on it)
            var free = owned && !_Owns(hid);
            var role = Kits.RoleOf(hid);
            var rim = Color.FromCode(GD.Str(ROLE_COL.Get(role, "#5a6470")));
            var b = new Button();
            b.FocusMode = Control.FOCUS_NONE;
            b.CustomMinimumSize = new Vector2(CARD_W, CARD_H);
            b.SetMeta("action_key", "moba_hero_" + hid);
            var sb = new StyleBoxFlat();
            sb.BgColor = owned ? rim.Darkened(0.82) : new Color(0.06, 0.06, 0.08);
            sb.BorderColor = on ? Color.FromCode("#ffc23d") : (owned ? rim.Darkened(0.1) : Color.FromCode("#3a3f48"));
            sb.SetBorderWidthAll(on ? 3 : 2);
            sb.SetCornerRadiusAll(8);
            if (on)
            {
                sb.ShadowColor = new Color(1.0, 0.78, 0.25, 0.55);
                sb.ShadowSize = 5;
            }
            foreach (var st in new[] { "normal", "hover", "pressed", "focus", "hover_pressed", "disabled" })
                b.AddThemeStyleboxOverride(st, sb);
            var glow = new TextureRect();
            glow.Texture = _Glow(role);
            glow.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            glow.StretchMode = TextureRect.STRETCH_SCALE;
            glow.Position = new Vector2(3, 3);
            glow.Size = new Vector2(CARD_W - 6, CARD_H - 6);
            glow.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            glow.Modulate = new Color(1, 1, 1, owned ? 0.9 : 0.25);
            b.AddChild(glow);
            var tex = new TextureRect();
            var p = Portrait(hid);
            tex.Texture = ResourceLoader.Exists(p) ? ResourceLoader.Load<Texture2D>(p) : null;
            tex.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            tex.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            tex.Position = new Vector2(3, 3);
            tex.Size = new Vector2(CARD_W - 6, CARD_H - 19);
            tex.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (!owned)
                tex.Modulate = new Color(0.45, 0.45, 0.5);
            b.AddChild(tex);
            // the name on a dark band across the card's foot
            var band = new ColorRect();
            band.Color = new Color(0.03, 0.02, 0.05, 0.82);
            band.Position = new Vector2(2, CARD_H - 17);
            band.Size = new Vector2(CARD_W - 4, 15);
            band.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(band);
            var nm = Moba.HEROES[hid].name.ToUpperInvariant();
            var nl = UI2.Text(b, nm, nm.Length <= 6 ? 8 : (nm.Length <= 8 ? 7 : 6), Color.WHITE, Color.FromCode("#120a20"), 3, false);
            nl.ClipText = true;
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            nl.Position = new Vector2(0, CARD_H - 16);
            nl.Size = new Vector2(CARD_W, 14);
            nl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (!owned)
            {
                var lk = new TextureRect();
                lk.Texture = _Tex(LOCK);
                lk.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                lk.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
                lk.Position = new Vector2(CARD_W * 0.5 - 11, CARD_H * 0.2);
                lk.Size = new Vector2(22, 22);
                lk.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                b.AddChild(lk);
                // the price under the padlock: a coin and the gold
                var chip = new HBoxContainer();
                chip.AddThemeConstantOverride("separation", 1);
                chip.Alignment = BoxContainer.ALIGNMENT_CENTER;
                chip.Position = new Vector2(0, CARD_H * 0.52);
                chip.Size = new Vector2(CARD_W, 16);
                chip.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                b.AddChild(chip);
                var ci = new TextureRect();
                ci.Texture = ResourceLoader.Exists(COIN) ? ResourceLoader.Load<Texture2D>(COIN) : null;
                ci.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
                ci.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
                ci.CustomMinimumSize = new Vector2(13, 13);
                ci.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                chip.AddChild(ci);
                var pl = UI2.Text(chip, GD.Str((int)app.profile.HeroPrice(hid).Get("gold", 0)), 10, Color.FromCode("#ffd65a"), Color.FromCode("#201002"), 3, false);
                pl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            else if (free)
            {
                var fr = UI2.Text(b, "FREE", 8, Color.FromCode("#9dff8a"), Color.FromCode("#0a2006"), 3, false);     // 0.31.185: this week's rotation
                fr.Position = new Vector2(3, 1);
                fr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            else if (Eco.HERO_PRICES.Has(hid))
            {
                var nw = UI2.Text(b, "★", 10, Color.FromCode("#ffd65a"), Color.FromCode("#201002"), 3, false);      // (one you bought)
                nw.Position = new Vector2(4, 1);
                nw.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            if (app.profile.ShardsOf(hid) > 0)                   // 0.31.185: a shard of him held
            {
                var sd = UI2.Text(b, "◆", 10, Color.FromCode("#9dff8a"), Color.FromCode("#0a2006"), 3, false);
                sd.Position = new Vector2(CARD_W - 13, CARD_H - 31);
                sd.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            if (on)
            {
                var ck = UI2.Text(b, "✔", 12, Color.FromCode("#ffd65a"), Color.FromCode("#201002"), 4, false);
                ck.Position = new Vector2(CARD_W - 15, 1);
                ck.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            }
            b.Pressed += () =>
            {
                hero = hid;
                app.Sfx("equip");
                _Render();
            };
            return b;
        }
    }
}
