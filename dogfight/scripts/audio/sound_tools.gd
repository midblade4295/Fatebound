class_name SoundTools
extends RefCounted
## Small helpers for audio streams.

static var _looped: Dictionary[AudioStream, AudioStream] = {}


## Returns a seamlessly looping version of [param stream]. The loop files in
## assets/audio are already cut to loop cleanly end to start (see
## tools/audio/process_sounds.py); this just tells Godot to play them that
## way, so nothing depends on per-file import settings.
static func looped(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	if _looped.has(stream):
		return _looped[stream]
	var result: AudioStream = stream
	var wav: AudioStreamWAV = stream as AudioStreamWAV
	if wav != null:
		var copy: AudioStreamWAV = wav.duplicate() as AudioStreamWAV
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD
		copy.loop_begin = 0
		copy.loop_end = roundi(wav.get_length() * float(wav.mix_rate))
		result = copy
	_looped[stream] = result
	return result
