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

func _adaptive_quality_tick(delta: float) -> void:
    _fps_timer += delta
    if _fps_timer < 1.5:
        return
    _fps_timer = 0.0
    var fps := Engine.get_frames_per_second()
    if fps > 52 and _quality_level != 2:
        _quality_level = 2
        _apply_mobile_quality()
    elif fps < 28 and _quality_level != 0:
        _quality_level = 0
        _apply_mobile_quality()
    elif fps < 40 and fps >= 28 and _quality_level != 1:
        _quality_level = 1
        _apply_mobile_quality()

func _apply_mobile_quality() -> void:
    if not sun:
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
        add_child(world_env)

    if world_env.environment == null:
        var env := Environment.new()
        env.background_mode = Environment.BG_SKY
        env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        env.ambient_light_energy = 0.95
        env.ambient_light_sky_contribution = 0.72
        env.fog_enabled = true
        env.fog_light_color = Color("#b7c7c9")
        env.fog_density = 0.00115
        env.fog_height = 18.0
        env.fog_height_density = 0.008
        env.glow_enabled = false
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

    sun = get_node_or_null("Sun") as DirectionalLight3D
    if sun == null:
        sun = DirectionalLight3D.new()
        sun.name = "Sun"
        add_child(sun)

    sun.light_color = Color("#fff4df")
    sun.light_energy = 1.45
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 90.0
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)

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

# ...existing world-generation functions are intentionally preserved...

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
    time_of_day = fmod(time_of_day + delta * 0.045, 24.0)
    var angle := (time_of_day / 24.0) * TAU
    sun.rotation_degrees.x = -32.0 + sin(angle) * 55.0
    sun.rotation_degrees.y = -35.0 + cos(angle) * 15.0
    sun.light_energy = clamp(0.18 + max(0.0,sin(angle)) * 1.35,0.12,1.5)
    world_env.environment.ambient_light_energy = 0.38 + max(0.0,sin(angle))*0.7

    _simulation_accumulator += delta
    if _simulation_accumulator < 0.033:
        return
    var simulation_delta := _simulation_accumulator
    _simulation_accumulator = 0.0

    var t := Time.get_ticks_msec() * 0.001
    for npc_data in npcs:
        var n: Node3D = npc_data["node"]
        var phase: float = npc_data["phase"]
        var base: Vector3 = npc_data["base"]
        var radius: float = npc_data["radius"]
        n.position = base + Vector3(cos(t*0.45+phase)*radius,0.05,sin(t*0.45+phase)*radius)
        n.rotation.y = -atan2(sin(t*0.45+phase),cos(t*0.45+phase))
        n.position.y = 0.05 + abs(sin(t*3.2+phase))*0.025

    for data in traffic:
        var car: Node3D = data["node"]
        var route: Dictionary = data["route"]
        var phase: float = fmod(float(data["phase"]) + float(data["speed"]) * simulation_delta / (float(route["to"]) - float(route["from"])), 1.0)
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

func _on_hud_run_pressed() -> void:
    var p := get_node_or_null("Player")
    if p:
        # RUN is a sprint toggle only. Movement remains controlled by the joystick.
        p.set_sprint(not p.sprint_touch)
        var b := get_node_or_null("HUD/Run") as Button
        if b:
            b.text = "STOP" if p.sprint_touch else "RUN"
        var v := get_node_or_null("HUD/Vehicle") as Label
        if v:
            v.text = "PLAYER  •  RUNNING" if p.sprint_touch else "PLAYER  •  READY"

func _on_hud_act_pressed() -> void:
    var p := get_node_or_null("Player")
    if p:
        var result := toggle_vehicle(p)
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
        if p.is_on_floor():
            p.velocity.y = 8.0
        var m := get_node_or_null("HUD/Mission") as Label
        if m:
            m.text = "ACTION  •  JUMP"
