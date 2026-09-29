extends Node3D

# Real World Open World — Visual Overhaul v5.
# Procedural open-world scene with detailed city, vehicles, pedestrians, lighting, weather and day/night.

var time_of_day: float = 8.0
var weather: String = "clear"
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var rain_particles: GPUParticles3D
var snow_particles: GPUParticles3D
var rng := RandomNumberGenerator.new()
var npcs: Array = []
var traffic: Array = []
var street_lamps: Array = []
var building_windows: Array = []
var traffic_signals: Array = []
var water_material: StandardMaterial3D
var day_night_speed: float = 0.045

func _ready() -> void:
    rng.seed = 190428
    _setup_environment()
    _make_terrain()
    _make_lake()
    _make_mountains()
    _make_forests()
    _make_city_and_roads()
    _make_cars()
    _make_traffic()
    _make_pedestrians()
    _make_landmarks()
    _make_city_props()
    _make_extra_street_detail()
    _make_sidewalk_lamps()
    _make_city_windows()
    _setup_weather_particles()

func _setup_environment() -> void:
    world_env = WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.95
    env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.glow_enabled = true
    env.glow_intensity = 0.78
    env.glow_strength = 1.15
    env.fog_enabled = true
    env.fog_light_color = Color("#b7c7c9")
    env.fog_density = 0.00075
    env.fog_height = 18.0
    env.fog_height_density = 0.008

    var sky := Sky.new()
    var sky_mat := ProceduralSkyMaterial.new()
    sky_mat.sky_top_color = Color("#123b62")
    sky_mat.sky_horizon_color = Color("#d6e6e8")
    sky_mat.ground_bottom_color = Color("#15201b")
    sky_mat.ground_horizon_color = Color("#9eafa8")
    sky_mat.sun_angle_max = 18.0
    sky_mat.sun_curve = 0.08
    sky_mat.energy_multiplier = 0.9
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
    m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
    if emission.a > 0.0:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 2.2
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
    var wm := _mat(Color("#176d82"), 0.035, 0.55)
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
    _box(pos + Vector3(0,0.12,0), size, _mat(Color("#25282b"), 0.86), false)
    # Dark road shoulders and raised curbs create more believable street depth.
    if size.x > size.z:
        _box(pos + Vector3(0,0.17,size.z*0.58), Vector3(size.x,0.18,0.32), _mat(Color("#5f6261"),0.88), false)
        _box(pos + Vector3(0,0.17,-size.z*0.58), Vector3(size.x,0.18,0.32), _mat(Color("#5f6261"),0.88), false)
    else:
        _box(pos + Vector3(size.x*0.58,0.17,0), Vector3(0.32,0.18,size.z), _mat(Color("#5f6261"),0.88), false)
        _box(pos + Vector3(-size.x*0.58,0.17,0), Vector3(0.32,0.18,size.z), _mat(Color("#5f6261"),0.88), false)
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
    # Roof parapet and facade trim.
    _box(pos + Vector3(0,size.y+0.52,0), Vector3(size.x*1.05,0.22,size.z*1.05), _mat(Color("#303235"),0.76,0.08), false)
    for side in [-1.0,1.0]:
        _box(pos + Vector3(0,1.1,side*(size.z/2+0.085)), Vector3(size.x,0.08,0.08), frame, false)

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
    street_lamps.append(lamp)

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

func _make_car(pos: Vector3, body_color: Color, rotation_y: float = 0.0) -> Node3D:
    var root := Node3D.new()
    root.position = pos
    root.rotation.y = rotation_y
    add_child(root)

    var body_mat := _mat(body_color, 0.24, 0.62)
    var trim := _mat(Color("#25282b"), 0.42, 0.18)
    var glass := _mat(Color("#102b39"), 0.07, 0.52)
    var tire := _mat(Color("#0c0d0e"), 0.96)
    var chrome := _mat(Color("#c6c8c7"), 0.18, 0.86)
    var head_mat := _mat(Color("#f6e9bd"), 0.10, 0.28, Color("#fff0b0"))
    var tail_mat := _mat(Color("#7e1118"), 0.18, 0.18, Color("#ff1b24"))

    _local_box(root, Vector3(0,0.64,0), Vector3(4.45,0.72,2.02), body_mat, false)
    _local_box(root, Vector3(0,1.08,0), Vector3(2.55,0.70,1.78), body_mat, false)
    _local_box(root, Vector3(0,1.16,0), Vector3(2.22,0.48,1.62), glass, false)
    _local_box(root, Vector3(0,0.36,0), Vector3(4.55,0.12,2.12), trim, false)
    _local_box(root, Vector3(0,0.84,-1.02), Vector3(3.35,0.16,0.08), chrome, false)
    _local_box(root, Vector3(0,0.84,1.02), Vector3(3.35,0.16,0.08), chrome, false)

    for sx in [-1.0,1.0]:
        for sz in [-0.76,0.76]:
            var wheel := MeshInstance3D.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 0.46; cyl.bottom_radius = 0.46; cyl.height = 0.28; cyl.radial_segments = 24
            wheel.mesh = cyl
            wheel.position = Vector3(sx*1.42,0.48,sz)
            wheel.rotation_degrees = Vector3(90,0,0)
            wheel.material_override = tire
            root.add_child(wheel)
            var hub := MeshInstance3D.new()
            var hm := CylinderMesh.new()
            hm.top_radius = 0.18; hm.bottom_radius = 0.18; hm.height = 0.30; hm.radial_segments = 18
            hub.mesh = hm; hub.position = wheel.position; hub.rotation_degrees = Vector3(90,0,0); hub.material_override = chrome
            root.add_child(hub)

    _local_box(root, Vector3(2.13,0.76,-0.56), Vector3(0.12,0.30,0.62), head_mat, false)
    _local_box(root, Vector3(2.13,0.76,0.56), Vector3(0.12,0.30,0.62), head_mat, false)
    _local_box(root, Vector3(-2.13,0.76,-0.56), Vector3(0.12,0.30,0.62), tail_mat, false)
    _local_box(root, Vector3(-2.13,0.76,0.56), Vector3(0.12,0.30,0.62), tail_mat, false)

    var head_l := OmniLight3D.new(); head_l.position=Vector3(2.25,0.78,-0.55); head_l.omni_range=16; head_l.light_energy=2.5; head_l.light_color=Color("#fff1c9"); head_l.visible=false; root.add_child(head_l)
    var head_r := OmniLight3D.new(); head_r.position=Vector3(2.25,0.78,0.55); head_r.omni_range=16; head_r.light_energy=2.5; head_r.light_color=Color("#fff1c9"); head_r.visible=false; root.add_child(head_r)
    root.set_meta("headlights", [head_l,head_r])
    return root

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

func _make_traffic() -> void:
    var routes := [
        {"axis":"x", "z":28.0, "from":-175.0, "to":175.0, "speed":7.0},
        {"axis":"x", "z":-58.0, "from":-110.0, "to":110.0, "speed":5.8},
        {"axis":"z", "x":-62.0, "from":-110.0, "to":125.0, "speed":6.4},
        {"axis":"z", "x":66.0, "from":-90.0, "to":105.0, "speed":6.0}
    ]
    var colors := [Color("#d7d2c8"),Color("#294e78"),Color("#a52f2f"),Color("#30343a"),Color("#6c5737")]
    for i in range(12):
        var r: Dictionary = routes[i % routes.size()]
        var t := float(i) / 12.0
        var car: Node3D
        if r["axis"] == "x":
            var x: float = lerp(float(r["from"]), float(r["to"]), t)
            car = _make_car(Vector3(x,0.45,float(r["z"])), colors[i % colors.size()], 0.0)
        else:
            var z: float = lerp(float(r["from"]), float(r["to"]), t)
            car = _make_car(Vector3(float(r["x"]),0.45,z), colors[i % colors.size()], PI/2.0)
        traffic.append({"node":car,"route":r,"phase":t,"speed":float(r["speed"]) * rng.randf_range(0.82,1.15)})

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

    var skin := _mat(Color("#b87857"),0.58)
    var shirt := _mat(shirt_color,0.74)
    var pants := _mat(Color("#20252a"),0.82)
    var shoes := _mat(Color("#111315"),0.92)
    var hair := _mat(Color("#181a1b"),0.90)
    var body := Node3D.new(); body.position.y=0.9; root.add_child(body)
    _local_person_part(body,Vector3(0,0.72,0),Vector3(0.54,0.92,0.36),shirt)
    _local_person_part(body,Vector3(0,1.38,0),Vector3(0.36,0.36,0.36),skin,true)
    _local_person_part(body,Vector3(0,1.56,0),Vector3(0.38,0.13,0.38),hair,true)
    var arm_l:=Node3D.new(); arm_l.position=Vector3(-0.37,0.95,0); body.add_child(arm_l); _local_person_part(arm_l,Vector3(0,-0.34,0),Vector3(0.14,0.70,0.14),skin)
    var arm_r:=Node3D.new(); arm_r.position=Vector3(0.37,0.95,0); body.add_child(arm_r); _local_person_part(arm_r,Vector3(0,-0.34,0),Vector3(0.14,0.70,0.14),skin)
    var leg_l:=Node3D.new(); leg_l.position=Vector3(-0.18,0.45,0); body.add_child(leg_l); _local_person_part(leg_l,Vector3(0,-0.35,0),Vector3(0.17,0.72,0.17),pants); _local_person_part(leg_l,Vector3(0,-0.73,-0.08),Vector3(0.22,0.14,0.40),shoes)
    var leg_r:=Node3D.new(); leg_r.position=Vector3(0.18,0.45,0); body.add_child(leg_r); _local_person_part(leg_r,Vector3(0,-0.35,0),Vector3(0.17,0.72,0.17),pants); _local_person_part(leg_r,Vector3(0,-0.73,-0.08),Vector3(0.22,0.14,0.40),shoes)
    root.set_meta("anim_parts",[arm_l,arm_r,leg_l,leg_r,body])
    return root

func _animate_person(root: Node3D, phase: float, t: float) -> void:
    var parts: Array = root.get_meta("anim_parts",[])
    if parts.size() < 5: return
    var swing := sin(t*4.0+phase)*0.42
    parts[0].rotation.x = swing; parts[1].rotation.x = -swing
    parts[2].rotation.x = -swing*0.8; parts[3].rotation.x = swing*0.8
    parts[4].position.y = 0.9 + abs(sin(t*4.0+phase))*0.025

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

func _make_city_props()
    _make_extra_street_detail()
    _make_sidewalk_lamps()
    _make_city_windows() -> void:
    # Crosswalks and lane separators
    for x in range(-155,156,18):
        for i in range(6):
            _box(Vector3(x + i*1.5 - 3.75,0.29,23.0), Vector3(0.95,0.035,3.2), _mat(Color("#e7e4d7"),0.72), false)
    # Traffic lights at the main intersection
    for p in [Vector3(-6,0,28),Vector3(6,0,28),Vector3(0,0,21),Vector3(0,0,35)]:
        _box(p+Vector3(0,2.3,0),Vector3(0.18,4.6,0.18),_mat(Color("#202326"),0.58,0.08),false)
        _box(p+Vector3(0,4.35,0),Vector3(0.52,0.95,0.38),_mat(Color("#17191a"),0.55),false)
    # Rooftop AC units / vents for visual detail
    for p in [Vector3(-52,18,-24),Vector3(-14,14,-24),Vector3(25,16,-24),Vector3(64,12,-24),Vector3(-52,18,66),Vector3(25,16,66)]:
        _box(p+Vector3(0,0.55,0),Vector3(1.5,1.1,1.1),_mat(Color("#c4c4bd"),0.72,0.08),false)
        _box(p+Vector3(0,1.15,0),Vector3(0.95,0.08,0.7),_mat(Color("#686d6d"),0.85),false)
    # Park benches near the lake
    for x in [-5.0, 12.0, 29.0]:
        _box(Vector3(x,0.65,-36),Vector3(3.0,0.18,0.55),_mat(Color("#6b4930"),0.82),false)
        for leg_x in [-1.0,1.0]:
            _box(Vector3(x+leg_x,0.28,-36),Vector3(0.14,0.75,0.14),_mat(Color("#303234"),0.62,0.15),false)

func _make_extra_street_detail() -> void:
    # Parking bays, bollards, bins and utility boxes make the city feel inhabited.
    for x in range(-150,151,18):
        _box(Vector3(x,0.30,37.5),Vector3(0.10,0.05,4.2),_mat(Color("#d8d8d2"),0.75),false)
        for side in [-1.0,1.0]:
            _box(Vector3(x+side*4.0,0.55,34.0),Vector3(0.20,1.0,0.20),_mat(Color("#303336"),0.62,0.1),false)
    for p in [Vector3(-48,0,24),Vector3(46,0,24),Vector3(-48,0,-52),Vector3(46,0,-52)]:
        _box(p+Vector3(0,0.55,0),Vector3(0.85,1.1,0.65),_mat(Color("#4d5a55"),0.88),false)
        _box(p+Vector3(0,1.18,0),Vector3(0.55,0.08,0.45),_mat(Color("#202425"),0.7),false)

func _make_sidewalk_lamps() -> void:
    for x in range(-150,151,30):
        var p:=Vector3(x,0,24.0)
        _box(p+Vector3(0,2.4,0),Vector3(0.10,4.8,0.10),_mat(Color("#303235"),0.5,0.15),false)
        _box(p+Vector3(0.42,4.62,0),Vector3(0.9,0.08,0.08),_mat(Color("#303235"),0.5,0.15),false)
        var l:=OmniLight3D.new(); l.position=p+Vector3(0.88,4.48,0); l.omni_range=9; l.light_energy=1.0; l.light_color=Color("#ffe0a5"); l.visible=false; add_child(l); street_lamps.append(l)

func _make_city_windows() -> void:
    # A second layer of small emissive windows switches on at night.
    for x in [-52.0,-14.0,25.0,64.0]:
        for z in [-24.0,66.0]:
            var base_y:=8.0
            for row in range(3):
                for col in range(3):
                    var w:=MeshInstance3D.new(); var bm:=BoxMesh.new(); bm.size=Vector3(1.1,0.8,0.06); w.mesh=bm
                    w.position=Vector3(x-3.5+col*3.5,base_y+row*3.0,z+7.0)
                    w.material_override=_mat(Color("#b6d8e7"),0.18,0.15,Color("#10222b"))
                    add_child(w); building_windows.append(w)

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
    time_of_day = fmod(time_of_day + delta * day_night_speed, 24.0)
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
        n.position.y = 0.05 + abs(sin(t*3.2+phase))*0.025
        _animate_person(n, phase, t)

    var night_now := time_of_day < 6.0 or time_of_day > 18.3
    for w in building_windows:
        var wm: StandardMaterial3D = w.material_override
        wm.emission_enabled = night_now
        if night_now:
            wm.emission = Color("#ffd98a")
            wm.emission_energy_multiplier = 1.7
        else:
            wm.emission = Color("#10222b")
            wm.emission_energy_multiplier = 0.0

    for data in traffic:
        var car: Node3D = data["node"]
        var route: Dictionary = data["route"]
        var phase: float = fmod(float(data["phase"]) + float(data["speed"]) * delta / (float(route["to"]) - float(route["from"])), 1.0)
        if route["axis"] == "x":
            car.position.x = lerp(float(route["from"]), float(route["to"]), phase)
            car.position.z = float(route["z"])
        else:
            car.position.z = lerp(float(route["from"]), float(route["to"]), phase)
            car.position.x = float(route["x"])
        data["phase"] = phase
        var lights: Array = car.get_meta("headlights")
        var night := time_of_day < 6.0 or time_of_day > 18.3
        for light in lights:
            light.visible = night

    var night := time_of_day < 6.0 or time_of_day > 18.3
    for lamp in street_lamps:
        lamp.visible = night

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
