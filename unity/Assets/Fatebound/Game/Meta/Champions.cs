// Ported from godot/scripts/meta/champions.gd (Fatebound 0.31.222).
using System;
using System.Collections.Generic;
using Fatebound.Sim;
using Fatebound.GUI;
using Color = Fatebound.GUI.Col;

namespace Fatebound.Game
{
    // 0.31.187 (Kevin: "give every champion a unique name that fits its class and character and give each one a short
    // background story ... When clicking on a champion, make a customized window for them that pops up that is themed around
    // them ... Use art and effects that match each characters lore"): who each of the 18 heroes is -- his own name (the class
    // name stays what he is: "Sir Aldric Vane, the Knight"), a title, a short story and a line he says; and his window's
    // theme: the painting behind him (ElevenLabs gpt-image-2, art_sources/champions/, tools/build_champion_art.py ->
    // assets/ui/champions/<hid>.webp and the Locker card's crop cards/<hid>.webp), his colour, and the effects drifting
    // over it (champion_fx.gd; the sprites are assets/vfx/weapon/'s).
    //
    // fx: layers of [sprite, colour, motion, how many, size px] -- the motions (champion_fx.gd):
    //   rise    float up from below, swaying (embers, motes, wisps)       fall    drift down, turning (leaves, feathers, petals)
    //   drift   blown across from one side (smoke, wind-borne embers)     twinkle appear, shine and fade where they are (stars)
    //   orbit   turn slowly round the champion (runes, sigils)            halo    one big light behind him, turning, breathing
    //   rain    fast slanting streaks                                     flash   a bolt now and then, the sky lighting with it
    //   meteor  a streak across the sky now and then
    // (in front of him: fall, rain, drift; the rest behind)
    public static class Champions
    {
        // (moba.gd HERO_ORDER -- here too so the Locker needn't load the 5v5 at boot; champions_test checks they match)
        public static readonly GArray ORDER = GArray.Of("knight", "barbarian", "rogue", "ranger", "mage", "priest", "crusader", "berserker", "assassin", "sniper",
            "archmage", "necromancer", "golem", "dragoon", "duelist", "stormcaller", "musketeer", "druid");
        public const string ART = "res://assets/ui/champions/%s.webp";
        public const string CARD = "res://assets/ui/champions/cards/%s.webp";

        public static readonly GDict CHAMPIONS = new GDict {
            { "knight", new GDict { { "name", "Sir Aldric Vane" }, { "short", "Aldric" }, { "title", "The Oathbound Wall" }, { "accent", "#8fb8ff" },
                { "lore", "The youngest squire ever to guard Harrowgate's bridge, Aldric held it alone for a night and a day while the village behind him fled. His sword was borrowed and his shield cracked in three places. The knights of Fatebound knighted him at dawn, and he has never taken a step back since." },
                { "quote", "Not one step back." },
                { "fx", GArray.Of(GArray.Of("rays", "#fff2c4", "halo", 1, 300), GArray.Of("sparkle", "#dfe9ff", "rise", 14, 14), GArray.Of("dot", "#ffffff", "twinkle", 10, 5)) } } },
            { "barbarian", new GDict { { "name", "Hroth Bearcloak" }, { "short", "Hroth" }, { "title", "Son of the Frostfang Clans" }, { "accent", "#ff9a4a" },
                { "lore", "Hroth wrestled the great bear of Frostfang Pass with his bare hands and wore its hide home. He fights the way the mountain clans feast: loudly, gladly, and until nothing is left standing. Somewhere under the pelt is the warmest laugh in the north." },
                { "quote", "Ha! Is that all the north wind has?" },
                { "fx", GArray.Of(GArray.Of("flame", "#ffb066", "rise", 18, 16), GArray.Of("dot", "#ffd28a", "rise", 16, 6), GArray.Of("snowflake", "#ffffff", "fall", 12, 15)) } } },
            { "rogue", new GDict { { "name", "Wren Ashveil" }, { "short", "Wren" }, { "title", "The Hooded Whisper" }, { "accent", "#7fd66b" },
                { "lore", "Nobody in Thornwood knows Wren's face -- only the green hood, and the purse that went missing just after. Caught robbing the wrong lord, Wren was given a choice: the gallows or the war. The war pays better, and its pockets are deeper." },
                { "quote", "What purse? I never saw a purse." },
                { "fx", GArray.Of(GArray.Of("leaf", "#8fd16f", "fall", 14, 24), GArray.Of("smoke", "#b9d8b0", "drift", 5, 110), GArray.Of("dot", "#e8ffb0", "twinkle", 8, 5)) } } },
            { "ranger", new GDict { { "name", "Kestrel Finn" }, { "short", "Kestrel" }, { "title", "Warden of the Greenmarch" }, { "accent", "#f2c14e" },
                { "lore", "Kestrel grew up on the edge of the Greenmarch, splitting apples off fence posts at a hundred paces. When raiders burned the border farms, Kestrel tracked them for nine days and never once missed. The wardens gave the hat; the feather was earned." },
                { "quote", "Wind's fair. Target's fair. Done." },
                { "fx", GArray.Of(GArray.Of("feather", "#fff4dc", "fall", 7, 26), GArray.Of("leaf", "#a8d86f", "fall", 8, 20), GArray.Of("dot", "#fff3b0", "twinkle", 14, 5)) } } },
            { "mage", new GDict { { "name", "Elara Flintwick" }, { "short", "Elara" }, { "title", "The Kindled Spark" }, { "accent", "#ff7a3a" },
                { "lore", "Elara set her first spellbook on fire by accident and her second on purpose. The masters of the Ember Tower said she had too much flame and not enough patience. She agreed, left with every book she could carry, and has been proving them half right ever since." },
                { "quote", "Careful -- it's hotter than it looks." },
                { "fx", GArray.Of(GArray.Of("runes", "#ffb15a", "orbit", 4, 40), GArray.Of("flame", "#ff8a3a", "rise", 18, 18), GArray.Of("dot", "#ffd27a", "rise", 14, 6)) } } },
            { "priest", new GDict { { "name", "Brother Cael Sunward" }, { "short", "Cael" }, { "title", "The Dawnbringer" }, { "accent", "#ffd66b" },
                { "lore", "Cael was the abbey's bell-ringer, the one who woke everyone before sunrise. When the shadow plague came, he kept ringing, and the light came with him. Now he carries that dawn into battle, and no one beside him is ever quite beyond saving." },
                { "quote", "Wake up. The dawn's not done with you." },
                { "fx", GArray.Of(GArray.Of("rays", "#fff1b8", "halo", 1, 320), GArray.Of("sparkle", "#fff6d0", "rise", 16, 14), GArray.Of("feather", "#ffffff", "fall", 5, 18)) } } },
            { "crusader", new GDict { { "name", "Lord Gideon Hale" }, { "short", "Gideon" }, { "title", "Hammer of the Dawn" }, { "accent", "#f2c14e" },
                { "lore", "Gideon led the Dawn Order's last charge at Ashen Ford and was the only one who came back, carrying the order's hammer and its banner both. He has sworn to rebuild it one battle at a time. His hammer always comes back to his hand; he says it knows the way home." },
                { "quote", "By hammer and by dawn!" },
                { "fx", GArray.Of(GArray.Of("rays", "#ffe8a0", "halo", 1, 290), GArray.Of("sigil", "#ffd76a", "orbit", 3, 54), GArray.Of("sparkle", "#ffe9a8", "rise", 12, 12)) } } },
            { "berserker", new GDict { { "name", "Ulfgar Blackmaw" }, { "short", "Ulfgar" }, { "title", "The Unbroken" }, { "accent", "#e0483a" },
                { "lore", "Ulfgar has been left for dead on four battlefields and walked off every one of them. The black bear whose hide he wears was the last thing that ever wounded him. They say the rage that keeps him standing is older than he is, and it is not finished yet." },
                { "quote", "Again." },
                { "fx", GArray.Of(GArray.Of("smoke", "#5a2a24", "drift", 6, 130), GArray.Of("flame", "#ff5a3a", "rise", 18, 14), GArray.Of("dot", "#ff8a5a", "rise", 14, 6)) } } },
            { "assassin", new GDict { { "name", "Vesper Nightshade" }, { "short", "Vesper" }, { "title", "The Crimson Veil" }, { "accent", "#e0486a" },
                { "lore", "Vesper was raised by the Veiled Court, where children learn to walk silently before they learn to speak. The Court sold every blade it made, until Vesper chose not to be sold. Now the Court's old clients find a red ribbon on their pillows, and then nothing at all." },
                { "quote", "You won't see me. That's the point." },
                { "fx", GArray.Of(GArray.Of("smoke", "#3b2050", "drift", 7, 130), GArray.Of("sparkle", "#ff6a8a", "twinkle", 10, 12), GArray.Of("leaf", "#c2334a", "fall", 6, 18)) } } },
            { "sniper", new GDict { { "name", "Hollis Thorne" }, { "short", "Hollis" }, { "title", "The Long Shot of Wolfden" }, { "accent", "#e8873a" },
                { "lore", "Hollis once shot the rope off a hanging bell from across Wolfden Valley to warn the village of wolves. Since then Hollis has hunted bigger things. A hunter's patience, a trapper's cunning, and one arrow is all it takes." },
                { "quote", "Patience. Then one arrow." },
                { "fx", GArray.Of(GArray.Of("leaf", "#e8742c", "fall", 14, 24), GArray.Of("leaf", "#f2b13c", "fall", 9, 20), GArray.Of("smoke", "#d9d2c0", "drift", 4, 150)) } } },
            { "archmage", new GDict { { "name", "Theron Starweave" }, { "short", "Theron" }, { "title", "Keeper of the Falling Stars" }, { "accent", "#a98bff" },
                { "lore", "For three hundred years Theron has watched the sky from the Observatory of Aelun, counting every star that falls. Somewhere along the way he learned to ask them to fall where he points. He is kind, forgetful and very old, and the sky still listens to him." },
                { "quote", "Now where did I leave that star?" },
                { "fx", GArray.Of(GArray.Of("stars", "#d9ccff", "twinkle", 12, 18), GArray.Of("runes", "#a98bff", "orbit", 4, 46), GArray.Of("flame", "#c7a6ff", "meteor", 1, 28)) } } },
            { "necromancer", new GDict { { "name", "Silas Graves" }, { "short", "Silas" }, { "title", "Warden of the Quiet Crypts" }, { "accent", "#7dff9a" },
                { "lore", "Silas was the gravekeeper of Morrow Hill until the night the dead began to whisper to him. He listens to them still. He doesn't raise the fallen to frighten anyone -- only because, as he says, nobody should have to stay down while a friend still needs them." },
                { "quote", "Rest later. We need you now." },
                { "fx", GArray.Of(GArray.Of("wisp", "#8dffa8", "rise", 10, 26), GArray.Of("smoke", "#3f6b52", "drift", 6, 120), GArray.Of("dot", "#b0ffc4", "twinkle", 10, 6)) } } },
            { "golem", new GDict { { "name", "Gorrak Stoneheart" }, { "short", "Gorrak" }, { "title", "The Living Mountain" }, { "accent", "#5fc4e8" },
                { "lore", "Gorrak slept in the side of Mount Kharum for a thousand years, until a war woke him with its noise. The runes carved into him are older than any kingdom. He speaks rarely and slowly, but when he plants his feet, no army has ever moved him." },
                { "quote", "... I ... remain." },
                { "fx", GArray.Of(GArray.Of("runes", "#6fe0ff", "orbit", 3, 44), GArray.Of("shard", "#c9d4dc", "rise", 9, 18), GArray.Of("dot", "#d9f4ff", "rise", 8, 6)) } } },
            { "dragoon", new GDict { { "name", "Kael Wyrmlance" }, { "short", "Kael" }, { "title", "Last Rider of Skyreach" }, { "accent", "#ff6a3a" },
                { "lore", "Kael was the last of the dragon riders of Skyreach, and his dragon was the last to fall. He kept her lance and her fire-red scarf, and taught himself to leap as high as she once flew. When he comes down out of the sky now, he comes down like a dragon." },
                { "quote", "Look up." },
                { "fx", GArray.Of(GArray.Of("flame", "#ff7a3a", "drift", 14, 14), GArray.Of("dot", "#ffc070", "drift", 14, 6), GArray.Of("feather", "#ffd0a0", "drift", 4, 20)) } } },
            { "duelist", new GDict { { "name", "Rafael Montclair" }, { "short", "Rafael" }, { "title", "The Masked Blade" }, { "accent", "#e04a5f" },
                { "lore", "Rafael won four hundred duels in the courts of Montclair and never once took off his mask, not even when the city crowned him its champion. He fights for honour, for applause and, now and then, for a rose. He has never lost, and he would very much like you to try." },
                { "quote", "En garde -- and do try to keep up." },
                { "fx", GArray.Of(GArray.Of("leaf", "#d0304a", "fall", 16, 20), GArray.Of("sparkle", "#ffd76a", "twinkle", 10, 12), GArray.Of("dot", "#ffe6a0", "rise", 8, 5)) } } },
            { "stormcaller", new GDict { { "name", "Torvald Stormcrown" }, { "short", "Torvald" }, { "title", "Voice of the Thunder" }, { "accent", "#6fb6ff" },
                { "lore", "Torvald climbed the Thunder Peaks to ask the storm a question. The storm answered by striking him nine times. He came down with white in his beard and lightning in his hands, and he has never told anyone what the question was." },
                { "quote", "Hear that? The sky is answering." },
                { "fx", GArray.Of(GArray.Of("dot", "#bfe0ff", "rain", 36, 10), GArray.Of("lightning", "#e8f4ff", "flash", 1, 260), GArray.Of("sparkle", "#9fd0ff", "twinkle", 8, 12)) } } },
            { "musketeer", new GDict { { "name", "Captain Armand Belleroc" }, { "short", "Armand" }, { "title", "The King's Last Musket" }, { "accent", "#5a90e6" },
                { "lore", "Armand served in the King's Musketeers until the King lost his crown. He kept his hat, his musket and his manners. Now he fights for whoever pays in gold and good company, and he never fires a shot without tipping his hat first." },
                { "quote", "After you, monsieur. I insist." },
                { "fx", GArray.Of(GArray.Of("smoke", "#e8e2d6", "drift", 6, 130), GArray.Of("sparkle", "#ffe7a0", "twinkle", 10, 12), GArray.Of("feather", "#ffffff", "fall", 4, 22)) } } },
            { "druid", new GDict { { "name", "Elowen Thornbloom" }, { "short", "Elowen" }, { "title", "Voice of the Old Grove" }, { "accent", "#8fe36b" },
                { "lore", "Elowen was found as a child asleep in the roots of the oldest tree in the Old Grove, her antlers already growing. The forest raised her. She speaks for every living thing that cannot, and wherever she walks, flowers follow." },
                { "quote", "Every root remembers." },
                { "fx", GArray.Of(GArray.Of("leaf", "#7fd66b", "fall", 14, 24), GArray.Of("wisp", "#e8ff9a", "twinkle", 14, 12), GArray.Of("dot", "#fff7a0", "rise", 10, 5)) } } },
        };

        public static GDict Of(string hid)
        {
            return CHAMPIONS.Get(hid, new GDict()).D;
        }

        public static string NameOf(string hid)
        {
            return GD.Str(Of(hid).Get("name", hid.Capitalize()));
        }

        public static string ShortOf(string hid)
        {
            return GD.Str(Of(hid).Get("short", hid.Capitalize()));
        }

        public static Color Accent(string hid)
        {
            return Color.FromCode(GD.Str(Of(hid).Get("accent", "#ffd65a")));
        }

        public static string Art(string hid)
        {
            return GD.Fmt(ART, hid);
        }

        public static string CardArt(string hid)
        {
            return GD.Fmt(CARD, hid);
        }
    }
}
