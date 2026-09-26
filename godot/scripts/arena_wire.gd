class_name FateboundArenaWire
extends RefCounted

const VERSION := 2
const GLOBAL := ["version","balanceVersion","id","mode","practice","startAt","endAt","regulationEnd","phase","ended","now","revision","seq","control","controlDuration","rally","holds","score","winner","objective","completedAt"]
const HERO := ["id","name","bot","substitute","connected","side","char","weapon","level","atk","maxHp","hp","tower","shieldSlots","downUntil","focus","focusAt","spell","loadout","ult","forcedCrits","rampage","surgeUntil","rollAt","moveAt","spellAt","rallyAt","ralliesLeft","damage","shieldsBroken","kos","rolls","paidRolls","triples","focusSpent","spellsCast","ultsUsed","streak","hot","lastFaces","giftDamage","storedDamage"]
const TOWER := ["id","name","pts","dmg","prev"]

var snapshots: Dictionary = {}
var latest: Dictionary = {}
var history := 96
var stats := {"full":0,"delta":0,"stale":0,"resync":0}

func clear() -> void:
    snapshots.clear()
    latest.clear()

func cursor() -> Dictionary:
    if latest.is_empty():
        return {}
    return {"match":latest.get("id",""),"revision":latest.get("revision",0),"seq":latest.get("seq",0)}

func _copy(value: Variant) -> Variant:
    if value is Dictionary or value is Array:
        return value.duplicate(true)
    return value

func _patch(target: Dictionary, data: Variant, allowed: Array) -> bool:
    if not data is Dictionary:
        return false
    for key in data.keys():
        if not allowed.has(key):
            return false
        target[key] = _copy(data[key])
    return true

func _valid(snapshot: Dictionary) -> bool:
    if not snapshot.has("id") or not snapshot.has("revision") or not snapshot.has("seq"):
        return false
    var heroes: Array = snapshot.get("heroes",[])
    var towers: Array = snapshot.get("towers",[])
    if heroes.size() != 20 or towers.size() != 10:
        return false
    var ids := {}
    for hero in heroes:
        if not hero is Dictionary:
            return false
        var hid := str(hero.get("id",""))
        if hid.is_empty() or ids.has(hid):
            return false
        ids[hid] = true
        if float(hero.get("hp",-1)) < 0 or int(hero.get("tower",-1)) < 0 or int(hero.get("tower",-1)) >= 10:
            return false
    return true

func decode(packet: Dictionary) -> Dictionary:
    if int(packet.get("wire",0)) != VERSION:
        return packet.duplicate(true)
    var room_id := str(packet.get("id",""))
    var next: Dictionary
    if packet.has("full"):
        next = packet["full"].duplicate(true)
        stats.full += 1
    else:
        var base_key := "%s:%s" % [room_id, packet.get("base",-1)]
        if not snapshots.has(base_key):
            stats.resync += 1
            return {"_resync":true,"error":"Arena baseline expired"}
        next = snapshots[base_key].duplicate(true)
        if not _patch(next, packet.get("set",{}), GLOBAL):
            return {"_error":"Invalid arena global patch"}
        for spec in [[packet.get("heroes",[]),"heroes",HERO,20],[packet.get("towers",[]),"towers",TOWER,10]]:
            var items: Array = spec[0]
            if items.size() > int(spec[3]):
                return {"_error":"Invalid arena slot count"}
            var seen := {}
            for entry in items:
                if not entry is Array or entry.size() != 2:
                    return {"_error":"Invalid arena patch entry"}
                var idx := int(entry[0])
                if idx < 0 or idx >= int(spec[3]) or seen.has(idx):
                    return {"_error":"Invalid arena slot index"}
                seen[idx] = true
                if not _patch(next[spec[1]][idx], entry[1], spec[2]):
                    return {"_error":"Invalid arena slot patch"}
        stats.delta += 1
    if not _valid(next):
        return {"_error":"Invalid arena snapshot"}
    if str(next.get("id","")) != room_id or int(next.get("revision",-1)) != int(packet.get("revision",-2)) or int(next.get("seq",-1)) != int(packet.get("seq",-2)):
        return {"_error":"Arena revision mismatch"}
    var events: Array = packet.get("events",[])
    if events.size() > 80:
        return {"_error":"Arena event overflow"}
    if not latest.is_empty() and str(latest.get("id","")) == room_id and int(next.get("revision",0)) < int(latest.get("revision",0)):
        stats.stale += 1
    else:
        latest = next.duplicate(true)
    var key := "%s:%s" % [room_id,next.get("revision",0)]
    snapshots[key] = next.duplicate(true)
    while snapshots.size() > history:
        snapshots.erase(snapshots.keys()[0])
    next["events"] = events.duplicate(true)
    return next

static func winning_dice(faces: Array) -> Dictionary:
    if faces.size() != 3:
        return {"indices":[],"tier":"none","symbol":null}
    var count := {}
    for face in faces:
        if not ["S","C","H","G","E","F"].has(face):
            return {"indices":[],"tier":"none","symbol":null}
        count[face] = int(count.get(face,0)) + 1
    var symbol: Variant = null
    for key in count:
        if count[key] == 3:
            symbol = key
            break
    if symbol == null:
        for key in count:
            if count[key] == 2:
                symbol = key
                break
    if symbol == null:
        symbol = "S" if faces.has("S") else ("G" if faces.has("G") else null)
    var indices: Array = []
    if symbol != null:
        for i in faces.size():
            if faces[i] == symbol:
                indices.append(i)
    var tier := "triple" if symbol != null and int(count.get(symbol,0)) == 3 else ("pair" if symbol != null and int(count.get(symbol,0)) == 2 else "none")
    return {"indices":indices,"tier":tier,"symbol":symbol}
