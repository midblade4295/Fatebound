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
            player.volume_db = -22.0 if quiet else -15.0
            player.play()
            return
