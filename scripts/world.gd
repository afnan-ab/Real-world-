extends Node3D

var time_of_day := 8.0
var weather := "clear"
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var rng := RandomNumberGenerator.new()

func _ready():
    rng.seed = 424242
    _setup_environment()
    _make_ground()
    _make_lake()
    _make_mountains()
    _make_forests()
    _make_roads()
    _make_landmarks()

func _setup_environment():
    world_env = WorldEnvironment.new()
    world_env.environment = Environment.new()
    world_env.environment.background_mode = Environment.BG_SKY
    var sky = Sky.new()
    var mat = ProceduralSkyMaterial.new()
    mat.sky_top_color = Color("#2384c4")
    mat.sky_horizon_color = Color("#d8f1ff")
    mat.ground_bottom_color = Color("#172016")
    mat.ground_horizon_color = Color("#b8d5bd")
    sky.sky_material = mat
    world_env.environment.sky = sky
    world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    world_env.environment.ambient_light_energy = 1.15
    world_env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    add_child(world_env)

    sun = DirectionalLight3D.new()
    sun.light_energy = 1.35
    sun.shadow_enabled = true
    sun.rotation_degrees = Vector3(-48, -35, 0)
    add_child(sun)

func _mat(color: Color, rough := 0.8) -> StandardMaterial3D:
    var m = StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    return m

func _box(pos: Vector3, size: Vector3, material: Material, collision := true):
    var mesh = MeshInstance3D.new()
    var pm = BoxMesh.new()
    pm.size = size
    mesh.mesh = pm
    mesh.material_override = material
    mesh.position = pos
    add_child(mesh)
    if collision:
        var body = StaticBody3D.new()
        body.position = pos
        var cs = CollisionShape3D.new()
        var shape = BoxShape3D.new()
        shape.size = size
        cs.shape = shape
        body.add_child(cs)
        add_child(body)

func _cylinder(pos: Vector3, radius: float, height: float, material: Material):
    var mesh = MeshInstance3D.new()
    var cm = CylinderMesh.new()
    cm.top_radius = radius
    cm.bottom_radius = radius
    cm.height = height
    mesh.mesh = cm
    mesh.material_override = material
    mesh.position = pos
    add_child(mesh)

func _make_ground():
    _box(Vector3(0,-1,0), Vector3(420,2,420), _mat(Color("#4f7138"), 1.0))
    # gentle terrain patches
    for i in range(55):
        var x = rng.randf_range(-190,190)
        var z = rng.randf_range(-190,190)
        var s = rng.randf_range(3,10)
        _box(Vector3(x,0.02,z), Vector3(s,0.08,s), _mat(Color("#5e8242"),1.0), false)

func _make_lake():
    var lake = MeshInstance3D.new()
    var pm = PlaneMesh.new()
    pm.size = Vector2(100,70)
    lake.mesh = pm
    lake.position = Vector3(70,0.18,-65)
    var wm = StandardMaterial3D.new()
    wm.albedo_color = Color("#167ca0")
    wm.metallic = 0.35
    wm.roughness = 0.12
    lake.material_override = wm
    add_child(lake)

func _make_mountains():
    var positions = [
        Vector3(-155,18,-130), Vector3(-115,24,-150), Vector3(-55,30,-155),
        Vector3(5,20,-165), Vector3(130,27,-145), Vector3(170,20,-95),
        Vector3(-175,22,70), Vector3(175,25,60)
    ]
    for p in positions:
        var mountain = MeshInstance3D.new()
        var cm = CylinderMesh.new()
        cm.top_radius = 2.0
        cm.bottom_radius = rng.randf_range(28,48)
        cm.height = rng.randf_range(55,85)
        mountain.mesh = cm
        mountain.position = p
        mountain.rotation.y = rng.randf_range(0,TAU)
        mountain.material_override = _mat(Color("#465e52"),1.0)
        add_child(mountain)
        # snow cap
        if p.y > 22:
            var cap = MeshInstance3D.new()
            var cone = CylinderMesh.new()
            cone.top_radius = 0.3
            cone.bottom_radius = 7
            cone.height = 9
            cap.mesh = cone
            cap.position = p + Vector3(0, cm.height/2.0 + 3.5, 0)
            cap.material_override = _mat(Color("#e9f2f1"),0.95)
            add_child(cap)

func _make_tree(pos: Vector3, scale := 1.0):
    var trunk = MeshInstance3D.new()
    var cm = CylinderMesh.new()
    cm.top_radius = 0.18 * scale
    cm.bottom_radius = 0.28 * scale
    cm.height = 3.2 * scale
    trunk.mesh = cm
    trunk.position = pos + Vector3(0,1.6*scale,0)
    trunk.material_override = _mat(Color("#49362a"),1.0)
    add_child(trunk)
    var crown = MeshInstance3D.new()
    var cone = CylinderMesh.new()
    cone.top_radius = 0.15 * scale
    cone.bottom_radius = 1.7 * scale
    cone.height = 4.8 * scale
    crown.mesh = cone
    crown.position = pos + Vector3(0,4.7*scale,0)
    crown.material_override = _mat(Color("#245d35"),1.0)
    add_child(crown)

func _make_forests():
    for i in range(360):
        var p = Vector3(rng.randf_range(-195,195),0,rng.randf_range(-195,195))
        # Keep central spawn area and lake relatively open.
        if p.length() < 35: continue
        if p.x > 20 and p.x < 120 and p.z < -25 and p.z > -100: continue
        _make_tree(p, rng.randf_range(0.75,1.45))

func _make_roads():
    _box(Vector3(0,0.08,25), Vector3(360,0.18,7), _mat(Color("#303335"),0.9), false)
    _box(Vector3(-55,0.09,-35), Vector3(7,0.18,180), _mat(Color("#303335"),0.9), false)
    # bridge toward lake
    _box(Vector3(40,0.12,-20), Vector3(90,0.2,6), _mat(Color("#343638"),0.9), false)

func _make_landmarks():
    # cabin
    _box(Vector3(-18,2,12), Vector3(10,4,8), _mat(Color("#8a5b3b"),0.95))
    _box(Vector3(-18,4.6,12), Vector3(11,1.2,9), _mat(Color("#4a3023"),1.0), false)
    # lookout
    _cylinder(Vector3(22,2.5,-5), 2.8, 5, _mat(Color("#6b4b2f"),0.95))
    _box(Vector3(22,5.5,-5), Vector3(8,1,8), _mat(Color("#7a5435"),0.95), false)

func _process(delta):
    time_of_day = fmod(time_of_day + delta * 0.08, 24.0)
    var angle = (time_of_day / 24.0) * TAU
    sun.rotation_degrees.x = -35.0 + sin(angle) * 55.0
    sun.light_energy = clamp(0.35 + max(0.0, sin(angle)) * 1.25, 0.15, 1.5)
    if world_env:
        world_env.environment.ambient_light_energy = 0.55 + max(0.0, sin(angle)) * 0.75

func set_weather(kind: String):
    weather = kind
    if kind == "snow":
        world_env.environment.fog_enabled = true
        world_env.environment.fog_density = 0.015
        sun.light_energy = 0.75
    elif kind == "rain":
        world_env.environment.fog_enabled = true
        world_env.environment.fog_density = 0.008
    else:
        world_env.environment.fog_enabled = false
