extends RefCounted
const C = preload("res://scripts/game/content.gd")
signal committed
var path := "user://fatebound-save.json"
var data: Dictionary = {}
var last_error := ""
var revision := 0
var writable := true
var memory_only := false
var fault_inject := false # tests only; no UI or network control exposes it

func _init(save_path := "user://fatebound-save.json", load_now := true) -> void:
    path = save_path
    data = normalized(defaults())
    if load_now:load_save()

static func defaults() -> Dictionary:
    var d: Dictionary = C.get_table("SAVE_DEF").duplicate(true)
    d.schema = 2
    d.adventure = {"loadout":["barrage","bulwark"],"mastery":{},"receipts":[],"path":"assault"}
    d.rollTrack = {"progress":0,"ready":0,"gold":0,"shards":{"steel":0,"arcane":0,"fletch":0}}
    d.damageGifts = {}
    d.allyProgress = {}
    d.allyRolls = {}
    d.titles = []
    d.native = {"version":3,"journal":{},"chat":[],"chatDraft":"","name":"You","settings":{"reduceMotion":false,"master":0.75,"combat":0.8,"ui":0.75},"cloud":{},"receiptsCursor":0}
    return d

static func _merge_missing(target: Dictionary, baseline: Dictionary) -> void:
    for k in baseline:
        var v: Variant = baseline[k]
        if not target.has(k) or (v is Dictionary and not target[k] is Dictionary) or (v is Array and not target[k] is Array):
            target[k] = v.duplicate(true) if v is Array or v is Dictionary else v
        elif v is Dictionary:
            _merge_missing(target[k],v)

static func normalized(value: Dictionary) -> Dictionary:
    var d := value.duplicate(true)
    _merge_missing(d,defaults())
    for key in ["gold","xp","bonus","tokens","rank","energyAt","cap"]:
        if not (d[key] is int or d[key] is float) or not is_finite(float(d[key])) or float(d[key]) < 0:
            d[key] = defaults()[key]
    d.level = maxi(1,int(d.get("level",5)))
    d.char = clampi(int(d.get("char",0)),0,4)
    var owned: Array = []
    for index in d.owned:
        if (index is int or index is float) and float(index) == int(index) and int(index) >= 0 and int(index) < 9 and not owned.has(int(index)):
            owned.append(int(index))
    if not owned.has(0):owned.push_front(0)
    d.owned = owned
    for group in [d.season,d.daily]:
        for key in (["free","prem"] if group == d.season else ["q","done"]):
            var indexes: Array = []
            for entry_value in group.get(key,[]):
                if (entry_value is int or entry_value is float) and float(entry_value) == int(entry_value) and int(entry_value) >= 0 and int(entry_value) < (10 if group == d.season else 9) and not indexes.has(int(entry_value)):
                    indexes.append(int(entry_value))
            group[key] = indexes
    if d.get("boss") is Dictionary:
        for key in ["tiers","milestones"]:
            var indexes: Array = []
            for entry_value in d.boss.get(key,[]):
                if (entry_value is int or entry_value is float) and int(entry_value)>=0 and int(entry_value)<4 and not indexes.has(int(entry_value)):indexes.append(int(entry_value))
            d.boss[key]=indexes
    if not owned.has(int(d.weapon)):d.weapon = 0
    for key in ["stats","relics","shards"]:
        for item in defaults()[key]:
            if not (d[key][item] is int or d[key][item] is float) or not is_finite(float(d[key][item])) or float(d[key][item]) < 0:
                d[key][item] = defaults()[key][item]
    for key in d.tiers:
        d.tiers[key] = clampi(int(d.tiers[key]),0,3)
    var p: Dictionary = d.adventure
    if not p.loadout is Array or p.loadout.size() != 2 or p.loadout[0] == p.loadout[1] or not ["barrage","bulwark","horn","surge"].has(p.loadout[0]) or not ["barrage","bulwark","horn","surge"].has(p.loadout[1]):
        p.loadout = ["barrage","bulwark"]
    if not ["assault","guardian","commander"].has(p.path):p.path = "assault"
    if not p.get("lastMoment") is Dictionary and p.get("lastScenario") is Dictionary:p.lastMoment=p.lastScenario.duplicate(true)
    for key in p.mastery.keys():
        if not p.mastery[key] is Dictionary:p.mastery[key] = {}
        _merge_missing(p.mastery[key],{"assault":0,"guardian":0,"commander":0})
    # Unfinished chest selection is returned to storage, never discarded or auto-rerolled.
    if d.get("pendingOpenChest") is Dictionary:
        d.chests.append(d.pendingOpenChest)
        d.pendingOpenChest = null
    return d

func load_save() -> bool:
    for source in [path,path+".bak"]:
        if not FileAccess.file_exists(source):continue
        var raw := FileAccess.get_file_as_string(source)
        var parsed = JSON.parse_string(raw)
        if parsed is Dictionary and parsed.get("owned") is Array:
            data = normalized(parsed)
            last_error = "Recovered previous backup" if source.ends_with(".bak") else ""
            return true
    if FileAccess.file_exists(path):
        last_error = "Save could not be read. Original file retained; restore a backup before playing."
        writable = false
    return false

func commit() -> bool:
    if memory_only:
        revision += 1
        committed.emit()
        return true
    if not writable or fault_inject:
        last_error = "Progress could not be saved. Nothing was charged."
        return false
    var bytes := JSON.stringify(data).to_utf8_buffer()
    if bytes.size() > 4*1024*1024:
        last_error = "Save exceeds the supported 4 MB limit. Export it before continuing."
        return false
    var target := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(target.get_base_dir())
    var tmp := target+".next"
    var file := FileAccess.open(tmp,FileAccess.WRITE)
    if file == null:
        last_error = "Storage is unavailable; progress was not written."
        return false
    file.store_buffer(bytes)
    file.flush()
    file.close()
    var verify := FileAccess.get_file_as_bytes(tmp)
    if verify != bytes or not JSON.parse_string(verify.get_string_from_utf8()) is Dictionary:
        last_error = "Save verification failed. Your previous save was kept."
        return false
    if FileAccess.file_exists(target):
        if DirAccess.copy_absolute(target,target+".bak") != OK:
            last_error = "Backup could not be written. Previous save retained."
            return false
    if DirAccess.rename_absolute(tmp,target) != OK:
        last_error = "Atomic save replacement failed. Previous save retained."
        return false
    revision += 1
    last_error = ""
    committed.emit()
    return true

func transaction(work: Callable) -> bool:
    var before := data.duplicate(true)
    var outcome: Variant = work.call()
    if outcome is bool and not outcome:
        data = before
        return false
    if not commit():
        data = before
        return false
    return true

func parse_import(raw: String) -> Dictionary:
    if raw.to_utf8_buffer().size() > 4*1024*1024:
        return {"ok":false,"error":"Save file is too large."}
    var item = JSON.parse_string(raw)
    if item is String:item = JSON.parse_string(item)
    if item is Dictionary and item.has("save"):
        item = JSON.parse_string(item.save) if item.save is String else item.save
    if item is Dictionary and item.has("fatebound-save"):
        item = JSON.parse_string(item["fatebound-save"]) if item["fatebound-save"] is String else item["fatebound-save"]
    if not item is Dictionary or not item.get("owned") is Array:
        return {"ok":false,"error":"This is not a Fatebound progression save. No data changed."}
    for key in ["gold","level","xp","tokens"]:
        if item.has(key) and (not (item[key] is int or item[key] is float) or not is_finite(float(item[key])) or float(item[key]) < 0 or float(item[key]) > 1e12):
            return {"ok":false,"error":"Invalid "+key+" in imported save. No data changed."}
    var value := normalized(item)
    return {"ok":true,"save":value,"summary":"Level %d · %d gold · %d weapons · %d stored chests" % [int(value.level),int(value.gold),value.owned.size(),value.chests.size()]}

func install_import(value: Dictionary) -> bool:
    # Keep a separately named, timestamped export before replacing preview progress.
    var backup := ProjectSettings.globalize_path(path)+".pre-import-"+str(C.now_ms())+".json"
    var f := FileAccess.open(backup,FileAccess.WRITE)
    if f == null:
        last_error = "Could not make the pre-import backup. Import cancelled."
        return false
    if FileAccess.file_exists(path):f.store_buffer(FileAccess.get_file_as_bytes(path))
    else:f.store_string(JSON.stringify(data))
    f.flush();f.close()
    var old_writable:=writable
    writable=true
    var okay:=transaction(func():data = normalized(value))
    if not okay:writable=old_writable
    return okay

func export_text() -> String:
    return JSON.stringify({"format":"fatebound-save","source":"native-port-0.3","exportedAt":C.now_ms(),"save":data},"  ")
