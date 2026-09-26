extends RefCounted
# Values are extracted verbatim from the approved v114 source, not hand-retuned.
const SOURCE_SHA := "84697859827127e8c9285b0cf57578a8fc2bcedcb3cf8d3247772f0309f3b4e9"
const SEASON_EPOCH := 1767571200000
const SEASON_MS := 2592000000
const REGEN_MS := 600000
static var _tables: Dictionary = {}
static func tables() -> Dictionary:
    if _tables.is_empty():
        var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/v114-content.json"))
        assert(data.source_sha256 == SOURCE_SHA)
        _tables = data.tables
    return _tables
static func get_table(key: String) -> Variant:
    return tables().get(key)
static func jsround(value: float) -> int:
    return int(floor(value+0.5))
static func now_ms() -> int:
    return int(Time.get_unix_time_from_system()*1000)
static func season_id(at: int) -> int:
    return maxi(0,int(floor(float(at-SEASON_EPOCH)/SEASON_MS)))
static func local_day(at: int) -> String:
    var offset := int(Time.get_time_zone_from_system().bias)*60
    var d := Time.get_datetime_dict_from_unix_time(int(at/1000)+offset)
    return "%s %s %02d %d" % [["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][int(d.weekday)],["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][int(d.month)-1],int(d.day),int(d.year)]
static func xp_need(level: int) -> int:
    return 60+30*level
static func shard_kind(weapon: int) -> String:
    var weapons: Array = tables().WEAPONS
    return str(tables().SHARD_OF[weapons[clampi(weapon,0,8)].cls])
static func character(ci: int) -> Dictionary:
    return tables().CHARS[clampi(ci,0,4)]
static func weapon(wi: int) -> Dictionary:
    return tables().WEAPONS[clampi(wi,0,8)]
static func resolve(faces: Array) -> Dictionary:
    if faces.size() != 3:
        return {}
    var counts := {"S":0,"C":0,"H":0,"G":0,"F":0,"E":0}
    for f in faces:
        if not counts.has(f):return {}
        counts[f] += 1
    var symbol: Variant = null
    for n in [3,2]:
        for key in counts:
            if counts[key] == n:
                symbol = key
                break
        if symbol != null:break
    var tier := "triple" if symbol != null and counts[symbol] == 3 else ("pair" if symbol != null else "none")
    var action: Variant = symbol if symbol != null else ("S" if counts.S > 0 else ("G" if counts.G > 0 else null))
    return {"action":action,"symbol":action,"tier":tier,"units":{"none":1,"pair":2,"triple":5}[tier],"gold":{"none":5,"pair":25,"triple":200}[tier] if action == "G" else 0,"energy":(5 if tier == "triple" else 1) if action == "E" else 0}
