extends "res://scripts/mad_city_assets.gd"

# Optimization + "bright low-poly" style layer (top of the stack).
#  1. The city used to be three huge meshes (buildings, dark windows, lit
#     windows) that were drawn in full even when you only saw a small part of
#     the city. They are split into 80 m chunks: the GPU skips every chunk that
#     is off screen, and far chunks are hidden (buildings 320 m, windows 190 m).
#  2. Dynamic resolution: the 3D resolution goes down when the frame rate drops
#     and up when there is room (50% .. 100%), the HUD stays sharp.
#  3. Sun shadows switch on only when the phone has headroom.
#  4. Distance fog is on: cheap, and it hides the chunk fade-out.
#  5. Style: every building gets its own bright colour (red, orange, yellow,
#     teal, blue, cream, pink, green, violet) chosen per building, and the whole
#     image gets a little more saturation and contrast. The traffic and
#     pedestrian counts are back at their full values.
# Not measured: I cannot run Godot here.

const MC_CHUNK_CELL := 80.0
const MC_BUILDING_RANGE := 320.0
const MC_WINDOW_RANGE := 190.0
const MC_MAX_TRAFFIC := 26
const MC_MAX_PEDS := 36
const MC_SCALE_MIN := 0.5
const MC_SCALE_MAX := 1.0
const MC_BIG_KEY := 99999
const MC_STYLE_PALETTE: Array = [
    Color("#e0533d"), Color("#f2a33a"), Color("#f4d35e"), Color("#3fa7a0"),
    Color("#4f86c6"), Color("#e8dcc4"), Color("#c0577a"), Color("#6aa84f"),
    Color("#d9d9d9"), Color("#8a6fb3")
]

var _opt_acc: float = 0.0
var _opt_frames: int = 0
var _opt_shadows_on: bool = false

func _ready() -> void:
    super._ready()
    _opt_chunk_mesh("MC_CityBlocks", MC_BUILDING_RANGE, true, true)
    _opt_chunk_mesh("MC_WindowsDark", MC_WINDOW_RANGE, false, false)
    _opt_chunk_mesh("MC_WindowsLit", MC_WINDOW_RANGE, false, false)
    _opt_trim_actors()
    if _mc_env != null:
        _mc_env.fog_enabled = true
        _mc_env.adjustment_enabled = true
        _mc_env.adjustment_saturation = 1.25
        _mc_env.adjustment_contrast = 1.06
        _mc_env.adjustment_brightness = 1.03

# Bright colour for a grey building wall triangle. All triangles of one building
# land in the same quadrant of its block, so the whole building gets one colour.
func _opt_vivid(a: Vector3, b: Vector3, c: Vector3, orig: Color) -> Color:
    var cen: Vector3 = (a + b + c) / 3.0
    var bi: int = floori((cen.x - 10.0) / MC_PITCH)
    var bj: int = floori((cen.z - 10.0) / MC_PITCH)
    var qx: int = 1 if fposmod(cen.x - 10.0, MC_PITCH) >= 30.0 else 0
    var qz: int = 1 if fposmod(cen.z - 10.0, MC_PITCH) >= 30.0 else 0
    var h: int = (bi * 73856093) ^ (bj * 19349663) ^ (qx * 83492791) ^ (qz * 49979687)
    var pal: Color = MC_STYLE_PALETTE[absi(h) % MC_STYLE_PALETTE.size()]
    var shade: float = clampf(orig.v / 0.62, 0.8, 1.1)
    return Color(minf(pal.r * shade, 1.0), minf(pal.g * shade, 1.0), minf(pal.b * shade, 1.0))

# Split one big triangle-list mesh into per-cell meshes with their own origin.
func _opt_chunk_mesh(node_name: String, range_end: float, shadows: bool, vivid: bool) -> void:
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
        var out_col: Color = cols[i]
        if vivid and (not big) and maxf(a.y, maxf(b.y, c.y)) > 1.0 and out_col.s < 0.25 and out_col.v > 0.35:
            out_col = _opt_vivid(a, b, c, out_col)
        if not buckets.has(key):
            buckets[key] = {"v": [], "n": [], "c": []}
        var bk: Dictionary = buckets[key]
        var bv: Array = bk["v"]
        var bn: Array = bk["n"]
        var bc: Array = bk["c"]
        for k in range(3):
            bv.append(verts[i + k])
            bn.append(norms[i + k])
            bc.append(out_col if vivid else cols[i + k])
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

# Only removes actors above the caps (the caps equal the full counts now).
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
