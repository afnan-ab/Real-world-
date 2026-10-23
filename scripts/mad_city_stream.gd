extends "res://scripts/mad_city_services.gd"

# GTA-style streaming ideas, scaled down for a phone (stacked on services):
#  1. Ring traffic and pedestrians. Cars / people that end up far from the
#     player are not simulated for nothing: they are moved to a ring around the
#     player (cars 90..200 m, people 50..130 m), always outside the camera view,
#     so nobody appears on screen. The same cars give a denser street near you.
#  2. Time-of-day density: fewer cars and people at night, full at day.
#     Inactive ones are parked far away and hidden.
#  3. Far LOD without a second model: the building boxes are cheap (the windows
#     are the heavy part), so the box chunks are now always drawn and only the
#     windows are cut at 190 m (with a fade where the renderer supports it).
# Not done on purpose: MultiMesh for lamps and trees. They are already merged
# into the 80 m city chunks, which is the same saving.
# Not measured: I cannot run Godot here.

const MC_RING_NEAR := 90.0
const MC_RING_SPAWN := 200.0
const MC_RING_FAR := 260.0
const MC_PED_RING_NEAR := 50.0
const MC_PED_RING_SPAWN := 130.0
const MC_PED_RING_FAR := 170.0
const MC_PARK := Vector3(6000.0, 0.0, 6000.0)

var _str_timer: float = 0.0
var _str_density_timer: float = 2.5

func _ready() -> void:
    super._ready()
    _str_tune_lod()

# ---------------------------------------------------------------------------
# LOD tuning
# ---------------------------------------------------------------------------

func _str_tune_lod() -> void:
    for child in get_children():
        var mi: MeshInstance3D = child as MeshInstance3D
        if mi == null:
            continue
        var n: String = String(mi.name)
        if n.begins_with("MC_CityBlocks"):
            mi.visibility_range_end = 0.0
        elif n.begins_with("MC_Windows"):
            mi.visibility_range_end_margin = 25.0
            mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

# ---------------------------------------------------------------------------
# Traffic: skip parked cars, recycle far cars into the ring
# ---------------------------------------------------------------------------

func _mc_step_car(a: Dictionary, dt: float) -> void:
    if bool(a.get("off", false)):
        return
    super._mc_step_car(a, dt)

func _str_random_dir(ix: float, iz: float) -> Vector2:
    var dirs: Array = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]
    var valid: Array = []
    for d in dirs:
        var dv: Vector2 = d
        if absf(ix + dv.x * MC_PITCH) <= MC_EXT + 0.1 and absf(iz + dv.y * MC_PITCH) <= MC_EXT + 0.1:
            valid.append(dv)
    if valid.is_empty():
        return Vector2(1.0, 0.0)
    return valid[rng.randi_range(0, valid.size() - 1)]

func _str_place_car_near(a: Dictionary, p: Vector3, cam: Camera3D) -> bool:
    for attempt in range(14):
        var ix: float = float(rng.randi_range(-MC_N, MC_N)) * MC_PITCH
        var iz: float = float(rng.randi_range(-MC_N, MC_N)) * MC_PITCH
        var dist: float = Vector2(ix - p.x, iz - p.z).length()
        if dist < MC_RING_NEAR or dist > MC_RING_SPAWN:
            continue
        var d: Vector2 = _str_random_dir(ix, iz)
        _mc_place(a, ix, iz, d)
        var ahead: float = rng.randf_range(5.0, 55.0)
        a["x"] = float(a["x"]) + d.x * ahead
        a["z"] = float(a["z"]) + d.y * ahead
        var final_pos := Vector3(float(a["x"]), CAR_Y, float(a["z"]))
        if cam != null and cam.is_position_in_frustum(final_pos + Vector3(0.0, 1.0, 0.0)):
            continue
        a["v"] = rng.randf_range(9.0, 15.0)
        a["wait"] = 0.0
        a["stun"] = 0.0
        var node: Node3D = a["node"]
        node.position = final_pos
        node.rotation.y = atan2(-d.y, d.x)
        return true
    return false

func _str_recycle_cars(p: Vector3, cam: Camera3D) -> void:
    for item in traffic:
        var a: Dictionary = item
        if bool(a.get("off", false)):
            continue
        if float(a.get("hp", 100.0)) <= 0.0:
            continue
        var node: Node3D = a["node"]
        if not is_instance_valid(node):
            continue
        var dist: float = Vector2(float(a["x"]) - p.x, float(a["z"]) - p.z).length()
        if dist > MC_RING_FAR:
            _str_place_car_near(a, p, cam)

# ---------------------------------------------------------------------------
# Pedestrians: recycle far people into the ring on the sidewalks
# ---------------------------------------------------------------------------

func _str_place_ped_near(d: Dictionary, p: Vector3, cam: Camera3D) -> bool:
    for attempt in range(14):
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
        var dist: float = Vector2(sx - p.x, sz - p.z).length()
        if dist < MC_PED_RING_NEAR or dist > MC_PED_RING_SPAWN:
            continue
        var pos := Vector3(sx, MC_SLAB_TOP + 0.04, sz)
        if cam != null and cam.is_position_in_frustum(pos + Vector3(0.0, 1.0, 0.0)):
            continue
        var node: Node3D = d["node"]
        node.global_position = pos
        node.set("origin", pos)
        node.set("target", pos)
        d["base"] = pos
        return true
    return false

func _str_recycle_peds(p: Vector3, cam: Camera3D) -> void:
    for item in npcs:
        var d: Dictionary = item
        if bool(d.get("off", false)):
            continue
        var node: Node3D = d["node"]
        if not is_instance_valid(node):
            continue
        var dist: float = Vector2(node.global_position.x - p.x, node.global_position.z - p.z).length()
        if dist > MC_PED_RING_FAR:
            _str_place_ped_near(d, p, cam)

# ---------------------------------------------------------------------------
# Time-of-day density
# ---------------------------------------------------------------------------

func _str_density_factor() -> float:
    var hour: float = fposmod(time_of_day, 24.0)
    if hour >= 6.0 and hour < 20.0:
        return 1.0
    if (hour >= 20.0 and hour < 23.0) or (hour >= 5.0 and hour < 6.0):
        return 0.75
    return 0.5

func _str_apply_density(p: Vector3, cam: Camera3D) -> void:
    var factor: float = _str_density_factor()

    var car_target: int = int(roundf(float(traffic.size()) * factor))
    var active_cars: Array = []
    var parked_cars: Array = []
    for item in traffic:
        var a: Dictionary = item
        var node: Node3D = a["node"]
        if not is_instance_valid(node):
            continue
        if bool(a.get("off", false)):
            parked_cars.append(a)
        else:
            active_cars.append(a)
    if active_cars.size() > car_target:
        active_cars.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
            return Vector2(float(x["x"]) - p.x, float(x["z"]) - p.z).length() > Vector2(float(y["x"]) - p.x, float(y["z"]) - p.z).length())
        for i in range(active_cars.size() - car_target):
            var a2: Dictionary = active_cars[i]
            a2["off"] = true
            a2["x"] = MC_PARK.x
            a2["z"] = MC_PARK.z
            var n2: Node3D = a2["node"]
            n2.visible = false
            n2.position = MC_PARK
    elif active_cars.size() < car_target:
        var need: int = car_target - active_cars.size()
        for a3 in parked_cars:
            if need <= 0:
                break
            var ad: Dictionary = a3
            if _str_place_car_near(ad, p, cam):
                ad["off"] = false
                var n3: Node3D = ad["node"]
                n3.visible = true
                need -= 1

    var ped_target: int = int(roundf(float(npcs.size()) * factor))
    var active_peds: Array = []
    var parked_peds: Array = []
    for item in npcs:
        var d: Dictionary = item
        var pn: Node3D = d["node"]
        if not is_instance_valid(pn):
            continue
        if bool(d.get("off", false)):
            parked_peds.append(d)
        else:
            active_peds.append(d)
    if active_peds.size() > ped_target:
        active_peds.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
            var nx: Node3D = x["node"]
            var ny: Node3D = y["node"]
            return Vector2(nx.global_position.x - p.x, nx.global_position.z - p.z).length() > Vector2(ny.global_position.x - p.x, ny.global_position.z - p.z).length())
        for i in range(active_peds.size() - ped_target):
            var d2: Dictionary = active_peds[i]
            d2["off"] = true
            var pn2: Node3D = d2["node"]
            pn2.visible = false
            pn2.global_position = MC_PARK
    elif active_peds.size() < ped_target:
        var need_p: int = ped_target - active_peds.size()
        for d3 in parked_peds:
            if need_p <= 0:
                break
            var dd: Dictionary = d3
            if _str_place_ped_near(dd, p, cam):
                dd["off"] = false
                var pn3: Node3D = dd["node"]
                pn3.visible = true
                need_p -= 1

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
    super._process(delta)
    if _player_ref == null or not is_instance_valid(_player_ref) or _mc_inside >= 0:
        return
    _str_timer += delta
    _str_density_timer += delta
    var cam: Camera3D = get_viewport().get_camera_3d()
    var p: Vector3 = _player_ref.global_position
    if _str_timer >= 0.5:
        _str_timer = 0.0
        _str_recycle_cars(p, cam)
        _str_recycle_peds(p, cam)
    if _str_density_timer >= 3.0:
        _str_density_timer = 0.0
        _str_apply_density(p, cam)
