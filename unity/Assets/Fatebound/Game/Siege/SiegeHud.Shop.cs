// Ported from godot/scripts/siege/siege_hud.gd (Fatebound 0.31.222) -- gold, the shop, the live scoreboard, the quick-buy,
// the jungle's timers (see SiegeHud.cs).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using Fatebound.Sim;
using Fatebound.GUI;
using Vector2 = Fatebound.Sim.Vec2;
using Vector3 = Fatebound.Sim.Vec3;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    using UI = Fatebound.Game.Ui;
    using UI2 = Fatebound.Game.Ui2;
    using Sim = Fatebound.Sim.SiegeSim;
    using Moba = Fatebound.Sim.Moba;
    using Kits = Fatebound.Sim.MobaKits;

    public partial class SiegeHud
    {
        // ---------- 5V5: gold, the shop, the jungle's timers (0.31.157) ----------
        // Under the towers line: your gold and SHOP (tap: the shop; it glows while you can afford the quick-buy -- 0.31.217),
        // your six item slots, the buffs you carry. The shop: your items (tap one to sell it), the basic and the big items (tap
        // one: what it gives, what it's built from, its price -- less what you own of it -- and BUY). Over a cleared camp in
        // view: when it's back.
        public static readonly GDict STAT_NAMES = GDict.Of("dmg", "damage", "hp", "health", "as", "attack speed", "spd", "speed", "cdr", "ability recharge", "ls", "lifesteal",
            "regen", "health/s", "armor", "less damage taken", "heal", "healing");
        public PanelContainer shop_panel = null;
        public Label _shop_gold;
        public Label _shop_where;
        public GArray _shop_slots = new GArray();
        public GDict _shop_cells = new GDict();               // item id -> {button, price}
        public Label _shop_name;
        public ItemIcon _shop_pick_icon;                       // 0.31.175: the picked item's icon beside its name
        public Label _shop_stats;
        public Label _shop_from;
        public Button _shop_act;
        public GDict _shop_sel = new GDict();                  // {"item": id} or {"slot": i}
        public string _shop_key = "";
        public StyleBox _shop_style = null;
        public Texture2D _coin_tex = null;

        public bool ShopOpen()
        {
            return shop_panel != null && shop_panel.Visible;
        }

        public static readonly GArray SHOP_TABS = GArray.Of("RECOMMENDED", "ATTACK", "MAGIC", "DEFENSE", "MOVEMENT");
        public int _shop_tab = 0;                             // 0.31.217: the shop's tab (SHOP_TABS)
        public GArray _shop_tabs = new GArray();
        public GridContainer _shop_grid = null;
        public Label _shop_hint = null;

        public GArray ShopTabItems(Unit me)
        {
            // the items the tab shows: RECOMMENDED your hero's list (each once, in order), else Moba.ITEM_TABS's
            if (_shop_tab <= 0)
            {
                var o = new GArray();
                foreach (var id in sim.moba.BuildOf(me))
                {
                    if (!o.Has(GD.Str(id)))
                        o.Append(GD.Str(id));
                }
                return o;
            }
            return GArray.From(Moba.ITEM_TABS[_shop_tab - 1].ids);
        }

        public void _FillShopGrid()
        {
            if (_shop_grid == null)
                return;
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            foreach (var c in _shop_grid.GetChildren())
            {
                _shop_grid.RemoveChild(c);
                c.QueueFree();
            }
            _shop_cells = new GDict();
            foreach (var id in ShopTabItems(me))
                _ItemCell(_shop_grid, GD.Str(id));
            _shop_hint.Text = _shop_tab == 0 ? "Your hero's build, in the order to buy it" : "Big items are built from the small ones you own";
            for (int i = 0; i < _shop_tabs.Size(); i++)
            {
                Button tb = _shop_tabs[i].As<Button>();
                var on = i == _shop_tab;
                var sb = new StyleBoxFlat();
                sb.BgColor = on ? new Color(0.36, 0.24, 0.08, 0.98) : new Color(0.08, 0.07, 0.1, 0.92);
                sb.BorderColor = on ? new Color("#ffd65a") : new Color("#4a4f5c");
                sb.SetBorderWidthAll(on ? 2 : 1);
                sb.SetCornerRadiusAll(8);
                foreach (var st in new[] { "normal", "hover", "pressed", "focus", "hover_pressed" })
                    tb.AddThemeStyleboxOverride(st, sb);
                tb.AddThemeColorOverride("font_color", on ? new Color("#ffe9a6") : new Color("#b8b0a0"));
                tb.AddThemeColorOverride("font_hover_color", on ? new Color("#ffe9a6") : new Color("#d8d0c0"));
            }
            _shop_key = "";
        }

        public Rect2 ShopRect()
        {
            return new Rect2(MAP_RECT.position.x + 54.0, MAP_RECT.End.y + 12.0, 140, 36);   // (0.31.216: beside your level, under the map; 70, 90 until then)
        }

        public void OpenShop()
        {
            if (sim == null || sim.moba == null)
                return;
            CloseBoard();
            if (shop_panel == null)
                _BuildShop();
            _shop_tab = 0;                                  // (0.31.217: it opens on RECOMMENDED)
            _FillShopGrid();
            _shop_key = "";
            shop_panel.Visible = true;
            _Center(shop_panel, true);
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            if (me != null)
                _RefreshShop(me);
        }

        public void CloseShop()
        {
            if (shop_panel != null)
                shop_panel.Visible = false;
        }

        public static string ItemText(string id)
        {
            ItemDef it = Moba.ITEMS.TryGetValue(id, out var itd) ? itd : null;
            var parts = new GArray();
            foreach (var k in new[] { "dmg", "hp", "as", "spd", "cdr", "ls", "armor", "heal" })
            {
                if (it != null && it.Has(k))
                    parts.Append(GD.Fmt("+%d%% %s", GD.Int(GD.Round(it.Stat(k) * 100.0)), STAT_NAMES[k]));
            }
            if (it != null && it.Has("regen"))
                parts.Append(GD.Fmt("+%.1f%% health/s", it.regen * 100.0));
            return GStr.Join(", ", parts);
        }

        public const string SHOP_BANNER = "res://assets/ui/menu/shop_banner.webp";
        public const double CELL_W = 84.0;
        public const double CELL_H = 82.0;

        public Button _ItemCell(Node parent, string id)
        {
            // 0.31.175: the item's painted icon, its name, and its price beside a coin
            var b = new Button();
            b.FocusMode = Control.FOCUS_NONE;
            b.CustomMinimumSize = new Vector2(CELL_W, CELL_H);
            b.SetMeta("action_key", "shop_item_" + id);
            parent.AddChild(b);
            var ic = new ItemIcon();
            ic.item = id;
            ic.Position = new Vector2((CELL_W - 44.0) * 0.5, 3);
            ic.Size = new Vector2(44, 44);
            ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(ic);
            var nl = new Label();
            nl.Text = GD.Str(Moba.ITEMS[id].name);
            nl.HorizontalAlignment = HorizontalAlignment.Center;
            nl.ClipText = true;
            nl.Position = new Vector2(2, 46);
            nl.Size = new Vector2(CELL_W - 4, 15);
            nl.AddThemeFontSizeOverride("font_size", 10);
            nl.AddThemeFontOverride("font", _bold);
            nl.AddThemeColorOverride("font_color", new Color("#f2e6cf"));
            nl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(nl);
            var row = new HBoxContainer();
            row.Alignment = BoxContainer.ALIGNMENT_CENTER;
            row.AddThemeConstantOverride("separation", 2);
            row.Position = new Vector2(0, 61);
            row.Size = new Vector2(CELL_W, 18);
            row.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            b.AddChild(row);
            var coin = new TextureRect();
            coin.Texture = _Coin();
            coin.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            coin.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            coin.CustomMinimumSize = new Vector2(14, 14);
            coin.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            row.AddChild(coin);
            var pl = new Label();
            pl.AddThemeFontSizeOverride("font_size", 13);
            pl.AddThemeFontOverride("font", _bold);
            pl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            row.AddChild(pl);
            b.Pressed += () =>
            {
                _shop_sel = GDict.Of("item", id);
                _shop_key = "";
            };
            _shop_cells[id] = GDict.Of("button", b, "price", pl, "icon", ic, "name", nl);
            return b;
        }

        public Texture2D _Coin()
        {
            if (_coin_tex == null && ResourceLoader.Exists("res://assets/ui/currency/coin.png"))
                _coin_tex = ResourceLoader.Load<Texture2D>("res://assets/ui/currency/coin.png");
            return _coin_tex;
        }

        public void _BuildShop()
        {
            // 0.31.216 (landscape): the items on the left, your slots and the picked item's card on the right (one column until then)
            shop_panel = _Panel(GD.Minf(740.0, Size.x - 24.0));
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 6);
            shop_panel.AddChild(v);
            // 0.31.175 (Kevin: "make these menus better looking and more high quality"): the keep's armory painted across the
            // top (ElevenLabs; tools/build_menu_icons.py), SHOP and your gold over it
            var hdr = new Panel();
            hdr.CustomMinimumSize = new Vector2(0, 50);
            hdr.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            var hs = new StyleBoxFlat();
            hs.BgColor = new Color(0.06, 0.04, 0.03);
            hs.SetCornerRadiusAll(12);
            hdr.AddThemeStyleboxOverride("panel", hs);
            hdr.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            v.AddChild(hdr);
            var art = new TextureRect();
            art.Texture = ResourceLoader.Exists(SHOP_BANNER) ? ResourceLoader.Load<Texture2D>(SHOP_BANNER) : null;
            art.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            art.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            art.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            art.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            hdr.AddChild(art);
            var shade = new TextureRect();                       // (darker toward the foot, under the words)
            var gg = new Gradient();
            gg.SetColor(0, new Color(0, 0, 0, 0.0));
            gg.SetColor(1, new Color(0.02, 0.01, 0.03, 0.78));
            var gt = new GradientTexture2D();
            gt.Gradient = gg;
            gt.FillFrom = new Vector2(0, 0.25);
            gt.FillTo = new Vector2(0, 1);
            shade.Texture = gt;
            shade.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            shade.StretchMode = TextureRect.STRETCH_SCALE;
            shade.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            shade.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            hdr.AddChild(shade);
            var rim = new Panel();
            var rs = new StyleBoxFlat();
            rs.DrawCenter = false;
            rs.BorderColor = new Color("#c99a3a");
            rs.SetBorderWidthAll(2);
            rs.SetCornerRadiusAll(12);
            rim.AddThemeStyleboxOverride("panel", rs);
            rim.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            rim.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            hdr.AddChild(rim);
            var hrow = new HBoxContainer();
            hrow.SetAnchorsAndOffsetsPreset(Control.PRESET_BOTTOM_WIDE);
            hrow.OffsetTop = -38;
            hrow.OffsetBottom = -4;
            hrow.OffsetLeft = 12;
            hrow.OffsetRight = -12;
            hrow.AddThemeConstantOverride("separation", 6);
            hrow.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            hdr.AddChild(hrow);
            var tl = UI2.Text(hrow, "SHOP", 28, UI2.GOLD);
            tl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            var gc = new TextureRect();
            gc.Texture = _Coin();
            gc.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            gc.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            gc.CustomMinimumSize = new Vector2(24, 24);
            gc.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            hrow.AddChild(gc);
            _shop_gold = UI2.Text(hrow, "", 22, new Color("#ffd65a"));
            var cols = new HBoxContainer();
            cols.AddThemeConstantOverride("separation", 12);
            v.AddChild(cols);
            var lv = new VBoxContainer();
            lv.AddThemeConstantOverride("separation", 5);
            lv.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            cols.AddChild(lv);
            var rv = new VBoxContainer();
            rv.AddThemeConstantOverride("separation", 6);
            rv.CustomMinimumSize = new Vector2(240, 0);
            cols.AddChild(rv);
            _shop_where = _Label(rv, "", 11, new Color("#d4cbbb"));
            _shop_where.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            UI2.Body(rv, "YOUR ITEMS · tap one to sell it", 10, UI2.MUTED, false);
            var slots = new GridContainer();
            slots.Columns = 3;
            slots.AddThemeConstantOverride("h_separation", 6);
            slots.AddThemeConstantOverride("v_separation", 6);
            var scc = new CenterContainer();
            scc.AddChild(slots);
            rv.AddChild(scc);
            _shop_slots = new GArray();
            for (int i = 0; i < Moba.ITEM_SLOTS; i++)
            {
                var sb = new Button();
                sb.FocusMode = Control.FOCUS_NONE;
                sb.CustomMinimumSize = new Vector2(52, 52);
                sb.SetMeta("action_key", GD.Fmt("shop_slot_%d", i));
                var ic = new ItemIcon();
                ic.Position = new Vector2(5, 5);
                ic.Size = new Vector2(42, 42);
                ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                sb.AddChild(ic);
                var slot = i;
                sb.Pressed += () =>
                {
                    _shop_sel = GDict.Of("slot", slot);
                    _shop_key = "";
                };
                slots.AddChild(sb);
                _shop_slots.Append(GDict.Of("button", sb, "icon", ic));
            }
            // 0.31.217 (Honor of Kings' shop): tabs -- RECOMMENDED (your hero's list, in the order to buy it), ATTACK, MAGIC,
            // DEFENSE, MOVEMENT -- over one grid (the small items, then the big ones built from them; BASIC and BIG until then)
            var tabs = new HBoxContainer();
            tabs.AddThemeConstantOverride("separation", 4);
            lv.AddChild(tabs);
            _shop_tabs = new GArray();
            for (int i = 0; i < SHOP_TABS.Size(); i++)
            {
                var tb = new Button();
                tb.Text = GD.Str(SHOP_TABS[i]);
                tb.FocusMode = Control.FOCUS_NONE;
                tb.CustomMinimumSize = new Vector2(0, 26);
                tb.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                tb.AddThemeFontOverride("font", _bold);
                tb.AddThemeFontSizeOverride("font_size", 10);
                tb.SetMeta("action_key", GD.Fmt("shop_tab_%d", i));
                var ti = i;
                tb.Pressed += () =>
                {
                    _shop_tab = ti;
                    _FillShopGrid();
                };
                tabs.AddChild(tb);
                _shop_tabs.Append(tb);
            }
            _shop_hint = UI2.Body(lv, "", 10, UI2.MUTED, false);
            _shop_grid = new GridContainer();
            _shop_grid.Columns = 5;
            _shop_grid.AddThemeConstantOverride("h_separation", 5);
            _shop_grid.AddThemeConstantOverride("v_separation", 5);
            var cc = new CenterContainer();
            cc.AddChild(_shop_grid);
            lv.AddChild(cc);
            var nrow = new HBoxContainer();
            nrow.Alignment = BoxContainer.ALIGNMENT_CENTER;
            nrow.AddThemeConstantOverride("separation", 8);
            rv.AddChild(nrow);
            _shop_pick_icon = new ItemIcon();
            _shop_pick_icon.CustomMinimumSize = new Vector2(40, 40);
            _shop_pick_icon.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            nrow.AddChild(_shop_pick_icon);
            _shop_name = _Label(nrow, "", 17, UI2.GOLD, _bold);
            _shop_name.CustomMinimumSize = new Vector2(0, 0);
            _shop_name.AutowrapMode = TextServer.AUTOWRAP_OFF;
            _shop_stats = _Label(rv, "", 12, Color.WHITE);
            _shop_stats.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            _shop_from = _Label(rv, "", 11, new Color("#d4cbbb"));
            _shop_from.AutowrapMode = TextServer.AUTOWRAP_WORD_SMART;
            var gap = new Control();
            gap.SizeFlagsVertical = Control.SIZE_EXPAND_FILL;
            rv.AddChild(gap);
            _shop_act = _Button(rv, "BUY", "gold", () => _ShopAction());
            _shop_act.SetMeta("action_key", "shop_act");
            var cb = _Button(rv, "CLOSE", "secondary", () => CloseShop());
            cb.SetMeta("action_key", "shop_close");
        }

        public void _ShopAction()
        {
            if (_shop_sel.Has("item"))
                ActionPressed?.Invoke("shop_buy:" + GD.Str(_shop_sel["item"]));
            else if (_shop_sel.Has("slot"))
            {
                ActionPressed?.Invoke(GD.Fmt("shop_sell:%d", GD.Int(_shop_sel["slot"])));
                _shop_sel = new GDict();
            }
            _shop_key = "";
        }

        public StyleBoxFlat _CellStyle(bool big, bool sel, bool can)
        {
            // 0.31.175: a warm ground for what you can buy now, cooler for the rest; the big items in gold on a deep purple;
            // the picked one lit
            var sb = new StyleBoxFlat();
            if (big)
                sb.BgColor = can ? new Color(0.2, 0.1, 0.24, 0.96) : new Color(0.09, 0.06, 0.12, 0.92);
            else
                sb.BgColor = can ? new Color(0.16, 0.11, 0.06, 0.96) : new Color(0.06, 0.06, 0.09, 0.92);
            sb.BorderColor = sel ? new Color("#ffe9a6") : (big ? new Color("#c99a3a") : new Color("#6a7486"));
            sb.SetBorderWidthAll(sel ? 3 : 2);
            sb.SetCornerRadiusAll(10);
            if (sel)
            {
                sb.ShadowColor = new Color(1.0, 0.85, 0.4, 0.55);
                sb.ShadowSize = 5;
            }
            return sb;
        }

        // (sim.moba._comps_owned(me, id): Fatebound.Sim.Moba keeps it private -- CompsOwned -- so it is reached by name)
        static MethodInfo _comps_owned_mi;
        static IList _CompsOwned(Moba m, Unit me, string id)
        {
            _comps_owned_mi ??= typeof(Moba).GetMethod("CompsOwned", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
            return (IList)_comps_owned_mi.Invoke(m, new object[] { me, id });
        }

        public void _RefreshShop(Unit me)
        {
            GArray inv = NetT_V(me.items);
            bool here = sim.moba.CanShop(me);
            var key = GD.Fmt("%d|%s|%s|%s", GD.Int(me.gold), GD.Str(inv), GD.Str(here), GD.Str(_shop_sel));
            if (key == _shop_key)
                return;
            _shop_key = key;
            var gold = GD.Int(me.gold);
            _shop_gold.Text = GD.Fmt("%d", gold);
            _shop_where.Text = here ? "Tap an item, then BUY -- anywhere, any time" : "You can't shop now";      // (0.31.217: anywhere)
            _shop_where.AddThemeColorOverride("font_color", here ? new Color("#9fe07a") : new Color("#ffb07a"));
            for (int i = 0; i < _shop_slots.Size(); i++)
            {
                GDict sl = _shop_slots[i].D;
                ItemIcon ic = sl["icon"].As<ItemIcon>();
                ic.item = i < inv.Size() ? GD.Str(inv[i]) : "";
                ic.QueueRedraw();
                var sb = _CellStyle(false, _shop_sel.Get("slot", -1) == i, ic.item != "");
                foreach (var st in new[] { "normal", "hover", "pressed", "focus", "hover_pressed", "disabled" })
                    sl["button"].As<Button>().AddThemeStyleboxOverride(st, sb);
            }
            foreach (var idv in _shop_cells)
            {
                var id = idv.AsString();
                GDict cell = _shop_cells[id].D;
                int pr = sim.moba.Price(me, id);
                string why = sim.moba.BuyWhy(me, id);
                var can = why == "" || why == "where";
                cell["price"].As<Label>().Text = GD.Str(pr);
                cell["price"].As<Label>().AddThemeColorOverride("font_color", gold >= pr ? Color.WHITE : new Color("#a08c70"));   // (0.31.195: white, not gold)
                cell["name"].As<Label>().AddThemeColorOverride("font_color", can ? new Color("#f2e6cf") : new Color("#9a927f"));
                cell["icon"].As<ItemIcon>().dim = !can;
                cell["icon"].As<ItemIcon>().QueueRedraw();
                var sb2 = _CellStyle(Moba.ITEMS[id].from.Length > 0, GD.Str(_shop_sel.Get("item", "")) == id, can);
                foreach (var st in new[] { "normal", "hover", "pressed", "focus", "hover_pressed", "disabled" })
                    cell["button"].As<Button>().AddThemeStyleboxOverride(st, sb2);
            }
            // the details of the one picked
            var picked = _shop_sel.Has("item") ? GD.Str(_shop_sel["item"]) : (_shop_sel.Has("slot") && GD.Int(_shop_sel["slot"]) < inv.Size() ? GD.Str(inv[GD.Int(_shop_sel["slot"])]) : "");
            _shop_pick_icon.item = picked;
            _shop_pick_icon.Visible = picked != "";
            _shop_pick_icon.QueueRedraw();
            if (_shop_sel.Has("item"))
            {
                var id2 = GD.Str(_shop_sel["item"]);
                ItemDef it = Moba.ITEMS[id2];
                _shop_name.Text = GD.Str(it.name).ToUpperInvariant();
                _shop_stats.Text = ItemText(id2);
                if (it.from.Length > 0)
                {
                    var names = new GArray();
                    foreach (var c in it.from)
                        names.Append(GD.Str(Moba.ITEMS[c].name));
                    int own = _CompsOwned(sim.moba, me, id2).Count;
                    _shop_from.Text = GD.Fmt("Built from %s%s · full price %d", GStr.Join(" + ", names), own > 0 ? GD.Fmt(" (you have %d)", own) : "", it.cost);
                }
                else
                {
                    var into = new GArray();
                    foreach (var x in Moba.ITEM_ORDER)
                        if (Array.IndexOf(Moba.ITEMS[x].from, id2) >= 0)
                            into.Append(GD.Str(Moba.ITEMS[x].name));
                    _shop_from.Text = GD.Fmt("Goes into: %s", GStr.Join(", ", into));
                }
                string why2 = sim.moba.BuyWhy(me, id2);
                _shop_act.Visible = true;
                _shop_act.Disabled = why2 != "";
                _shop_act.Text = GD.Str(GDict.Of("", GD.Fmt("BUY · %d", sim.moba.Price(me, id2)), "gold", GD.Fmt("NEED %d GOLD", sim.moba.Price(me, id2)), "where", "BUY IN YOUR CASTLE",
                    "full", "NO ROOM (6 ITEMS)", "boots", "ONE PAIR OF BOOTS").Get(why2, "BUY"));
            }
            else if (_shop_sel.Has("slot") && GD.Int(_shop_sel["slot"]) < inv.Size())
            {
                var id3 = GD.Str(inv[GD.Int(_shop_sel["slot"])]);
                _shop_name.Text = GD.Str(Moba.ITEMS[id3].name).ToUpperInvariant();
                _shop_stats.Text = ItemText(id3);
                _shop_from.Text = "Yours";
                _shop_act.Visible = true;
                _shop_act.Disabled = !here;
                _shop_act.Text = here ? GD.Fmt("SELL · +%d", GD.Int((double)Moba.ITEMS[id3].cost * Moba.SELL_BACK)) : "SELL IN YOUR CASTLE";
            }
            else
            {
                _shop_name.Text = "PICK AN ITEM";
                _shop_stats.Text = "Gold comes in every second, and from last hits, knockouts, towers and the jungle's camps.";
                _shop_from.Text = "";
                _shop_act.Visible = false;
            }
        }

        // (me.get("items", []): the unit's items as the Array the .gd reads)
        static GArray NetT_V(List<string> items) => items != null ? SiegeNet._V(items).A : new GArray();

        // ---------------- the live scoreboard (0.31.176) ----------------
        // Kevin: "I'm wanting to give players ability to pull up live score anytime in match. Make a scoreboard that gives the
        // stats that league of legends does" -> concept A ("Full board"), opened by tapping the score bar. League's Tab board:
        // your side, then the enemy -- each a strip of the side's knockouts, towers destroyed, Bone Lords and Grave Wyrms slain,
        // its gold (what its heroes carry and their items' worth) and the lead -- and a row a hero (by role): portrait with his
        // level (greyed with the seconds to his return while he's down), name (0.31.177: a bot's, "Bot Alfred") and hero, K / D / A, CS (minions
        // last-hit), his six item slots, his gold. Live while open (the match goes on); the score bar again, the X, or a tap
        // outside closes it.
        public PanelContainer board_panel = null;
        public GDict _board_rows = new GDict();               // unit id -> the row's controls
        public GArray _board_heads = new GArray();                   // per side (mine first): the strip's controls
        public Label _board_clock;
        public double _board_tick = 0.0;
        public const string BOARD_SKULL = "res://assets/ui/v2/icons/skull.png";
        public const string BOARD_TOWER = "res://assets/ui/v2/icons/castle.png";
        public static readonly GDict BOARD_W = GDict.Of("por", 40.0, "name", 80.0, "kda", 58.0, "cs", 28.0, "slot", 19.0);

        public bool BoardOpen()
        {
            return board_panel != null && board_panel.Visible;
        }

        public static int NetWorth(Unit u)
        {
            // a hero's gold as League counts it on the board: what he carries and what his items cost
            var n = u.gold;
            foreach (var id in u.items ?? new List<string>())
                n += Moba.ITEMS.TryGetValue(GD.Str(id), out var it) ? (double)it.cost : 0.0;
            return GD.Int(n);
        }

        public static string GoldK(double n)
        {
            return GD.Fmt("%.1fk", n / 1000.0);
        }

        public List<Unit> BoardHeroes(int side)
        {
            // a side's heroes, by role (tank first), as the hero window lists them
            List<Unit> o = sim.units.FindAll(u => u.team == side && u.hero);
            GSort.Sort(o, (a, b) =>
            {
                var ra = Array.IndexOf(Kits.ROLE_ORDER, Kits.RoleOf(GD.Str(a.hid ?? "")));
                var rb = Array.IndexOf(Kits.ROLE_ORDER, Kits.RoleOf(GD.Str(b.hid ?? "")));
                return ra != rb ? ra < rb : GMarshal.CodePointCompare(GD.Str(a.id), GD.Str(b.id)) < 0;
            });
            return o;
        }

        public GDict BoardTeam(int side)
        {
            // a side's strip: knockouts, enemy towers down, epic monsters slain, gold
            var towers = 0;
            foreach (var tw in sim.moba.towers)
            {
                if (tw.team != side && tw.dead)
                    towers += 1;
            }
            var ek = sim.moba.epic_kills;
            var gold = 0;
            foreach (var u in BoardHeroes(side))
                gold += NetWorth(u);
            return GDict.Of("kills", sim.kills[side], "towers", towers, "lord", (ek.TryGetValue("lord", out var el) ? el : new[] { 0, 0 })[side],
                "wyrm", (ek.TryGetValue("wyrm", out var ew) ? ew : new[] { 0, 0 })[side], "gold", gold);
        }

        public void OpenBoard()
        {
            if (sim == null || sim.moba == null)
                return;
            CloseShop();
            if (board_panel != null)
                board_panel.QueueFree();
            _BuildBoard();
            board_panel.Visible = true;
            _RefreshBoard();
            board_panel.ResetSize();
            board_panel.Position = new Vector2((Size.x - board_panel.Size.x) * 0.5, ScoreBarRect().End.y + 6.0);
            var fit = GD.Minf(1.0, (Size.y - board_panel.Position.y - 8.0) / GD.Maxf(1.0, board_panel.Size.y));
            fit = GD.Minf(fit, (Size.x - 12.0) / GD.Maxf(1.0, board_panel.Size.x));      // (0.31.216: the two sides side by side)
            board_panel.PivotOffset = new Vector2(board_panel.Size.x * 0.5, 0);
            board_panel.Scale = Vector2.ONE * fit;
        }

        public void CloseBoard()
        {
            if (board_panel != null)
                board_panel.Visible = false;
        }

        public Label _Bl(Node parent, string text, int px, Color col, double w = 0.0, HorizontalAlignment align = HorizontalAlignment.Left, bool lg = true)
        {
            // a board label: the title face (numbers, names of sides; Lilita One since 0.31.195) or the bold body font
            var l = new Label();
            l.Text = text;
            l.AddThemeFontOverride("font", lg ? UI2.LG : _bold);
            l.AddThemeFontSizeOverride("font_size", px);
            l.AddThemeColorOverride("font_color", col);
            if (lg)
            {
                l.AddThemeColorOverride("font_outline_color", new Color("#0b0820"));
                l.AddThemeConstantOverride("outline_size", 4);
            }
            l.HorizontalAlignment = align;
            l.VerticalAlignment = VerticalAlignment.Center;
            l.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            if (w > 0.0)
            {
                l.CustomMinimumSize = new Vector2(w, 0);
                l.ClipText = true;
            }
            parent.AddChild(l);
            return l;
        }

        public TextureRect _Bimg(Node parent, string path, double px)
        {
            var t = new TextureRect();
            t.Texture = ResourceLoader.Exists(path) ? ResourceLoader.Load<Texture2D>(path) : null;
            t.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            t.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;
            t.CustomMinimumSize = new Vector2(px, px);
            t.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            t.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            parent.AddChild(t);
            return t;
        }

        public StyleBoxFlat _Bstyle(Color bg, Color? border = null, int bw = 0, int r = 10, double m = 5.0)
        {
            var sb = new StyleBoxFlat();
            sb.BgColor = bg;
            sb.BorderColor = border ?? new Color(0, 0, 0, 0);
            sb.SetBorderWidthAll(bw);
            sb.SetCornerRadiusAll(r);
            sb.ContentMarginLeft = m;
            sb.ContentMarginRight = m;
            sb.ContentMarginTop = m * 0.8;
            sb.ContentMarginBottom = m * 0.8;
            return sb;
        }

        public void _BuildBoard()
        {
            board_panel = new PanelContainer();
            board_panel.Name = "LiveBoard";
            var ps = new StyleBoxEmpty();
            foreach (var side in new[] { "left", "right" })
                GObject.Set(ps, "content_margin_" + side, 10);
            ps.ContentMarginTop = 12;
            ps.ContentMarginBottom = 12;
            board_panel.AddThemeStyleboxOverride("panel", ps);
            board_panel.CustomMinimumSize = new Vector2(0, 0);          // (0.31.216: as wide as the two sides; 440 at most in portrait)
            board_panel.Visible = false;
            board_panel.MouseFilter = Control.MOUSE_FILTER_STOP;
            AddChild(board_panel);
            UI2.Plate(board_panel, "night", 18.0, "gold", GDict.Of("rim", 3.0, "shadow_y", 8.0, "shadow_alpha", 0.6, "shadow_soft", 10.0));
            var v = new VBoxContainer();
            v.AddThemeConstantOverride("separation", 3);
            board_panel.AddChild(v);
            var top = new HBoxContainer();
            top.AddThemeConstantOverride("separation", 8);
            v.AddChild(top);
            var tl = UI2.Text(top, "SCOREBOARD", 22, UI2.GOLD, new Color("#1a0c02"), 5);
            tl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _board_clock = _Bl(top, "", 14, new Color("#c8d0f0"));
            var x = UI2.Button(top, "✕", "ghost", () => CloseBoard(), "board_close", 16, 32.0, 10.0);
            x.CustomMinimumSize = new Vector2(34, 32);
            x.SetMeta("action_key", "board_close");
            _board_rows = new GDict();
            _board_heads = new GArray();
            Unit me = sim.by_id.TryGetValue(player_id, out var mu) ? mu : null;
            var my_team = me != null ? me.team : 0;
            // 0.31.216 (landscape, Honor of Kings' scoreboard): your side on the left, theirs on the right (one under the other
            // in portrait)
            var sides = new HBoxContainer();
            sides.AddThemeConstantOverride("separation", 12);
            v.AddChild(sides);
            foreach (var side in new[] { my_team, 1 - my_team })
            {
                var sv = new VBoxContainer();
                sv.AddThemeConstantOverride("separation", 3);
                var svm = sv.CustomMinimumSize;
                svm.x = 420.0f;
                sv.CustomMinimumSize = svm;
                sides.AddChild(sv);
                _board_heads.Append(_BoardHead(sv, side, side == my_team));
                var cols = new HBoxContainer();
                cols.AddThemeConstantOverride("separation", 6);
                sv.AddChild(cols);
                var pad = new Control();
                pad.CustomMinimumSize = new Vector2(4, 0);
                cols.AddChild(pad);
                foreach (var c in GArray.Of(GArray.Of("HERO", (double)BOARD_W["por"] + 6.0 + (double)BOARD_W["name"]), GArray.Of("K / D / A", BOARD_W["kda"]), GArray.Of("CS", BOARD_W["cs"]), GArray.Of("ITEMS", (double)BOARD_W["slot"] * 6.0 + 5.0)))
                    _Bl(cols, GD.Str(c[0]), 9, new Color("#a9b2d6"), (double)c[1], HorizontalAlignment.Left, false);
                var gl = _Bl(cols, "GOLD", 9, new Color("#a9b2d6"), 0.0, HorizontalAlignment.Right, false);
                gl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
                foreach (var u in BoardHeroes(side))
                    _board_rows[GD.Str(u.id)] = _BoardRow(sv, u, side);
            }
        }

        public GDict _BoardHead(VBoxContainer v, int side, bool mine)
        {
            var pc = new PanelContainer();
            pc.AddThemeStyleboxOverride("panel", _Bstyle(Vt(side) == 0 ? new Color("#14305e") : new Color("#4a1a22"), new Color(0, 0, 0, 0), 0, 10, 7.0));
            v.AddChild(pc);
            var h = new HBoxContainer();
            h.AddThemeConstantOverride("separation", 7);
            pc.AddChild(h);
            var nl = _Bl(h, mine ? "YOUR SIDE" : "ENEMY", 16, TEAM_COLORS[Vt(side)].Lightened(0.1));
            nl.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            _Bimg(h, BOARD_SKULL, 17);
            var kl = _Bl(h, "", 15, Color.WHITE);
            _Bimg(h, BOARD_TOWER, 17);
            var tw = _Bl(h, "", 15, Color.WHITE);
            var ep = _Bl(h, "", 10, new Color("#d8c2ff"));
            _Bimg(h, "res://assets/ui/currency/coin.png", 14);
            var gl = _Bl(h, "", 15, new Color("#ffd65a"));
            var ld = _Bl(h, "", 11, new Color("#9fe07a"));
            return GDict.Of("side", side, "kills", kl, "towers", tw, "epics", ep, "gold", gl, "lead", ld);
        }

        public GDict _BoardRow(VBoxContainer v, Unit u, int side)
        {
            var mine = GD.Str(u.id) == player_id;
            var pc = new PanelContainer();
            pc.AddThemeStyleboxOverride("panel", _Bstyle(mine ? new Color(1.0, 0.76, 0.24, 0.1) : new Color(1, 1, 1, 0.06),
                mine ? new Color("#ffc23d") : new Color(0, 0, 0, 0), mine ? 2 : 0, 10, 5.0));
            pc.SetMeta("unit", GD.Str(u.id));
            v.AddChild(pc);
            var h = new HBoxContainer();
            h.AddThemeConstantOverride("separation", 6);
            pc.AddChild(h);
            double por_w = (double)BOARD_W["por"];
            // the portrait: a frame in the side's colour, his level in the corner; down: grey, and the seconds to his return
            var holder = new Control();                     // (0.31.180: the portrait and, over its top, the bounty)
            holder.CustomMinimumSize = new Vector2(por_w, por_w);
            holder.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            h.AddChild(holder);
            var frame = new Panel();
            frame.CustomMinimumSize = new Vector2(por_w, por_w);
            frame.Size = new Vector2(por_w, por_w);
            frame.AddThemeStyleboxOverride("panel", _Bstyle(new Color("#0b0f26"), TEAM_COLORS[Vt(side)], 2, 9, 0.0));
            frame.ClipChildren = CanvasItem.CLIP_CHILDREN_AND_DRAW;
            frame.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            holder.AddChild(frame);
            // 0.31.180: his bounty -- a gold coin badge once it's 150 or more (League's: steps of 50)
            var bbox = new PanelContainer();
            bbox.AddThemeStyleboxOverride("panel", _Bstyle(new Color("#e3a72c"), new Color("#3a2205"), 1, 8, 1.0));
            bbox.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            bbox.Position = new Vector2(-3, -7);
            bbox.Visible = false;
            holder.AddChild(bbox);
            var bh = new HBoxContainer();
            bh.AddThemeConstantOverride("separation", 1);
            bbox.AddChild(bh);
            _Bimg(bh, "res://assets/ui/currency/coin.png", 10);
            var bty = _Bl(bh, "", 10, new Color("#3a2205"));
            bty.AddThemeConstantOverride("outline_size", 0);
            var por = new TextureRect();
            var pp = GD.Fmt("res://assets/ui/skins/default_%s.png", u.hid != "" ? GD.Str(u.hid) : GD.Str(u.cls));     // (u.get("hid", u.cls))
            por.Texture = ResourceLoader.Exists(pp) ? ResourceLoader.Load<Texture2D>(pp) : null;
            por.ExpandMode = TextureRect.EXPAND_IGNORE_SIZE;
            por.StretchMode = TextureRect.STRETCH_KEEP_ASPECT_COVERED;
            por.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            por.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            frame.AddChild(por);
            var resp = _Bl(frame, "", 17, new Color("#ff8a7a"), 0.0, HorizontalAlignment.Center);
            resp.SetAnchorsAndOffsetsPreset(Control.PRESET_FULL_RECT);
            var lvb = new PanelContainer();
            lvb.AddThemeStyleboxOverride("panel", _Bstyle(new Color("#0b0820"), new Color(0, 0, 0, 0), 0, 5, 2.0));
            lvb.MouseFilter = Control.MOUSE_FILTER_IGNORE;
            frame.AddChild(lvb);
            var lv = _Bl(lvb, "", 10, new Color("#ffe9b0"));
            lvb.Position = new Vector2(por_w - 17, por_w - 15);
            var nb = new VBoxContainer();
            nb.AddThemeConstantOverride("separation", 0);
            nb.CustomMinimumSize = new Vector2((double)BOARD_W["name"], 0);
            nb.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
            h.AddChild(nb);
            var who = DisplayName(u);                     // (0.31.177: a bot by its name: "Bot Alfred")
            var who_l = _Bl(nb, who, 12, Color.WHITE, (double)BOARD_W["name"], HorizontalAlignment.Left, false);
            var hr = new HBoxContainer();
            hr.AddThemeConstantOverride("separation", 3);
            nb.AddChild(hr);
            _Bimg(hr, GD.Fmt("res://assets/ui/roles/%s.png", Kits.RoleOf(GD.Str(u.hid ?? ""))), 12);
            _Bl(hr, sim.ClassLabel(u), 10, new Color("#a9b2d6"), (double)BOARD_W["name"] - 15.0, HorizontalAlignment.Left, false);
            var kda = new HBoxContainer();
            kda.AddThemeConstantOverride("separation", 0);
            kda.CustomMinimumSize = new Vector2((double)BOARD_W["kda"], 0);
            h.AddChild(kda);
            var kk = _Bl(kda, "", 15, Color.WHITE);
            _Bl(kda, "/", 15, new Color("#8890b0"));
            var dd = _Bl(kda, "", 15, new Color("#ff8a7a"));
            _Bl(kda, "/", 15, new Color("#8890b0"));
            var aa = _Bl(kda, "", 15, Color.WHITE);
            var cs = _Bl(h, "", 14, Color.WHITE, (double)BOARD_W["cs"]);
            var its = new HBoxContainer();
            its.AddThemeConstantOverride("separation", 1);
            h.AddChild(its);
            var slots = new GArray();
            for (int i = 0; i < Moba.ITEM_SLOTS; i++)
            {
                var sl = new Panel();
                sl.CustomMinimumSize = new Vector2((double)BOARD_W["slot"], (double)BOARD_W["slot"]);
                sl.SizeFlagsVertical = Control.SIZE_SHRINK_CENTER;
                sl.AddThemeStyleboxOverride("panel", _Bstyle(new Color("#0b0f26"), new Color("#3a4568"), 1, 4, 0.0));
                sl.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                its.AddChild(sl);
                var ic = new ItemIcon();
                ic.Position = new Vector2(1, 1);
                ic.Size = new Vector2((double)BOARD_W["slot"] - 2.0, (double)BOARD_W["slot"] - 2.0);
                ic.MouseFilter = Control.MOUSE_FILTER_IGNORE;
                sl.AddChild(ic);
                slots.Append(ic);
            }
            var gold = _Bl(h, "", 13, new Color("#ffd65a"), 0.0, HorizontalAlignment.Right);
            gold.SizeFlagsHorizontal = Control.SIZE_EXPAND_FILL;
            return GDict.Of("por", por, "resp", resp, "lv", lv, "k", kk, "d", dd, "a", aa, "cs", cs, "slots", slots, "gold", gold,
                "bounty_box", bbox, "bounty", bty, "who", who_l);
        }

        public void _RefreshBoard()
        {
            if (board_panel == null || sim == null || sim.moba == null)
                return;
            var left = GD.Maxf(0.0, sim.match_time - sim.time);
            _board_clock.Text = GD.Fmt("%d:%02d", GD.Int(left) / 60, GD.Int(left) % 60);
            var teams = new GDict();
            foreach (var hd in _board_heads)
                teams[GD.Int(hd["side"])] = BoardTeam(GD.Int(hd["side"]));
            foreach (var hd in _board_heads)
            {
                GDict t = teams[GD.Int(hd["side"])].D;
                GDict o = teams.Get(1 - GD.Int(hd["side"]), t).D;
                hd["kills"].As<Label>().Text = GD.Str(t["kills"]);
                hd["towers"].As<Label>().Text = GD.Str(t["towers"]);
                hd["epics"].As<Label>().Text = GD.Fmt("LORD %d\nWYRM %d", GD.Int(t["lord"]), GD.Int(t["wyrm"]));
                hd["gold"].As<Label>().Text = GoldK((double)t["gold"]);
                var lead = GD.Int(t["gold"]) - GD.Int(o["gold"]);
                hd["lead"].As<Label>().Text = (lead > 0 ? "+" : "") + GoldK((double)lead);
                hd["lead"].As<Label>().AddThemeColorOverride("font_color", lead >= 0 ? new Color("#9fe07a") : new Color("#ff8a7a"));
            }
            foreach (var idv in _board_rows)
            {
                var id = idv.AsString();
                Unit u = sim.by_id.TryGetValue(id, out var uu) ? uu : null;
                if (u == null)
                    continue;
                GDict r = _board_rows[id].D;
                var nm = DisplayName(u);                  // 0.31.209: the names kept up to date (players' names arriving, one leaving)
                if (r["who"].As<Label>().Text != nm)
                    r["who"].As<Label>().Text = nm;
                bool down = !sim.Alive(u);
                r["por"].As<TextureRect>().Modulate = down ? new Color(0.42, 0.42, 0.46) : Color.WHITE;
                r["resp"].As<Label>().Text = down ? GD.Str(GD.Int(GD.Ceil(GD.Maxf(0.0, u.respawn_at - sim.time)))) : "";
                r["lv"].As<Label>().Text = GD.Str(u.level);
                r["k"].As<Label>().Text = GD.Str(u.kills);
                r["d"].As<Label>().Text = GD.Str(u.deaths);
                r["a"].As<Label>().Text = GD.Str(u.assists);
                r["cs"].As<Label>().Text = GD.Str(u.lh);
                var inv = u.items ?? new List<string>();
                for (int i = 0; i < r["slots"].A.Size(); i++)
                {
                    ItemIcon ic = r["slots"].A[i].As<ItemIcon>();
                    var it = i < inv.Count ? GD.Str(inv[i]) : "";
                    if (ic.item != it)
                    {
                        ic.item = it;
                        ic.QueueRedraw();
                    }
                }
                r["gold"].As<Label>().Text = GoldK((double)NetWorth(u));
                int bshown = sim.moba.BountyShown(u);
                r["bounty_box"].As<Control>().Visible = bshown > 0;
                r["bounty"].As<Label>().Text = GD.Str(bshown);
            }
        }

        public void _DrawGoldAndItems(Unit me)
        {
            // 0.31.178: the gold-and-shop button, the slots framed, the buffs pills. 0.31.179 (Kevin: "The shop button changes
            // weird colors"): one look always -- dark with its gold rim; where you can shop it only glows (_draw_shop_pulse)
            var r = ShopRect();
            if (_shop_styles.IsEmpty())
            {
                _shop_styles = GArray.Of(Var.Of(VisualTheme.Tactile("secondary", "normal", 10)));
                foreach (var full in new[] { false, true })
                {
                    var ss = new StyleBoxFlat();
                    ss.BgColor = new Color(0.03, 0.05, 0.07, 0.78);
                    ss.BorderColor = new Color(VisualTheme.GOLD_DARK, full ? 0.95 : 0.5);
                    ss.SetBorderWidthAll(1);
                    ss.BorderWidthBottom = 2;
                    ss.SetCornerRadiusAll(6);
                    ss.AntiAliasing = true;
                    _slot_styles.Append(Var.Of(ss));
                }
            }
            _ci.DrawStyleBox(_shop_styles[0].As<StyleBox>(), r);
            if (_coin_tex == null && ResourceLoader.Exists("res://assets/ui/currency/coin.png"))
                _coin_tex = ResourceLoader.Load<Texture2D>("res://assets/ui/currency/coin.png");
            var face = r.position + new Vector2(0, -1);                         // (the face sits above the button's lip)
            _ci.DrawCircle(face + new Vector2(20, 18), 13.0, new Color(0.16, 0.09, 0.01, 0.8));                      // (the coin's inset)
            if (_coin_tex != null)
                _ci.DrawTextureRect(_coin_tex, new Rect2(face + new Vector2(9, 7), new Vector2(22, 22)), false);
            else
                _ci.DrawCircle(face + new Vector2(20, 18), 10, new Color("#ffcf4a"));
            var ink = new Color("#ffd65a");
            _Text(face + new Vector2(38, 25), GD.Str(GD.Int(me.gold)), 17, ink, _bold, HorizontalAlignment.Left, 62);
            var dx = face.x + r.size.x - 50.0;
            _ci.DrawLine(new Vector2(dx, face.y + 8.0), new Vector2(dx, face.y + 29.0), new Color(ink, 0.35), 1.5);
            _Text(new Vector2(dx + 6.0, face.y + 24.0), "SHOP", 12, new Color(1, 1, 1, 0.85), _bold, HorizontalAlignment.Left, 44);
            var inv = me.items ?? new List<string>();
            for (int i = 0; i < Moba.ITEM_SLOTS; i++)
            {
                var q = ItemSlotRect(i);
                _ci.DrawStyleBox(_slot_styles[i < inv.Count ? 1 : 0].As<StyleBox>(), q);
                if (i < inv.Count)
                    ItemIcon.DrawItem(_ci, GD.Str(inv[i]), q.GetCenter(), q.size.x - 4.0);
            }
            _DrawQuickBuy(me);
            // the buffs: a pill each, its colour, its time (0.31.217: under the quick-buy)
            double x = MAP_RECT.position.x;
            var qr = QuickRects(me);
            double y = (!qr.IsEmpty() ? qr[-1]["r"].As<Rect2>().End.y : ItemSlotRect(0).End.y) + 8.0;
            var b = me.buffs;
            var pills = new GArray();
            foreach (var k in new[] { "arcane", "ember", "lord" })
            {
                var left = (b != null ? b.Get(k, -1.0) : -1.0) - sim.time;
                if (left > 0.0)
                    pills.Append(GArray.Of(GD.Fmt("%s %d:%02d", GD.Str(Moba.BUFF_NAMES[k]), GD.Int(left) / 60, GD.Int(left) % 60),
                        k == "arcane" ? new Color("#7fb8ff") : (k == "ember" ? new Color("#ff9a5a") : new Color("#d8c2ff"))));
            }
            var hide = sim.moba.wyrm_stacks[GD.Clampi(me.team, 0, 1)];
            if (hide > 0)                                          // 0.31.166: the side's WYRM'S HIDE (for the rest of the match)
                pills.Append(GArray.Of(GD.Fmt("WYRM'S HIDE x%d +%d%%", hide, GD.Int(GD.Round(Moba.WYRM_HIDE * 100.0 * hide))), new Color("#7fffd4")));
            foreach (var pl in pills)
            {
                var txt = GD.Str(pl[0]);
                Color col = pl[1].As<Color>();
                var tw = _bold.GetStringSize(txt, HorizontalAlignment.Left, -1, 10).x;
                if (x + tw + 22.0 > MAP_RECT.End.x + 70.0 && x > MAP_RECT.position.x)
                {
                    x = MAP_RECT.position.x;
                    y += 22.0;
                }
                var pr = new Rect2(x, y, tw + 22.0, 18.0);
                if (_pill_style == null)
                {
                    _pill_style = new StyleBoxFlat();
                    _pill_style.SetCornerRadiusAll(9);
                    _pill_style.SetBorderWidthAll(1);
                    _pill_style.AntiAliasing = true;
                }
                _pill_style.BgColor = new Color(col.Darkened(0.72), 0.85);
                _pill_style.BorderColor = new Color(col, 0.75);
                _ci.DrawStyleBox(_pill_style, pr);
                _ci.DrawCircle(pr.position + new Vector2(9, 9), 3.5, col);
                _Text(pr.position + new Vector2(16, 13), txt, 10, col.Lightened(0.25), _bold, HorizontalAlignment.Left, tw + 4.0);
                x += pr.size.x + 6.0;
            }
        }

        // 0.31.217 (Honor of Kings' quick-buy, Kevin: "the shop system"): on the left under your items, the next two things on
        // your hero's list -- its icon, its name, its price; lit when you can afford it, a tap buys it there and then
        public GArray QuickRects(Unit me)
        {
            var o = new GArray();
            if (sim == null || sim.moba == null || me == null || !me.hero)
                return o;
            var y = ItemSlotRect(0).End.y + 8.0;
            foreach (var id in sim.moba.NextBuys(me, 2))
            {
                var h = o.IsEmpty() ? 40.0 : 32.0;
                o.Append(GDict.Of("id", GD.Str(id), "r", new Rect2(MAP_RECT.position.x, y, 132.0, h)));
                y += h + 4.0;
            }
            return o;
        }

        public GArray _qb_styles = new GArray();

        public void _DrawQuickBuy(Unit me)
        {
            if (_qb_styles.IsEmpty())
            {
                foreach (var lit in new[] { false, true })
                {
                    var st = new StyleBoxFlat();
                    st.BgColor = lit ? new Color(0.2, 0.13, 0.04, 0.9) : new Color(0.03, 0.05, 0.07, 0.72);
                    st.BorderColor = lit ? new Color("#ffd65a") : new Color(VisualTheme.GOLD_DARK, 0.55);
                    st.SetBorderWidthAll(lit ? 2 : 1);
                    st.SetCornerRadiusAll(8);
                    st.AntiAliasing = true;
                    _qb_styles.Append(Var.Of(st));
                }
            }
            var gold = me.gold;
            var first = true;
            foreach (var q in QuickRects(me))
            {
                Rect2 r = q["r"].As<Rect2>();
                var id = GD.Str(q["id"]);
                int pr = sim.moba.Price(me, id);
                bool can = sim.moba.BuyWhy(me, id) == "";
                _ci.DrawStyleBox(_qb_styles[can ? 1 : 0].As<StyleBox>(), r);      // (its glow per frame: _draw_shop_pulse)
                var isz = r.size.y - 8.0;
                ItemIcon.DrawItem(_ci, id, r.position + new Vector2(4.0 + isz * 0.5, r.size.y * 0.5), isz);
                var tx = r.position.x + isz + 10.0;
                _Text(new Vector2(tx, r.position.y + (first ? 15.0 : 13.0)), GD.Str(Moba.ITEMS[id].name), first ? 10 : 9,
                    can ? new Color("#f2e6cf") : new Color("#a8a090"), _bold, HorizontalAlignment.Left, r.End.x - tx - 4.0);
                var py = r.position.y + (first ? 31.0 : 26.0);
                if (_coin_tex != null)
                    _ci.DrawTextureRect(_coin_tex, new Rect2(new Vector2(tx, py - 10.0), new Vector2(11, 11)), false);
                _Text(new Vector2(tx + 13.0, py), GD.Str(pr), first ? 11 : 10, can ? new Color("#ffd65a") : new Color("#c0a070"), _bold, HorizontalAlignment.Left, 50);
                if (!can && pr > 0)                         // how near you are to it
                {
                    var bw = r.size.x - (tx - r.position.x) - 52.0;
                    var bx = tx + 48.0;
                    _ci.DrawRect(new Rect2(bx, py - 6.0, bw, 4.0), new Color(0, 0, 0, 0.5));
                    _ci.DrawRect(new Rect2(bx, py - 6.0, bw * GD.Clampf(gold / (double)pr, 0.0, 1.0), 4.0), new Color("#c99a3a"));
                }
                else if (can)
                    _Text(new Vector2(r.End.x - 34.0, py), "BUY", 10, new Color("#ffe9a6"), _bold, HorizontalAlignment.Left, 32);
                first = false;
            }
        }

        public Rect2 ItemSlotRect(int i)
        {
            return new Rect2(MAP_RECT.position.x + 22.0 * (double)i, MAP_RECT.End.y + 62.0, 20.0, 20.0);      // (0.31.216: 12 + 31 i, 140)
        }

        public GArray _shop_styles = new GArray();
        public GArray _slot_styles = new GArray();
        public StyleBoxFlat _pill_style = null;

        public void _DrawShopPulse(Unit me)
        {
            var nb = me != null ? sim.moba.NextBuys(me, 1) : new List<string>();
            if (nb.Count != 0 && sim.moba.BuyWhy(me, GD.Str(nb[0])) == "")   // (0.31.217: you can afford the next one; in your castle until then)
            {
                var pulse = 0.5 + 0.5 * Math.Sin(_time * 4.0);
                if (_pulse_style == null)
                {
                    _pulse_style = new StyleBoxFlat();
                    _pulse_style.DrawCenter = false;
                    _pulse_style.SetBorderWidthAll(2);
                    _pulse_style.SetCornerRadiusAll(12);
                    _pulse_style.AntiAliasing = true;
                }
                _pulse_style.BorderColor = new Color(1.0, 0.86, 0.4, 0.25 + 0.45 * pulse);
                DrawStyleBox(_pulse_style, ShopRect().Grow(3.0));
                var qr = QuickRects(me);
                if (!qr.IsEmpty())                       // (0.31.217: and the quick-buy's card)
                    DrawStyleBox(_pulse_style, qr[0]["r"].As<Rect2>().Grow(2.0 + 2.0 * pulse));
            }
            _DrawKingAlert(me);
        }

        public StyleBoxFlat _pulse_style = null;

        public void _DrawCampTimers()
        {
            if (project == null || on_screen == null)
                return;
            foreach (var camp in sim.moba.camps)
            {
                if (camp.alive)
                    continue;
                Vector2 p = camp.p;
                var w = new Vector3(p.x, Sim.HeightAt(p) + 1.0, p.y);
                if (!on_screen(w))
                    continue;
                Vector2 sp = project(w);
                if (sp.y < 70.0 || MAP_RECT.Grow(8.0).HasPoint(sp))
                    continue;
                sp.x = (float)GD.Clampf(sp.x, 70.0, Size.x - 70.0);
                var left = GD.Maxf(0.0, camp.next - sim.time);
                var nm = GArray.Of("lord", "wyrm", "arcane", "ember").Has(GD.Str(camp.kind)) ? GD.Str(Moba.CAMP_KINDS[camp.kind].name).ToUpperInvariant() + " " : "";
                _Text(sp, GD.Fmt("%s%d:%02d", nm, GD.Int(left) / 60, GD.Int(left) % 60), 13, new Color("#e8dcc0"), _bold);
            }
        }
    }
}
