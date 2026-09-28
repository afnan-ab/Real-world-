extends Node3D

# Procedural realistic-style open world. Designed for Android: no external assets required.
var time_of_day := 8.0
var weather := "clear"
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var rng := RandomNumberGenerator.new()
var terrain_material: StandardMaterial3D

func _ready():
    rng.seed = 190428
    _setup_environment()
    _make_terrain()
    _make_lake()
    _make_mountains()
    _make_forests()
    _make_city_and_roads()
    _make_landmarks()

func _setup_environment():
    world_env = WorldEnvironment.new()
    world_env.environment = Environment.new()
    world_env.environment.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var mat := ProceduralSkyMaterial.new()
    mat.sky_top_color = Color("#0d3d67")
    mat.sky_horizon_color = Color("#b9d9e8")
    mat.ground_bottom_color = Color("#182018")
    mat.ground_horizon_color = Color("#9ab3a1")
    mat.sun_angle_max = 12.0
    sky.sky_material = mat
    world_env.environment.sky = sky
    world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    world_env.environment.ambient_light_energy = 0.9
    world_env.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    world_env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    world_env.environment.glow_enabled = true
    world_env.environment.glow_intensity = 0.55
    world_env.environment.fog_enabled = true
    world_env.environment.fog_light_color = Color("#b9c9c2")
    world_env.environment.fog_density = 0.0018
    add_child(world_env)

    sun = DirectionalLight3D.new()
    sun.light_energy = 1.35
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 110.0
    sun.rotation_degrees = Vector3(-48, -35, 0)
    add_child(sun)

func _mat(color: Color, rough := 0.8, metallic := 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    m.metallic = metallic
    return m

func _box(pos: Vector3, size: Vector3, material: Material, collision := true):
    var mesh := MeshInstance3D.new()
    var pm := BoxMesh.new()
    pm.size = size
    mesh.mesh = pm
    mesh.material_override = material
    mesh.position = pos
    add_child(mesh)
    if collision:
        var body := StaticBody3D.new()
        body.position = pos
        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        cs.shape = shape
        body.add_child(cs)
        add_child(body)

func _height(x: float, z: float) -> float:
    # Flat urban/spawn core, rolling hills outside it.
    if Vector2(x, z).length() < 48.0:
        return 0.0
    var h := sin(x * 0.028) * 3.2 + cos(z * 0.034) * 2.7
    h += sin((x + z) * 0.017) * 4.0
    h += sin(x * 0.085 + z * 0.021) * 0.8
    var d := Vector2(x, z).length()
    return h + max(0.0, d - 95.0) * 0.055

func _make_terrain():
    terrain_material = _mat(Color("#496b3d"), 0.98)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var n := 72
    var extent := 210.0
    var step := (extent * 2.0) / float(n)
    for iz in range(n):
        for ix in range(n):
            var x0 := -extent + ix * step
            var z0 := -extent + iz * step
            var x1 := x0 + step
            var z1 := z0 + step
            var a := Vector3(x0, _height(x0, z0), z0)
            var b := Vector3(x1, _height(x1, z0), z0)
            var c := Vector3(x1, _height(x1, z1), z1)
            var d := Vector3(x0, _height(x0, z1), z1)
            st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
            st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
    st.generate_normals()
    var mesh := st.commit()
    var terrain := MeshInstance3D.new()
    terrain.mesh = mesh
    terrain.material_override = terrain_material
    add_child(terrain)

    var body := StaticBody3D.new()
    var collision := CollisionShape3D.new()
    var shape := ConcavePolygonShape3D.new()
    var faces := PackedVector3Array()
    for iz in range(n):
        for ix in range(n):
            var x0 := -extent + ix * step
            var z0 := -extent + iz * step
            var x1 := x0 + step
            var z1 := z0 + step
            var a := Vector3(x0, _height(x0, z0), z0)
            var b := Vector3(x1, _height(x1, z0), z0)
            var c := Vector3(x1, _height(x1, z1), z1)
            var d := Vector3(x0, _height(x0, z1), z1)
            faces.append(a); faces.append(b); faces.append(c)
            faces.append(a); faces.append(c); faces.append(d)
    shape.set_faces(faces)
    collision.shape = shape
    body.add_child(collision)
    add_child(body)

func _make_lake():
    var lake := MeshInstance3D.new()
    var pm := PlaneMesh.new()
    pm.size = Vector2(105, 72)
    lake.mesh = pm
    lake.position = Vector3(76, 0.35, -68)
    var wm := _mat(Color("#126b87"), 0.08, 0.55)
    wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    wm.albedo_color.a = 0.82
    lake.material_override = wm
    add_child(lake)

func _make_mountains():
    var positions := [Vector3(-170,12,-150), Vector3(-110,15,-175), Vector3(-35,10,-180), Vector3(70,16,-175), Vector3(160,12,-150), Vector3(178,10,70), Vector3(-178,9,90)]
    for p in positions:
        var hill := MeshInstance3D.new()
        var sm := SphereMesh.new()
        sm.radius = rng.randf_range(30, 48)
        sm.height = rng.randf_range(55, 85)
        sm.radial_segments = 20
        sm.rings = 10
        hill.mesh = sm
        hill.position = p
        hill.scale = Vector3(1.3, 0.75, 1.0)
        hill.material_override = _mat(Color("#405a4c"), 1.0)
        add_child(hill)

func _make_tree(pos: Vector3, s := 1.0):
    var root := Node3D.new()
    root.position = Vector3(pos.x, _height(pos.x, pos.z), pos.z)
    add_child(root)
    var trunk := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 0.16 * s; cm.bottom_radius = 0.30 * s; cm.height = 3.0 * s
    cm.radial_segments = 8
    trunk.mesh = cm; trunk.position.y = 1.5 * s
    trunk.material_override = _mat(Color("#4a3427"), 1.0)
    root.add_child(trunk)
    for k in range(3):
        var crown := MeshInstance3D.new()
        var cone := CylinderMesh.new()
        cone.top_radius = 0.05 * s; cone.bottom_radius = (1.5 - k * 0.22) * s; cone.height = (3.0 - k * 0.2) * s
        cone.radial_segments = 8
        crown.mesh = cone; crown.position.y = (3.5 + k * 1.35) * s
        crown.material_override = _mat(Color("#1f4d2c"), 0.96)
        root.add_child(crown)

func _make_forests():
    for i in range(260):
        var p := Vector3(rng.randf_range(-198,198), 0, rng.randf_range(-198,198))
        if p.length() < 52.0: continue
        if p.x > 22 and p.x < 130 and p.z < -28 and p.z > -105: continue
        _make_tree(p, rng.randf_range(0.8, 1.5))

func _make_road(pos: Vector3, size: Vector3):
    _box(pos + Vector3(0,0.16,0), size, _mat(Color("#25272a"), 0.92), false)
    # Broken centre line.
    if size.x > size.z:
        for x in range(-int(size.x / 2) + 8, int(size.x / 2) - 5, 14):
            _box(pos + Vector3(x,0.27,0), Vector3(7,0.035,0.16), _mat(Color("#e7d98d"), 0.7), false)
    else:
        for z in range(-int(size.z / 2) + 8, int(size.z / 2) - 5, 14):
            _box(pos + Vector3(0,0.27,z), Vector3(0.16,0.035,7), _mat(Color("#e7d98d"), 0.7), false)

func _make_building(pos: Vector3, size: Vector3, color: Color):
    _box(pos + Vector3(0,size.y/2.0,0), size, _mat(color, 0.82), true)
    var roof := _mat(Color("#292d31"), 0.8)
    _box(pos + Vector3(0,size.y + 0.25,0), Vector3(size.x * 1.03,0.5,size.z * 1.03), roof, false)
    # Windows on the street-facing side.
    var glass := _mat(Color("#7fa9ba"), 0.18, 0.25)
    for x in range(-int(size.x/2)+2, int(size.x/2), 3):
        _box(pos + Vector3(x, size.y*0.58, size.z/2+0.03), Vector3(1.2,1.2,0.08), glass, false)

func _make_streetlight(pos: Vector3):
    _box(pos + Vector3(0,2.6,0), Vector3(0.14,5.2,0.14), _mat(Color("#25282b"),0.7), false)
    _box(pos + Vector3(0.65,5.15,0), Vector3(1.3,0.12,0.12), _mat(Color("#25282b"),0.7), false)
    var lamp := OmniLight3D.new()
    lamp.position = pos + Vector3(1.15,5.0,0)
    lamp.omni_range = 9.0
    lamp.light_energy = 1.0
    lamp.visible = false
    add_child(lamp)

func _make_city_and_roads():
    _make_road(Vector3(0,0,28), Vector3(370,0.22,8))
    _make_road(Vector3(-62,0,-20), Vector3(8,0.22,250))
    _make_road(Vector3(65,0,30), Vector3(8,0.22,210))
    _make_road(Vector3(-10,0,-55), Vector3(220,0.22,7))
    for x in [-48.0,-12.0,25.0,62.0]:
        for z in [-22.0, 65.0]:
            _make_building(Vector3(x,0,z), Vector3(rng.randf_range(12,20), rng.randf_range(7,15), rng.randf_range(10,18)), Color("#7a7770"))
    for x in range(-170,171,24):
        _make_streetlight(Vector3(x,0,33))

func _make_landmarks():
    _make_building(Vector3(-18,0,12), Vector3(12,5,9), Color("#8b5f40"))
    # A small wooden lookout.
    var deck := _box(Vector3(22,5.0,-5), Vector3(9,0.5,9), _mat(Color("#765033"),0.95), false)
    for x in [-3.5,3.5]:
        for z in [-3.5,3.5]:
            _box(Vector3(22+x,2.5,-5+z), Vector3(0.3,5,0.3), _mat(Color("#5b3d29"),1.0), false)

func _process(delta):
    time_of_day = fmod(time_of_day + delta * 0.06, 24.0)
    var angle := (time_of_day / 24.0) * TAU
    sun.rotation_degrees.x = -35.0 + sin(angle) * 55.0
    sun.light_energy = clamp(0.25 + max(0.0, sin(angle)) * 1.25, 0.12, 1.5)
    if world_env:
        world_env.environment.ambient_light_energy = 0.45 + max(0.0, sin(angle)) * 0.7

func set_weather(kind: String):
    weather = kind
    world_env.environment.fog_enabled = kind != "clear"
    if kind == "snow":
        world_env.environment.fog_density = 0.012
        sun.light_energy = 0.7
    elif kind == "rain":
        world_env.environment.fog_density = 0.007
    else:
        world_env.environment.fog_density = 0.0018
