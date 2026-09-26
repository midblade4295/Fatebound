extends Node
# Exact existing Fatebound PCM effects exported to local WAV assets, never fetched during combat.
var voices: Array[AudioStreamPlayer] = []
var cache: Dictionary = {}
var muted := false
var last: Dictionary = {}

func _ready() -> void:
    var cfg := ConfigFile.new()
    if cfg.load("user://native_audio.cfg") == OK:
        muted = bool(cfg.get_value("audio","muted",false))
    for i in 8:
        var player := AudioStreamPlayer.new()
        player.volume_db = -15.0
        add_child(player)
        voices.append(player)
    get_tree().root.focus_exited.connect(stop)

func stop() -> void:
    for player in voices:
        player.stop()

func toggle() -> void:
    muted = not muted
    if muted:
        stop()
    var cfg := ConfigFile.new()
    cfg.set_value("audio","muted",muted)
    cfg.save("user://native_audio.cfg")

func play(cue: String, quiet := false) -> void:
    if muted or not get_window().has_focus():
        return
    var now := Time.get_ticks_msec()
    if now-int(last.get(cue,-9999)) < 90:
        return
    var path := "res://assets/sounds/"+cue+".wav"
    if not cache.has(cue):
        if not ResourceLoader.exists(path):
            return
        cache[cue] = load(path)
    last[cue] = now
    for player in voices:
        if not player.playing:
            player.stream = cache[cue]
            var ui_cue:bool=cue in ["tap","menuOpen","menuClose","equip","purchase","coin","confirm","error","chest","level","energy"]
            var gain:float=0.12*float(levels.master)*float(levels.ui if ui_cue else levels.combat)*(0.40 if quiet else 1.0)
            if gain<=0:return
            player.volume_db = linear_to_db(gain)
            player.play()
            return

var levels:Dictionary={"master":0.75,"combat":0.8,"ui":0.75}
func set_levels(value:Dictionary)->void:
    for key in levels:
        if value.get(key) is float or value.get(key) is int:levels[key]=clampf(float(value[key]),0,1)
    if float(levels.master)<=0:stop()
