class_name FateboundArenaApi
extends Node

const ArenaWireScript = preload("res://scripts/arena_wire.gd")

const DEFAULT_URL := "https://136-113-125-3.sslip.io/fatebound/arena"
const DEFAULT_IDENTITY_PATH := "user://fatebound_godot_identity.json"

var base_url := DEFAULT_URL
var identity_path := DEFAULT_IDENTITY_PATH
var player_id := ""
var token := ""
var wire = ArenaWireScript.new()
var bytes_received := 0
var request_count := 0

func _ready() -> void:
    _load_identity()

func _load_identity() -> void:
    if not FileAccess.file_exists(identity_path):
        return
    var file := FileAccess.open(identity_path, FileAccess.READ)
    if file == null:
        return
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary and str(parsed.get("playerId","")) != "" and str(parsed.get("token","")).length() >= 20:
        player_id = str(parsed["playerId"])
        token = str(parsed["token"])

func _save_identity(data: Dictionary) -> void:
    var file := FileAccess.open(identity_path, FileAccess.WRITE)
    if file != null:
        file.store_string(JSON.stringify(data))
    player_id = str(data.get("playerId",""))
    token = str(data.get("token",""))

func _make_url(route: String, synchronized: bool, full: bool) -> String:
    var url := base_url.trim_suffix("/") + route
    if not synchronized:
        return url
    var query: Array[String] = ["transport=2"]
    if not full:
        var c := wire.cursor()
        if not c.is_empty():
            query.append("match=" + str(c.get("match","")).uri_encode())
            query.append("revision=" + str(c.get("revision",0)))
            query.append("seq=" + str(c.get("seq",0)))
    return url + "?" + "&".join(query)

func _request(route: String, body: Variant = null, auth := true, full := false) -> Dictionary:
    var synchronized := ["/state","/action","/queue","/cancel"].has(route)
    var http := HTTPRequest.new()
    add_child(http)
    http.timeout = 10.0
    http.accept_gzip = true
    http.body_size_limit = 4 * 1024 * 1024
    var headers := PackedStringArray(["Accept: application/json"])
    if auth and token != "":
        headers.append("Authorization: Bearer " + token)
    var method := HTTPClient.METHOD_GET
    var payload := ""
    if body != null:
        method = HTTPClient.METHOD_POST
        headers.append("Content-Type: application/json")
        payload = JSON.stringify(body)
    var err := http.request(_make_url(route,synchronized,full),headers,method,payload)
    if err != OK:
        http.queue_free()
        return {"ok":false,"status":0,"error":"Could not start HTTP request (%s)" % err}
    var response: Array = await http.request_completed
    http.queue_free()
    request_count += 1
    var result := int(response[0])
    var code := int(response[1])
    var raw: PackedByteArray = response[3]
    bytes_received += raw.size()
    if result != HTTPRequest.RESULT_SUCCESS:
        return {"ok":false,"status":0,"error":"Network request failed (%s)" % result}
    var parsed = JSON.parse_string(raw.get_string_from_utf8())
    if not parsed is Dictionary:
        return {"ok":false,"status":code,"error":"Arena returned invalid JSON"}
    var data: Dictionary = parsed
    var envelope: Dictionary = data.get("state",data)
    if envelope.has("match") and envelope["match"] is Dictionary and int(envelope["match"].get("wire",0)) == ArenaWireScript.VERSION:
        var decoded := wire.decode(envelope["match"])
        if decoded.get("_resync",false) and not full:
            wire.clear()
            var replacement := await _request("/state",null,true,true)
            if not replacement.get("ok",false):
                return replacement
            if data.has("state"):
                data["state"] = replacement
            else:
                data = replacement
        elif decoded.has("_error"):
            return {"ok":false,"status":code,"error":decoded["_error"]}
        else:
            envelope["match"] = decoded
            if data.has("state"):
                data["state"] = envelope
            else:
                data = envelope
    if code < 200 or code >= 300:
        return {"ok":false,"status":code,"error":str(data.get("error","Arena request failed")),"state":data.get("state",{})}
    data["ok"] = true
    data["status_code"] = code
    return data

func ensure_session(display_name := "Godot Player") -> Dictionary:
    if player_id != "" and token != "":
        var profile := await _request("/profile")
        if profile.get("ok",false):
            return {"ok":true,"playerId":player_id,"token":token,"profile":profile}
        if int(profile.get("status",0)) != 401:
            return profile
        player_id = ""
        token = ""
        wire.clear()
    var fresh := await _request("/session",{"name":display_name},false)
    if fresh.get("ok",false):
        _save_identity(fresh)
    return fresh

func profile() -> Dictionary:
    return await _request("/profile")

func queue(char_index := 0, weapon_index := 0, loadout := ["barrage","bulwark"]) -> Dictionary:
    return await _request("/queue",{"char":char_index,"weapon":weapon_index,"loadout":loadout})

func state(full := false) -> Dictionary:
    return await _request("/state",null,true,full)

func cancel() -> Dictionary:
    return await _request("/cancel",{})

func action(kind: String, match_id: String, payload := {}) -> Dictionary:
    var command: Dictionary = payload.duplicate(true)
    command["type"] = kind
    command["matchId"] = match_id
    command["actionId"] = _uuid()
    var first := await _request("/action",command)
    if first.get("ok",false) or int(first.get("status",0)) in [400,401,403,409,429]:
        return first
    return await _request("/action",command)

func claim(match_id: String, shard_kind := "steel") -> Dictionary:
    return await _request("/claim",{"matchId":match_id,"shardKind":shard_kind})

func _uuid() -> String:
    var crypto := Crypto.new()
    var bytes := crypto.generate_random_bytes(16)
    var out := ""
    for b in bytes:
        out += "%02x" % int(b)
    return out
