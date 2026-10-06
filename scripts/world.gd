extends Node3D

# Real World Open World — Realistic Foundation v4.
# Procedural open-world foundation with traffic, city props, weather and day/night.

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
var driveable_vehicle: CharacterBody3D
var driveable_vehicles: Array[CharacterBody3D] = []
var _fps_timer: float = 0.0
var _quality_level: int = 2
var _simulation_accumulator: float = 0.0
var _player_ref: Node3D
const NPC_SIMULATION_RADIUS := 95.0
const NPC_REDUCED_RADIUS := 145.0
const TRAFFIC_SIMULATION_RADIUS := 155.0
const TRAFFIC_REDUCED_RADIUS := 215.0
const REDUCED_SIMULATION_INTERVAL := 0.12
var _reduced_simulation_accumulator: float = 0.0

# STEP 5: sector-aware dynamic simulation cache.
# The world stays fully present; sectors only reduce how many distant actors
# are considered by the CPU each simulation tick.
const DYNAMIC_SECTOR_SIZE := 80.0
const SECTOR_REFRESH_INTERVAL := 0.75
var _sector_refresh_timer: float = 0.0
var _dynamic_sector_cache_player := Vector2i(999999, 999999)
var _nearby_npcs: Array = []
var _nearby_traffic: Array = []

# STEP 6: distance-based collision LOD for static world props.
const COLLISION_ACTIVE_RADIUS := 125.0
const COLLISION_DISABLE_RADIUS := 155.0
const COLLISION_REFRESH_INTERVAL := 0.25
var _collision_lod_bodies: Array[StaticBody3D] = []
var _collision_refresh_timer: float = 0.0

# STEP 7: adaptive shadow quality. Keep the world and lighting intact,
# but scale shadow distance/softness with actual mobile performance.
var _shadow_quality_level: int = 2

# STEP 10: distance-based shadow caster LOD.
# Small decorative geometry keeps its mesh, collision and gameplay, but stops
# casting expensive dynamic shadows when far away. This reduces mobile GPU work
# without removing any world content.
const SHADOW_LOD_ENABLE_RADIUS := 55.0
const SHADOW_LOD_DISABLE_RADIUS := 85.0
const SHADOW_LOD_REFRESH_INTERVAL := 0.35
var _shadow_lod_geometries: Array[GeometryInstance3D] = []
var _shadow_lod_timer: float = 0.0

# STEP 12: vehicle render LOD.
# Cars keep their full geometry, but distant vehicle shadows and headlights
# are disabled when they are too far to make a visible difference on mobile.
const VEHICLE_LOD_LIGHT_ON_RADIUS := 70.0
const VEHICLE_LOD_LIGHT_OFF_RADIUS := 105.0
const VEHICLE_LOD_SHADOW_ON_RADIUS := 65.0
const VEHICLE_LOD_SHADOW_OFF_RADIUS := 95.0
const VEHICLE_LOD_REFRESH_INTERVAL := 0.35
var _vehicle_lod_roots: Array[Node3D] = []
var _vehicle_lod_timer: float = 0.0

# STEP 8: shared opaque material cache.
# Reusing identical StandardMaterial3D resources reduces material/state changes
# while keeping the same colors, roughness, metallic values and emissions.
var _material_cache: Dictionary = {}

func _ready() -> void:
    rng.seed = 190428
    _setup_environment()
    _make_terrain()
    _make_lake()
    _make_mountains()
    _make_forests()
    _make_city_and_roads()
    _make_cars()
    _make_driveable_vehicle()
    _make_traffic()
    _make_pedestrians()
    _make_landmarks()
    _make_service_buildings()
    _make_waterfront()
    _make_job_locations()
    _make_city_props()
    _make_realistic_facades()
    _make_road_details()
    _setup_weather_particles()
    _player_ref = get_node_or_null("Player") as Node3D
    _refresh_dynamic_sector_cache(true)
    _configure_world_lod()
    _apply_step9_culling(self)
    _apply_shadow_lod(true)
    _apply_vehicle_lod(true)


func _configure_world_lod() -> void:
    # STEP 3 + STEP 9: hierarchical visibility plus tighter distant culling.
    # Major world pieces stay visible farther away; small decoration is culled
    # earlier to reduce GPU work without removing gameplay content.
    _apply_lod_recursive(self)

func _apply_step9_culling(node: Node) -> void:
    for child in node.get_children():
        if child is GeometryInstance3D:
            var geo := child as GeometryInstance3D
            var distance := float(geo.get_meta("lod_distance", geo.visibility_range_end))
            if distance <= 0.0:
                distance = 260.0

            var n := String(geo.name).to_lower()
            if n.contains("road") or n.contains("terrain") or n.contains("mountain"):
                geo.visibility_range_end = max(distance, 300.0)
            elif n.contains("window") or n.contains("awning") or n.contains("balcony") or n.contains("curb"):
                geo.visibility_range_end = min(distance, 205.0)
            else:
                geo.visibility_range_end = min(distance, 260.0)
        _apply_step9_culling(child)

func _apply_lod_recursive(node: Node) -> void:
    for child in node.get_children():
        if child is GeometryInstance3D:
            var geo := child as GeometryInstance3D
            var distance := float(geo.get_meta("lod_distance", 0.0))
            if distance <= 0.0:
                distance = geo.visibility_range_end
            if distance <= 0.0:
                distance = 260.0

            var n := String(geo.name).to_lower()
            if n.contains("tree") or n.contains("crown") or n.contains("trunk"):
                distance = min(distance, 210.0)
            elif n.contains("window") or n.contains("awning") or n.contains("balcony"):
                distance = min(distance, 205.0)
            elif n.contains("road") or n.contains("terrain"):
                distance = max(distance, 300.0)

            geo.visibility_range_end = distance
        _apply_lod_recursive(child)

func _distance_to_player(node: Node3D) -> float:
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref == null:
        return 0.0
    return node.global_position.distance_to(_player_ref.global_position)

func _dynamic_sector_key(pos: Vector3) -> Vector2i:
    return Vector2i(floori(pos.x / DYNAMIC_SECTOR_SIZE), floori(pos.z / DYNAMIC_SECTOR_SIZE))

func _refresh_dynamic_sector_cache(force: bool = false) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref == null:
        return

    var player_sector := _dynamic_sector_key(_player_ref.global_position)
    _sector_refresh_timer += get_process_delta_time()

    if not force and player_sector == _dynamic_sector_cache_player and _sector_refresh_timer < SECTOR_REFRESH_INTERVAL:
        return

    _sector_refresh_timer = 0.0
    _dynamic_sector_cache_player = player_sector

    # Build small spatial buckets from the full NPC list, then keep only
    # nearby candidates. This fixes the initial empty-cache case from Step 5.
    var npc_buckets: Dictionary = {}
    for npc_data in npcs:
        var actor: Node3D = npc_data["node"]
        if not is_instance_valid(actor):
            continue
        var key := _dynamic_sector_key(actor.global_position)
        if not npc_buckets.has(key):
            npc_buckets[key] = []
        npc_buckets[key].append(npc_data)

    var traffic_buckets: Dictionary = {}
    for traffic_data in traffic:
        var actor: Node3D = traffic_data["node"]
        if not is_instance_valid(actor):
            continue
        var key := _dynamic_sector_key(actor.global_position)
        if not traffic_buckets.has(key):
            traffic_buckets[key] = []
        traffic_buckets[key].append(traffic_data)

    _nearby_npcs.clear()
    _nearby_traffic.clear()

    # Include a one-sector safety margin so actors crossing a sector boundary
    # never disappear from simulation just because the cache refreshed late.
    var npc_radius_sectors := ceili(NPC_REDUCED_RADIUS / DYNAMIC_SECTOR_SIZE) + 1
    var traffic_radius_sectors := ceili(TRAFFIC_REDUCED_RADIUS / DYNAMIC_SECTOR_SIZE) + 1

    for dz in range(-npc_radius_sectors, npc_radius_sectors + 1):
        for dx in range(-npc_radius_sectors, npc_radius_sectors + 1):
            var key := player_sector + Vector2i(dx, dz)
            if npc_buckets.has(key):
                _nearby_npcs.append_array(npc_buckets[key])

    for dz in range(-traffic_radius_sectors, traffic_radius_sectors + 1):
        for dx in range(-traffic_radius_sectors, traffic_radius_sectors + 1):
            var key := player_sector + Vector2i(dx, dz)
            if traffic_buckets.has(key):
                _nearby_traffic.append_array(traffic_buckets[key])

func _collision_lod_tick(delta: float) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref == null:
        return
    _collision_refresh_timer += delta
    if _collision_refresh_timer < COLLISION_REFRESH_INTERVAL:
        return
    _collision_refresh_timer = 0.0
    var player_pos := _player_ref.global_position
    for body in _collision_lod_bodies:
        if not is_instance_valid(body):
            continue
        var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
        if shape == null:
            continue
        var distance := player_pos.distance_to(body.global_position)
        if distance <= COLLISION_ACTIVE_RADIUS:
            shape.disabled = false
        elif distance >= COLLISION_DISABLE_RADIUS:
            shape.disabled = true

func _apply_vehicle_lod(force: bool = false, delta: float = 0.0) -> void:
    _vehicle_lod_timer += delta
    if not force and _vehicle_lod_timer < VEHICLE_LOD_REFRESH_INTERVAL:
        return
    _vehicle_lod_timer = 0.0
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref == null:
        return
    var player_pos := _player_ref.global_position
    for root in _vehicle_lod_roots:
        if not is_instance_valid(root):
            continue
        var distance := player_pos.distance_to(root.global_position)
        var shadow_on := distance <= VEHICLE_LOD_SHADOW_ON_RADIUS
        var shadow_off := distance >= VEHICLE_LOD_SHADOW_OFF_RADIUS
        var light_on := distance <= VEHICLE_LOD_LIGHT_ON_RADIUS
        var light_off := distance >= VEHICLE_LOD_LIGHT_OFF_RADIUS
        var shadow_state := root.get_meta("vehicle_shadow_state", -1)
        if shadow_on and shadow_state != 1:
            for child in root.get_children():
                if child is GeometryInstance3D:
                    (child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            root.set_meta("vehicle_shadow_state", 1)
        elif shadow_off and shadow_state != 0:
            for child in root.get_children():
                if child is GeometryInstance3D:
                    (child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            root.set_meta("vehicle_shadow_state", 0)

        var lights: Array = root.get_meta("headlights", [])
        var light_state := root.get_meta("vehicle_light_state", -1)
        if light_on and light_state != 1:
            for light in lights:
                if is_instance_valid(light):
                    light.visible = true
            root.set_meta("vehicle_light_state", 1)
        elif light_off and light_state != 0:
            for light in lights:
                if is_instance_valid(light):
                    light.visible = false
            root.set_meta("vehicle_light_state", 0)

func _apply_shadow_lod(force: bool = false, delta: float = 0.0) -> void:
    _shadow_lod_timer += delta
    if not force and _shadow_lod_timer < SHADOW_LOD_REFRESH_INTERVAL:
        return
    _shadow_lod_timer = 0.0
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref == null:
        return
    var player_pos := _player_ref.global_position
    for geo in _shadow_lod_geometries:
        if not is_instance_valid(geo):
            continue
        var distance := player_pos.distance_to(geo.global_position)
        if distance <= SHADOW_LOD_ENABLE_RADIUS:
            geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        elif distance >= SHADOW_LOD_DISABLE_RADIUS:
            geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _adaptive_quality_tick(delta: float) -> void:
    # Adaptive quality: keep the full world loaded, but reduce expensive rendering
    # only when the phone is actually struggling, then restore it when stable.
    _fps_timer += delta
    if _fps_timer < 1.5:
        return
    _fps_timer = 0.0
    var fps := Engine.get_frames_per_second()
    var next_quality := 2
    if fps < 28:
        next_quality = 0
    elif fps < 40:
        next_quality = 1
    if next_quality != _quality_level:
        _quality_level = next_quality
        _apply_mobile_quality()
    if next_quality != _shadow_quality_level:
        _shadow_quality_level = next_quality
        _apply_shadow_quality()

func _apply_shadow_quality() -> void:
    if not sun:
        return
    if _shadow_quality_level == 2:
        sun.directional_shadow_max_distance = 90.0
        sun.shadow_bias = 0.08
        sun.shadow_normal_bias = 1.0
    elif _shadow_quality_level == 1:
        sun.directional_shadow_max_distance = 68.0
        sun.shadow_bias = 0.10
        sun.shadow_normal_bias = 1.25
    else:
        sun.directional_shadow_max_distance = 48.0
        sun.shadow_bias = 0.12
        sun.shadow_normal_bias = 1.5

func _apply_mobile_quality() -> void:
    if not sun:
        return
    # World geometry/assets stay intact. Only costly effects are scaled dynamically.
    if _quality_level == 2:
        sun.directional_shadow_max_distance = 90.0
        if rain_particles: rain_particles.amount = 220
        if snow_particles: snow_particles.amount = 120
    elif _quality_level == 1:
        sun.directional_shadow_max_distance = 65.0
        if rain_particles: rain_particles.amount = 140
        if snow_particles: snow_particles.amount = 80
    else:
        sun.directional_shadow_max_distance = 45.0
        if rain_particles: rain_particles.amount = 80
        if snow_particles: snow_particles.amount = 50

func _setup_environment() -> void:
    # STEP 14: lighting + environment overhaul.
    # Keep the full world and all gameplay content. This only improves the
    # outdoor presentation while staying friendly to the Compatibility renderer.
    world_env = get_node_or_null("WorldEnvironment") as WorldEnvironment
    if world_env == null:
        world_env = WorldEnvironment.new()
        world_env.name = "WorldEnvironment"
        add_child(world_env)

    var env := world_env.environment
    if env == null:
        env = Environment.new()
        world_env.environment = env

    # A procedural sky gives the scene a real outdoor horizon instead of the
    # flat gray/white background. It also contributes ambient/specular light.
    env.background_mode = Environment.BG_SKY
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.72
    env.ambient_light_sky_contribution = 0.78

    var sky := env.sky
    if sky == null:
        sky = Sky.new()
        env.sky = sky

    var sky_mat := sky.sky_material as ProceduralSkyMaterial
    if sky_mat == null:
        sky_mat = ProceduralSkyMaterial.new()
        sky.sky_material = sky_mat

    sky_mat.sky_top_color = Color("#0b2748")
    sky_mat.sky_horizon_color = Color("#9bc4d5")
    sky_mat.ground_bottom_color = Color("#18231f")
    sky_mat.ground_horizon_color = Color("#71877d")
    sky_mat.sun_angle_max = 12.0
    sky_mat.sun_curve = 0.08

    # Depth fog blends distant buildings into the sky and gives the large world
    # atmospheric depth without using expensive volumetric fog.
    env.fog_enabled = true
    env.fog_light_color = Color("#a9c3cb")
    env.fog_light_energy = 0.55
    env.fog_density = 0.00065
    env.fog_height = 10.0
    env.fog_height_density = 0.003
    env.fog_sun_scatter = 0.18
    env.fog_aerial_perspective = 0.72
    env.fog_sky_affect = 0.18
    env.fog_depth_begin = 65.0
    env.fog_depth_end = 320.0

    # Gentle color correction makes materials read better on mobile screens.
    # Auto exposure and heavy post-processing stay disabled for performance.
    env.adjustment_enabled = true
    env.adjustment_brightness = 1.03
    env.adjustment_contrast = 1.08
    env.adjustment_saturation = 1.06
    env.glow_enabled = false

    sun = get_node_or_null("Sun") as DirectionalLight3D
    if sun == null:
        sun = DirectionalLight3D.new()
        sun.name = "Sun"
        add_child(sun)

    sun.light_color = Color("#fff0d2")
    sun.light_energy = 1.30
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 90.0
    sun.shadow_bias = 0.08
    sun.shadow_normal_bias = 1.0
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)

func _mat(color: Color, rough: float = 0.8, metallic: float = 0.0, emission: Color = Color(0,0,0,0)) -> StandardMaterial3D:
    var key := "%s|%.3f|%.3f|%s" % [color.to_html(true), rough, metallic, emission.to_html(true)]
    if _material_cache.has(key):
        return _material_cache[key] as StandardMaterial3D

    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    m.metallic = metallic
    if emission.a > 0.0:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 1.5
    _material_cache[key] = m
    return m

func _mat_unique(color: Color, rough: float = 0.8, metallic: float = 0.0, emission: Color = Color(0,0,0,0)) -> StandardMaterial3D:
    # Use this when a caller will mutate the material after creation.
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

    # STEP 3: choose visibility distance from object size.
    var max_dim := max(size.x, max(size.y, size.z))
    var lod_distance := 260.0
    if max_dim >= 120.0:
        lod_distance = 330.0
    elif max_dim >= 40.0:
        lod_distance = 300.0
    elif max_dim >= 10.0:
        lod_distance = 260.0
    elif max_dim >= 3.0:
        lod_distance = 230.0
    else:
        lod_distance = 205.0
    mesh.visibility_range_end = lod_distance
    mesh.set_meta("lod_distance", lod_distance)
    # Decorative props do not cast dynamic shadows; buildings/roads keep shadows.
    if collision:
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    else:
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

    # STEP 10: register only small collidable props for shadow LOD.
    # Large buildings/roads keep their normal shadow behavior.
    if collision and max_dim <= 10.0:
        _shadow_lod_geometries.append(mesh)
        mesh.set_meta("shadow_lod", true)

    add_child(mesh)
    if collision:
        var body := StaticBody3D.new()
        body.position = pos
        var cs := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        cs.shape = shape
        body.add_child(cs)
        _collision_lod_bodies.append(body)
        add_child(body)
    return mesh

func _height(x: float, z: float) -> float:
    var d := Vector2(x, z).length()
    if d < 58.0:
        return 0.0
    var h: float = sin(x * 0.026) * 3.0
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

    # Physics uses a much coarser collision mesh than the visual terrain.
    # The full 78x78 terrain remains rendered; this cuts collision triangles heavily.
    var body := StaticBody3D.new()
    var collision := CollisionShape3D.new()
    var shape := ConcavePolygonShape3D.new()
    var collision_n := 26
    var collision_step := (extent * 2.0) / float(collision_n)
    var faces := PackedVector3Array()
    for iz in range(collision_n):
        for ix in range(collision_n):
            var x0 := -extent + ix * collision_step
            var z0 := -extent + iz * collision_step
            var x1 := x0 + collision_step
            var z1 := z0 + collision_step
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
    # Lake material is intentionally unique because its alpha/transparency
    # is modified after creation and must not affect cached opaque materials.
    var wm := _mat_unique(Color("#176d82"), 0.08, 0.65)
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
    root.visibility_range_end = 190.0
    root.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
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
    # Batch the forest into regional MultiMeshes. This keeps the same visible
    # tree count while replacing hundreds of individual render nodes with a
    # small number of GPU-instanced batches.
    var regions := [
        Rect2(Vector2(-205, -205), Vector2(135, 410)),
        Rect2(Vector2(-70, -205), Vector2(140, 410)),
        Rect2(Vector2(70, -205), Vector2(135, 410))
    ]
    for region_index in range(regions.size()):
        _make_forest_multimesh(regions[region_index], region_index)

func _make_forest_multimesh(region: Rect2, region_index: int) -> void:
    var transforms: Array[Transform3D] = []
    var attempts := 0
    while transforms.size() < 50 and attempts < 500:
        attempts += 1
        var x := rng.randf_range(region.position.x, region.end.x)
        var z := rng.randf_range(region.position.y, region.end.y)
        var p := Vector3(x, 0, z)
        if p.length() < 54.0:
            continue
        if p.x > 18 and p.x < 142 and p.z < -28 and p.z > -112:
            continue
        var s := rng.randf_range(0.75, 1.55)
        var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
        transforms.append(Transform3D(basis, Vector3(p.x, _height(p.x, p.z), p.z)))
    if transforms.is_empty():
        return

    var batch := MultiMeshInstance3D.new()
    batch.name = "ForestMultiMesh_%d" % region_index
    batch.visibility_range_end = 210.0

    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.instance_count = transforms.size()

    # Two-surface tree: trunk + three foliage tiers, packed into one mesh.
    # Materials are shared by the whole batch, which is exactly what makes
    # MultiMesh efficient.
    var tree_mesh := ArrayMesh.new()
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _append_tree_geometry(st)
    var mesh := st.commit()
    mm.mesh = mesh

    for i in range(transforms.size()):
        mm.set_instance_transform(i, transforms[i])

    batch.multimesh = mm
    add_child(batch)

func _append_tree_geometry(st: SurfaceTool) -> void:
    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.13
    trunk.bottom_radius = 0.28
    trunk.height = 3.1
    trunk.radial_segments = 8
    var crown := CylinderMesh.new()
    crown.top_radius = 0.02
    crown.bottom_radius = 1.35
    crown.height = 2.8
    crown.radial_segments = 8
    # SurfaceTool cannot directly append primitive resources, so build a
    # compact low-poly tree from repeated cone vertices.
    _append_cone(st, 0.28, 0.13, 3.1, 8, 0.0, Color("#493326"))
    _append_cone(st, 1.35, 0.02, 2.8, 8, 3.6, Color("#235437"))
    _append_cone(st, 1.10, 0.02, 2.6, 8, 4.8, Color("#235437"))
    _append_cone(st, 0.85, 0.02, 2.4, 8, 5.9, Color("#2e6641"))

func _append_cone(st: SurfaceTool, bottom_radius: float, top_radius: float, height: float, segments: int, center_y: float, color: Color) -> void:
    var half := height * 0.5
    for i in range(segments):
        var a0 := TAU * float(i) / segments
        var a1 := TAU * float(i + 1) / segments
        var v0 := Vector3(cos(a0) * bottom_radius, center_y - half, sin(a0) * bottom_radius)
        var v1 := Vector3(cos(a1) * bottom_radius, center_y - half, sin(a1) * bottom_radius)
        var v2 := Vector3(cos(a1) * top_radius, center_y + half, sin(a1) * top_radius)
        var v3 := Vector3(cos(a0) * top_radius, center_y + half, sin(a0) * top_radius)
        st.set_color(color); st.add_vertex(v0)
        st.set_color(color); st.add_vertex(v1)
        st.set_color(color); st.add_vertex(v2)
        st.set_color(color); st.add_vertex(v0)
        st.set_color(color); st.add_vertex(v2)
        st.set_color(color); st.add_vertex(v3)

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
    var window_rows: int = max(1, floors)
    for row in range(window_rows):
        var y: float = 2.0 + row * (size.y / float(window_rows))
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
    root.visibility_range_end = 220.0
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

    var head_l := OmniLight3D.new()
    head_l.position = Vector3(2.05,0.78,-0.55)
    head_l.omni_range = 13.0
    head_l.light_energy = 2.0
    head_l.light_color = Color("#fff1c9")
    head_l.visible = false
    root.add_child(head_l)
    var head_r := OmniLight3D.new()
    head_r.position = Vector3(2.05,0.78,0.55)
    head_r.omni_range = 13.0
    head_r.light_energy = 2.0
    head_r.light_color = Color("#fff1c9")
    head_r.visible = false
    root.add_child(head_r)
    root.set_meta("headlights", [head_l, head_r])
    root.set_meta("vehicle_shadow_state", 1)
    root.set_meta("vehicle_light_state", 0)
    _vehicle_lod_roots.append(root)
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
    for i in range(8):
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
    root.visibility_range_end = 150.0
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
    for i in range(5):
        var start := Vector3(-55 + i * 22, 0.05, 19 + (i % 2) * 18)
        var person := _make_person(start, shirt_colors[i % shirt_colors.size()], rng.randf_range(0.92,1.06))
        npcs.append({"node":person, "base":start, "phase":rng.randf_range(0.0,TAU), "radius":rng.randf_range(2.0,5.0)})

func _make_landmarks() -> void:
    _make_building(Vector3(-18,0,12), Vector3(13,5.5,10), Color("#8b6248"), 1)
    _box(Vector3(22,5.0,-5), Vector3(10,0.5,10), _mat(Color("#765033"),0.92), false)
    for x in [-3.8,3.8]:
        for z in [-3.8,3.8]:
            _box(Vector3(22+x,2.5,-5+z), Vector3(0.3,5,0.3), _mat(Color("#5b3d29"),0.96), false)

func _make_city_props() -> void:
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

func _make_realistic_facades() -> void:
    # Extra facade depth: awnings, balconies, AC units and warm window lighting.
    var glass_day := _mat(Color("#31586b"), 0.12, 0.35)
    var frame := _mat(Color("#34383b"), 0.52, 0.15)
    var balcony := _mat(Color("#c3b9aa"), 0.68, 0.05)
    var awning := _mat(Color("#48545b"), 0.58, 0.08)
    for x in [-52.0,-14.0,25.0,64.0]:
        for z in [-24.0,66.0]:
            var h: float = 8.0
            var w: float = 15.0
            for row in range(2):
                var y: float = 3.2 + row * 4.0
                for side in [-1.0,1.0]:
                    _box(Vector3(x + side * (w * 0.38), y, z), Vector3(2.2,0.16,8.0), balcony, false)
                _box(Vector3(x, y + 0.15, z - 5.3), Vector3(3.8,0.12,0.65), awning, false)
            for wx in [-5.0,-1.7,1.7,5.0]:
                _box(Vector3(x + wx, 2.8, z - 6.05), Vector3(1.25,1.45,0.08), glass_day, false)
                _box(Vector3(x + wx, 2.8, z - 6.11), Vector3(1.36,0.08,0.07), frame, false)

func _make_road_details() -> void:
    var curb := _mat(Color("#b0aea6"), 0.88)
    var dark := _mat(Color("#34373a"), 0.96)
    for p in [Vector3(0,0,28),Vector3(-62,0,-20),Vector3(66,0,28),Vector3(-8,0,-58)]:
        if abs(p.z - 28.0) < 0.1:
            _box(p + Vector3(0,0.28,4.9), Vector3(390,0.28,0.22), curb, false)
            _box(p + Vector3(0,0.28,-4.9), Vector3(390,0.28,0.22), curb, false)
        elif abs(p.z + 58.0) < 0.1:
            _box(p + Vector3(0,0.28,4.9), Vector3(240,0.28,0.22), curb, false)
            _box(p + Vector3(0,0.28,-4.9), Vector3(240,0.28,0.22), curb, false)
        else:
            _box(p + Vector3(4.9,0.28,0), Vector3(0.22,0.28,270 if p.x < 0 else 230), curb, false)
            _box(p + Vector3(-4.9,0.28,0), Vector3(0.22,0.28,270 if p.x < 0 else 230), curb, false)
    # Small asphalt repair patches give the roads more visual variation.
    for i in range(18):
        var x: float = rng.randf_range(-170.0,170.0)
        var z: float = 28.0 + rng.randf_range(-3.4,3.4)
        _box(Vector3(x,0.255,z), Vector3(rng.randf_range(1.0,3.5),0.025,rng.randf_range(0.35,0.8)), dark, false)

func _setup_weather_particles() -> void:
    rain_particles = _weather_particles(false)
    snow_particles = _weather_particles(true)
    rain_particles.visible = false
    snow_particles.visible = false

func _weather_particles(snow: bool) -> GPUParticles3D:
    var particles := GPUParticles3D.new()
    particles.amount = 120 if snow else 220
    particles.lifetime = 2.0 if snow else 0.65
    particles.visibility_aabb = AABB(Vector3(-55,-3,-55),Vector3(110,42,110))
    var process := ParticleProcessMaterial.new()
    process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process.emission_box_extents = Vector3(48,15,48)
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


func _make_sign(pos: Vector3, text_value: String, color: Color) -> void:
    var post := _box(pos + Vector3(0,1.2,0), Vector3(0.10,2.4,0.10), _mat(Color("#2a2d2f"),0.7), false)
    var sign := _box(pos + Vector3(0,2.45,0), Vector3(2.8,0.85,0.10), _mat(color,0.68), false)
    sign.set_meta("label", text_value)

func _make_service_buildings() -> void:
    # Civic district: hospital, police, fire and bank landmarks.
    var civic := [
        {"p":Vector3(-42,0,-6),"s":Vector3(22,9,16),"c":Color("#d8d6d0"),"sign":"HOSPITAL"},
        {"p":Vector3(38,0,-6),"s":Vector3(20,8,15),"c":Color("#596b78"),"sign":"POLICE"},
        {"p":Vector3(-42,0,78),"s":Vector3(20,7,15),"c":Color("#a34b3e"),"sign":"FIRE STATION"},
        {"p":Vector3(38,0,78),"s":Vector3(18,10,14),"c":Color("#75624b"),"sign":"BANK"}
    ]
    for d in civic:
        _make_building(d["p"],d["s"],d["c"],max(1,int(d["s"].y/4.0)))
        _make_sign(d["p"] + Vector3(0,d["s"].y + 0.05,d["s"].z/2 + 0.5),d["sign"],Color("#1d3542"))

    # Hospital entrance canopy and emergency bays.
    for x in [-47.0,-42.0,-37.0]:
        _box(Vector3(x,0.35,3.0),Vector3(3.8,0.25,6.0),_mat(Color("#d8d6d0"),0.65),false)
    _box(Vector3(-42,3.2,2.7),Vector3(16,0.35,6),_mat(Color("#f2f0ea"),0.55),false)

    # Fire-station garage doors.
    for x in [-47.0,-42.0,-37.0]:
        _box(Vector3(x,2.0,85.55),Vector3(3.8,3.2,0.12),_mat(Color("#262b2e"),0.35,0.2),false)

func _make_boat(pos: Vector3, scale_v: float = 1.0, rotation_y: float = 0.0) -> void:
    var boat := Node3D.new()
    boat.position = pos
    boat.rotation.y = rotation_y
    boat.scale = Vector3.ONE * scale_v
    add_child(boat)
    var hull := _mat(Color("#e8e2d6"),0.28,0.25)
    var dark := _mat(Color("#27313a"),0.38,0.3)
    var glass := _mat(Color("#31566a"),0.10,0.42)
    _local_box(boat,Vector3(0,0,0),Vector3(5.8,0.55,1.7),hull,false)
    _local_box(boat,Vector3(0,0.45,0),Vector3(2.5,0.65,1.35),dark,false)
    _local_box(boat,Vector3(0,0.8,0),Vector3(1.55,0.42,1.15),glass,false)
    _local_box(boat,Vector3(-1.75,0.62,0),Vector3(0.10,1.5,0.10),dark,false)

func _make_waterfront() -> void:
    # Marina pier, bollards and leisure boats at the lake.
    _box(Vector3(78,0.65,-75),Vector3(48,0.35,4.2),_mat(Color("#6c5239"),0.88),false)
    for x in range(57,101,6):
        _box(Vector3(x,0.75,-73.0),Vector3(0.35,1.2,0.35),_mat(Color("#3b2c23"),0.9),false)
    _make_boat(Vector3(62,0.55,-80),0.85,-0.35)
    _make_boat(Vector3(82,0.55,-83),1.0,0.25)
    _make_boat(Vector3(102,0.55,-77),0.72,-0.15)
    for x in [52.0,67.0,91.0,108.0]:
        _box(Vector3(x,0.18,-68),Vector3(0.55,0.25,0.55),_mat(Color("#b7a27d"),0.92),false)

func _make_job_locations() -> void:
    # Lightweight location metadata used by the HUD/interactions.
    var jobs := [
        {"name":"CITY HOSPITAL","pos":Vector3(-42,0,-6)},
        {"name":"POLICE HQ","pos":Vector3(38,0,-6)},
        {"name":"FIRE STATION","pos":Vector3(-42,0,78)},
        {"name":"BANK","pos":Vector3(38,0,78)},
        {"name":"MARINA","pos":Vector3(78,0,-75)},
        {"name":"PARK","pos":Vector3(10,0,-36)}
    ]
    for j in jobs:
        var marker := Marker3D.new()
        marker.position = j["pos"] + Vector3(0,0.15,0)
        marker.name = String(j["name"]).replace(" ","_")
        marker.set_meta("job_location",j["name"])
        add_child(marker)


# Safe civic mission loop.
var mission_index: int = -1
var mission_active: bool = false
var mission_target: Vector3 = Vector3.ZERO
var mission_name: String = ""
var mission_reward: int = 0
var mission_marker: MeshInstance3D

func start_next_mission() -> void:
    var missions := [
        {"name":"CLINIC DELIVERY","target":Vector3(-42,0,-6),"reward":250},
        {"name":"CITY DOCUMENTS","target":Vector3(38,0,-6),"reward":300},
        {"name":"FIRE DEPOT SUPPLY","target":Vector3(-42,0,78),"reward":350},
        {"name":"MARKET COURIER","target":Vector3(38,0,78),"reward":275},
        {"name":"MARINA DELIVERY","target":Vector3(78,0,-75),"reward":400},
        {"name":"PARK MAINTENANCE","target":Vector3(10,0,-36),"reward":225}
    ]
    mission_index = (mission_index + 1) % missions.size()
    var m: Dictionary = missions[mission_index]
    mission_name = String(m["name"])
    mission_target = m["target"]
    mission_reward = int(m["reward"])
    mission_active = true
    if is_instance_valid(mission_marker):
        mission_marker.queue_free()
    mission_marker = MeshInstance3D.new()
    var ring := TorusMesh.new()
    ring.inner_radius = 1.7
    ring.outer_radius = 2.1
    ring.rings = 12
    ring.ring_segments = 32
    mission_marker.mesh = ring
    mission_marker.material_override = _mat(Color("#f0d35b"),0.28,0.15,Color("#f0d35b"))
    mission_marker.position = mission_target + Vector3(0,0.12,0)
    add_child(mission_marker)

func get_mission_status(player_position: Vector3) -> String:
    if not mission_active:
        return "PRESS ACT TO START A CIVIC MISSION"
    var distance := player_position.distance_to(mission_target)
    if distance < 3.5:
        mission_active = false
        if is_instance_valid(mission_marker):
            mission_marker.queue_free()
        return "MISSION COMPLETE  +$%d" % mission_reward
    return "%s  •  %dm" % [mission_name, int(distance)]


func _make_driveable_vehicle() -> void:
    var script := load("res://scripts/vehicle.gd")
    var setups := [
        {"pos":Vector3(9.0,0.75,20.0),"rot":PI,"color":Color("#b52f32")},
        {"pos":Vector3(-28.0,0.75,35.0),"rot":0.0,"color":Color("#2b5ea8")},
        {"pos":Vector3(30.0,0.75,24.0),"rot":PI,"color":Color("#d2b24c")}
    ]
    for i in range(setups.size()):
        var car := CharacterBody3D.new()
        car.set_script(script)
        car.position = setups[i]["pos"]
        car.rotation.y = setups[i]["rot"]
        car.name = "DriveableVehicle_%d" % i
        add_child(car)
        car.set_vehicle_color(setups[i]["color"])
        driveable_vehicles.append(car)
    driveable_vehicle = driveable_vehicles[0]

func _nearest_vehicle(player_position: Vector3) -> CharacterBody3D:
    var nearest: CharacterBody3D = null
    var best_distance := 5.0
    for car in driveable_vehicles:
        if is_instance_valid(car) and not car.is_driving():
            var distance := player_position.distance_to(car.global_position)
            if distance < best_distance:
                best_distance = distance
                nearest = car
    return nearest

func get_nearest_driveable_vehicle(player_position: Vector3) -> CharacterBody3D:
    return _nearest_vehicle(player_position)

func toggle_vehicle(player: Node) -> String:
    if player.in_vehicle:
        var current_vehicle: CharacterBody3D = player.vehicle
        player.exit_vehicle()
        if current_vehicle and is_instance_valid(current_vehicle):
            current_vehicle.exit()
        return "ON FOOT"
    var vehicle := _nearest_vehicle(player.global_position)
    if vehicle == null:
        return "WALK CLOSER TO THE CAR"
    player.enter_vehicle(vehicle)
    vehicle.enter()
    return "DRIVING"

func _process(delta: float) -> void:
    _adaptive_quality_tick(delta)
    _collision_lod_tick(delta)
    _apply_shadow_lod(false, delta)
    _apply_vehicle_lod(false, delta)

    var hud_speed := get_node_or_null("HUD/Speed") as Label
    var hud_player := get_node_or_null("Player")
    if hud_speed and hud_player:
        var shown_speed := 0.0
        if hud_player.in_vehicle and hud_player.vehicle and is_instance_valid(hud_player.vehicle):
            shown_speed = hud_player.vehicle.speed_kmh
        else:
            shown_speed = hud_player.velocity.length() * 3.6
        hud_speed.text = "%d km/h" % int(shown_speed)

    time_of_day = fmod(time_of_day + delta * 0.045, 24.0)
    var angle := (time_of_day / 24.0) * TAU
    sun.rotation_degrees.x = -32.0 + sin(angle) * 55.0
    sun.rotation_degrees.y = -35.0 + cos(angle) * 15.0
    sun.light_energy = clamp(0.18 + max(0.0,sin(angle)) * 1.35,0.12,1.5)
    world_env.environment.ambient_light_energy = 0.38 + max(0.0,sin(angle))*0.7

    # NPC/traffic simulation runs at a stable ~30 Hz instead of every render frame.
    # This lowers CPU use on phones without changing the visible world.
    _simulation_accumulator += delta
    if _simulation_accumulator < 0.033:
        return
    var simulation_delta := _simulation_accumulator
    _simulation_accumulator = 0.0
    _reduced_simulation_accumulator += simulation_delta
    var reduced_update := _reduced_simulation_accumulator >= REDUCED_SIMULATION_INTERVAL
    var reduced_delta := _reduced_simulation_accumulator
    if reduced_update:
        _reduced_simulation_accumulator = 0.0

    _refresh_dynamic_sector_cache()

    var t := Time.get_ticks_msec() * 0.001
    # STEP 4 + STEP 5 + STEP 8: sector-aware candidates and shared materials.
    # Nearby actors stay smooth while distant actors cost almost nothing until
    # the player approaches their sector. Rendering also reuses identical
    # materials to reduce GPU state changes without removing world detail.
    for npc_data in _nearby_npcs:
        var n: Node3D = npc_data["node"]
        var npc_distance := _distance_to_player(n)
        if npc_distance > NPC_REDUCED_RADIUS:
            continue

        var medium_npc := npc_distance > NPC_SIMULATION_RADIUS
        if medium_npc and not reduced_update:
            continue

        var phase: float = npc_data["phase"]
        var base: Vector3 = npc_data["base"]
        var radius: float = npc_data["radius"]
        var step_t := t if not medium_npc else t - reduced_delta
        var walk_rate := 0.45 if not medium_npc else 0.38
        n.position = base + Vector3(cos(step_t*walk_rate+phase)*radius,0.05,sin(step_t*walk_rate+phase)*radius)
        n.rotation.y = -atan2(sin(step_t*walk_rate+phase),cos(step_t*walk_rate+phase))
        n.position.y = 0.05 + abs(sin(step_t*3.2+phase))*0.025

    var night := time_of_day < 6.0 or time_of_day > 18.3
    for data in _nearby_traffic:
        var car: Node3D = data["node"]
        var traffic_distance := _distance_to_player(car)
        if traffic_distance > TRAFFIC_REDUCED_RADIUS:
            continue

        var medium_traffic := traffic_distance > TRAFFIC_SIMULATION_RADIUS
        if medium_traffic and not reduced_update:
            continue

        var route: Dictionary = data["route"]
        var step_delta := reduced_delta if medium_traffic else simulation_delta
        var route_span := float(route["to"]) - float(route["from"])
        if abs(route_span) < 0.001:
            continue

        var phase: float = fmod(float(data["phase"]) + float(data["speed"]) * step_delta / route_span, 1.0)
        if phase < 0.0:
            phase += 1.0

        if route["axis"] == "x":
            car.position.x = lerp(float(route["from"]), float(route["to"]), phase)
            car.position.z = float(route["z"])
        else:
            car.position.z = lerp(float(route["from"]), float(route["to"]), phase)
            car.position.x = float(route["x"])

        data["phase"] = phase

        if car.has_meta("headlights"):
            var lights: Array = car.get_meta("headlights")
            for light in lights:
                light.visible = night

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


func _on_hud_run_pressed() -> void:
    var p := get_node_or_null("Player")
    if p:
        # Touch down/up on the mobile control layer owns sprint state.
        var b := get_node_or_null("HUD/Run") as Button
        if b:
            b.text = "STOP"
        var v := get_node_or_null("HUD/Vehicle") as Label
        if v:
            v.text = "PLAYER  •  RUNNING"

func _on_hud_act_pressed() -> void:
    var p := get_node_or_null("Player")
    if p:
        var result := toggle_vehicle(p)
        if result == "WALK CLOSER TO THE CAR":
            start_next_mission()
            result = "MISSION STARTED  •  " + mission_name
        var b := get_node_or_null("HUD/Act") as Button
        if b:
            b.text = "EXIT" if p.in_vehicle else "ACT"
        var v := get_node_or_null("HUD/Vehicle") as Label
        if v:
            v.text = "VEHICLE  •  " + result
        var m := get_node_or_null("HUD/Mission") as Label
        if m:
            m.text = "ACTION  •  " + result

func _on_hud_jump_pressed() -> void:
    var p := get_node_or_null("Player")
    if p and not p.in_vehicle:
        # Mobile jump must respond immediately even when floor contact is delayed.
        p.velocity.y = 8.0
        var m := get_node_or_null("HUD/Mission") as Label
        if m:
            m.text = "ACTION  •  JUMP"
