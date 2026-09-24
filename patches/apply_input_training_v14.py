from pathlib import Path

html = Path("fatebound.html")
t = html.read_text(encoding="utf-8")
if "inputTrainingFixV14" in t:
    print("already applied")
    raise SystemExit(0)

def must_replace(old, new, label):
    global t
    n = t.count(old)
    print(label, "count", n)
    if n != 1:
        raise SystemExit(f"{label}: expected 1 match, got {n}")
    t = t.replace(old, new, 1)

def replace_array(marker, replacement, label):
    global t
    start = t.find(marker)
    if start < 0:
        raise SystemExit(f"{label}: start marker missing")
    end = t.find("\n];", start)
    if end < 0:
        raise SystemExit(f"{label}: end marker missing")
    end += 3
    t = t[:start] + replacement + t[end:]
    print(label, "replaced")

# --- Input recovery: only lock navigation while the actual live battle screen is visible.
must_replace(
    'function matchLocked(){ try{ return !!(M && !M.ended && !M.lobby && typeof inWar==="function" && inWar() && war() && war().phase!=="complete"); }catch(_){ return false; } }',
    'function battleUiVisible(){ const b=document.getElementById("battle"); return !!(b && !b.hidden && document.body.classList.contains("ui-battle-v2")); }\nfunction matchLocked(){ try{ return !!(battleUiVisible() && M && !M.ended && !M.lobby && typeof inWar==="function" && inWar() && war() && war().phase!=="complete"); }catch(_){ return false; } }',
    "matchLocked"
)

must_replace(
    "function live(){try{return !!(M&&!M.ended&&!M.lobby&&typeof inWar==='function'&&inWar());}catch(_){return false;}}",
    "function live(){try{const b=document.getElementById('battle');return !!(b&&!b.hidden&&document.body.classList.contains('ui-battle-v2')&&M&&!M.ended&&!M.lobby&&typeof inWar==='function'&&inWar());}catch(_){return false;}}",
    "clash live"
)

# --- Hub copy
for old, new in [
    ("$('hubSub').textContent='Train, gear up, and help your guild. Battle when you’re ready.';",
     "$('hubSub').textContent='Master Focus, control lanes, earn crowns, and push your guild to victory.';"),
    ("$('hubWarText').textContent=started?'Your 5-minute guild battle is in progress. Jump back in.':'Fight for tower control in a fast 5-minute match. Pressure rises after 2:00 and the final minute boosts attacks.';",
     "$('hubWarText').textContent=started?'Your 5-minute guild battle is in progress. Jump back in.':'Matches are free to enter. Build Focus, take towers across three lanes, and finish with more crowns before the 5-minute clock expires.';"),
    ("$('hubTrainingText').textContent=t?.done?'Training complete. Revisit any lesson whenever you like.':`Free practice · no energy spent${t?.step?' · lesson '+(t.step+1)+' of '+LESSONS.length:''}`;",
     "$('hubTrainingText').textContent=t?.done?'Training complete. Replay it anytime to practice the new battle systems.':`Free practice · no Fate cost · Focus, lanes, spells and crowns${t?.step?' · lesson '+(t.step+1)+' of '+LESSONS.length:''}`;")
]:
    if old in t:
        t = t.replace(old, new, 1)
        print("hub copy updated")

# --- Rebuild overview training around current mechanics.
lessons = """const LESSONS=[
 {title:'Welcome to Fatebound',text:'Battles last 5 minutes and are free to enter. Your objective is to help Brass Company control towers, earn crowns, and finish ahead when the clock expires.',action:'Learn the battle'},
 {title:'Choose your hero',text:'Each hero has a unique ultimate. Pick one below. You can change heroes and equipment later from the Hero page.',kind:'hero'},
 {title:'Roll to create actions',text:'Dice drive combat. Matching symbols produce stronger results. In battle, rolls use Focus — not Fate. Tap ROLL to see a scripted triple.',kind:'roll'},
 {title:'Attack and take control',text:'Sword and critical results damage the enemy presence at your tower. More pressure helps your guild capture or defend that objective.',kind:'attack'},
 {title:'Protect your hero',text:'Shields absorb incoming damage before health. You can hold up to 3 shield slots, and stronger shields can replace weaker ones.',kind:'shield'},
 {title:'Focus and multipliers',text:'Focus is your in-match combat resource. It regenerates during the fight and is gained from battle results. Higher multipliers spend more Focus. With enough Focus you can use ALL-IN for one large swing.',kind:'mult'},
 {title:'Guild gifts',text:'Gift results can send stored help to a guildmate. The glowing recipient gets the special bonus. Stored damage can be activated later, even if the player was offline when it arrived.',kind:'gift'},
 {title:'Three battle lanes',text:'The map is divided into Outposts, Camp, and Courtyard. Move where your guild needs pressure most. Capturing important towers and controlling key areas contributes to your crown result.',kind:'tower'},
 {title:'Triples charge battle spells',text:'Triples do more than hit harder: they charge your battle spell. Spells can create a sudden tactical advantage, so deciding when to spend one matters.',action:'Continue'},
 {title:'Enemy telegraphs',text:'Watch highlighted towers and enemy Focus indicators. They warn you where pressure is building so you can defend, move, or counterattack before a push lands.',action:'Continue'},
 {title:'Use your ultimate',text:'Battle actions charge your hero’s ultimate. When the meter is full, activate it for the hero’s signature power.',kind:'ult'},
 {title:'Crowns and the clock',text:'The match lasts 5 minutes. Tower flips, lane control, and the final battle state determine crowns. Late-match warnings matter, and a tied fight can move into sudden-death pressure.',action:'Continue'},
 {title:'Fate is not an entry ticket',text:'Fate is persistent soft currency for optional bonuses and progression. Wars and raids no longer charge Fate just to play, so you can keep battling without waiting for an entry resource.',action:'Continue'},
 {title:'You’re ready',text:'Build Focus, choose the right multiplier, react to enemy pressure, charge spells with triples, use your ultimate, and fight for the towers that will secure the crown lead.',action:'Finish training'}
];"""
replace_array("const LESSONS=[", lessons, "LESSONS")

# Update the interactive multiplier practice from the retired energy model.
if "mult:'<div class=\"practice-stat\" id=\"practiceMult\">×1 · 1 energy · 500 damage</div><button data-practice=\"mult\">TRY ×30</button>'," in t:
    t = t.replace(
        "mult:'<div class=\"practice-stat\" id=\"practiceMult\">×1 · 1 energy · 500 damage</div><button data-practice=\"mult\">TRY ×30</button>',",
        "mult:'<div class=\"practice-stat\" id=\"practiceMult\">FOCUS 4/8 · ×1 · 500 damage</div><button data-practice=\"mult\">TRY ALL-IN</button>',",
        1
    )
if "else if(kind==='mult'){$('practiceMult').textContent='×30 · 30 energy · 15,000 damage';lessonDone('30 times the cost and 30 times the base reward. This example spent no energy.');}" in t:
    t = t.replace(
        "else if(kind==='mult'){$('practiceMult').textContent='×30 · 30 energy · 15,000 damage';lessonDone('30 times the cost and 30 times the base reward. This example spent no energy.');}",
        "else if(kind==='mult'){$('practiceMult').textContent='FOCUS 8/8 · ALL-IN x16 · big swing';lessonDone('Multipliers spend Focus, and ALL-IN commits your available Focus for one large roll. Fate is not spent.');}",
        1
    )

# Improve practice feedback for the new systems.
if "Three swords! A triple attack is stronger than a pair. Real rolls can also give mixed results." in t:
    t = t.replace(
        "Three swords! A triple attack is stronger than a pair. Real rolls can also give mixed results.",
        "Three swords! Triples hit harder and also charge your battle spell in a live match.",
        1
    )
if "selected. In a real battle, roll here to help your guild take or defend it." in t:
    t = t.replace(
        "selected. In a real battle, roll here to help your guild take or defend it.",
        "selected. In a real battle, pressure this tower to capture or defend its lane and improve your crown position.",
        1
    )

# --- Rebuild real-battle guided lessons using the existing supported actions.
battle_lessons = """const BATTLE_LESSONS=[
 {title:'The real battle screen',text:'This practice uses the real dice, heroes, tower map, Focus system, and combat controls. Training never charges Fate and does not change live war results.',target:'#board'},
 {title:'Fate and Focus are different',text:'Fate is persistent soft currency outside combat. Focus is the resource you spend inside the match for roll multipliers and ALL-IN. Matches themselves are free to enter.',target:'.stat'},
 {title:'Roll an attack',text:'Tap ROLL. This training result is scripted to land three swords so you can see a triple attack and how combat pressure begins.',target:'#roll',action:'roll',faces:['S','S','S']},
 {title:'Tower control wins the map',text:'Damage and pressure at a tower help your guild take or defend it. Do not stay on one objective automatically — move when another lane matters more.',target:'.tbar'},
 {title:'Build your shields',text:'Tap ROLL for three shields. Shields absorb damage before health and can keep you standing during an enemy push.',target:'#roll',action:'roll',faces:['H','H','H']},
 {title:'Read enemy pressure',text:'Enemy telegraphs and Focus indicators show where a dangerous action may be forming. Use that information to defend, rotate, or counterattack.',target:'#board'},
 {title:'Gain Focus',text:'Roll the Focus result. During a battle these resource faces refill Focus so you can afford stronger multipliers without spending Fate.',target:'#roll',action:'roll',faces:['E','E','E']},
 {title:'Choose a multiplier',text:'Tap the multiplier once to increase it. Higher multipliers spend more Focus and amplify the roll, so use them when the situation is worth the cost.',target:'#mults',action:'mult'},
 {title:'Try a multiplied attack',text:'Tap ROLL at ×2. The same triple now creates a larger swing while consuming more Focus.',target:'#roll',action:'roll',faces:['S','S','S'],mult:2},
 {title:'ALL-IN is a commitment',text:'When enough Focus is available, cycling past your normal multipliers can reach ALL-IN. It commits your available Focus to one major roll, so timing matters.',target:'#mults'},
 {title:'Critical attacks',text:'Tap ROLL for critical symbols. Critical results can trigger a close-up skill sequence and produce a much stronger hit.',target:'#roll',action:'roll',faces:['C','C','C']},
 {title:'Triples charge spells',text:'Triples also charge your battle spell. Once charged, your spell gives you another tactical tool for breaking a defense or protecting an important objective.',target:'#roll'},
 {title:'Guild gifts',text:'Tap ROLL for gifts, then choose a guildmate. Stored damage can be saved and activated later by the recipient.',target:'#roll',action:'giftRoll',faces:['F','F','F']},
 {title:'Choose the bonus recipient',text:'Tap the glowing card. Its displayed value already includes the special bonus.',target:'#friends .gift-bonus',action:'gift'},
 {title:'Use your ultimate',text:'Your training ultimate is fully charged. Tap it now. In a live match, battle actions refill the ultimate meter over time.',target:'#ultBar',action:'ult'},
 {title:'Open the war map',text:'Tap Map. Fatebound has three strategic lanes: Outposts, Camp, and Courtyard. Rotating between them is a core part of winning.',target:'#tbarBack',action:'map'},
 {title:'Choose the next tower',text:'Tap a tower to enter its battlefield. Look at where your guild is winning or losing instead of simply choosing the nearest objective.',target:'#warcv',action:'tower'},
 {title:'Win the 5-minute battle',text:'Finish with the stronger crown position when the clock expires. Late-match warnings and sudden-death pressure make the final decisions especially important.',target:'#board'}
];"""
replace_array("const BATTLE_LESSONS=[", battle_lessons, "BATTLE_LESSONS")

# Runtime safety net: no invisible/stale battle layer should be able to freeze the hub.
recovery = r'''
<style id="inputTrainingFixV14">
canvas#fx,#battleAtmos,#heroMoment,#suddenBanner{pointer-events:none!important}
[hidden]{pointer-events:none!important}
</style>
<script id="inputTrainingRecoveryV14">
(()=>{
 if(window.__inputTrainingRecoveryV14)return;
 window.__inputTrainingRecoveryV14=1;
 const battleVisible=()=>{
   const b=document.getElementById('battle');
   return !!(b && !b.hidden && document.body.classList.contains('ui-battle-v2'));
 };
 const recover=()=>{
   try{
     if(!battleVisible()){
       document.body.classList.remove('clash-lock','v2-final','v2-final30','v2-sudden');
     }
     const fx=document.getElementById('fx');
     if(fx)fx.style.pointerEvents='none';
   }catch(_){}
 };
 document.addEventListener('visibilitychange',recover);
 window.addEventListener('pageshow',recover);
 document.addEventListener('pointerdown',recover,{capture:true,passive:true});
 setInterval(recover,750);
 recover();
})();
</script>
'''
if "</body>" not in t:
    raise SystemExit("body end missing")
t = t.replace("</body>", recovery + "</body>", 1)

html.write_text(t, encoding="utf-8")

# Bump Android build for a distinct fixed build.
gradle = Path("android/app/build.gradle")
g = gradle.read_text(encoding="utf-8")
if 'versionCode 13' in g:
    g = g.replace('versionCode 13', 'versionCode 14', 1)
if 'versionName "1.0.12"' in g:
    g = g.replace('versionName "1.0.12"', 'versionName "1.0.13"', 1)
gradle.write_text(g, encoding="utf-8")

print("patched", html.stat().st_size)
