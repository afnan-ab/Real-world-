extends "res://scripts/mad_city_assets.gd"

# Optimization layer (top of the stack). What it does, in order of effect:
#  1. The city used to be three huge meshes (buildings, dark windows, lit
#     windows) that were drawn in full even when you only saw a small part of
#     the city. They are split into 80 m chunks: the GPU skips every chunk that
#     is off screen, and far chunks are hidden (buildings 320 m, windows 190 m).
#  2. Dynamic resolution: the 3D resolution goes down when the frame rate drops
#     and up when there is room (50% .. 100%), the HUD stays sharp.
#  3. Sun shadows switch on only when the phone has headroom (and off again if
#     it starts to struggle).
#  4. Distance fog is switched back on: it is cheap, looks better and hides the
#     chunk fade-out.
#  5. Fewer AI cars (16) and pedestrians (24): less CPU, fewer lights.
# Not measured: I cannot run Godot here.

const MC_CHUNK_CELL := 80.0
const MC_BUILDING_RANGE := 320.0
const MC_WINDOW_RANGE := 190.0
const MC_MAX_TRAFFIC := 16
const MC_MAX_PEDS := 24
const MC_SCALE_MIN := 0.5
const MC_SCALE_MAX := 1.0
const MC_BIG_KEY := 99999

var _opt_acc: float = 0.0
var _opt_frames: int = 0
var _opt_shadows_on: bool = false

func _ready() -> void:
    super._ready()
    _opt_chunk_mesh("MC_CityBlocks", MC_BUILDING_RANGE, true)
    _opt_chunk_mesh("MC_WindowsDark", MC_WINDOW_RANGE, false)
    _opt_chunk_mesh("MC_WindowsLit", MC_WINDOW_RANGE, false)
    _opt_trim_actors()
    if _mc_env != null:
        _mc_env.fog_enabled = true

# Split one big triangle-list mesh into per-cell meshes with their own origin.
func _opt_chunk_mesh(node_name: String, range_end: float, shadows: bool) -> void:
    var src: MeshInstance3D = get_node_or_null(node_name) as MeshInstance3D
    if src == null or src.mesh == null or src.mesh.get_surface_count() == 0:
        return
    var arrays: Array = src.mesh.surface_get_arrays(0)
    var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
    var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
    var mat: Material = src.material_override
    var buckets: Dictionary = {}
    var i: int = 0
    var count: int = verts.size()
    while i + 2 < count:
        var a: Vector3 = verts[i]
        var b: Vector3 = verts[i + 1]
        var c: Vector3 = verts[i + 2]
        var big: bool = (a - b).length() > 100.0 or (b - c).length() > 100.0 or (a - c).length() > 100.0
        var key: Vector2i = Vector2i(MC_BIG_KEY, MC_BIG_KEY)
        if not big:
            var cen: Vector3 = (a + b + c) / 3.0
            key = Vector2i(floori(cen.x / MC_CHUNK_CELL), floori(cen.z / MC_CHUNK_CELL))
        if not buckets.has(key):
            buckets[key] = {"v": [], "n": [], "c": []}
        var bk: Dictionary = buckets[key]
        var bv: Array = bk["v"]
        var bn: Array = bk["n"]
        var bc: Array = bk["c"]
        for k in range(3):
            bv.append(verts[i + k])
            bn.append(norms[i + k])
            bc.append(cols[i + k])
        i += 3

    for key_v in buckets.keys():
        var kk: Vector2i = key_v
        var is_big: bool = kk.x == MC_BIG_KEY
        var center := Vector3.ZERO
        if not is_big:
            center = Vector3((float(kk.x) + 0.5) * MC_CHUNK_CELL, 0.0, (float(kk.y) + 0.5) * MC_CHUNK_CELL)
        var bucket: Dictionary = buckets[key_v]
        var lv: Array = bucket["v"]
        var ln: Array = bucket["n"]
        var lc: Array = bucket["c"]
        var pv := PackedVector3Array()
        pv.resize(lv.size())
        for j in range(lv.size()):
            pv[j] = (lv[j] as Vector3) - center
        var arr: Array = []
        arr.resize(Mesh.ARRAY_MAX)
        arr[Mesh.ARRAY_VERTEX] = pv
        arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(ln)
        arr[Mesh.ARRAY_COLOR] = PackedColorArray(lc)
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
        var mi := MeshInstance3D.new()
        mi.name = "%s_chunk" % node_name
        mi.mesh = mesh
        mi.material_override = mat
        mi.position = center
        if shadows:
            mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        else:
            mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        if not is_big:
            mi.visibility_range_end = range_end
        add_child(mi)
    src.queue_free()

func _opt_trim_actors() -> void:
    for i in range(traffic.size() - 1, MC_MAX_TRAFFIC - 1, -1):
        var d: Dictionary = traffic[i]
        var node: Node3D = d["node"]
        if is_instance_valid(node):
            node.queue_free()
        traffic.remove_at(i)
    for i in range(npcs.size() - 1, MC_MAX_PEDS - 1, -1):
        var d2: Dictionary = npcs[i]
        var node2: Node3D = d2["node"]
        if is_instance_valid(node2):
            node2.queue_free()
        npcs.remove_at(i)

func _process(delta: float) -> void:
    super._process(delta)
    _opt_acc += delta
    _opt_frames += 1
    if _opt_acc < 1.5:
        return
    var fps: float = float(_opt_frames) / _opt_acc
    _opt_acc = 0.0
    _opt_frames = 0

    var vp: Viewport = get_viewport()
    var old_scale: float = vp.scaling_3d_scale
    var s: float = old_scale
    if fps < 30.0:
        s = maxf(MC_SCALE_MIN, s - 0.08)
    elif fps > 52.0:
        s = minf(MC_SCALE_MAX, s + 0.04)
    if absf(s - old_scale) > 0.001:
        vp.scaling_3d_scale = s

    var sun: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D
    if sun != null:
        if fps > 55.0 and s >= 0.9 and not _opt_shadows_on:
            sun.shadow_enabled = true
            sun.directional_shadow_max_distance = 60.0
            _opt_shadows_on = true
        elif fps < 40.0 and _opt_shadows_on:
            sun.shadow_enabled = false
            _opt_shadows_on = false
