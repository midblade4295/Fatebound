extends SceneTree

func _init() -> void:
    var report := {"frames_verified":0,"strips":0,"max_width":0}
    var clips := {"idle":[0,6],"attack":[6,8],"big":[14,8],"hit":[22,3],"death":[25,1]}
    for row in 45:
        var source := "res://assets/art/row_%02d.webp" % row
        var image := Image.load_from_file(source)
        assert(image != null and image.get_size() == Vector2i(8840,280))
        image.convert(Image.FORMAT_RGBA8)
        for clip in clips:
            var count: int = clips[clip][1]
            var start: int = clips[clip][0]
            var strip := image.get_region(Rect2i(start*340,0,count*340,280))
            var path := "res://assets/art/hero_%02d_%s.webp" % [row,clip]
            assert(strip.save_webp(path,false) == OK)
            var verify := Image.load_from_file(path)
            verify.convert(Image.FORMAT_RGBA8)
            assert(strip.get_data() == verify.get_data(),path)
            report.frames_verified += count
            report.strips += 1
            report.max_width = maxi(report.max_width,count*340)
        # Remove only extracted source copies after all clips verify; original HTML stays intact.
        assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(source)) == OK)
    var file := FileAccess.open("res://reports/ART_PIXEL_VERIFICATION.json",FileAccess.WRITE)
    file.store_string(JSON.stringify(report,"  ")+"\n")
    print("ART_SPLIT_PASS ",JSON.stringify(report))
    quit(0)
