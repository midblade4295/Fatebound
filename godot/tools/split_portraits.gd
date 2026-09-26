extends SceneTree
func _init():
    var path:=""
    for name in DirAccess.get_files_at("res://assets/portraits"):
        if name.begins_with("source.") and not name.ends_with(".import"):path="res://assets/portraits/"+name
    assert(not path.is_empty())
    var image:=Image.load_from_file(path);assert(image!=null)
    print("PORTRAIT_SOURCE_SIZE ",image.get_size())
    assert(image.get_size()==Vector2i(4320,3000))
    image.convert(Image.FORMAT_RGBA8)
    for row in 45:
        var cell:=image.get_region(Rect2i((row%9)*480,(row/9)*600,480,600))
        var target:="res://assets/portraits/portrait_%02d.webp"%row
        assert(cell.save_webp(target,false)==OK)
        var check:=Image.load_from_file(target);check.convert(Image.FORMAT_RGBA8)
        assert(cell.get_data()==check.get_data())
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    print("PORTRAIT_PIXEL_PASS 45")
    quit(0)
