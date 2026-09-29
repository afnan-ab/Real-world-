extends Node3D

# Real World Open World — procedural realistic-style pass.
# No external 3D assets required. Built for a polished mobile-friendly look.

var time_of_day: float = 8.0
var weather: String = "clear"
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var rain_particles: GPUParticles3D
var snow_particles: GPUParticles3D
var rng := RandomNumberGenerator.new()
var npcs: Array = []

func _ready() -> void:
    rng.seed = 190428
    _setup_environment()
    _make_terrain()
    _make_lake()
    _make_mountains()
    _make_forests()
    _make_city_and_roads()
    _make_cars()
    _make_pedestrians()
    _make_landmarks()
    _setup_weather_particles()

func _setup_environment() -> void:
    world_env = WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.8
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.glow_enabled = true
    env.glow_intensity = 0.65
    env.glow_strength = 1.15
    env.fog_enabled = true
    env.fog_light_color = Color("#b7c7c9")
    env.fog_density = 0.00115
    env.fog_height = 18.0
    env.fog_height_density = 0.008

    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color("#123b62")
    sky_mat.sky_horizon_color = Color("#d6e6e8")
    sky_mat.ground_bottom_color = Color("#15201b")
    sky_mat.ground_horizon_color = Color("#9eafa8")
    sky_mat.sun_angle_max = 18.0
    sky_mat.sun_curve = 0.12
    sky.sky_material = sky_mat
    env.sky = sky
    world_env.environment = env
    add_child(world_env)

    sun = DirectionalLight3D.new()
    sun.light_color = Color("#fff4df")
    sun.light_energy = 1.45
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 125.0
    sun.directional_shadow_fade_start = 0.75
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    add_child(sun)

func _mat(color: Color, rough: float = 0.8, metallic: float = 0.0, emission: Color = Color(0,0,0,0)) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    m.metallic = metallic
    if emission.a > 0.0:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 1.5
    return m

func _box(pos: Vector3, size: Vector3, material: Material, collision: bool = true) -> MeshInstance3D:
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
    return mesh

func _height(x: float, z: float) -> float:
    var d := Vector2(x, z).length()
    if d < 58.0:
        return 0.0
    var h := sin(x * 0.026) * 3.0
    h += cos(z * 0.031) * 2.6
    h += sin((x + z) * 0.017) * 3.8
    h += sin(x * 0.083 + z * 0.024) * 0.7
    return h + max(0.0, d - 105.0) * 0.05

func _make_terrain() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var n := 78
    var extent := 220.0
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
            var ca := _ground_color(a.y, x0, z0)
            var cb := _ground_color(b.y, x1, z0)
            var cc := _ground_color(c.y, x1, z1)
            var cd := _ground_color(d.y, x0, z1)
            st.set_color(ca); st.add_vertex(a)
            st.set_color(cb); st.add_vertex(b)
            st.set_color(cc); st.add_vertex(c)
            st.set_color(ca); st.add_vertex(a)
            st.set_color(cc); st.add_vertex(c)
            st.set_color(cd); st.add_vertex(d)
    st.generate_normals()
    var mesh := st.commit()
    var terrain := MeshInstance3D.new()
    terrain.mesh = mesh
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.96
    terrain.material_override = mat
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

func _ground_color(y: float, x: float, z: float) -> Color:
    var variation := sin(x * 0.11) * 0.025 + cos(z * 0.09) * 0.02
    if y > 6.0:
        return Color(0.25 + variation, 0.30 + variation, 0.22 + variation)
    return Color(0.18 + variation, 0.34 + variation, 0.18 + variation)

func _make_lake() -> void:
    var lake := MeshInstance3D.new()
    var pm := PlaneMesh.new()
    pm.size = Vector2(115.0, 78.0)
    lake.mesh = pm
    lake.position = Vector3(82, 0.28, -76)
    var wm := _mat(Color("#176d82"), 0.08, 0.65)
    wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    wm.albedo_color.a = 0.86
    lake.material_override = wm
    add_child(lake)

    for i in range(7):
        var ripple := MeshInstance3D.new()
        var ring := TorusMesh.new()
        ring.inner_radius = 1.8 + i * 1.1
        ring.outer_radius = ring.inner_radius + 0.035
        ring.rings = 8
        ring.ring_segments = 24
        ripple.mesh = ring
        ripple.position = Vector3(45 + i * 7, 0.32, -58 + sin(i) * 9)
        ripple.material_override = _mat(Color("#75b8c4"), 0.15, 0.35)
        add_child(ripple)

func _make_mountains() -> void:
    var positions := [
        Vector3(-175, 16, -155), Vector3(-110, 20, -178),
        Vector3(-35, 14, -188), Vector3(55, 19, -180),
        Vector3(150, 15, -160), Vector3(180, 13, 70),
        Vector3(-180, 12, 90)
    ]
    for p in positions:
        var hill := MeshInstance3D.new()
        var sm := SphereMesh.new()
        sm.radius = rng.randf_range(32.0, 48.0)
        sm.height = rng.randf_range(62.0, 92.0)
        sm.radial_segments = 24
        sm.rings = 14
        hill.mesh = sm
        hill.position = p
        hill.scale = Vector3(1.5, 0.9, 1.0)
        hill.material_override = _mat(Color("#3e564c"), 0.98)
        add_child(hill)

func _make_tree(pos: Vector3, s: float = 1.0) -> void:
    var root := Node3D.new()
    root.position = Vector3(pos.x, _height(pos.x, pos.z), pos.z)
    add_child(root)

    var trunk := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 0.13 * s
    cm.bottom_radius = 0.28 * s
    cm.height = 3.1 * s
    cm.radial_segments = 10
    trunk.mesh = cm
    trunk.position.y = 1.55 * s
    trunk.material_override = _mat(Color("#493326"), 0.96)
    root.add_child(trunk)

    for k in range(3):
        var crown := MeshInstance3D.new()
        var cone := CylinderMesh.new()
        cone.top_radius = 0.02 * s
        cone.bottom_radius = (1.65 - k * 0.25) * s
        cone.height = (2.8 - k * 0.12) * s
        cone.radial_segments = 12
        cone.rings = 3
        crown.mesh = cone
        crown.position.y = (3.6 + k * 1.2) * s
        crown.material_override = _mat(Color("#235437") if k < 2 else Color("#2e6641"), 0.92)
        root.add_child(crown)

func _make_forests() -> void:
    for i in range(300):
        var p := Vector3(rng.randf_range(-205,205), 0, rng.randf_range(-205,205))
        if p.length() < 54.0:
            continue
        if p.x > 18 and p.x < 142 and p.z < -28 and p.z > -112:
            continue
        _make_tree(p, rng.randf_range(0.75, 1.55))

func _make_road(pos: Vector3, size: Vector3) -> void:
    _box(pos + Vector3(0,0.12,0), size, _mat(Color("#1e2225"), 0.92), false)
    var sidewalk_size := Vector3(size.x, 0.16, 1.8) if size.x > size.z else Vector3(1.8, 0.16, size.z)
    if size.x > size.z:
        _box(pos + Vector3(0,0.21,size.z * 0.65), sidewalk_size, _mat(Color("#8c8d88"), 0.86), false)
        _box(pos + Vector3(0,0.21,-size.z * 0.65), sidewalk_size, _mat(Color("#8c8d88"), 0.86), false)
        for x in range(-int(size.x/2)+8, int(size.x/2)-5, 14):
            _box(pos + Vector3(x,0.26,0), Vector3(7,0.035,0.13), _mat(Color("#e6d28d"), 0.65), false)
    else:
        _box(pos + Vector3(size.x * 0.65,0.21,0), sidewalk_size, _mat(Color("#8c8d88"), 0.86), false)
        _box(pos + Vector3(-size.x * 0.65,0.21,0), sidewalk_size, _mat(Color("#8c8d88"), 0.86), false)
        for z in range(-int(size.z/2)+8, int(size.z/2)-5, 14):
            _box(pos + Vector3(0,0.26,z), Vector3(0.13,0.035,7), _mat(Color("#e6d28d"), 0.65), false)

func _make_building(pos: Vector3, size: Vector3, color: Color, floors: int = 2) -> void:
    _box(pos + Vector3(0,size.y/2.0,0), size, _mat(color, 0.72), true)
    _box(pos + Vector3(0,size.y + 0.22,0), Vector3(size.x*1.03,0.44,size.z*1.03), _mat(Color("#25282b"), 0.78, 0.05), false)

    var glass := _mat(Color("#254a60"), 0.16, 0.32, Color("#0b2530"))
    var frame := _mat(Color("#2b2d2f"), 0.65)
    var window_rows := max(1, floors)
    for row in range(window_rows):
        var y := 2.0 + row * (size.y / float(window_rows))
        for x in range(-int(size.x/2)+2, int(size.x/2)-1, 3):
            _box(pos + Vector3(x,y,size.z/2+0.025), Vector3(1.45,1.25,0.07), glass, false)
            _box(pos + Vector3(x,y,size.z/2+0.065), Vector3(1.58,0.08,0.06), frame, false)

    _box(pos + Vector3(0,1.15,size.z/2+0.045), Vector3(1.25,2.3,0.09), _mat(Color("#302b26"),0.45), false)

func _make_streetlight(pos: Vector3) -> void:
    _box(pos + Vector3(0,2.7,0), Vector3(0.13,5.4,0.13), _mat(Color("#202326"),0.55,0.1), false)
    _box(pos + Vector3(0.72,5.18,0), Vector3(1.45,0.12,0.12), _mat(Color("#202326"),0.55,0.1), false)
    var lamp := OmniLight3D.new()
    lamp.position = pos + Vector3(1.3,5.0,0)
    lamp.omni_range = 11.0
    lamp.light_energy = 1.25
    lamp.light_color = Color("#ffe0a1")
    lamp.visible = false
    add_child(lamp)

func _make_city_and_roads() -> void:
    _make_road(Vector3(0,0,28), Vector3(390,0.24,9))
    _make_road(Vector3(-62,0,-20), Vector3(9,0.24,270))
    _make_road(Vector3(66,0,28), Vector3(9,0.24,230))
    _make_road(Vector3(-8,0,-58), Vector3(240,0.24,8))

    var colors := [Color("#777a78"),Color("#9a9085"),Color("#646b70"),Color("#8a6f5c"),Color("#a4a09a"),Color("#6e7775")]
    for x in [-52.0,-14.0,25.0,64.0]:
        for z in [-24.0, 66.0]:
            var h := rng.randf_range(8.0, 18.0)
            var w := rng.randf_range(13.0, 21.0)
            var d := rng.randf_range(11.0, 18.0)
            _make_building(Vector3(x,0,z), Vector3(w,h,d), colors[rng.randi_range(0, colors.size()-1)], max(1,int(h/4.0)))
    for x in range(-174,175,24):
        _make_streetlight(Vector3(x,0,33))

func _make_car(pos: Vector3, body_color: Color, rotation_y: float = 0.0) -> void:
    var root := Node3D.new()
    root.position = pos
    root.rotation.y = rotation_y
    add_child(root)

    var body_mat := _mat(body_color, 0.28, 0.58)
    var glass := _mat(Color("#162b37"), 0.12, 0.42)
    var tire := _mat(Color("#111214"), 0.92)
    var chrome := _mat(Color("#b9bdbe"), 0.2, 0.8)
    var lamp := _mat(Color("#f6e9bd"), 0.16, 0.25, Color("#fff0b0"))

    _local_box(root, Vector3(0,0.62,0), Vector3(4.3,0.7,2.0), body_mat)
    _local_box(root, Vector3(0,1.12,0), Vector3(2.35,0.65,1.75), body_mat)
    _local_box(root, Vector3(0,1.14,0), Vector3(2.1,0.46,1.58), glass, false)

    for sx in [-1.0,1.0]:
        for sz in [-0.72,0.72]:
            var wheel := MeshInstance3D.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 0.43
            cyl.bottom_radius = 0.43
            cyl.height = 0.24
            cyl.radial_segments = 16
            wheel.mesh = cyl
            wheel.position = Vector3(sx*1.38,0.48,sz)
            wheel.rotation_degrees = Vector3(90,0,0)
            wheel.material_override = tire
            root.add_child(wheel)
            var hub := MeshInstance3D.new()
            var hm := CylinderMesh.new()
            hm.top_radius = 0.16
            hm.bottom_radius = 0.16
            hm.height = 0.25
            hm.radial_segments = 12
            hub.mesh = hm
            hub.position = wheel.position
            hub.rotation_degrees = Vector3(90,0,0)
            hub.material_override = chrome
            root.add_child(hub)

    _local_box(root, Vector3(1.93,0.72,0.0), Vector3(0.12,0.24,0.62), lamp, false)
    _local_box(root, Vector3(-1.93,0.72,0.0), Vector3(0.12,0.24,0.62), _mat(Color("#8d1d1d"),0.2,0.15,Color("#5d0808")), false)

func _local_box(root: Node3D, pos: Vector3, size: Vector3, mat: Material, collision: bool = false) -> void:
    var mesh := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mesh.mesh = box
    mesh.position = pos
    mesh.material_override = mat
    root.add_child(mesh)
    if collision:
        var body := StaticBody3D.new()
        body.position = pos
        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        cs.shape = shape
        body.add_child(cs)
        root.add_child(body)

func _make_cars() -> void:
    _make_car(Vector3(-32,0.45,29), Color("#b92c2c"), 0.0)
    _make_car(Vector3(42,0.45,29), Color("#2b5ea8"), 0.0)
    _make_car(Vector3(-62,0.45,62), Color("#d3d0c8"), PI/2.0)
    _make_car(Vector3(66,0.45,-20), Color("#202a32"), PI/2.0)
    _make_car(Vector3(20,0.45,-58), Color("#8a6d38"), 0.0)

func _make_person(pos: Vector3, shirt_color: Color, scale_v: float = 1.0) -> Node3D:
    var root := Node3D.new()
    root.position = pos
    root.scale = Vector3.ONE * scale_v
    add_child(root)

    var skin := _mat(Color("#b87958"),0.68)
    var shirt := _mat(shirt_color,0.78)
    var pants := _mat(Color("#22262a"),0.86)
    var shoes := _mat(Color("#141517"),0.92)

    _local_person_part(root, Vector3(0,1.02,0), Vector3(0.52,0.88,0.34), shirt)
    _local_person_part(root, Vector3(0,1.68,0), Vector3(0.34,0.34,0.34), skin, true)
    _local_person_part(root, Vector3(-0.18,0.37,0), Vector3(0.16,0.72,0.16), pants)
    _local_person_part(root, Vector3(0.18,0.37,0), Vector3(0.16,0.72,0.16), pants)
    _local_person_part(root, Vector3(-0.38,1.02,0), Vector3(0.14,0.72,0.14), skin)
    _local_person_part(root, Vector3(0.38,1.02,0), Vector3(0.14,0.72,0.14), skin)
    _local_person_part(root, Vector3(-0.18,0.0,-0.02), Vector3(0.22,0.12,0.4), shoes)
    _local_person_part(root, Vector3(0.18,0.0,-0.02), Vector3(0.22,0.12,0.4), shoes)
    return root

func _local_person_part(root: Node3D, pos: Vector3, scale_v: Vector3, mat: Material, sphere: bool = false) -> void:
    var mi := MeshInstance3D.new()
    if sphere:
        var sm := SphereMesh.new()
        sm.radial_segments = 16
        sm.rings = 10
        mi.mesh = sm
    else:
        var box := BoxMesh.new()
        box.size = Vector3.ONE
        mi.mesh = box
    mi.position = pos
    mi.scale = scale_v
    mi.material_override = mat
    root.add_child(mi)

func _make_pedestrians() -> void:
    var shirt_colors := [Color("#345f8a"),Color("#8a3f3f"),Color("#557b4a"),Color("#8c6b3e"),Color("#5d4f86")]
    for i in range(8):
        var start := Vector3(-70 + i * 18, 0.05, 19 + (i % 2) * 18)
        var person := _make_person(start, shirt_colors[i % shirt_colors.size()], rng.randf_range(0.92,1.06))
        npcs.append({"node":person, "base":start, "phase":rng.randf_range(0.0,TAU), "radius":rng.randf_range(2.0,5.0)})

func _make_landmarks() -> void:
    _make_building(Vector3(-18,0,12), Vector3(13,5.5,10), Color("#8b6248"), 1)
    _box(Vector3(22,5.0,-5), Vector3(10,0.5,10), _mat(Color("#765033"),0.92), false)
    for x in [-3.8,3.8]:
        for z in [-3.8,3.8]:
            _box(Vector3(22+x,2.5,-5+z), Vector3(0.3,5,0.3), _mat(Color("#5b3d29"),0.96), false)

func _setup_weather_particles() -> void:
    rain_particles = _weather_particles(false)
    snow_particles = _weather_particles(true)
    rain_particles.visible = false
    snow_particles.visible = false

func _weather_particles(snow: bool) -> GPUParticles3D:
    var particles := GPUParticles3D.new()
    particles.amount = 420 if snow else 700
    particles.lifetime = 2.4 if snow else 0.8
    particles.visibility_aabb = AABB(Vector3(-80,-5,-80),Vector3(160,55,160))
    var process := ParticleProcessMaterial.new()
    process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process.emission_box_extents = Vector3(65,18,65)
    process.direction = Vector3(0,-1,0)
    process.initial_velocity_min = 2.0 if snow else 26.0
    process.initial_velocity_max = 4.5 if snow else 34.0
    process.gravity = Vector3(0,-1.2,0) if snow else Vector3(0,-3,0)
    process.scale_min = 0.035 if snow else 0.015
    process.scale_max = 0.07 if snow else 0.025
    particles.process_material = process

    var mesh := QuadMesh.new()
    mesh.size = Vector2(0.08,0.35) if not snow else Vector2(0.10,0.10)
    mesh.material = _mat(Color("#d8eef4") if snow else Color("#a8cfe0"),0.18,0.05)
    particles.draw_pass_1 = mesh
    add_child(particles)
    return particles

func _process(delta: float) -> void:
    time_of_day = fmod(time_of_day + delta * 0.045, 24.0)
    var angle := (time_of_day / 24.0) * TAU
    sun.rotation_degrees.x = -32.0 + sin(angle) * 55.0
    sun.rotation_degrees.y = -35.0 + cos(angle) * 15.0
    sun.light_energy = clamp(0.18 + max(0.0,sin(angle)) * 1.35,0.12,1.5)
    world_env.environment.ambient_light_energy = 0.38 + max(0.0,sin(angle))*0.7

    var t := Time.get_ticks_msec() * 0.001
    for npc_data in npcs:
        var n: Node3D = npc_data["node"]
        var phase: float = npc_data["phase"]
        var base: Vector3 = npc_data["base"]
        var radius: float = npc_data["radius"]
        n.position = base + Vector3(cos(t*0.45+phase)*radius,0.05,sin(t*0.45+phase)*radius)
        n.rotation.y = -atan2(sin(t*0.45+phase),cos(t*0.45+phase))

func set_weather(kind: String) -> void:
    weather = kind
    rain_particles.visible = kind == "rain"
    snow_particles.visible = kind == "snow"
    if kind == "snow":
        world_env.environment.fog_density = 0.008
    elif kind == "rain":
        world_env.environment.fog_density = 0.0045
    else:
        world_env.environment.fog_density = 0.00115
