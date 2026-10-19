extends "res://scripts/world.gd"

# Mad City port - Phase 1: city layout + traffic.
# This script extends the existing world.gd and replaces the old hand-placed
# layout with Mad City's grid: 9 x 9 roads, 80 m apart, 20 m wide, 60 m city
# blocks (sidewalk slabs with buildings or parks), traffic lights on every
# junction and AI cars that follow the grid and turn at junctions.
# The player scripts are untouched (only the world boundary is widened in
# player_mc.gd / vehicle_mc.gd).

const MC_N := 4
const MC_PITCH := 80.0
const MC_EXT := 320.0
const MC_SLAB_SIZE := 60.0
const MC_SLAB_TOP := 0.34
const MC_ASPHALT_HALF := 340.0
const MC_WORLD := 470.0
const MC_TERRAIN_CELLS := 118
const MC_CITY_HALF := 345.0
const MC_BLEND := 90.0
const MC_MARK_Y := 0.255
const MC_TRAFFIC_COUNT := 26
const MC_PED_COUNT := 36
const MC_START := Vector3(30.0, 0.0, 12.0)

# Delivery points sit on sidewalks / parks (never inside buildings).
const MC_MISSIONS: Array = [
    {"name": "CLINIC DELIVERY", "target": Vector3(-146.0, 0.0, 14.0), "reward": 250},
    {"name": "CITY DOCUMENTS", "target": Vector3(94.0, 0.0, -14.0), "reward": 300},
    {"name": "NORTH DEPOT SUPPLY", "target": Vector3(14.0, 0.0, -146.0), "reward": 350},
    {"name": "MARKET COURIER", "target": Vector3(-14.0, 0.0, 146.0), "reward": 275},
    {"name": "EAST SIDE PARCEL", "target": Vector3(174.0, 0.0, 14.0), "reward": 400},
    {"name": "WEST SIDE PARCEL", "target": Vector3(-174.0, 0.0, -14.0), "reward": 225}
]

var _mc_phase: int = 0
var _mc_signal_time: float = 0.0
var _mc_sig_mm: MultiMesh
var _mc_sig_tags: PackedInt32Array = PackedInt32Array()
var _mc_lit_mat: StandardMaterial3D

# ---------------------------------------------------------------------------
# Small mesh batcher: boxes and quads with vertex colours in one draw call.
# ---------------------------------------------------------------------------

class MCBatch:
    var verts := PackedVector3Array()
    var norms := PackedVector3Array()
    var cols := PackedColorArray()

    func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
        verts.append(a)
        verts.append(b)
        verts.append(c)
        norms.append(n)
        norms.append(n)
        norms.append(n)
        cols.append(col)
        cols.append(col)
        cols.append(col)

    # a,b,c,d go around the face; n is the outward normal. Winding is fixed
    # automatically so Godot (clockwise front faces) always draws the outside.
    func face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
        var cr: Vector3 = (b - a).cross(c - a)
        if cr.dot(n) > 0.0:
            _tri(a, c, b, n, col)
            _tri(a, d, c, n, col)
        else:
            _tri(a, b, c, n, col)
            _tri(a, c, d, n, col)

    func quad(center: Vector3, right: Vector3, up: Vector3, n: Vector3, col: Color) -> void:
        face(center - right - up, center + right - up, center + right + up, center - right + up, n, col)

    func box(c: Vector3, s: Vector3, col: Color) -> void:
        var hx: float = s.x * 0.5
        var hy: float = s.y * 0.5
        var hz: float = s.z * 0.5
        face(c + Vector3(hx, -hy, -hz), c + Vector3(hx, -hy, hz), c + Vector3(hx, hy, hz), c + Vector3(hx, hy, -hz), Vector3.RIGHT, col)
        face(c + Vector3(-hx, -hy, -hz), c + Vector3(-hx, -hy, hz), c + Vector3(-hx, hy, hz), c + Vector3(-hx, hy, -hz), Vector3.LEFT, col)
        face(c + Vector3(-hx, hy, -hz), c + Vector3(hx, hy, -hz), c + Vector3(hx, hy, hz), c + Vector3(-hx, hy, hz), Vector3.UP, col)
        face(c + Vector3(-hx, -hy, hz), c + Vector3(hx, -hy, hz), c + Vector3(hx, hy, hz), c + Vector3(-hx, hy, hz), Vector3.BACK, col)
        face(c + Vector3(-hx, -hy, -hz), c + Vector3(hx, -hy, -hz), c + Vector3(hx, hy, -hz), c + Vector3(-hx, hy, -hz), Vector3.FORWARD, col)

    func build(mat: Material, node_name: String, shadows: bool) -> MeshInstance3D:
        if verts.is_empty():
            return null
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = verts
        arrays[Mesh.ARRAY_NORMAL] = norms
        arrays[Mesh.ARRAY_COLOR] = cols
        var mesh := ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        var mi := MeshInstance3D.new()
        mi.name = node_name
        mi.mesh = mesh
        mi.material_override = mat
        if shadows:
            mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        else:
            mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        return mi

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

func _ready() -> void:
    rng.seed = 190428
    _setup_environment()
    _lower_scene_failsafe_ground()
    _make_terrain()
    _make_outer_scenery()
    _make_city_and_roads()
    _make_mc_markings()
    _make_mc_signals()
    _make_mc_traffic()
    _make_mc_driveables()
    _make_mc_pedestrians()
    _setup_weather_particles()
    _step18_visual_setup()
    _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref != null:
        _player_ref.global_position = Vector3(MC_START.x, MC_SLAB_TOP + 1.2, MC_START.z)
    _refresh_dynamic_sector_cache(true)
    _apply_vehicle_lod(true)
    _set_hud_label("Mission", "FREE ROAM  •  PRESS ACTION FOR A MISSION")

# ---------------------------------------------------------------------------
# Terrain: flat city square, hills outside it
# ---------------------------------------------------------------------------

func _road_distance(x: float, z: float) -> float:
    var kx: float = clampf(roundf(x / MC_PITCH), -float(MC_N), float(MC_N))
    var kz: float = clampf(roundf(z / MC_PITCH), -float(MC_N), float(MC_N))
    var d_zline: float = Vector2(x - kx * MC_PITCH, maxf(absf(z) - MC_EXT, 0.0)).length()
    var d_xline: float = Vector2(z - kz * MC_PITCH, maxf(absf(x) - MC_EXT, 0.0)).length()
    return minf(d_zline, d_xline)

func _height(x: float, z: float) -> float:
    var edge: float = maxf(absf(x), absf(z))
    var t: float = smoothstep(MC_CITY_HALF, MC_CITY_HALF + MC_BLEND, edge)
    var rise: float = _raw_hills(x, z) + maxf(0.0, edge - MC_CITY_HALF) * 0.08
    return ROAD_LEVEL + rise * t

func _mc_ground_y(x: float, z: float) -> float:
    # Walking height: sidewalk slab top inside a block, road level elsewhere.
    var fx: float = fposmod(x, MC_PITCH)
    var fz: float = fposmod(z, MC_PITCH)
    if absf(x) <= 310.0 and absf(z) <= 310.0 and fx >= 10.0 and fx <= 70.0 and fz >= 10.0 and fz <= 70.0:
        return MC_SLAB_TOP
    return ROAD_LEVEL

func _make_terrain() -> void:
    var cells: int = MC_TERRAIN_CELLS
    var stride: int = cells + 1
    var step: float = (MC_WORLD * 2.0) / float(cells)
    var heights := PackedFloat32Array()
    heights.resize(stride * stride)
    for iz in range(stride):
        for ix in range(stride):
            heights[iz * stride + ix] = _height(-MC_WORLD + float(ix) * step, -MC_WORLD + float(iz) * step)

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var faces := PackedVector3Array()
    for iz in range(cells):
        for ix in range(cells):
            var x0: float = -MC_WORLD + float(ix) * step
            var x1: float = x0 + step
            var z0: float = -MC_WORLD + float(iz) * step
            var z1: float = z0 + step
            var a := Vector3(x0, heights[iz * stride + ix], z0)
            var b := Vector3(x1, heights[iz * stride + ix + 1], z0)
            var c := Vector3(x1, heights[(iz + 1) * stride + ix + 1], z1)
            var d := Vector3(x0, heights[(iz + 1) * stride + ix], z1)
            var ca: Color = _ground_color(a)
            var cb: Color = _ground_color(b)
            var cc: Color = _ground_color(c)
            var cd: Color = _ground_color(d)
            st.set_color(ca)
            st.add_vertex(a)
            st.set_color(cb)
            st.add_vertex(b)
            st.set_color(cc)
            st.add_vertex(c)
            st.set_color(ca)
            st.add_vertex(a)
            st.set_color(cc)
            st.add_vertex(c)
            st.set_color(cd)
            st.add_vertex(d)
            faces.append(a)
            faces.append(b)
            faces.append(c)
            faces.append(a)
            faces.append(c)
            faces.append(d)
    st.generate_normals()
    var terrain := MeshInstance3D.new()
    terrain.name = "WorldTerrain"
    terrain.mesh = st.commit()
    terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.92
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    terrain.material_override = mat
    add_child(terrain)

    var body := StaticBody3D.new()
    body.name = "TerrainBody"
    var collision := CollisionShape3D.new()
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(faces)
    shape.backface_collision = true
    collision.shape = shape
    body.add_child(collision)
    add_child(body)

func _make_outer_scenery() -> void:
    var strips: Array = [
        Rect2(Vector2(-465.0, -465.0), Vector2(930.0, 110.0)),
        Rect2(Vector2(-465.0, 355.0), Vector2(930.0, 110.0)),
        Rect2(Vector2(-465.0, -355.0), Vector2(110.0, 710.0)),
        Rect2(Vector2(355.0, -355.0), Vector2(110.0, 710.0))
    ]
    for s in range(strips.size()):
        var rect: Rect2 = strips[s]
        for rep in range(3):
            _make_forest_multimesh(rect, s * 3 + rep)
    for i in range(10):
        var ang: float = TAU * float(i) / 10.0 + 0.2
        var rad: float = 560.0 + rng.randf_range(-20.0, 30.0)
        var hill := MeshInstance3D.new()
        hill.name = "Mountain"
        var sm := SphereMesh.new()
        sm.radius = rng.randf_range(55.0, 80.0)
        sm.height = sm.radius * 1.8
        sm.radial_segments = 24
        sm.rings = 14
        hill.mesh = sm
        hill.position = Vector3(cos(ang) * rad, 8.0, sin(ang) * rad)
        hill.scale = Vector3(1.4, 0.8, 1.0)
        hill.material_override = _mat(Color("#3e564c"), 0.98)
        add_child(hill)

# ---------------------------------------------------------------------------
# City: asphalt, block slabs, buildings, parks, lamps
# ---------------------------------------------------------------------------

func _mc_is_special(i: int, j: int) -> bool:
    return (i == 0 and j == 0) or (i == -1 and j == 0) or (i == 1 and j == 0) or (i == -1 and j == -1) or (i == 0 and j == -1) or (i == 1 and j == -1) or (i == -1 and j == 1)

func _mc_vertex_material(rough: float, metal: float, emissive: bool) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.roughness = rough
    m.metallic = metal
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    if emissive:
        m.emission_enabled = true
        m.emission = Color(1.0, 0.82, 0.45)
        m.emission_energy_multiplier = 0.1
    return m

func _make_city_and_roads() -> void:
    var city := MCBatch.new()
    var dark := MCBatch.new()
    var lit := MCBatch.new()

    # One big asphalt sheet; the roads are the gaps between the block slabs.
    city.box(Vector3(0.0, 0.12, 0.0), Vector3(MC_ASPHALT_HALF * 2.0, 0.24, MC_ASPHALT_HALF * 2.0), Color("#23272a"))

    for i in range(-MC_N, MC_N):
        for j in range(-MC_N, MC_N):
            var cx: float = float(i) * MC_PITCH + MC_PITCH * 0.5
            var cz: float = float(j) * MC_PITCH + MC_PITCH * 0.5
            var special: bool = _mc_is_special(i, j)
            var park: bool = special or rng.randf() < 0.12

            city.box(Vector3(cx, MC_SLAB_TOP * 0.5, cz), Vector3(MC_SLAB_SIZE, MC_SLAB_TOP, MC_SLAB_SIZE), Color("#8d8f8a"))
            var slab_body := StaticBody3D.new()
            slab_body.position = Vector3(cx, MC_SLAB_TOP * 0.5, cz)
            var slab_cs := CollisionShape3D.new()
            var slab_shape := BoxShape3D.new()
            slab_shape.size = Vector3(MC_SLAB_SIZE, MC_SLAB_TOP, MC_SLAB_SIZE)
            slab_cs.shape = slab_shape
            slab_body.add_child(slab_cs)
            add_child(slab_body)

            # Two street lamps per block (emissive heads, no real lights: mobile friendly).
            for lamp in [Vector2(cx - 27.0, cz - 27.0), Vector2(cx + 27.0, cz + 27.0)]:
                var lp: Vector2 = lamp
                city.box(Vector3(lp.x, MC_SLAB_TOP + 3.0, lp.y), Vector3(0.18, 6.0, 0.18), Color("#2a2d30"))
                lit.box(Vector3(lp.x + 0.6, MC_SLAB_TOP + 6.1, lp.y), Vector3(1.3, 0.2, 0.4), Color(1.0, 0.86, 0.52))

            if park:
                city.box(Vector3(cx, 0.175, cz), Vector3(54.0, 0.35, 54.0), Color("#3f7a3a"))
                if not special:
                    for t in range(7):
                        _mc_add_tree(city, cx + rng.randf_range(-24.0, 24.0), cz + rng.randf_range(-24.0, 24.0))
                continue

            var dist: float = Vector2(float(i) + 0.5, float(j) + 0.5).length()
            var any_building: bool = false
            for q in [Vector2(-15.0, -15.0), Vector2(15.0, -15.0), Vector2(-15.0, 15.0), Vector2(15.0, 15.0)]:
                var qv: Vector2 = q
                if rng.randf() < 0.55 or ((not any_building) and qv.x > 0.0 and qv.y > 0.0):
                    any_building = true
                    var bw: float = rng.randf_range(20.0, 26.0)
                    var bd: float = rng.randf_range(20.0, 26.0)
                    var bh: float = 10.0
                    if cx > 160.0:
                        bh = rng.randf_range(6.0, 14.0)
                    elif cx < -160.0:
                        bh = rng.randf_range(8.0, 22.0)
                    else:
                        bh = rng.randf_range(10.0, maxf(14.0, 75.0 - dist * 11.0))
                    _mc_add_building(city, dark, lit, cx + qv.x + rng.randf_range(-1.0, 1.0), cz + qv.y + rng.randf_range(-1.0, 1.0), bw, bd, bh)

    # Signal poles at the four corners of every junction.
    for ix in range(-MC_N, MC_N + 1):
        for iz in range(-MC_N, MC_N + 1):
            for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                    city.box(Vector3(float(ix) * MC_PITCH + float(sx) * 11.5, MC_SLAB_TOP + 2.7, float(iz) * MC_PITCH + float(sz) * 11.5), Vector3(0.2, 5.4, 0.2), Color("#202326"))

    var city_mi: MeshInstance3D = city.build(_mc_vertex_material(0.85, 0.0, false), "MC_CityBlocks", true)
    if city_mi != null:
        add_child(city_mi)
    var dark_mi: MeshInstance3D = dark.build(_mc_vertex_material(0.15, 0.3, false), "MC_WindowsDark", false)
    if dark_mi != null:
        add_child(dark_mi)
    _mc_lit_mat = _mc_vertex_material(0.4, 0.0, true)
    var lit_mi: MeshInstance3D = lit.build(_mc_lit_mat, "MC_WindowsLit", false)
    if lit_mi != null:
        add_child(lit_mi)

func _mc_add_tree(city: MCBatch, x: float, z: float) -> void:
    var base_y: float = MC_SLAB_TOP + 0.01
    var s: float = rng.randf_range(0.8, 1.4)
    city.box(Vector3(x, base_y + 1.6 * s, z), Vector3(0.6 * s, 3.2 * s, 0.6 * s), Color("#4a3426"))
    city.box(Vector3(x, base_y + 4.2 * s, z), Vector3(3.6 * s, 2.8 * s, 3.6 * s), Color("#2c6a3a"))
    city.box(Vector3(x, base_y + 6.2 * s, z), Vector3(2.2 * s, 2.0 * s, 2.2 * s), Color("#357a43"))

func _mc_add_building(city: MCBatch, dark: MCBatch, lit: MCBatch, x: float, z: float, w: float, d: float, h: float) -> void:
    var palette: Array = [Color("#8b8f93"), Color("#a29a8e"), Color("#7b8794"), Color("#9c7f6b"), Color("#b3ada2"), Color("#6f7b7a"), Color("#8e6f6f"), Color("#a9b2b8")]
    var col: Color = palette[rng.randi_range(0, palette.size() - 1)]
    col = col.darkened(rng.randf_range(0.0, 0.18))
    var base_y: float = MC_SLAB_TOP - 0.04
    city.box(Vector3(x, base_y + h * 0.5, z), Vector3(w, h, d), col)
    city.box(Vector3(x, base_y + h + 0.25, z), Vector3(w * 1.02, 0.5, d * 1.02), Color("#25282b"))
    city.box(Vector3(x + rng.randf_range(-w * 0.2, w * 0.2), base_y + h + 1.5, z + rng.randf_range(-d * 0.2, d * 0.2)), Vector3(w * 0.28, 2.0, d * 0.28), Color("#6a6e70"))
    _mc_windows(dark, lit, x, z, w, d, h)

    var body := StaticBody3D.new()
    body.position = Vector3(x, base_y + h * 0.5, z)
    var cs := CollisionShape3D.new()
    cs.name = "CollisionShape3D"
    var shp := BoxShape3D.new()
    shp.size = Vector3(w, h, d)
    cs.shape = shp
    body.add_child(cs)
    add_child(body)
    _collision_lod_bodies.append(body)

func _mc_windows(dark: MCBatch, lit: MCBatch, x: float, z: float, w: float, d: float, h: float) -> void:
    var base_y: float = MC_SLAB_TOP - 0.04
    var rows: int = mini(int((h - 3.0) / 3.6), 14)
    if rows < 1:
        return
    var cols_x: int = maxi(1, int((w - 2.0) / 4.2))
    var cols_z: int = maxi(1, int((d - 2.0) / 4.2))
    var win_dark: Color = Color(0.11, 0.19, 0.26)
    var win_lit: Color = Color(1.0, 0.86, 0.52)
    for r in range(rows):
        var y: float = base_y + 3.2 + float(r) * 3.6
        for c in range(cols_x):
            var px: float = x - w * 0.5 + 1.0 + (float(c) + 0.5) * ((w - 2.0) / float(cols_x))
            for side in [-1.0, 1.0]:
                var sf: float = float(side)
                var use_lit: bool = rng.randf() < 0.3
                var wc: Color = win_lit if use_lit else win_dark
                var batch: MCBatch = lit if use_lit else dark
                batch.quad(Vector3(px, y, z + sf * (d * 0.5 + 0.05)), Vector3(1.1, 0.0, 0.0), Vector3(0.0, 0.9, 0.0), Vector3(0.0, 0.0, sf), wc)
        for c in range(cols_z):
            var pz: float = z - d * 0.5 + 1.0 + (float(c) + 0.5) * ((d - 2.0) / float(cols_z))
            for side in [-1.0, 1.0]:
                var sf2: float = float(side)
                var use_lit2: bool = rng.randf() < 0.3
                var wc2: Color = win_lit if use_lit2 else win_dark
                var batch2: MCBatch = lit if use_lit2 else dark
                batch2.quad(Vector3(x + sf2 * (w * 0.5 + 0.05), y, pz), Vector3(0.0, 0.0, 1.1), Vector3(0.0, 0.9, 0.0), Vector3(sf2, 0.0, 0.0), wc2)

# ---------------------------------------------------------------------------
# Road markings (MultiMesh) and traffic signals
# ---------------------------------------------------------------------------

func _mc_make_multimesh(xforms: Array[Transform3D], color: Color, node_name: String) -> void:
    if xforms.is_empty():
        return
    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    var bm := BoxMesh.new()
    bm.size = Vector3(1.0, 0.02, 1.0)
    mm.mesh = bm
    mm.instance_count = xforms.size()
    for i in range(xforms.size()):
        mm.set_instance_transform(i, xforms[i])
    var inst := MultiMeshInstance3D.new()
    inst.name = node_name
    inst.multimesh = mm
    inst.material_override = _mat(color, 0.7)
    inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(inst)

func _make_mc_markings() -> void:
    var dashes: Array[Transform3D] = []
    var stripes: Array[Transform3D] = []
    for k in range(-MC_N, MC_N + 1):
        var line: float = float(k) * MC_PITCH
        var t: float = -MC_EXT - 20.0
        while t < MC_EXT + 20.0:
            var o: float = fposmod(t, MC_PITCH)
            if o >= 14.0 and o <= 66.0 and absf(t) <= MC_EXT + 10.0:
                dashes.append(Transform3D(Basis.from_scale(Vector3(4.0, 1.0, 0.35)), Vector3(t, MC_MARK_Y, line)))
                dashes.append(Transform3D(Basis.from_scale(Vector3(0.35, 1.0, 4.0)), Vector3(line, MC_MARK_Y, t)))
            t += 8.0
    for ix in range(-MC_N, MC_N + 1):
        for iz in range(-MC_N, MC_N + 1):
            for sd in [-1.0, 1.0]:
                var sdf: float = float(sd)
                for si in range(-4, 5):
                    var s: float = float(si) * 2.0
                    stripes.append(Transform3D(Basis.from_scale(Vector3(3.0, 1.0, 1.0)), Vector3(float(ix) * MC_PITCH + sdf * 13.0, MC_MARK_Y, float(iz) * MC_PITCH + s)))
                    stripes.append(Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 3.0)), Vector3(float(ix) * MC_PITCH + s, MC_MARK_Y, float(iz) * MC_PITCH + sdf * 13.0)))
    _mc_make_multimesh(dashes, Color("#d9c978"), "MC_LaneDashes")
    _mc_make_multimesh(stripes, Color("#dcdcd4"), "MC_Crosswalks")

func _make_mc_signals() -> void:
    var count: int = (MC_N * 2 + 1) * (MC_N * 2 + 1) * 4
    _mc_sig_mm = MultiMesh.new()
    _mc_sig_mm.transform_format = MultiMesh.TRANSFORM_3D
    _mc_sig_mm.use_colors = true
    var bm := BoxMesh.new()
    bm.size = Vector3(0.7, 0.7, 0.7)
    var sm := StandardMaterial3D.new()
    sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    sm.vertex_color_use_as_albedo = true
    bm.material = sm
    _mc_sig_mm.mesh = bm
    _mc_sig_mm.instance_count = count
    _mc_sig_tags.resize(count)
    var idx: int = 0
    for ix in range(-MC_N, MC_N + 1):
        for iz in range(-MC_N, MC_N + 1):
            for sx in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                    var px: float = float(ix) * MC_PITCH + float(sx) * 11.5
                    var pz: float = float(iz) * MC_PITCH + float(sz) * 11.5
                    _mc_sig_mm.set_instance_transform(idx, Transform3D(Basis(), Vector3(px, MC_SLAB_TOP + 5.7, pz)))
                    _mc_sig_tags[idx] = 0 if float(sx) * float(sz) > 0.0 else 1
                    idx += 1
    _mc_update_signal_colors()
    var inst := MultiMeshInstance3D.new()
    inst.name = "MC_SignalHeads"
    inst.multimesh = _mc_sig_mm
    inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(inst)

func _mc_update_signal_colors() -> void:
    if _mc_sig_mm == null:
        return
    for i in range(_mc_sig_tags.size()):
        var go: bool = _mc_sig_tags[i] == _mc_phase
        _mc_sig_mm.set_instance_color(i, Color(0.15, 1.0, 0.3) if go else Color(1.0, 0.12, 0.08))

# ---------------------------------------------------------------------------
# Traffic: cars follow the grid, turn at junctions, obey the signals
# ---------------------------------------------------------------------------

func _mc_place(a: Dictionary, ix: float, iz: float, d: Vector2) -> void:
    a["dx"] = d.x
    a["dz"] = d.y
    # Drive on the right-hand lane of the heading (-dz, dx).
    a["x"] = ix + (-d.y) * 4.5 + d.x * 0.6
    a["z"] = iz + d.x * 4.5 + d.y * 0.6

func _make_mc_traffic() -> void:
    var colors: Array = [Color("#d7d2c8"), Color("#294e78"), Color("#a52f2f"), Color("#30343a"), Color("#6c5737"), Color("#6b7d80"), Color("#d2b24c"), Color("#3d7a52")]
    var dirs: Array = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]
    for n in range(MC_TRAFFIC_COUNT):
        var d: Vector2 = dirs[n % 4]
        var ix: float = float(rng.randi_range(-MC_N, MC_N)) * MC_PITCH
        var iz: float = float(rng.randi_range(-MC_N, MC_N)) * MC_PITCH
        # The next junction ahead must exist, otherwise face the other way.
        if absf(ix + d.x * MC_PITCH) > MC_EXT + 0.1 or absf(iz + d.y * MC_PITCH) > MC_EXT + 0.1:
            d = -d
        var body_color: Color = colors[n % colors.size()]
        var car: Node3D = _make_car(Vector3(0.0, CAR_Y, 0.0), body_color, 0.0)
        var data: Dictionary = {"node": car, "x": 0.0, "z": 0.0, "dx": 0.0, "dz": 0.0, "v": rng.randf_range(9.0, 15.0), "wait": 0.0}
        _mc_place(data, ix, iz, d)
        var ahead: float = rng.randf_range(8.0, 60.0)
        data["x"] = float(data["x"]) + d.x * ahead
        data["z"] = float(data["z"]) + d.y * ahead
        car.position = Vector3(float(data["x"]), CAR_Y, float(data["z"]))
        car.rotation.y = atan2(-d.y, d.x)
        traffic.append(data)

func _mc_ahead(x: float, z: float, dx: float, dz: float, ox: float, oz: float) -> bool:
    var rx: float = ox - x
    var rz: float = oz - z
    var along: float = rx * dx + rz * dz
    var lat: float = absf(-rx * dz + rz * dx)
    return along > 0.0 and along < 8.5 and lat < 2.5

# 0 = free, 1 = red light, 2 = car ahead
func _mc_hold(a: Dictionary) -> int:
    var x: float = a["x"]
    var z: float = a["z"]
    var dx: float = a["dx"]
    var dz: float = a["dz"]
    var ax: bool = dx != 0.0
    var al: float = x if ax else z
    var sg: float = dx if ax else dz
    if (ax and _mc_phase != 0) or ((not ax) and _mc_phase != 1):
        var line: float = floorf(al / MC_PITCH) * MC_PITCH
        if sg > 0.0:
            line = ceilf(al / MC_PITCH) * MC_PITCH
        var dist: float = (line - al) * sg
        if dist > 10.0 and dist < 17.0:
            return 1
    for other in traffic:
        var od: Dictionary = other
        if od["node"] == a["node"]:
            continue
        if _mc_ahead(x, z, dx, dz, float(od["x"]), float(od["z"])):
            return 2
    if _player_ref != null and is_instance_valid(_player_ref) and bool(_player_ref.get("in_vehicle")):
        var pp: Vector3 = _player_ref.global_position
        if _mc_ahead(x, z, dx, dz, pp.x, pp.z):
            return 2
    return 0

func _mc_turn(a: Dictionary, ix: float, iz: float) -> void:
    var dx: float = a["dx"]
    var dz: float = a["dz"]
    var cand: Array = [Vector2(dx, dz), Vector2(dx, dz), Vector2(dz, -dx), Vector2(-dz, dx)]
    var opts: Array = []
    for c in cand:
        var cv: Vector2 = c
        if absf(ix + cv.x * MC_PITCH) <= MC_EXT + 0.1 and absf(iz + cv.y * MC_PITCH) <= MC_EXT + 0.1:
            opts.append(cv)
    var choice: Vector2 = Vector2(-dx, -dz)
    if not opts.is_empty():
        choice = opts[rng.randi_range(0, opts.size() - 1)]
    _mc_place(a, ix, iz, choice)

func _mc_step_car(a: Dictionary, dt: float) -> void:
    var node: Node3D = a["node"]
    if not is_instance_valid(node):
        return
    var hold: int = _mc_hold(a)
    var stopped: bool = false
    if hold == 1:
        stopped = true
    elif hold == 2:
        var waiting: float = float(a["wait"]) + dt
        a["wait"] = waiting
        if waiting < 4.0:
            stopped = true
    else:
        a["wait"] = 0.0
    if not stopped:
        var dx: float = a["dx"]
        var dz: float = a["dz"]
        var v: float = a["v"]
        var px: float = a["x"]
        var pz: float = a["z"]
        var nx: float = px + dx * v * dt
        var nz: float = pz + dz * v * dt
        a["x"] = nx
        a["z"] = nz
        var ax: bool = dx != 0.0
        var cur: float = nx if ax else nz
        var prev: float = px if ax else pz
        var k0: float = floorf(prev / MC_PITCH)
        var k1: float = floorf(cur / MC_PITCH)
        if k0 != k1:
            var k: float = maxf(k0, k1) * MC_PITCH
            var ix: float = k if ax else roundf(nx / MC_PITCH) * MC_PITCH
            var iz: float = roundf(nz / MC_PITCH) * MC_PITCH if ax else k
            _mc_turn(a, ix, iz)
    node.position = Vector3(float(a["x"]), CAR_Y, float(a["z"]))
    node.rotation.y = atan2(-float(a["dz"]), float(a["dx"]))

# ---------------------------------------------------------------------------
# Driveable cars and pedestrians
# ---------------------------------------------------------------------------

func _make_mc_driveables() -> void:
    var vehicle_script: Script = load("res://scripts/vehicle_mc.gd")
    # Parked at the kerb next to the start, in line with the lane direction.
    var setups: Array = [
        {"x": 26.0, "z": 8.3, "rot": -PI / 2.0, "color": Color("#b52f32")},
        {"x": 48.0, "z": 8.3, "rot": -PI / 2.0, "color": Color("#2b5ea8")},
        {"x": -26.0, "z": -8.3, "rot": PI / 2.0, "color": Color("#d2b24c")}
    ]
    for i in range(setups.size()):
        var s: Dictionary = setups[i]
        var car := CharacterBody3D.new()
        car.set_script(vehicle_script)
        var car_x: float = s["x"]
        var car_z: float = s["z"]
        car.position = Vector3(car_x, _height(car_x, car_z) + 0.1, car_z)
        car.rotation.y = float(s["rot"])
        car.name = "DriveableVehicle_%d" % i
        add_child(car)
        car.call("set_vehicle_color", s["color"])
        driveable_vehicles.append(car)
    driveable_vehicle = driveable_vehicles[0]

func _make_mc_pedestrians() -> void:
    var shirt_colors: Array = [
        Color("#345f8a"), Color("#8a3f3f"), Color("#557b4a"),
        Color("#8c6b3e"), Color("#5d4f86"), Color("#496b70"),
        Color("#6f4f3d"), Color("#6b6f43")
    ]
    for i in range(MC_PED_COUNT):
        var bi: int = rng.randi_range(-MC_N, MC_N - 1)
        var bj: int = rng.randi_range(-MC_N, MC_N - 1)
        var cx: float = float(bi) * MC_PITCH + MC_PITCH * 0.5
        var cz: float = float(bj) * MC_PITCH + MC_PITCH * 0.5
        var along: float = rng.randf_range(-24.0, 24.0)
        var edge: float = 27.0 if rng.randf() < 0.5 else -27.0
        var sx: float = cx + along
        var sz: float = cz + edge
        if rng.randf() < 0.5:
            sx = cx + edge
            sz = cz + along
        var start := Vector3(sx, MC_SLAB_TOP + 0.04, sz)
        var shirt: Color = shirt_colors[i % shirt_colors.size()]
        var person: Node3D = _make_person(start, shirt, rng.randf_range(0.92, 1.06))
        npcs.append({"node": person, "base": start, "phase": rng.randf_range(0.0, TAU), "radius": rng.randf_range(3.0, 6.0)})

# ---------------------------------------------------------------------------
# Missions (targets moved onto the new sidewalks)
# ---------------------------------------------------------------------------

func start_next_mission() -> void:
    mission_index = (mission_index + 1) % MC_MISSIONS.size()
    var m: Dictionary = MC_MISSIONS[mission_index]
    mission_name = String(m["name"])
    mission_target = m["target"]
    mission_reward = int(m["reward"])
    mission_active = true
    if is_instance_valid(mission_marker):
        mission_marker.queue_free()
    mission_marker = MeshInstance3D.new()
    mission_marker.name = "MissionMarker"
    var ring := TorusMesh.new()
    ring.inner_radius = 1.7
    ring.outer_radius = 2.1
    ring.rings = 12
    ring.ring_segments = 32
    mission_marker.mesh = ring
    mission_marker.material_override = _mat(Color("#f0d35b"), 0.28, 0.15, Color("#f0d35b"))
    mission_marker.position = Vector3(mission_target.x, MC_SLAB_TOP + 0.12, mission_target.z)
    add_child(mission_marker)
    _mission_hud_timer = 1.0

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
    super._process(delta)
    if _mc_lit_mat != null:
        var target: float = 1.9 if _is_night else 0.1
        _mc_lit_mat.emission_energy_multiplier = lerpf(_mc_lit_mat.emission_energy_multiplier, target, minf(1.0, delta * 1.5))

func _simulate_actors(delta: float) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
        if _player_ref == null:
            return

    _simulation_accumulator += delta
    if _simulation_accumulator < 0.033:
        return
    var simulation_delta: float = _simulation_accumulator
    _simulation_accumulator = 0.0
    _reduced_simulation_accumulator += simulation_delta
    var reduced_update: bool = _reduced_simulation_accumulator >= REDUCED_SIMULATION_INTERVAL
    var reduced_delta: float = _reduced_simulation_accumulator
    if reduced_update:
        _reduced_simulation_accumulator = 0.0

    _refresh_dynamic_sector_cache()

    # Traffic lights: 7 seconds per phase, like Mad City.
    _mc_signal_time += simulation_delta
    var phase: int = int(floorf(_mc_signal_time / 7.0)) % 2
    if phase != _mc_phase:
        _mc_phase = phase
        _mc_update_signal_colors()

    var player_pos: Vector3 = _player_ref.global_position
    for npc_data in _nearby_npcs:
        var n: Node3D = npc_data["node"]
        if not is_instance_valid(n):
            continue
        var npc_distance: float = _distance_to_player(n)
        if npc_distance > NPC_REDUCED_RADIUS:
            continue
        var medium_npc: bool = npc_distance > NPC_SIMULATION_RADIUS
        if medium_npc and not reduced_update:
            continue
        if n.has_method("ai_tick"):
            n.call("ai_tick", reduced_delta if medium_npc else simulation_delta, player_pos, medium_npc)
            n.position.y = _mc_ground_y(n.position.x, n.position.z) + 0.04

    for data in traffic:
        var car_data: Dictionary = data
        _mc_step_car(car_data, simulation_delta)
