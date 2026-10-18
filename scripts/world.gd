extends Node3D

# Real World Open World — Realistic Foundation v4 (bug-fix pass).
# Procedural open-world foundation with traffic, city props, weather and day/night.
#
# Main fixes in this file:
#  - removed duplicate member variables (mission_index / mission_active) that stopped the script compiling
#  - removed property writes that do not exist on Node3D (visibility_range_end) which aborted _ready()
#  - every ':=' on a Variant result is now explicitly typed
#  - terrain: smooth city->hills blend, flat road corridors, lake basin, same-resolution
#    two-sided collision, correct winding, fail-safe ground planes moved out of the way
#  - sun elevation no longer starts below the horizon
#  - missions use one system, targets are reachable, ACTION/DRIVE no longer fight
#  - traffic heading / lanes / ground height, headlight LOD is the single authority
#  - NPC limbs are pivoted and registered so they animate
#  - weather particles follow the player and weather changes over time

const WORLD_EXTENT := 220.0
const TERRAIN_CELLS := 78
const CITY_FLAT_RADIUS := 118.0
const CITY_BLEND_RADIUS := 165.0
const ROAD_LEVEL := 0.22
const ROAD_FLAT_HALF_WIDTH := 11.0
const ROAD_BLEND_WIDTH := 16.0
const CAR_Y := 0.19
const LAKE_CENTER := Vector2(82.0, -76.0)
const LAKE_HALF := Vector2(57.5, 39.0)
const LAKE_BED_Y := -1.8
const LAKE_SURFACE_Y := -0.06

# Road layout is data so terrain flattening, road meshes, curbs and traffic agree.
const ROADS: Array = [
    {"axis": "x", "c": 28.0, "from": -195.0, "to": 195.0, "w": 9.0},
    {"axis": "z", "c": -62.0, "from": -155.0, "to": 115.0, "w": 9.0},
    {"axis": "z", "c": 66.0, "from": -30.0, "to": 143.0, "w": 9.0},
    {"axis": "x", "c": -58.0, "from": -128.0, "to": 20.0, "w": 8.0}
]
# Building grid keeps clear of the N-S roads (x=-62 and x=66) and of the civic buildings.
const BUILDING_XS: Array = [-34.0, -8.0, 18.0, 44.0, 94.0]
const BUILDING_ZS: Array = [-24.0, 58.0]

const MISSIONS: Array = [
    {"name": "CLINIC DELIVERY", "target": Vector3(-42.0, 0.0, 5.5), "reward": 250},
    {"name": "CITY DOCUMENTS", "target": Vector3(38.0, 0.0, 5.0), "reward": 300},
    {"name": "FIRE DEPOT SUPPLY", "target": Vector3(-42.0, 0.0, 89.0), "reward": 350},
    {"name": "MARKET COURIER", "target": Vector3(38.0, 0.0, 88.5), "reward": 275},
    {"name": "MARINA DELIVERY", "target": Vector3(78.0, 0.0, -75.0), "reward": 400},
    {"name": "PARK MAINTENANCE", "target": Vector3(10.0, 0.0, -34.0), "reward": 225}
]

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
var _city_buildings: Array = []
var _is_night: bool = false
var _lamp_state: int = -1
var _weather_timer: float = 60.0
var _fps_timer: float = 0.0
var _quality_level: int = 2
var _simulation_accumulator: float = 0.0
var _player_ref: Node3D
const NPC_SIMULATION_RADIUS := 95.0
const NPC_REDUCED_RADIUS := 145.0
const TRAFFIC_SIMULATION_RADIUS := 155.0
const TRAFFIC_REDUCED_RADIUS := 215.0
const TRAFFIC_INTERSECTION_X := 0.0
const TRAFFIC_INTERSECTION_Z := 28.0
var traffic_signal_time: float = 0.0
var traffic_signal_green_x: bool = true
const REDUCED_SIMULATION_INTERVAL := 0.12
var _reduced_simulation_accumulator: float = 0.0

# STEP 5: sector-aware dynamic simulation cache.
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

# STEP 7: adaptive shadow quality.
var _shadow_quality_level: int = 2

# STEP 10: distance-based shadow caster LOD.
const SHADOW_LOD_ENABLE_RADIUS := 55.0
const SHADOW_LOD_DISABLE_RADIUS := 85.0
const SHADOW_LOD_REFRESH_INTERVAL := 0.35
var _shadow_lod_geometries: Array[GeometryInstance3D] = []
var _shadow_lod_timer: float = 0.0

# STEP 12: vehicle render LOD.
const VEHICLE_LOD_LIGHT_ON_RADIUS := 70.0
const VEHICLE_LOD_LIGHT_OFF_RADIUS := 105.0
const VEHICLE_LOD_SHADOW_ON_RADIUS := 65.0
const VEHICLE_LOD_SHADOW_OFF_RADIUS := 95.0
const VEHICLE_LOD_REFRESH_INTERVAL := 0.35
var _vehicle_lod_roots: Array[Node3D] = []
var _vehicle_lod_timer: float = 0.0

# STEP 8: shared opaque material cache.
var _material_cache: Dictionary = {}

# Mission system (single, safe civic mission loop).
var mission_index: int = -1
var mission_active: bool = false
var mission_target: Vector3 = Vector3.ZERO
var mission_name: String = ""
var mission_reward: int = 0
var mission_marker: MeshInstance3D
var _mission_hud_timer: float = 0.0

func _ready() -> void:
    rng.seed = 190428
    _setup_environment()
    _lower_scene_failsafe_ground()
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
    _make_step16_world_detail()
    _setup_weather_particles()
    _step18_visual_setup()
    _player_ref = get_node_or_null("Player") as Node3D
    # Start the character at the generated terrain height before the first frame.
    if _player_ref != null:
        var spawn_pos: Vector3 = _player_ref.global_position
        spawn_pos.y = _height(spawn_pos.x, spawn_pos.z) + 1.0
        _player_ref.global_position = spawn_pos
    _refresh_dynamic_sector_cache(true)
    _configure_world_lod()
    _apply_step9_culling(self)
    _apply_shadow_lod(true)
    _apply_vehicle_lod(true)
    _set_hud_label("Mission", "FREE ROAM  •  PRESS ACTION FOR A MISSION")

func _set_hud_label(node_name: String, text_value: String) -> void:
    var label := get_node_or_null("HUD/" + node_name) as Label
    if label != null:
        label.text = text_value

func _lower_scene_failsafe_ground() -> void:
    # main.tscn ships a big opaque fail-safe plane. At y=-0.45 it hid every
    # valley of the terrain (the player walked underneath it). Keep it as a
    # last-resort backdrop but far below the lowest terrain.
    var failsafe := get_node_or_null("GroundFailsafe") as Node3D
    if failsafe != null:
        failsafe.position.y = -14.0

func _configure_world_lod() -> void:
    _apply_lod_recursive(self)

func _apply_step9_culling(node: Node) -> void:
    for child in node.get_children():
        if child is GeometryInstance3D:
            var geo := child as GeometryInstance3D
            # Keep the immediate play area unculled so mobile builds never open on an empty floor.
            var near_spawn: bool = false
            if _player_ref != null and is_instance_valid(_player_ref):
                near_spawn = geo.global_position.distance_to(_player_ref.global_position) < 95.0
            if near_spawn:
                geo.visibility_range_end = 0.0
            else:
                var distance: float = float(geo.get_meta("lod_distance", geo.visibility_range_end))
                if distance <= 0.0:
                    distance = 260.0
                var n: String = String(geo.name).to_lower()
                if n.contains("road") or n.contains("terrain") or n.contains("mountain"):
                    geo.visibility_range_end = maxf(distance, 320.0)
                elif n.contains("window") or n.contains("awning") or n.contains("balcony") or n.contains("curb"):
                    geo.visibility_range_end = minf(distance, 205.0)
                else:
                    geo.visibility_range_end = minf(distance, 260.0)
        _apply_step9_culling(child)

func _apply_lod_recursive(node: Node) -> void:
    for child in node.get_children():
        if child is GeometryInstance3D:
            var geo := child as GeometryInstance3D
            var distance: float = float(geo.get_meta("lod_distance", 0.0))
            if distance <= 0.0:
                distance = geo.visibility_range_end
            if distance <= 0.0:
                distance = 260.0

            var n: String = String(geo.name).to_lower()
            if n.contains("tree") or n.contains("crown") or n.contains("trunk"):
                distance = minf(distance, 210.0)
            elif n.contains("window") or n.contains("awning") or n.contains("balcony"):
                distance = minf(distance, 205.0)
            elif n.contains("road") or n.contains("terrain"):
                distance = maxf(distance, 300.0)

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

    var player_sector: Vector2i = _dynamic_sector_key(_player_ref.global_position)
    _sector_refresh_timer += get_process_delta_time()

    if not force and player_sector == _dynamic_sector_cache_player and _sector_refresh_timer < SECTOR_REFRESH_INTERVAL:
        return

    _sector_refresh_timer = 0.0
    _dynamic_sector_cache_player = player_sector

    var npc_buckets: Dictionary = {}
    for npc_data in npcs:
        var npc_actor: Node3D = npc_data["node"]
        if not is_instance_valid(npc_actor):
            continue
        var npc_key: Vector2i = _dynamic_sector_key(npc_actor.global_position)
        if not npc_buckets.has(npc_key):
            npc_buckets[npc_key] = []
        npc_buckets[npc_key].append(npc_data)

    var traffic_buckets: Dictionary = {}
    for traffic_data in traffic:
        var traffic_actor: Node3D = traffic_data["node"]
        if not is_instance_valid(traffic_actor):
            continue
        var traffic_key: Vector2i = _dynamic_sector_key(traffic_actor.global_position)
        if not traffic_buckets.has(traffic_key):
            traffic_buckets[traffic_key] = []
        traffic_buckets[traffic_key].append(traffic_data)

    _nearby_npcs.clear()
    _nearby_traffic.clear()

    var npc_radius_sectors: int = ceili(NPC_REDUCED_RADIUS / DYNAMIC_SECTOR_SIZE) + 1
    var traffic_radius_sectors: int = ceili(TRAFFIC_REDUCED_RADIUS / DYNAMIC_SECTOR_SIZE) + 1

    for dz in range(-npc_radius_sectors, npc_radius_sectors + 1):
        for dx in range(-npc_radius_sectors, npc_radius_sectors + 1):
            var near_npc_key: Vector2i = player_sector + Vector2i(dx, dz)
            if npc_buckets.has(near_npc_key):
                _nearby_npcs.append_array(npc_buckets[near_npc_key])

    for dz in range(-traffic_radius_sectors, traffic_radius_sectors + 1):
        for dx in range(-traffic_radius_sectors, traffic_radius_sectors + 1):
            var near_traffic_key: Vector2i = player_sector + Vector2i(dx, dz)
            if traffic_buckets.has(near_traffic_key):
                _nearby_traffic.append_array(traffic_buckets[near_traffic_key])

func _collision_lod_tick(delta: float) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref == null:
        return
    _collision_refresh_timer += delta
    if _collision_refresh_timer < COLLISION_REFRESH_INTERVAL:
        return
    _collision_refresh_timer = 0.0
    var player_pos: Vector3 = _player_ref.global_position
    for body in _collision_lod_bodies:
        if not is_instance_valid(body):
            continue
        var shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
        if shape == null:
            continue
        var distance: float = player_pos.distance_to(body.global_position)
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
    var player_pos: Vector3 = _player_ref.global_position
    for root in _vehicle_lod_roots:
        if not is_instance_valid(root):
            continue
        var distance: float = player_pos.distance_to(root.global_position)
        var shadow_on: bool = distance <= VEHICLE_LOD_SHADOW_ON_RADIUS
        var shadow_off: bool = distance >= VEHICLE_LOD_SHADOW_OFF_RADIUS
        var shadow_state: int = int(root.get_meta("vehicle_shadow_state", -1))
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

        # Headlights: on only at night and only when the car is close.
        # This is the single place that toggles them (the traffic loop no longer does).
        var light_state: int = int(root.get_meta("vehicle_light_state", 0))
        var want_state: int = light_state
        if (not _is_night) or distance >= VEHICLE_LOD_LIGHT_OFF_RADIUS:
            want_state = 0
        elif distance <= VEHICLE_LOD_LIGHT_ON_RADIUS:
            want_state = 1
        if want_state != light_state:
            var lights: Array = root.get_meta("headlights", [])
            for light in lights:
                if is_instance_valid(light):
                    light.visible = want_state == 1
            root.set_meta("vehicle_light_state", want_state)

func _apply_shadow_lod(force: bool = false, delta: float = 0.0) -> void:
    _shadow_lod_timer += delta
    if not force and _shadow_lod_timer < SHADOW_LOD_REFRESH_INTERVAL:
        return
    _shadow_lod_timer = 0.0
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
    if _player_ref == null:
        return
    var player_pos: Vector3 = _player_ref.global_position
    for geo in _shadow_lod_geometries:
        if not is_instance_valid(geo):
            continue
        var distance: float = player_pos.distance_to(geo.global_position)
        if distance <= SHADOW_LOD_ENABLE_RADIUS:
            geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
        elif distance >= SHADOW_LOD_DISABLE_RADIUS:
            geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _adaptive_quality_tick(delta: float) -> void:
    _fps_timer += delta
    if _fps_timer < 1.5:
        return
    _fps_timer = 0.0
    var fps: float = Engine.get_frames_per_second()
    var next_quality: int = 2
    if fps < 28.0:
        next_quality = 0
    elif fps < 40.0:
        next_quality = 1
    if next_quality != _quality_level:
        _quality_level = next_quality
        _apply_mobile_quality()
    if next_quality != _shadow_quality_level:
        _shadow_quality_level = next_quality
        _apply_shadow_quality()

func _apply_shadow_quality() -> void:
    if sun == null:
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
    if sun == null:
        return
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
    world_env = get_node_or_null("WorldEnvironment") as WorldEnvironment
    if world_env == null:
        world_env = WorldEnvironment.new()
        world_env.name = "WorldEnvironment"
        add_child(world_env)

    var env: Environment = world_env.environment
    if env == null:
        env = Environment.new()
        world_env.environment = env

    env.background_mode = Environment.BG_SKY
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_energy = 0.48
    env.ambient_light_sky_contribution = 0.42

    var sky: Sky = env.sky
    if sky == null:
        sky = Sky.new()
        env.sky = sky

    var sky_mat := sky.sky_material as ProceduralSkyMaterial
    if sky_mat == null:
        sky_mat = ProceduralSkyMaterial.new()
        sky.sky_material = sky_mat

    sky_mat.sky_top_color = Color("#173b59")
    sky_mat.sky_horizon_color = Color("#9bb9c2")
    sky_mat.ground_bottom_color = Color("#15221d")
    sky_mat.ground_horizon_color = Color("#35483b")
    sky_mat.sun_angle_max = 12.0
    sky_mat.sun_curve = 0.08

    env.fog_enabled = false
    env.fog_light_color = Color("#829ca4")
    env.fog_light_energy = 0.34
    env.fog_density = 0.0
    env.fog_height = 8.0
    env.fog_height_density = 0.00025
    env.fog_sun_scatter = 0.08
    env.fog_aerial_perspective = 0.28
    env.fog_sky_affect = 0.10
    env.fog_depth_begin = 150.0
    env.fog_depth_end = 360.0

    env.adjustment_enabled = true
    env.adjustment_brightness = 0.92
    env.adjustment_contrast = 1.20
    env.adjustment_saturation = 1.16
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

func _mat(color: Color, rough: float = 0.8, metallic: float = 0.0, emission: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
    # Shared PBR material profiles (cached). Do not mutate the returned material.
    var key: String = "%s|%.3f|%.3f|%s" % [color.to_html(true), rough, metallic, emission.to_html(true)]
    if _material_cache.has(key):
        return _material_cache[key] as StandardMaterial3D

    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = clampf(rough, 0.04, 1.0)
    m.metallic = clampf(metallic, 0.0, 1.0)
    m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
    m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
    m.cull_mode = BaseMaterial3D.CULL_BACK
    if emission.a > 0.0:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 1.35

    _material_cache[key] = m
    return m

func _mat_unique(color: Color, rough: float = 0.8, metallic: float = 0.0, emission: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
    # Use this when a caller will mutate the material after creation.
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = clampf(rough, 0.04, 1.0)
    m.metallic = clampf(metallic, 0.0, 1.0)
    m.metallic_specular = 0.5
    if emission.a > 0.0:
        m.emission_enabled = true
        m.emission = emission
        m.emission_energy_multiplier = 1.5
    return m

func _car_body_mat(color: Color) -> StandardMaterial3D:
    var key: String = "carpaint|%s" % color.to_html(true)
    if _material_cache.has(key):
        return _material_cache[key] as StandardMaterial3D

    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.22
    m.metallic = 0.58
    m.metallic_specular = 0.5
    m.clearcoat_enabled = true
    m.clearcoat = 0.65
    m.clearcoat_roughness = 0.18
    _material_cache[key] = m
    return m

func _box(pos: Vector3, size: Vector3, material: Material, collision: bool = true) -> MeshInstance3D:
    var mesh := MeshInstance3D.new()
    var pm := BoxMesh.new()
    pm.size = size
    mesh.mesh = pm
    mesh.material_override = material
    mesh.position = pos

    var max_dim: float = maxf(size.x, maxf(size.y, size.z))
    var lod_distance: float = 260.0
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
    if collision:
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    else:
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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

# ---------------------------------------------------------------------------
# Terrain height field
# ---------------------------------------------------------------------------

func _road_distance(x: float, z: float) -> float:
    var p := Vector2(x, z)
    var best: float = 100000.0
    for road in ROADS:
        var c: float = road["c"]
        var from_v: float = road["from"]
        var to_v: float = road["to"]
        var a: Vector2 = Vector2(from_v, c) if road["axis"] == "x" else Vector2(c, from_v)
        var b: Vector2 = Vector2(to_v, c) if road["axis"] == "x" else Vector2(c, to_v)
        var ab: Vector2 = b - a
        var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
        best = minf(best, p.distance_to(a + ab * t))
    return best

func _raw_hills(x: float, z: float) -> float:
    var h: float = sin(x * 0.026) * 3.0
    h += cos(z * 0.031) * 2.6
    h += sin((x + z) * 0.017) * 3.8
    h += sin(x * 0.083 + z * 0.024) * 0.7
    return h

func _height(x: float, z: float) -> float:
    var d: float = Vector2(x, z).length()
    # Smooth city -> hills transition (it used to be a ~9 m cliff at radius 58).
    var h: float = _raw_hills(x, z) * smoothstep(CITY_FLAT_RADIUS, CITY_BLEND_RADIUS, d)
    h += maxf(0.0, d - 140.0) * 0.05
    # Roads (and their sidewalks) stay level so cars and people are never buried.
    var road_t: float = 1.0 - smoothstep(ROAD_FLAT_HALF_WIDTH, ROAD_FLAT_HALF_WIDTH + ROAD_BLEND_WIDTH, _road_distance(x, z))
    h = lerpf(h, ROAD_LEVEL, road_t)
    # Lake basin: terrain meets the water line at the lake edge and dips inside.
    var lake_d: float = maxf(absf(x - LAKE_CENTER.x) - LAKE_HALF.x, absf(z - LAKE_CENTER.y) - LAKE_HALF.y)
    if lake_d < 0.0:
        return lerpf(0.0, LAKE_BED_Y, smoothstep(0.0, 10.0, -lake_d))
    return h * smoothstep(0.0, 26.0, lake_d)

func _grid_point(ix: int, iz: int, heights: PackedFloat32Array, cells: int, step: float) -> Vector3:
    return Vector3(-WORLD_EXTENT + float(ix) * step, heights[iz * (cells + 1) + ix], -WORLD_EXTENT + float(iz) * step)

func _make_terrain() -> void:
    var cells: int = TERRAIN_CELLS
    var step: float = (WORLD_EXTENT * 2.0) / float(cells)
    var heights := PackedFloat32Array()
    heights.resize((cells + 1) * (cells + 1))
    for iz in range(cells + 1):
        for ix in range(cells + 1):
            heights[iz * (cells + 1) + ix] = _height(-WORLD_EXTENT + float(ix) * step, -WORLD_EXTENT + float(iz) * step)

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var faces := PackedVector3Array()
    for iz in range(cells):
        for ix in range(cells):
            var a: Vector3 = _grid_point(ix, iz, heights, cells, step)
            var b: Vector3 = _grid_point(ix + 1, iz, heights, cells, step)
            var c: Vector3 = _grid_point(ix + 1, iz + 1, heights, cells, step)
            var d: Vector3 = _grid_point(ix, iz + 1, heights, cells, step)
            var ca: Color = _ground_color(a)
            var cb: Color = _ground_color(b)
            var cc: Color = _ground_color(c)
            var cd: Color = _ground_color(d)
            # Godot front faces are clockwise when seen from the front. Seen from
            # above (+Y) a->b->c / a->c->d is clockwise, i.e. facing UP.
            st.set_color(ca); st.add_vertex(a)
            st.set_color(cb); st.add_vertex(b)
            st.set_color(cc); st.add_vertex(c)
            st.set_color(ca); st.add_vertex(a)
            st.set_color(cc); st.add_vertex(c)
            st.set_color(cd); st.add_vertex(d)
            faces.append(a); faces.append(b); faces.append(c)
            faces.append(a); faces.append(c); faces.append(d)
    st.generate_normals()
    var terrain := MeshInstance3D.new()
    terrain.name = "WorldTerrain"
    terrain.mesh = st.commit()
    terrain.visibility_range_end = 520.0
    terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var mat := StandardMaterial3D.new()
    mat.vertex_color_use_as_albedo = true
    mat.roughness = 0.92
    mat.metallic = 0.0
    mat.metallic_specular = 0.35
    # Keep visible from both sides so a winding mistake can never blank the world.
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    terrain.material_override = mat
    add_child(terrain)

    # Collision uses the SAME grid as the visible terrain (it used to be 3x coarser,
    # so the visible ground and the physics ground disagreed) and is two-sided,
    # which fixes the player falling through the terrain.
    var body := StaticBody3D.new()
    body.name = "TerrainBody"
    var collision := CollisionShape3D.new()
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(faces)
    shape.backface_collision = true
    collision.shape = shape
    body.add_child(collision)
    add_child(body)

func _ground_color(p: Vector3) -> Color:
    var variation: float = sin(p.x * 0.11) * 0.025 + cos(p.z * 0.09) * 0.02
    if p.y < -0.25:
        return Color(0.50 + variation, 0.46 + variation, 0.33 + variation)
    if p.y > 6.0:
        return Color(0.25 + variation, 0.30 + variation, 0.22 + variation)
    return Color(0.18 + variation, 0.34 + variation, 0.18 + variation)

func _make_lake() -> void:
    var lake := MeshInstance3D.new()
    lake.name = "LakeWater"
    var pm := PlaneMesh.new()
    pm.size = Vector2(LAKE_HALF.x * 2.0, LAKE_HALF.y * 2.0)
    lake.mesh = pm
    lake.position = Vector3(LAKE_CENTER.x, LAKE_SURFACE_Y, LAKE_CENTER.y)
    var wm := _mat_unique(Color("#176d82"), 0.08, 0.65)
    wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    wm.albedo_color.a = 0.86
    lake.material_override = wm
    add_child(lake)

    for i in range(7):
        var ripple := MeshInstance3D.new()
        var ring := TorusMesh.new()
        ring.inner_radius = 1.8 + float(i) * 1.1
        ring.outer_radius = ring.inner_radius + 0.035
        ring.rings = 8
        ring.ring_segments = 24
        ripple.mesh = ring
        ripple.position = Vector3(45.0 + float(i) * 7.0, LAKE_SURFACE_Y + 0.03, -58.0 + sin(float(i)) * 9.0)
        ripple.material_override = _mat(Color("#75b8c4"), 0.15, 0.35)
        add_child(ripple)

func _make_mountains() -> void:
    var positions: Array = [
        Vector3(-175, 16, -155), Vector3(-110, 20, -178),
        Vector3(-35, 14, -188), Vector3(55, 19, -180),
        Vector3(150, 15, -160), Vector3(180, 13, 70),
        Vector3(-180, 12, 90)
    ]
    for p in positions:
        var hill := MeshInstance3D.new()
        hill.name = "Mountain"
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

func _make_forests() -> void:
    # Batch the forest into regional MultiMeshes (a few draw calls instead of hundreds of nodes).
    var regions: Array = [
        Rect2(Vector2(-205, -205), Vector2(135, 410)),
        Rect2(Vector2(-70, -205), Vector2(140, 410)),
        Rect2(Vector2(70, -205), Vector2(135, 410))
    ]
    for region_index in range(regions.size()):
        _make_forest_multimesh(regions[region_index], region_index)

func _make_forest_multimesh(region: Rect2, region_index: int) -> void:
    var transforms: Array[Transform3D] = []
    var attempts: int = 0
    while transforms.size() < 50 and attempts < 700:
        attempts += 1
        var x: float = rng.randf_range(region.position.x, region.end.x)
        var z: float = rng.randf_range(region.position.y, region.end.y)
        # Keep trees out of the city, off the roads and out of the lake.
        if Vector2(x, z).length() < CITY_FLAT_RADIUS - 4.0:
            continue
        if x > 14.0 and x < 146.0 and z < -24.0 and z > -118.0:
            continue
        if _road_distance(x, z) < 14.0:
            continue
        var s: float = rng.randf_range(0.75, 1.55)
        var tree_basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * s)
        transforms.append(Transform3D(tree_basis, Vector3(x, _height(x, z), z)))
    if transforms.is_empty():
        return

    var batch := MultiMeshInstance3D.new()
    batch.name = "ForestMultiMesh_%d" % region_index
    batch.visibility_range_end = 210.0

    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.instance_count = transforms.size()

    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _append_tree_geometry(st)
    st.generate_normals()
    # The vertices carry colours; without a material using them the trees were white.
    var tree_mat := StandardMaterial3D.new()
    tree_mat.vertex_color_use_as_albedo = true
    tree_mat.roughness = 0.92
    tree_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    st.set_material(tree_mat)
    mm.mesh = st.commit()

    for i in range(transforms.size()):
        mm.set_instance_transform(i, transforms[i])

    batch.multimesh = mm
    add_child(batch)

func _append_tree_geometry(st: SurfaceTool) -> void:
    # The trunk is centred at 1.55 so it spans 0..3.1 (it used to be centred at 0
    # and half buried, leaving the crowns floating above it).
    _append_cone(st, 0.28, 0.13, 3.1, 8, 1.55, Color("#493326"))
    _append_cone(st, 1.35, 0.02, 2.8, 8, 3.6, Color("#235437"))
    _append_cone(st, 1.10, 0.02, 2.6, 8, 4.8, Color("#235437"))
    _append_cone(st, 0.85, 0.02, 2.4, 8, 5.9, Color("#2e6641"))

func _append_cone(st: SurfaceTool, bottom_radius: float, top_radius: float, height: float, segments: int, center_y: float, color: Color) -> void:
    var half: float = height * 0.5
    for i in range(segments):
        var a0: float = TAU * float(i) / float(segments)
        var a1: float = TAU * float(i + 1) / float(segments)
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

# ---------------------------------------------------------------------------
# Roads and buildings
# ---------------------------------------------------------------------------

func _make_road(pos: Vector3, size: Vector3) -> void:
    var asphalt := _mat(Color("#1e2225"), 0.86)
    var walk := _mat(Color("#8c8d88"), 0.84)
    var paint := _mat(Color("#e6d28d"), 0.65)
    _box(pos + Vector3(0.0, 0.12, 0.0), size, asphalt, false)
    if size.x > size.z:
        var side := Vector3(size.x, 0.16, 1.8)
        _box(pos + Vector3(0.0, 0.21, size.z * 0.65), side, walk, false)
        _box(pos + Vector3(0.0, 0.21, -size.z * 0.65), side, walk, false)
        var x_start: int = -int(size.x / 2.0) + 8
        var x_end: int = int(size.x / 2.0) - 5
        for x in range(x_start, x_end, 14):
            _box(pos + Vector3(float(x), 0.26, 0.0), Vector3(7.0, 0.035, 0.13), paint, false)
    else:
        var side_v := Vector3(1.8, 0.16, size.z)
        _box(pos + Vector3(size.x * 0.65, 0.21, 0.0), side_v, walk, false)
        _box(pos + Vector3(-size.x * 0.65, 0.21, 0.0), side_v, walk, false)
        var z_start: int = -int(size.z / 2.0) + 8
        var z_end: int = int(size.z / 2.0) - 5
        for z in range(z_start, z_end, 14):
            _box(pos + Vector3(0.0, 0.26, float(z)), Vector3(0.13, 0.035, 7.0), paint, false)

func _make_building(pos: Vector3, size: Vector3, color: Color, floors: int = 2) -> void:
    _box(pos + Vector3(0.0, size.y / 2.0, 0.0), size, _mat(color, 0.78), true)
    _box(pos + Vector3(0.0, size.y + 0.22, 0.0), Vector3(size.x * 1.03, 0.44, size.z * 1.03), _mat(Color("#25282b"), 0.78, 0.05), false)

    var glass := _mat(Color("#254a60"), 0.16, 0.32, Color("#0b2530"))
    var frame := _mat(Color("#2b2d2f"), 0.65)
    var window_rows: int = maxi(1, floors)
    for row in range(window_rows):
        var y: float = 2.0 + float(row) * (size.y / float(window_rows))
        var x_start: int = -int(size.x / 2.0) + 2
        var x_end: int = int(size.x / 2.0) - 1
        for x in range(x_start, x_end, 3):
            _box(pos + Vector3(float(x), y, size.z / 2.0 + 0.025), Vector3(1.45, 1.25, 0.07), glass, false)
            _box(pos + Vector3(float(x), y, size.z / 2.0 + 0.065), Vector3(1.58, 0.08, 0.06), frame, false)

    _box(pos + Vector3(0.0, 1.15, size.z / 2.0 + 0.045), Vector3(1.25, 2.3, 0.09), _mat(Color("#302b26"), 0.45), false)

func _make_streetlight(pos: Vector3) -> void:
    _box(pos + Vector3(0.0, 2.7, 0.0), Vector3(0.13, 5.4, 0.13), _mat(Color("#202326"), 0.55, 0.1), false)
    _box(pos + Vector3(0.72, 5.18, 0.0), Vector3(1.45, 0.12, 0.12), _mat(Color("#202326"), 0.55, 0.1), false)
    var lamp := OmniLight3D.new()
    lamp.position = pos + Vector3(1.3, 5.0, 0.0)
    lamp.omni_range = 11.0
    lamp.light_energy = 1.25
    lamp.light_color = Color("#ffe0a1")
    lamp.visible = false
    add_child(lamp)
    street_lamps.append(lamp)

func _make_city_and_roads() -> void:
    for road in ROADS:
        var c: float = road["c"]
        var from_v: float = road["from"]
        var to_v: float = road["to"]
        var road_w: float = road["w"]
        var mid: float = (from_v + to_v) * 0.5
        var length: float = to_v - from_v
        if road["axis"] == "x":
            _make_road(Vector3(mid, 0.0, c), Vector3(length, 0.24, road_w))
        else:
            _make_road(Vector3(c, 0.0, mid), Vector3(road_w, 0.24, length))

    var colors: Array = [Color("#777a78"), Color("#9a9085"), Color("#646b70"), Color("#8a6f5c"), Color("#a4a09a"), Color("#6e7775")]
    for bx in BUILDING_XS:
        for bz in BUILDING_ZS:
            var bh: float = rng.randf_range(8.0, 18.0)
            var bw: float = rng.randf_range(13.0, 21.0)
            var bd: float = rng.randf_range(11.0, 18.0)
            var color: Color = colors[rng.randi_range(0, colors.size() - 1)]
            var b_pos := Vector3(float(bx), 0.0, float(bz))
            var b_size := Vector3(bw, bh, bd)
            var b_floors: int = maxi(1, int(bh / 4.0))
            _make_building(b_pos, b_size, color, b_floors)
            _city_buildings.append({"pos": b_pos, "size": b_size, "floors": b_floors})
    for lx in range(-174, 175, 24):
        _make_streetlight(Vector3(float(lx), 0.0, 33.0))

# ---------------------------------------------------------------------------
# Cars, traffic, people
# ---------------------------------------------------------------------------

func _make_car(pos: Vector3, body_color: Color, rotation_y: float = 0.0) -> Node3D:
    var root := Node3D.new()
    root.position = pos
    root.rotation.y = rotation_y
    add_child(root)

    var body_mat: StandardMaterial3D = _car_body_mat(body_color)
    var glass := _mat(Color("#162b37"), 0.10, 0.30)
    var tire := _mat(Color("#111214"), 0.96)
    var chrome := _mat(Color("#b9bdbe"), 0.16, 0.86)
    var lamp := _mat(Color("#f6e9bd"), 0.16, 0.25, Color("#fff0b0"))

    _local_box(root, Vector3(0.0, 0.62, 0.0), Vector3(4.3, 0.7, 2.0), body_mat)
    _local_box(root, Vector3(0.0, 1.12, 0.0), Vector3(2.35, 0.65, 1.75), body_mat)
    _local_box(root, Vector3(0.0, 1.14, 0.0), Vector3(2.1, 0.46, 1.58), glass, false)

    # This car is built with its length along X (front = +X), so the axle runs along Z.
    for sx in [-1.0, 1.0]:
        for sz in [-0.72, 0.72]:
            var wheel := MeshInstance3D.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 0.43
            cyl.bottom_radius = 0.43
            cyl.height = 0.24
            cyl.radial_segments = 16
            wheel.mesh = cyl
            wheel.position = Vector3(float(sx) * 1.38, 0.48, float(sz))
            wheel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
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
            hub.rotation_degrees = Vector3(90.0, 0.0, 0.0)
            hub.material_override = chrome
            root.add_child(hub)

    _local_box(root, Vector3(1.93, 0.72, 0.0), Vector3(0.12, 0.24, 0.62), lamp, false)
    _local_box(root, Vector3(-1.93, 0.72, 0.0), Vector3(0.12, 0.24, 0.62), _mat(Color("#8d1d1d"), 0.2, 0.15, Color("#5d0808")), false)

    var head_l := OmniLight3D.new()
    head_l.position = Vector3(2.05, 0.78, -0.55)
    head_l.omni_range = 13.0
    head_l.light_energy = 2.0
    head_l.light_color = Color("#fff1c9")
    head_l.visible = false
    root.add_child(head_l)
    var head_r := OmniLight3D.new()
    head_r.position = Vector3(2.05, 0.78, 0.55)
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
    # Two lanes per road (left-hand traffic). Lanes sit 2.4 m from the road centre
    # and every route stays inside the road it drives on.
    var routes: Array = [
        {"axis": "x", "z": 25.6, "from": -175.0, "to": 175.0, "speed": 7.0, "dir": 1},
        {"axis": "x", "z": 30.4, "from": 175.0, "to": -175.0, "speed": 6.5, "dir": -1},
        {"axis": "x", "z": -60.0, "from": -110.0, "to": 10.0, "speed": 5.8, "dir": 1},
        {"axis": "x", "z": -56.0, "from": 10.0, "to": -110.0, "speed": 5.4, "dir": -1},
        {"axis": "z", "x": -59.6, "from": -110.0, "to": 105.0, "speed": 6.4, "dir": 1},
        {"axis": "z", "x": -64.4, "from": 105.0, "to": -110.0, "speed": 6.0, "dir": -1},
        {"axis": "z", "x": 68.4, "from": -25.0, "to": 135.0, "speed": 6.0, "dir": 1},
        {"axis": "z", "x": 63.6, "from": 135.0, "to": -25.0, "speed": 5.6, "dir": -1}
    ]
    var colors: Array = [Color("#d7d2c8"), Color("#294e78"), Color("#a52f2f"), Color("#30343a"), Color("#6c5737"), Color("#6b7d80")]
    for i in range(16):
        var r: Dictionary = routes[i % routes.size()]
        var t: float = fmod(float(i) * 0.071, 1.0)
        var car: Node3D
        var heading: float = 0.0
        var body_color: Color = colors[i % colors.size()]
        # Car front is +X. Moving +X -> heading 0, -X -> PI, +Z -> -PI/2, -Z -> +PI/2.
        if r["axis"] == "x":
            var x_pos: float = lerpf(float(r["from"]), float(r["to"]), t)
            heading = 0.0 if int(r["dir"]) > 0 else PI
            car = _make_car(Vector3(x_pos, CAR_Y, float(r["z"])), body_color, heading)
        else:
            var z_pos: float = lerpf(float(r["from"]), float(r["to"]), t)
            heading = -PI / 2.0 if int(r["dir"]) > 0 else PI / 2.0
            car = _make_car(Vector3(float(r["x"]), CAR_Y, z_pos), body_color, heading)
        traffic.append({"node": car, "route": r, "phase": t, "speed": float(r["speed"]) * rng.randf_range(0.86, 1.12)})

func _make_cars() -> void:
    # Parked cars sit in the median strip between the two lanes.
    _make_car(Vector3(-32.0, CAR_Y, 28.0), Color("#b92c2c"), 0.0)
    _make_car(Vector3(42.0, CAR_Y, 28.0), Color("#2b5ea8"), 0.0)
    _make_car(Vector3(-62.0, CAR_Y, 62.0), Color("#d3d0c8"), PI / 2.0)
    _make_car(Vector3(66.0, CAR_Y, 40.0), Color("#202a32"), PI / 2.0)
    _make_car(Vector3(-50.0, CAR_Y, -58.0), Color("#8a6d38"), 0.0)

func _person_part(parent: Node3D, pos: Vector3, scale_v: Vector3, mat: Material, sphere: bool = false) -> void:
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
    parent.add_child(mi)

func _person_arm(root: Node3D, pivot_pos: Vector3, mat: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.position = pivot_pos
    root.add_child(pivot)
    _person_part(pivot, Vector3(0.0, -0.36, 0.0), Vector3(0.14, 0.72, 0.14), mat)
    return pivot

func _person_leg(root: Node3D, pivot_pos: Vector3, pants_mat: Material, shoe_mat: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.position = pivot_pos
    root.add_child(pivot)
    _person_part(pivot, Vector3(0.0, -0.36, 0.0), Vector3(0.16, 0.72, 0.16), pants_mat)
    _person_part(pivot, Vector3(0.0, -0.72, -0.02), Vector3(0.22, 0.12, 0.4), shoe_mat)
    return pivot

func _make_person(pos: Vector3, shirt_color: Color, scale_v: float = 1.0) -> Node3D:
    var root := Node3D.new()
    root.set_script(load("res://scripts/npc.gd"))
    root.position = pos
    root.scale = Vector3.ONE * scale_v

    var skin := _mat(Color("#b87958"), 0.68)
    var shirt := _mat(shirt_color, 0.78)
    var pants := _mat(Color("#22262a"), 0.86)
    var shoes := _mat(Color("#141517"), 0.92)

    _person_part(root, Vector3(0.0, 1.02, 0.0), Vector3(0.52, 0.88, 0.34), shirt)
    _person_part(root, Vector3(0.0, 1.68, 0.0), Vector3(0.34, 0.34, 0.34), skin, true)
    var left_arm_node: Node3D = _person_arm(root, Vector3(-0.38, 1.38, 0.0), skin)
    var right_arm_node: Node3D = _person_arm(root, Vector3(0.38, 1.38, 0.0), skin)
    var left_leg_node: Node3D = _person_leg(root, Vector3(-0.18, 0.72, 0.0), pants, shoes)
    var right_leg_node: Node3D = _person_leg(root, Vector3(0.18, 0.72, 0.0), pants, shoes)

    # Add to the tree only after the body exists, then hand the limb pivots to the
    # NPC script (it used to look for limbs in _ready(), before any existed).
    add_child(root)
    root.set("left_arm", left_arm_node)
    root.set("right_arm", right_arm_node)
    root.set("left_leg", left_leg_node)
    root.set("right_leg", right_leg_node)
    return root

func _make_pedestrians() -> void:
    var shirt_colors: Array = [
        Color("#345f8a"), Color("#8a3f3f"), Color("#557b4a"),
        Color("#8c6b3e"), Color("#5d4f86"), Color("#496b70"),
        Color("#6f4f3d"), Color("#6b6f43")
    ]
    # Start points are outside building footprints and out of the lake.
    var starts: Array = [
        Vector2(-55.0, 19.0), Vector2(-33.0, 37.0), Vector2(-11.0, 18.0),
        Vector2(12.0, 39.0), Vector2(34.0, 18.0), Vector2(56.0, 36.0),
        Vector2(-76.0, 60.0), Vector2(-26.0, 72.0), Vector2(6.0, 74.0),
        Vector2(24.0, 72.0), Vector2(52.0, 78.0), Vector2(-76.0, -8.0),
        Vector2(-24.0, -31.0), Vector2(14.0, -35.0), Vector2(30.0, -20.0),
        Vector2(80.0, -8.0), Vector2(10.0, -52.0), Vector2(-12.0, -45.0)
    ]
    for i in range(starts.size()):
        var sp: Vector2 = starts[i]
        var start := Vector3(sp.x, _height(sp.x, sp.y) + 0.04, sp.y)
        var person: Node3D = _make_person(start, shirt_colors[i % shirt_colors.size()], rng.randf_range(0.92, 1.06))
        npcs.append({"node": person, "base": start, "phase": rng.randf_range(0.0, TAU), "radius": rng.randf_range(3.0, 7.0)})

# ---------------------------------------------------------------------------
# Props / landmarks / details
# ---------------------------------------------------------------------------

func _make_landmarks() -> void:
    _make_building(Vector3(-18.0, 0.0, 12.0), Vector3(13.0, 5.5, 10.0), Color("#8b6248"), 1)
    _box(Vector3(22.0, 5.0, -5.0), Vector3(10.0, 0.5, 10.0), _mat(Color("#765033"), 0.92), false)
    for px in [-3.8, 3.8]:
        for pz in [-3.8, 3.8]:
            _box(Vector3(22.0 + float(px), 2.5, -5.0 + float(pz)), Vector3(0.3, 5.0, 0.3), _mat(Color("#5b3d29"), 0.96), false)

func _make_city_props() -> void:
    # Crosswalks
    for x in range(-155, 156, 18):
        for i in range(6):
            _box(Vector3(float(x) + float(i) * 1.5 - 3.75, 0.29, 23.0), Vector3(0.95, 0.035, 3.2), _mat(Color("#e7e4d7"), 0.72), false)
    # Traffic lights at the main intersection
    for p in [Vector3(-6, 0, 28), Vector3(6, 0, 28), Vector3(0, 0, 21), Vector3(0, 0, 35)]:
        _box(p + Vector3(0.0, 2.3, 0.0), Vector3(0.18, 4.6, 0.18), _mat(Color("#202326"), 0.58, 0.08), false)
        _box(p + Vector3(0.0, 4.35, 0.0), Vector3(0.52, 0.95, 0.38), _mat(Color("#17191a"), 0.55), false)
    # Rooftop AC units sit on the real roof of every generated building.
    for b in _city_buildings:
        var bp: Vector3 = b["pos"]
        var bs: Vector3 = b["size"]
        var roof_y: float = bs.y + 0.44
        var ac_pos := Vector3(bp.x - bs.x * 0.12, roof_y + 0.55, bp.z + bs.z * 0.08)
        _box(ac_pos, Vector3(1.5, 1.1, 1.1), _mat(Color("#c4c4bd"), 0.72, 0.08), false)
        _box(ac_pos + Vector3(0.0, 0.6, 0.0), Vector3(0.95, 0.08, 0.7), _mat(Color("#686d6d"), 0.85), false)
    # Park benches (kept clear of the lake shore)
    for bench_x in [-18.0, -5.0, 12.0]:
        _box(Vector3(bench_x, 0.65, -36.0), Vector3(3.0, 0.18, 0.55), _mat(Color("#6b4930"), 0.82), false)
        for leg_x in [-1.0, 1.0]:
            _box(Vector3(bench_x + float(leg_x), 0.28, -36.0), Vector3(0.14, 0.75, 0.14), _mat(Color("#303234"), 0.62, 0.15), false)

func _make_realistic_facades() -> void:
    # Awnings and balconies are placed on the real front (+Z) face of each generated building.
    var balcony := _mat(Color("#c3b9aa"), 0.74, 0.04)
    var railing := _mat(Color("#34383b"), 0.52, 0.15)
    var awning := _mat(Color("#48545b"), 0.62, 0.08)
    for b in _city_buildings:
        var bp: Vector3 = b["pos"]
        var bs: Vector3 = b["size"]
        var b_floors: int = int(b["floors"])
        var front_z: float = bp.z + bs.z * 0.5
        _box(Vector3(bp.x, 3.1, front_z + 0.8), Vector3(3.8, 0.12, 1.6), awning, false)
        for row in range(1, b_floors):
            var window_y: float = 2.0 + float(row) * (bs.y / float(b_floors))
            for side in [-1.0, 1.0]:
                var bx: float = bp.x + float(side) * bs.x * 0.28
                _box(Vector3(bx, window_y - 0.8, front_z + 0.55), Vector3(2.6, 0.16, 1.1), balcony, false)
                _box(Vector3(bx, window_y - 0.3, front_z + 1.05), Vector3(2.6, 0.08, 0.06), railing, false)

func _make_road_details() -> void:
    var curb := _mat(Color("#b0aea6"), 0.82)
    var dark := _mat(Color("#34373a"), 0.90)
    for road in ROADS:
        var c: float = road["c"]
        var from_v: float = road["from"]
        var to_v: float = road["to"]
        var offset: float = float(road["w"]) * 0.5 + 0.4
        var mid: float = (from_v + to_v) * 0.5
        var length: float = to_v - from_v
        if road["axis"] == "x":
            _box(Vector3(mid, 0.28, c + offset), Vector3(length, 0.28, 0.22), curb, false)
            _box(Vector3(mid, 0.28, c - offset), Vector3(length, 0.28, 0.22), curb, false)
        else:
            _box(Vector3(c + offset, 0.28, mid), Vector3(0.22, 0.28, length), curb, false)
            _box(Vector3(c - offset, 0.28, mid), Vector3(0.22, 0.28, length), curb, false)
    # Small asphalt repair patches give the main road some variation.
    for i in range(18):
        var px: float = rng.randf_range(-170.0, 170.0)
        var pz: float = 28.0 + rng.randf_range(-3.4, 3.4)
        _box(Vector3(px, 0.255, pz), Vector3(rng.randf_range(1.0, 3.5), 0.025, rng.randf_range(0.35, 0.8)), dark, false)

func _make_step16_world_detail() -> void:
    var sidewalk := _mat(Color("#8f908b"), 0.86)
    var road_mark := _mat(Color("#e2ddc8"), 0.62)
    var metal := _mat(Color("#3e4549"), 0.58, 0.16)
    for x in range(-180, 181, 12):
        _box(Vector3(float(x), 0.34, 33.6), Vector3(10.8, 0.16, 2.8), sidewalk, false)
        _box(Vector3(float(x), 0.34, 22.4), Vector3(10.8, 0.16, 2.8), sidewalk, false)
    for x in range(-170, 171, 14):
        _box(Vector3(float(x), 0.285, 28.0), Vector3(7.0, 0.035, 0.12), road_mark, false)
    # Rooftop vents / stair boxes on the real roofs.
    for b in _city_buildings:
        var bp: Vector3 = b["pos"]
        var bs: Vector3 = b["size"]
        var roof_y: float = bs.y + 0.44
        _box(bp + Vector3(bs.x * 0.22, roof_y + 0.65, -bs.z * 0.22), Vector3(2.8, 1.3, 2.2), sidewalk, false)
        _box(bp + Vector3(-bs.x * 0.25, roof_y + 1.0, bs.z * 0.18), Vector3(1.1, 2.0, 1.1), metal, false)
    # Street lamp posts with emissive heads. The heads are plain decoration and
    # stay visible all day (they used to vanish at daytime because they were
    # registered as night lights).
    for x in range(-150, 151, 30):
        _box(Vector3(float(x), 3.0, 20.0), Vector3(0.16, 6.0, 0.16), metal, false)
        _box(Vector3(float(x) + 0.9, 5.9, 20.0), Vector3(0.9, 0.18, 0.32), _mat(Color("#d9d0a2"), 0.25, 0.05, Color("#ffd98a")), false)

func _setup_weather_particles() -> void:
    rain_particles = _weather_particles(false)
    snow_particles = _weather_particles(true)

func _weather_particles(snow: bool) -> GPUParticles3D:
    var particles := GPUParticles3D.new()
    particles.name = "SnowParticles" if snow else "RainParticles"
    particles.amount = 120 if snow else 220
    particles.lifetime = 2.0 if snow else 0.65
    particles.visibility_aabb = AABB(Vector3(-55.0, -35.0, -55.0), Vector3(110.0, 70.0, 110.0))
    var pmat := ParticleProcessMaterial.new()
    pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    pmat.emission_box_extents = Vector3(48.0, 15.0, 48.0)
    pmat.direction = Vector3(0.0, -1.0, 0.0)
    pmat.initial_velocity_min = 2.0 if snow else 26.0
    pmat.initial_velocity_max = 4.5 if snow else 34.0
    pmat.gravity = Vector3(0.0, -1.2, 0.0) if snow else Vector3(0.0, -3.0, 0.0)
    pmat.scale_min = 0.035 if snow else 0.015
    pmat.scale_max = 0.07 if snow else 0.025
    particles.process_material = pmat

    var quad := QuadMesh.new()
    quad.size = Vector2(0.10, 0.10) if snow else Vector2(0.08, 0.35)
    var qmat := _mat_unique(Color("#d8eef4") if snow else Color("#a8cfe0"), 0.18, 0.05)
    qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    qmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
    qmat.cull_mode = BaseMaterial3D.CULL_DISABLED
    quad.material = qmat
    particles.draw_pass_1 = quad
    particles.visible = false
    add_child(particles)
    return particles

func _make_sign(pos: Vector3, text_value: String, color: Color) -> void:
    _box(pos + Vector3(0.0, 1.2, 0.0), Vector3(0.10, 2.4, 0.10), _mat(Color("#2a2d2f"), 0.7), false)
    var board: MeshInstance3D = _box(pos + Vector3(0.0, 2.45, 0.0), Vector3(2.8, 0.85, 0.10), _mat(color, 0.68), false)
    board.set_meta("label", text_value)
    # The sign used to be a blank board; give it its text.
    var label := Label3D.new()
    label.text = text_value
    label.font_size = 36
    label.pixel_size = 0.01
    label.outline_size = 6
    label.modulate = Color("#f4f1e6")
    label.position = Vector3(0.0, 0.0, 0.07)
    board.add_child(label)

func _make_service_buildings() -> void:
    var civic: Array = [
        {"p": Vector3(-42, 0, -6), "s": Vector3(22, 9, 16), "c": Color("#d8d6d0"), "sign": "HOSPITAL"},
        {"p": Vector3(38, 0, -6), "s": Vector3(20, 8, 15), "c": Color("#596b78"), "sign": "POLICE"},
        {"p": Vector3(-42, 0, 78), "s": Vector3(20, 7, 15), "c": Color("#a34b3e"), "sign": "FIRE STATION"},
        {"p": Vector3(38, 0, 78), "s": Vector3(18, 10, 14), "c": Color("#75624b"), "sign": "BANK"}
    ]
    for d in civic:
        var cp: Vector3 = d["p"]
        var cs: Vector3 = d["s"]
        var cc: Color = d["c"]
        var ctext: String = d["sign"]
        _make_building(cp, cs, cc, maxi(1, int(cs.y / 4.0)))
        _make_sign(cp + Vector3(0.0, cs.y + 0.05, cs.z / 2.0 + 0.5), ctext, Color("#1d3542"))

    # Hospital entrance canopy and emergency bays.
    for x in [-47.0, -42.0, -37.0]:
        _box(Vector3(x, 0.35, 3.0), Vector3(3.8, 0.25, 6.0), _mat(Color("#d8d6d0"), 0.65), false)
    _box(Vector3(-42.0, 3.2, 2.7), Vector3(16.0, 0.35, 6.0), _mat(Color("#f2f0ea"), 0.55), false)

    # Fire-station garage doors.
    for x in [-47.0, -42.0, -37.0]:
        _box(Vector3(x, 2.0, 85.55), Vector3(3.8, 3.2, 0.12), _mat(Color("#262b2e"), 0.35, 0.2), false)

func _make_boat(pos: Vector3, scale_v: float = 1.0, rotation_y: float = 0.0) -> void:
    var boat := Node3D.new()
    boat.position = pos
    boat.rotation.y = rotation_y
    boat.scale = Vector3.ONE * scale_v
    add_child(boat)
    var hull := _mat(Color("#e8e2d6"), 0.28, 0.25)
    var dark := _mat(Color("#27313a"), 0.38, 0.3)
    var glass := _mat(Color("#31566a"), 0.10, 0.42)
    _local_box(boat, Vector3(0.0, 0.0, 0.0), Vector3(5.8, 0.55, 1.7), hull, false)
    _local_box(boat, Vector3(0.0, 0.45, 0.0), Vector3(2.5, 0.65, 1.35), dark, false)
    _local_box(boat, Vector3(0.0, 0.8, 0.0), Vector3(1.55, 0.42, 1.15), glass, false)
    _local_box(boat, Vector3(-1.75, 0.62, 0.0), Vector3(0.10, 1.5, 0.10), dark, false)

func _make_waterfront() -> void:
    # Marina pier now starts on the shore (x=24) instead of floating mid-lake.
    _box(Vector3(63.0, 0.65, -75.0), Vector3(78.0, 0.35, 4.2), _mat(Color("#6c5239"), 0.88), false)
    for x in range(28, 101, 6):
        _box(Vector3(float(x), 0.75, -72.9), Vector3(0.35, 1.2, 0.35), _mat(Color("#3b2c23"), 0.9), false)
    _make_boat(Vector3(62.0, 0.12, -81.0), 0.85, -0.35)
    _make_boat(Vector3(82.0, 0.12, -84.0), 1.0, 0.25)
    _make_boat(Vector3(102.0, 0.12, -78.0), 0.72, -0.15)
    for bollard_x in [58.0, 70.0, 86.0, 98.0]:
        _box(Vector3(float(bollard_x), 1.0, -73.4), Vector3(0.55, 0.25, 0.55), _mat(Color("#b7a27d"), 0.92), false)

func _make_job_locations() -> void:
    var jobs: Array = [
        {"name": "CITY HOSPITAL", "pos": Vector3(-42, 0, -6)},
        {"name": "POLICE HQ", "pos": Vector3(38, 0, -6)},
        {"name": "FIRE STATION", "pos": Vector3(-42, 0, 78)},
        {"name": "BANK", "pos": Vector3(38, 0, 78)},
        {"name": "MARINA", "pos": Vector3(78, 0, -75)},
        {"name": "PARK", "pos": Vector3(10, 0, -36)}
    ]
    for j in jobs:
        var marker := Marker3D.new()
        var job_pos: Vector3 = j["pos"]
        marker.position = job_pos + Vector3(0.0, 0.15, 0.0)
        marker.name = String(j["name"]).replace(" ", "_")
        marker.set_meta("job_location", j["name"])
        add_child(marker)

# ---------------------------------------------------------------------------
# Missions
# ---------------------------------------------------------------------------

func start_next_mission() -> void:
    mission_index = (mission_index + 1) % MISSIONS.size()
    var m: Dictionary = MISSIONS[mission_index]
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
    mission_marker.position = Vector3(mission_target.x, _height(mission_target.x, mission_target.z) + 0.12, mission_target.z)
    add_child(mission_marker)
    _mission_hud_timer = 1.0

func get_mission_status(player_position: Vector3) -> String:
    if not mission_active:
        return "PRESS ACTION TO START A CIVIC MISSION"
    var flat := Vector2(player_position.x - mission_target.x, player_position.z - mission_target.z)
    var distance: float = flat.length()
    if distance < 4.5:
        mission_active = false
        if is_instance_valid(mission_marker):
            mission_marker.queue_free()
        return "MISSION COMPLETE  +$%d" % mission_reward
    return "%s  •  %dm" % [mission_name, int(distance)]

func _process_mission(delta: float) -> void:
    if not mission_active:
        return
    _mission_hud_timer += delta
    if _mission_hud_timer < 0.25:
        return
    _mission_hud_timer = 0.0
    if _player_ref == null or not is_instance_valid(_player_ref):
        return
    var status: String = get_mission_status(_player_ref.global_position)
    _set_hud_label("Mission", "MISSION  •  " + status)

# ---------------------------------------------------------------------------
# Driveable vehicles
# ---------------------------------------------------------------------------

func _make_driveable_vehicle() -> void:
    var vehicle_script: Script = load("res://scripts/vehicle.gd")
    # Parked in the median of the main road, away from the traffic lanes.
    var setups: Array = [
        {"x": 9.0, "z": 28.0, "rot": -PI / 2.0, "color": Color("#b52f32")},
        {"x": -14.0, "z": 28.0, "rot": -PI / 2.0, "color": Color("#2b5ea8")},
        {"x": 30.0, "z": 28.0, "rot": PI / 2.0, "color": Color("#d2b24c")}
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

func _nearest_vehicle(player_position: Vector3) -> CharacterBody3D:
    var nearest: CharacterBody3D = null
    var best_distance: float = 5.0
    for car in driveable_vehicles:
        if is_instance_valid(car) and not bool(car.call("is_driving")):
            var distance: float = player_position.distance_to(car.global_position)
            if distance < best_distance:
                best_distance = distance
                nearest = car
    return nearest

func get_nearest_driveable_vehicle(player_position: Vector3) -> CharacterBody3D:
    return _nearest_vehicle(player_position)

func toggle_vehicle(player: Node3D) -> String:
    if bool(player.get("in_vehicle")):
        var current_vehicle: CharacterBody3D = player.get("vehicle")
        player.call("exit_vehicle")
        if current_vehicle != null and is_instance_valid(current_vehicle):
            current_vehicle.call("exit")
        return "ON FOOT"
    var vehicle: CharacterBody3D = _nearest_vehicle(player.global_position)
    if vehicle == null:
        return "WALK CLOSER TO THE CAR"
    player.call("enter_vehicle", vehicle)
    vehicle.call("enter")
    return "DRIVING"

# ---------------------------------------------------------------------------
# Day / night / weather
# ---------------------------------------------------------------------------

func _step18_visual_setup() -> void:
    if world_env == null or world_env.environment == null:
        return
    world_env.environment.glow_enabled = false
    world_env.environment.fog_enabled = false

func _update_sun() -> void:
    if sun == null:
        return
    # +1 at noon, 0 at 06:00 / 18:00, negative at night. The sun used to sit
    # BELOW the horizon at the 08:00 start time (light pointing up from the ground).
    var elevation: float = sin((time_of_day - 6.0) / 24.0 * TAU)
    var pitch: float = -40.0
    if elevation > 0.0:
        pitch = -lerpf(8.0, 62.0, elevation)
    var yaw: float = -35.0 + cos(time_of_day / 24.0 * TAU) * 15.0
    sun.rotation_degrees = Vector3(pitch, yaw, 0.0)

func _step18_visual_update() -> void:
    if world_env == null or world_env.environment == null or sun == null:
        return
    var elevation: float = sin((time_of_day - 6.0) / 24.0 * TAU)
    var daylight: float = clampf(elevation * 0.5 + 0.5, 0.0, 1.0)
    var night_amount: float = 1.0 - daylight
    sun.light_color = Color("#fff0d2").lerp(Color("#9db9df"), night_amount * 0.72)
    sun.light_energy = lerpf(0.16, 1.42, daylight)
    world_env.environment.ambient_light_energy = lerpf(0.30, 1.05, daylight)

func _update_lamps() -> void:
    var state: int = 1 if _is_night else 0
    if state == _lamp_state:
        return
    _lamp_state = state
    for lamp in street_lamps:
        if is_instance_valid(lamp):
            lamp.visible = _is_night

func _update_weather(delta: float) -> void:
    # Weather used to be unreachable (nothing ever called set_weather).
    _weather_timer -= delta
    if _weather_timer > 0.0:
        return
    _weather_timer = randf_range(90.0, 180.0)
    var roll: float = randf()
    if roll < 0.55:
        set_weather("clear")
    elif roll < 0.85:
        set_weather("rain")
    else:
        set_weather("snow")

func set_weather(kind: String) -> void:
    weather = kind
    if rain_particles != null:
        rain_particles.visible = kind == "rain"
    if snow_particles != null:
        snow_particles.visible = kind == "snow"

func _follow_weather_particles() -> void:
    # The emitters are 96 m wide boxes; keep them above the player so rain/snow
    # appears wherever the player is, not only around the world origin.
    if _player_ref == null or not is_instance_valid(_player_ref):
        return
    var anchor: Vector3 = _player_ref.global_position + Vector3(0.0, 12.0, 0.0)
    if rain_particles != null and rain_particles.visible:
        rain_particles.global_position = anchor
    if snow_particles != null and snow_particles.visible:
        snow_particles.global_position = anchor

func _update_hud_speed() -> void:
    var hud_speed := get_node_or_null("HUD/Speed") as Label
    var hud_player := get_node_or_null("Player")
    if hud_speed == null or hud_player == null:
        return
    var shown_speed: float = 0.0
    if bool(hud_player.get("in_vehicle")):
        var car: Object = hud_player.get("vehicle")
        if car != null and is_instance_valid(car):
            shown_speed = float(car.get("speed_kmh"))
    else:
        var vel: Vector3 = hud_player.get("velocity")
        shown_speed = Vector2(vel.x, vel.z).length() * 3.6
    hud_speed.text = "%d km/h" % int(shown_speed)

func _process(delta: float) -> void:
    time_of_day = fmod(time_of_day + delta * 0.045, 24.0)
    _is_night = time_of_day < 6.0 or time_of_day > 18.3

    _process_mission(delta)
    _adaptive_quality_tick(delta)
    _collision_lod_tick(delta)
    _apply_shadow_lod(false, delta)
    _apply_vehicle_lod(false, delta)
    _update_hud_speed()
    _update_sun()
    _step18_visual_update()
    _update_lamps()
    _update_weather(delta)
    _follow_weather_particles()
    _simulate_actors(delta)

func _simulate_actors(delta: float) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        _player_ref = get_node_or_null("Player") as Node3D
        if _player_ref == null:
            return

    # NPC/traffic simulation runs at a stable ~30 Hz instead of every render frame.
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

    traffic_signal_time = fmod(traffic_signal_time + simulation_delta, 12.0)
    traffic_signal_green_x = traffic_signal_time < 6.0

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
            # Follow the ground (pedestrians used to stay at a fixed height).
            n.position.y = _height(n.position.x, n.position.z) + 0.04

    for data in _nearby_traffic:
        var car: Node3D = data["node"]
        if not is_instance_valid(car):
            continue
        var traffic_distance: float = _distance_to_player(car)
        if traffic_distance > TRAFFIC_REDUCED_RADIUS:
            continue

        var medium_traffic: bool = traffic_distance > TRAFFIC_SIMULATION_RADIUS
        if medium_traffic and not reduced_update:
            continue

        var route: Dictionary = data["route"]
        var step_delta: float = reduced_delta if medium_traffic else simulation_delta
        var route_from: float = float(route["from"])
        var route_to: float = float(route["to"])
        var route_span: float = route_to - route_from
        if absf(route_span) < 0.001:
            continue

        var is_x_axis: bool = route["axis"] == "x"
        var route_dir: int = int(route["dir"])
        var phase: float = float(data["phase"])
        var desired_speed: float = float(data["speed"])
        var should_stop: bool = false
        if is_x_axis:
            var x_now: float = lerpf(route_from, route_to, phase)
            if absf(x_now - TRAFFIC_INTERSECTION_X) < 12.0 and absf(float(route["z"]) - TRAFFIC_INTERSECTION_Z) < 6.0:
                should_stop = not traffic_signal_green_x
                if route_dir > 0 and x_now > TRAFFIC_INTERSECTION_X:
                    should_stop = false
                elif route_dir < 0 and x_now < TRAFFIC_INTERSECTION_X:
                    should_stop = false
        else:
            var z_now: float = lerpf(route_from, route_to, phase)
            if absf(z_now - TRAFFIC_INTERSECTION_Z) < 12.0 and absf(float(route["x"]) - TRAFFIC_INTERSECTION_X) < 8.0:
                should_stop = traffic_signal_green_x
                if route_dir > 0 and z_now > TRAFFIC_INTERSECTION_Z:
                    should_stop = false
                elif route_dir < 0 and z_now < TRAFFIC_INTERSECTION_Z:
                    should_stop = false
        if should_stop:
            desired_speed = 0.0
        var direction: float = 1.0 if route_dir > 0 else -1.0
        phase += (desired_speed * step_delta / absf(route_span)) * direction
        if phase > 1.0:
            phase -= 1.0
        elif phase < 0.0:
            phase += 1.0

        if is_x_axis:
            car.position.x = lerpf(route_from, route_to, phase)
            car.position.z = float(route["z"])
        else:
            car.position.z = lerpf(route_from, route_to, phase)
            car.position.x = float(route["x"])

        data["phase"] = phase

# ---------------------------------------------------------------------------
# HUD callbacks (called by mobile_controls.gd)
# ---------------------------------------------------------------------------

func _on_hud_act_pressed() -> void:
    # DRIVE / EXIT button: enter or leave the nearest car. It no longer starts a
    # mission when no car is nearby (that is the ACTION button's job).
    var p := get_node_or_null("Player") as Node3D
    if p == null:
        return
    var result: String = toggle_vehicle(p)
    _set_hud_label("Vehicle", "VEHICLE  •  " + result)

func _on_hud_action_pressed() -> void:
    if mission_active:
        var ppos: Vector3 = Vector3.ZERO
        if _player_ref != null and is_instance_valid(_player_ref):
            ppos = _player_ref.global_position
        _set_hud_label("Mission", "MISSION  •  " + get_mission_status(ppos))
    else:
        start_next_mission()
        _set_hud_label("Mission", "MISSION  •  " + mission_name)

func _on_hud_jump_pressed() -> void:
    var p := get_node_or_null("Player")
    if p != null and p.has_method("jump"):
        p.call("jump")
