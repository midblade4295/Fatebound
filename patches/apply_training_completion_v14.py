from pathlib import Path
p=Path("fatebound.html")
t=p.read_text(encoding="utf-8")
if "vc14TrainingCompletionFix" in t:
    print("already")
    raise SystemExit(0)

start=t.find("const BATTLE_LESSONS=[")
if start<0:
    raise SystemExit("BATTLE_LESSONS missing")
end=t.find("\n];",start)
if end<0:
    raise SystemExit("BATTLE_LESSONS end missing")
end+=3

arr="""const BATTLE_LESSONS=[
 {title:'The real battle screen',text:'This practice uses the real dice, heroes, tower map, Focus system, and combat controls. Training never charges Fate and does not change live war results.',target:'#board'},
 {title:'Fate and Focus are different',text:'Fate is persistent soft currency outside combat. Focus is the resource you spend inside the match for roll multipliers and ALL-IN. Matches themselves are free to enter.',target:'.stat'},
 {title:'Roll an attack',text:'Tap ROLL. This training result is scripted to land three swords so you can see a triple attack and how combat pressure begins.',target:'#roll',action:'roll',faces:['S','S','S']},
 {title:'Tower control wins the map',text:'Damage and pressure at a tower help your guild take or defend it. Do not stay on one objective automatically — rotate when another lane matters more.',target:'.tbar'},
 {title:'Build your shields',text:'Tap ROLL for three shields. Shields absorb damage before health and can keep you standing during an enemy push.',target:'#roll',action:'roll',faces:['H','H','H']},
 {title:'Read enemy pressure',text:'Enemy telegraphs and Focus indicators show where a dangerous action may be forming. Use that information to defend, rotate, or counterattack.',target:'#board'},
 {title:'Gain Focus',text:'Roll the Focus result. During battle these resource faces refill Focus so you can afford stronger multipliers without spending Fate.',target:'#roll',action:'roll',faces:['E','E','E']},
 {title:'Choose a multiplier',text:'Tap the multiplier once to increase it. Higher multipliers spend more Focus and amplify the roll, so use them when the situation is worth the cost.',target:'#mults',action:'mult'},
 {title:'Try a multiplied attack',text:'Tap ROLL at ×2. The same triple now creates a larger swing while consuming more Focus.',target:'#roll',action:'roll',faces:['S','S','S'],mult:2},
 {title:'ALL-IN is a commitment',text:'With enough Focus, cycling beyond your normal multipliers can reach ALL-IN. It commits your available Focus to one major roll, so save it for a meaningful swing.',target:'#mults'},
 {title:'Critical attacks',text:'Tap ROLL for critical symbols. Critical results can trigger a close-up skill sequence and produce a much stronger hit.',target:'#roll',action:'roll',faces:['C','C','C']},
 {title:'Triples charge battle spells',text:'Triples also charge your battle spell. A charged spell can break a defense, hold an objective, or create pressure at the right moment.',target:'#roll'},
 {title:'Guild gifts',text:'Tap ROLL for gifts, then choose a guildmate. Stored damage can be saved and activated later by the recipient.',target:'#roll',action:'giftRoll',faces:['F','F','F']},
 {title:'Choose the bonus recipient',text:'Tap the glowing card. Its displayed value already includes the special bonus.',target:'#friends .gift-bonus',action:'gift'},
 {title:'Use your ultimate',text:'Your training ultimate is fully charged. Tap it now. In a live match, battle actions refill the ultimate meter over time.',target:'#ultBar',action:'ult'},
 {title:'Open the war map',text:'Tap Map. Fatebound has three strategic lanes: Outposts, Camp, and Courtyard. Rotating between them is a core part of winning.',target:'#tbarBack',action:'map'},
 {title:'Choose the next tower',text:'Tap a tower to enter its battlefield. Look at where your guild is winning or losing instead of simply choosing the nearest objective.',target:'#warcv',action:'tower'},
 {title:'Call your guild',text:'Tap Rally to ask teammates to focus this tower. Rally is for coordinated pressure, so use it on an objective that can change the match.',target:'#rally',action:'rally'},
 {title:'Crowns, spells, and the final push',text:'Triples charge spells, tower control shapes crowns, and the last part of the 5-minute clock is where rotations matter most. A tied finish can create sudden-death pressure.',target:'#heat'},
 {title:'Return home safely',text:'Tap Home. Outside a live locked battle, you can return to the hub without losing your permanent hero or resources. Training progress is isolated from real war progress.',target:'nav [data-tab="home"]',action:'home'},
 {title:'Review your hero',text:'Tap Hero to inspect attack power, critical attack, equipment, upgrades, and your ultimate. Stronger progression improves what each successful battle action can do.',target:'nav [data-tab="hero"]',action:'hero'},
 {title:'Ready for a real 5-minute battle',text:'Training is complete. Win by managing Focus, choosing smart multipliers, reacting to enemy pressure, rotating across lanes, charging spells, using Rally and your ultimate, and finishing with the stronger crown position.',target:'nav [data-tab="home"]',finish:true}
];"""
t=t[:start]+arr+t[end:]
marker='''<script id="vc14TrainingCompletionFix">window.__vc14TrainingCompletionFix=1;</script>'''
t=t.replace("</body>",marker+"</body>",1)
p.write_text(t,encoding="utf-8")
print("updated",p.stat().st_size)
