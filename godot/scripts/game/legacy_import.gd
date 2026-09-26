extends RefCounted
const Solo=preload("res://scripts/game/solo_campaign.gd")
const C=preload("res://scripts/game/content.gd")
static func convert(progress)->Dictionary:
    var war:Variant=progress.d.get("war")
    if not war is Dictionary:return {"ok":true,"converted":false,"reason":"no web session"}
    if progress.d.native.get("session") is Dictionary:return {"ok":true,"converted":false,"reason":"native session already present"}
    var snap:Variant=war.get("snapshot")
    var now:int=progress.now()
    if int(war.get("sessionBuild",0))!=106 or int(war.get("model",0))!=2 or int(war.get("matchVersion",0))!=3 or not snap is Dictionary or int(snap.get("sessionBuild",0))!=106:
        return {"ok":true,"converted":false,"reason":"incompatible historical web session retained in save; progression is imported"}
    if snap.get("ended",false) or snap.get("lobby",false) or str(war.get("phase",""))=="complete" or int(war.get("endAt",0))<now-60000:
        return {"ok":true,"converted":false,"reason":"finished or expired web session retained; no new rewards synthesized"}
    var roster:Variant=snap.get("heroes");var towers:Variant=snap.get("towers")
    if not roster is Array or roster.size()!=40 or not towers is Array or towers.size()!=10:
        return {"ok":false,"error":"Web battle snapshot is incomplete. Progression is safe; battle conversion was not attempted."}
    var player:Dictionary={}
    var ids:Dictionary={}
    for h in roster:
        if not h is Dictionary or not h.has("id") or ids.has(str(h.id)):return {"ok":false,"error":"Invalid saved battle roster; original retained."}
        ids[str(h.id)]=true
        if str(h.id)==str(war.get("playerId","")):player=h
    if player.is_empty():return {"ok":false,"error":"Saved battle is missing its player; original retained."}
    var saved:Dictionary=progress.d.duplicate(true)
    var e=Solo.new();e.configure(progress);e.start(int(war.startAt),7919)
    progress.store.data=saved
    var state:Dictionary=e.s
    for key in ["tally","rally","ralliesLeft","rallyCdUntil","extraBotAt","bulwarkUntil","exposedUntil","holdUntil","captureRewardAt","spellSurgeUntil","excitement","enemyRallyMarks","allyRallyMarks"]:
        if snap.has(key):state[key]=snap[key].duplicate(true) if snap[key] is Array or snap[key] is Dictionary else snap[key]
    state.id=str(war.id);state.startAt=int(war.startAt);state.endAt=int(war.endAt);state.regulationEnd=int(war.startAt)+300000
    state.phase=str(war.get("phase","day"));state.now=maxi(int(war.startAt),mini(now,int(snap.get("lastTick",now))))
    state.control=war.get("control",[0,0]).duplicate();state.controlDuration=int(war.get("controlDuration",0));state.preview=bool(war.get("preview",false));state.rallyEnergyClaimed=bool(war.get("rallyClaimed",false))
    state.towers=[]
    for i in 10:
        var original:Dictionary=towers[i]
        if not original.get("dmg") is Array or original.dmg.size()!=2:return {"ok":false,"error":"Invalid saved tower; original retained."}
        state.towers.append({"id":i,"name":str(original.get("name",Solo.ROMAN[i])),"pts":int(original.get("pts",3 if i>=8 else (2 if i>=5 else 1))),"dmg":original.dmg.duplicate(),"prev":int(original.get("prev",-1)),"playerFlipPaid":bool(original.get("playerFlipPaid",false)),"playerRewardMult":float(original.get("playerRewardMult",0))})
    var actors:Array=[]
    var ordered:Array=[player]
    for h in roster:
        if str(h.id)!=str(player.id):ordered.append(h)
    for i in ordered.size():
        var original:Dictionary=ordered[i]
        var base:Dictionary=e.s.heroes[mini(i,e.s.heroes.size()-1)].duplicate(true)
        for key in base:
            if original.has(key):base[key]=original[key].duplicate(true) if original[key] is Array or original[key] is Dictionary else original[key]
        base.id="you" if i==0 else str(original.id)
        base.bot=i!=0;base.tower=clampi(int(original.get("tower",0) if original.get("tower")!=null else 0),0,9)
        base.homeTower=base.tower;base.rallyJoin=int(original.get("rallyJoin",0) if original.get("rallyJoin")!=null else 9999999999999)
        base.hp=maxi(0,int(original.get("hp",0)));base.maxHp=maxi(1,int(original.get("maxHp",1)))
        base.shieldSlots=original.get("shieldSlots",[]).duplicate();base.action={};base.lastFaces=null
        base.focusSpent=int(original.get("spentEnergy",0));base.paidRolls=int(original.get("paidRolls",0))
        if i==0:
            base.side=0;base.char=int(progress.d.char);base.weapon=int(progress.d.weapon);base.focus=int(snap.get("focus",4));base.focusAt=int(snap.get("focusAt",now));base.loadout=progress.d.adventure.loadout.duplicate()
            base.ralliesLeft=int(state.ralliesLeft[0]);base.rallyAt=int(state.rallyCdUntil[0]);base.gold=progress.d.gold;base.xp=progress.d.xp
        actors.append(base)
    state.heroes=actors;state.events=[];state.seq=0;state.revision=0
    var old_id:=str(war.playerId)
    for rally in state.rally:
        if rally is Dictionary and rally.get("rollers") is Array:
            for i in rally.rollers.size():
                if str(rally.rollers[i])==old_id:rally.rollers[i]="you"
    var okay:bool=progress.perform(func():
        progress.d.native.importedLegacyWar=war.duplicate(true)
        progress.d.native.session={"kind":"campaign","snapshot":{"seed":e.seed,"state":state},"savedAt":now,"convertedFrom":"web-session106"}
        progress.d.war=null
    )
    return {"ok":okay,"converted":okay,"error":progress.store.last_error if not okay else ""}
