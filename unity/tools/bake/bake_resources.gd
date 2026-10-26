extends SceneTree
# Fatebound -> Unity: bakes every scene/resource the game loads (.glb .gltf .scn .tscn .res .tres under res://assets)
# into data the port's engine-free loader (Assets/Fatebound/GUI/Scene3D/BakedLoader.cs) rebuilds as the Godot-facade
# objects, so `load("res://assets/kaykit/heroes/Knight.glb").instantiate()` in the port gives the node tree Godot gives.
#
#   godot --headless --path godot -s unity/tools/bake/bake_resources.gd -- [--out DIR] [--dry] [--manifest-only] [PATH|DIR ...]
#   (unity/tools/bake/bake.sh wraps it; no PATH = everything under res://assets)
#
# Output: <out>/<path>.bytes (out = unity/Assets/Resources/res; Unity reads it as the TextAsset "<file>.glb", the host's
# ReadFile("res://<path>")), plus <out>/_baked/*.png (textures that live inside a scene file) and
# <out>/_baked/manifest.json (every baked res:// path: ResourceLoader.exists answers from it without loading the file).
#
# ---------------------------------------------------------------------------------------------- the format (bake 1)
# Each .bytes file is var_to_bytes(D), D a Dictionary holding no Objects:
#   "bake": 1                      format version
#   "path": "res://..."            the source path
#   "type": "PackedScene" or the main resource's class ("AnimationLibrary", "Image", "Resource"...)
#   "resources": [entry...]        the file's resource table: every sub-resource reached from the main resource / the
#                                  scene's nodes, each once (shared resources stay shared), dependencies BEFORE the
#                                  resources that use them (the loader creates and fills them in this order)
#   "main": int                    (not PackedScene) index of the main resource in "resources"
#   "nodes": [node...]             (PackedScene) the tree instantiate() gives in Godot, pre-order (parents first)
# A resource entry: {"class": Godot class, "name": resource_name (if set), "script": "res://x.gd" (if any),
#   "props": {name: value} -- the stored properties (PROPERTY_USAGE_STORAGE) whose value differs from the class default
#            (what Godot's own savers write), in get_property_list() order, values as Godot holds them after import,
#   "surfaces": [...] (ArrayMesh only, see below)}
# A node entry: {"class", "name", "parent": node index (-1: the root), "owner": node index (-1: none), "props",
#   "groups": [..] (if any), "script" (if any)}. Only nodes the scene owns (owner set) are kept, as PackedScene does.
# Values are Godot Variants; an Object inside a value (at any depth) is replaced by a one-key Dictionary:
#   {"@res": i}                     entry i of "resources"
#   {"@ext": "res://path", "@type": class}  a resource in its own file (a texture/png/jpg, a script, a shader, another
#                                   baked file): the loader load()s it by path
#   {"@node": "rel/path"}           a node of the same scene (path from the scene root)
#   (null for a null Object). No real dictionary in the assets has these keys (the bake checks).
# Special cases:
#   ArrayMesh: "_surfaces" (Godot's GPU-packed blob) and "shadow_mesh" (a depth-only copy the port doesn't draw) are
#     not stored; instead "surfaces": [{"primitive": int, "format": surface_get_format (flags: custom formats, 8 bone
#     weights...), "aabb": the surface's AABB as Godot keeps it (computed at import from the uncompressed vertices, blend
#     shapes included), "arrays": surface_get_arrays(i) (ARRAY_MAX entries, decompressed), "blend_shapes":
#     surface_get_blend_shape_arrays(i) (if any), "material": value (if any), "name": surface_get_name(i) (if set)}].
#     LODs are not stored (the port draws LOD 0).
#   Textures that are files (res://assets/x.png, imported by Godot from the glb next to it): {"@ext": their path} (the
#     png/jpg itself is mirrored by tools/sync_assets.py). Textures with no file of their own (embedded in a scene):
#     written as PNG to _baked/<source>_<n>.png (..._normal.png when used as a normal map: imported linear) and
#     referenced by that path; Editor/AssetImport.cs imports _baked/ textures as Godot imports 3D textures (VRAM
#     compressed, mipmaps, repeat). Procedural textures (GradientTexture1D, CurveTexture...) are resource entries.
#   Image: its stored "data" property as Godot stores it ({width, height, format name, mipmaps, data bytes}).
#   Metadata ("metadata/x") is kept (nodes: set_meta).
# Godot runs headless on the project's import cache (.godot): the values are exactly the imported ones.

const EXTS := ["glb", "gltf", "scn", "tscn", "res", "tres"]
const BAKE_VERSION := 1
# stored properties written elsewhere in the entry (or not at all)
const SKIP := {"script": true, "resource_path": true, "resource_local_to_scene": true, "resource_scene_unique_id": true,
	"resource_name": true}
const SKIP_CLASS := {"ArrayMesh": {"_surfaces": true, "shadow_mesh": true}}
const MARKERS := ["@res", "@ext", "@node"]
const FILE_TEXTURES := ["CompressedTexture2D", "ImageTexture", "PortableCompressedTexture2D", "CompressedTexture3D"]

var repo := ""
var out_root := ""
var dry := false
var verbose := false

# per file
var file_path := ""
var res_index := {}          # Resource -> index in res_table (-1 while its properties are being encoded)
var res_table := []
var scene_root: Node = null
var png_n := 0
var cur_prop := ""           # the property being encoded (normal maps get a _normal png name)

# totals
var classes := {}            # class -> {prop: count}
var warnings := {}
var baked := {}              # res:// path -> bytes written
var pngs := []
var failed := []

func _init() -> void:
	repo = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	out_root = repo.path_join("unity/Assets/Resources/res")
	var targets: Array = []
	var manifest_only := false
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--out":
			i += 1
			out_root = args[i]
		elif a == "--dry":
			dry = true
		elif a == "--verbose":
			verbose = true
		elif a == "--manifest-only":
			manifest_only = true
		else:
			targets.append(a if a.begins_with("res://") else "res://" + a.trim_prefix("godot/"))
		i += 1
	if targets.is_empty():
		targets = ["res://assets"]
	var files: Array = []
	for t in targets:
		if t.get_extension().to_lower() in EXTS:
			files.append(t)
		else:
			_collect(t.trim_suffix("/"), files)
	files.sort()
	var t0 := Time.get_ticks_msec()
	if not manifest_only:
		for f in files:
			_bake_file(f)
	if not dry:
		_write_manifest()
	_report(files.size(), Time.get_ticks_msec() - t0)
	quit(1 if not failed.is_empty() else 0)

func _collect(dir: String, out: Array) -> void:
	if FileAccess.file_exists(dir.path_join(".gdignore")) or dir.begins_with("res://.godot"):
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var p := dir.path_join(f)
		# what load() can open: an imported scene (.glb/.gltf with its .import) or a Godot resource file
		if f.get_extension().to_lower() in EXTS and ResourceLoader.exists(p):
			out.append(p)
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)

func _warn(msg: String) -> void:
	if not warnings.has(msg):
		warnings[msg] = 0
		push_warning("bake: " + msg)
	warnings[msg] += 1

# ---------------------------------------------------------------------------------------------- one file
func _bake_file(path: String) -> void:
	file_path = path
	res_index = {}
	res_table = []
	scene_root = null
	png_n = 0
	var r: Resource = load(path)
	if r == null:
		failed.append(path)
		push_error("bake: can't load " + path)
		return
	var d := {"bake": BAKE_VERSION, "path": path, "type": r.get_class()}
	if r is PackedScene:
		d["type"] = "PackedScene"
		var inst: Node = (r as PackedScene).instantiate()
		scene_root = inst
		var nodes := []
		_add_node(inst, -1, {}, nodes)
		d["nodes"] = nodes
		inst.free()
		scene_root = null
	else:
		var m = _enc_res(r, true)
		d["main"] = m["@res"] if m is Dictionary and m.has("@res") else -1
	d["resources"] = res_table
	var bytes := var_to_bytes(d)
	if bytes.is_empty():
		failed.append(path)
		push_error("bake: var_to_bytes failed for " + path)
		return
	baked[path] = bytes.size()
	if verbose:
		print("baked ", path, " ", bytes.size(), " bytes, ", res_table.size(), " resources")
	if dry:
		return
	var out := out_root.path_join(path.trim_prefix("res://") + ".bytes")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		failed.append(path)
		push_error("bake: can't write " + out)
		return
	f.store_buffer(bytes)
	f.close()

func _add_node(n: Node, parent: int, index: Dictionary, nodes: Array) -> void:
	if n != scene_root and n.owner == null:
		return          # (made by a script at runtime, not part of the scene)
	var i := nodes.size()
	index[n] = i
	var e := {"class": n.get_class(), "name": String(n.name), "parent": parent, "owner": index.get(n.owner, -1)}
	nodes.append(e)
	if n.get_script() != null:
		e["script"] = (n.get_script() as Script).resource_path
	e["props"] = _props(n)
	var groups := []
	for g in n.get_groups():
		if not String(g).begins_with("_"):
			groups.append(String(g))
	if not groups.is_empty():
		e["groups"] = groups
	for c in n.get_children():
		_add_node(c, i, index, nodes)

# ---------------------------------------------------------------------------------------------- properties
func _is_default(cls: String, name: String, v) -> bool:
	# (a property ClassDB has no default for -- "bones/0/rest", "tracks/1/keys" -- gives null: kept unless null too)
	var d = ClassDB.class_get_property_default_value(cls, name)
	if v == null:
		return d == null
	if d == null:
		return false
	return typeof(v) == typeof(d) and v == d

func _props(o: Object) -> Dictionary:
	var cls := o.get_class()
	var skip_cls: Dictionary = SKIP_CLASS.get(cls, {})
	var out := {}
	var st: Dictionary = classes.get_or_add(cls, {})
	for pr in o.get_property_list():
		if not (pr.usage & PROPERTY_USAGE_STORAGE):
			continue
		var name: String = pr.name
		if SKIP.has(name) or skip_cls.has(name):
			continue
		var v = o.get(name)
		if _is_default(cls, name, v):
			continue
		cur_prop = name
		out[name] = _enc(v)
		var key := name
		var sl := name.find("/")
		if sl > 0 and name.substr(sl + 1, 1).is_valid_int():
			key = name.substr(0, sl) + "/N/" + name.substr(name.find("/", sl + 1) + 1) if name.find("/", sl + 1) > 0 else name.substr(0, sl) + "/N"
		st[key] = st.get(key, 0) + 1
	return out

func _enc(v):
	match typeof(v):
		TYPE_OBJECT:
			if v == null:
				return null
			if v is Resource:
				return _enc_res(v, false)
			if v is Node and scene_root != null and (v == scene_root or scene_root.is_ancestor_of(v)):
				return {"@node": String(scene_root.get_path_to(v))}
			_warn("object of class %s in a property: stored as null" % v.get_class())
			return null
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				if k is String and k in MARKERS:
					_warn("a dictionary has the reserved key %s (%s)" % [k, file_path])
				d[_enc(k)] = _enc(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for e in v:
				a.append(_enc(e))
			return a
		TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
			_warn("%s value in a stored property: stored as null" % type_string(typeof(v)))
			return null
	return v

func _enc_res(r: Resource, main: bool):
	if res_index.has(r):
		if res_index[r] < 0:
			push_error("bake: resource cycle in %s (%s)" % [file_path, r.get_class()])
			return null
		return {"@res": res_index[r]}
	var p := r.resource_path
	if not main and p != "" and not p.contains("::") and p != file_path:
		return {"@ext": p, "@type": r.get_class()}
	if not main and r.get_class() in FILE_TEXTURES:
		return {"@ext": _save_png(r as Texture2D), "@type": "Texture2D"}
	if r is Script:
		_warn("built-in script in %s: not stored" % file_path)
		return null
	if r.resource_local_to_scene:
		_warn("local-to-scene resource (%s) in %s: shared by every instance in the port" % [r.get_class(), file_path])
	var hint := cur_prop
	res_index[r] = -1
	var e := {"class": r.get_class()}
	if r.resource_name != "":
		e["name"] = r.resource_name
	if r.get_script() != null:
		e["script"] = (r.get_script() as Script).resource_path
	e["props"] = _props(r)
	if r is ArrayMesh:
		e["surfaces"] = _surfaces(r as ArrayMesh)
	elif r is Mesh and not (r is PrimitiveMesh):
		_warn("mesh class %s: only its stored properties are kept" % r.get_class())
	var i := res_table.size()
	res_table.append(e)
	res_index[r] = i
	cur_prop = hint
	return {"@res": i}

func _surfaces(m: ArrayMesh) -> Array:
	var out := []
	var packed: Array = m.get("_surfaces")          # (only for each surface's AABB: Godot's, from the uncompressed import)
	for i in m.get_surface_count():
		var s := {"primitive": m.surface_get_primitive_type(i), "format": m.surface_get_format(i), "arrays": m.surface_get_arrays(i)}
		if i < packed.size() and packed[i] is Dictionary and packed[i].has("aabb"):
			s["aabb"] = packed[i]["aabb"]
		var bs := m.surface_get_blend_shape_arrays(i)
		if not bs.is_empty():
			s["blend_shapes"] = bs
		var mat := m.surface_get_material(i)
		if mat != null:
			cur_prop = "material"
			s["material"] = _enc_res(mat, false)
		if m.surface_get_name(i) != "":
			s["name"] = m.surface_get_name(i)
		out.append(s)
	return out

func _save_png(t: Texture2D) -> String:
	var img := t.get_image()
	var stem := file_path.trim_prefix("res://").replace("/", "_").replace(".", "_")
	var name := "%s_%d%s.png" % [stem, png_n, "_normal" if cur_prop.contains("normal") else ""]
	png_n += 1
	var rp := "res://_baked/" + name
	if img == null:
		_warn("embedded texture without image data in %s" % file_path)
		return rp
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	pngs.append(rp)
	if not dry:
		DirAccess.make_dir_recursive_absolute(out_root.path_join("_baked"))
		var err := img.save_png(out_root.path_join("_baked/" + name))
		if err != OK:
			push_error("bake: can't write " + name)
	return rp

# ---------------------------------------------------------------------------------------------- manifest / report
func _write_manifest() -> void:
	# every baked path, from what is on disk (a partial bake keeps the others)
	var all := {}
	_scan_baked(out_root, "", all)
	var mf := out_root.path_join("_baked/manifest.json")
	DirAccess.make_dir_recursive_absolute(mf.get_base_dir())
	var keys := all.keys()
	keys.sort()
	var f := FileAccess.open(mf, FileAccess.WRITE)
	f.store_string(JSON.stringify({"bake": BAKE_VERSION, "files": keys}, "\t"))
	f.close()

func _scan_baked(dir: String, rel: String, all: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".bytes"):
			var src := f.trim_suffix(".bytes")
			if src.get_extension().to_lower() in EXTS:
				all["res://" + rel.path_join(src).trim_prefix("/")] = true
	for sub in d.get_directories():
		_scan_baked(dir.path_join(sub), rel.path_join(sub) if rel != "" else sub, all)

func _report(n: int, ms: int) -> void:
	var total := 0
	var per_dir := {}
	for p in baked:
		total += baked[p]
		var dir: String = p.trim_prefix("res://").get_base_dir()
		var parts := dir.split("/")
		var top := "/".join(parts.slice(0, mini(parts.size(), 3)))
		per_dir[top] = per_dir.get(top, 0) + baked[p]
	print("bake: %d files, %d baked (%.1f MB), %d embedded textures -> _baked/, %d failed, %.1f s" % [n, baked.size(),
		total / 1048576.0, pngs.size(), failed.size(), ms / 1000.0])
	var dirs := per_dir.keys()
	dirs.sort()
	for k in dirs:
		print("  %-40s %8.1f MB" % [k, per_dir[k] / 1048576.0])
	if verbose or dry:
		var cl := classes.keys()
		cl.sort()
		for c in cl:
			var ps: Array = classes[c].keys()
			ps.sort()
			print("class ", c, ": ", ", ".join(ps))
	for w in warnings:
		print("warning (x%d): %s" % [warnings[w], w])
	for f in failed:
		print("FAILED: ", f)
