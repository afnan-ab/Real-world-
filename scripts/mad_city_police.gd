extends "res://scripts/mad_city_world.gd"

# Mad City port - Phase 2: police, wanted stars, ambulance and fire truck.
# Stacked on Phase 1 (mad_city_world.gd). Ported rules from Mad_City.html:
#   stars = min(5, ceil(heat / 20)), cops spawn while stars > 0 up to stars + 1,
#   cops drive the road grid toward the player (speed 18 + 3 * stars), stop when
#   within 12 m of a slow player, heat decays 1.5/s with a cop within 45 m else
#   5/s, BUSTED after 2.2 s with a cop within 6 m while the player is slow,
#   hitting a moving AI car adds +10 heat and stuns it for 1.2 s.
# Not in this phase: cops on foot, shooting, road blocks, helicopter (they need
# weapons / health, which come later), and real car-to-car physics.

const MC_CRASH_RESPONSE_DELAY := 5.0
const MC_RESPONDER_WAIT := 12.0

var _mc_heat: float = 0.0
var _mc_bust: float = 0.0
var _mc_time: float = 0.0
var _mc_last_stars: int = -1
var _mc_msg_timer: float = 0.0
var _mc_cops: Array = []
var _mc_responders: Array = []
var _mc_crashes: Array = []

func _ready() -> void:
    super._ready()
    _mc_update_wanted_hud(0)

# ---------------------------------------------------------------------------
# Traffic cars can be stunned after the player hits them
# ---------------------------------------------------------------------------

func _mc_step_car(a: Dictionary, dt: float) -> void:
    var stun: float = float(a.get("stun", 0.0))
    if stun > 0.0:
        a["stun"] = stun - dt
        return
    super._mc_step_car(a, dt)

# ---------------------------------------------------------------------------
# HUD helpers
# ---------------------------------------------------------------------------

func _mc_update_wanted_hud(stars: int) -> void:
    if stars == _mc_last_stars:
        return
    _mc_last_stars = stars
    var text_value: String = "WANTED  "
    for i in range(5):
        text_value += "★ " if i < stars else "☆ "
    _set_hud_label("Wanted", text_value)

func _mc_say(text_value: String) -> void:
    _mc_msg_timer = 3.0
    _set_hud_label("Top/Status", text_value)

# ---------------------------------------------------------------------------
# Vehicle builders (front of every model is +X, like _make_car)
# ---------------------------------------------------------------------------

func _mc_make_light_bar(root: Node3D, y: float, length: float) -> StandardMaterial3D:
    var bar := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(0.5, 0.18, length)
    bar.mesh = bm
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(1.0, 0.1, 0.1)
    bar.material_override = mat
    bar.position = Vector3(0.0, y, 0.0)
    root.add_child(bar)
    return mat

func _mc_make_ambulance() -> Dictionary:
    var root := Node3D.new()
    add_child(root)
    var white: StandardMaterial3D = _mat(Color("#f1f3f4"), 0.5)
    var red: StandardMaterial3D = _mat(Color("#c0261f"), 0.5)
    var tire: StandardMaterial3D = _mat(Color("#111214"), 0.96)
    var glass: StandardMaterial3D = _mat(Color("#162b37"), 0.1, 0.3)
    _local_box(root, Vector3(-0.3, 1.45, 0.0), Vector3(4.6, 2.0, 2.2), white)
    _local_box(root, Vector3(2.5, 1.15, 0.0), Vector3(1.3, 1.4, 2.1), white)
    _local_box(root, Vector3(3.05, 1.45, 0.0), Vector3(0.1, 0.55, 1.8), glass)
    _local_box(root, Vector3(-0.3, 1.2, 1.11), Vector3(4.2, 0.3, 0.05), red)
    _local_box(root, Vector3(-0.3, 1.2, -1.11), Vector3(4.2, 0.3, 0.05), red)
    _local_box(root, Vector3(-0.3, 1.9, 1.12), Vector3(0.9, 0.9, 0.05), red)
    _local_box(root, Vector3(-0.3, 1.9, -1.12), Vector3(0.9, 0.9, 0.05), red)
    for sx in [-1.5, 2.0]:
        for sz in [-1.0, 1.0]:
            _local_box(root, Vector3(float(sx), 0.45, float(sz)), Vector3(0.9, 0.9, 0.3), tire)
    var bar_mat: StandardMaterial3D = _mc_make_light_bar(root, 2.6, 1.6)
    return {"node": root, "bar_mat": bar_mat}

func _mc_make_fire_truck() -> Dictionary:
    var root := Node3D.new()
    add_child(root)
    var red: StandardMaterial3D = _mat(Color("#b3201a"), 0.45, 0.2)
    var white: StandardMaterial3D = _mat(Color("#e9e6dc"), 0.6)
    var grey: StandardMaterial3D = _mat(Color("#8a9094"), 0.4, 0.5)
    var tire: StandardMaterial3D = _mat(Color("#111214"), 0.96)
    var glass: StandardMaterial3D = _mat(Color("#162b37"), 0.1, 0.3)
    _local_box(root, Vector3(-0.7, 1.35, 0.0), Vector3(5.2, 1.8, 2.4), red)
    _local_box(root, Vector3(2.7, 1.4, 0.0), Vector3(1.6, 1.9, 2.3), red)
    _local_box(root, Vector3(3.52, 1.8, 0.0), Vector3(0.08, 0.7, 2.0), glass)
    _local_box(root, Vector3(-0.7, 1.1, 1.21), Vector3(5.0, 0.18, 0.05), white)
    _local_box(root, Vector3(-0.7, 1.1, -1.21), Vector3(5.0, 0.18, 0.05), white)
    _local_box(root, Vector3(-0.9, 2.45, 0.0), Vector3(4.4, 0.18, 0.6), grey)
    _local_box(root, Vector3(-0.9, 2.62, 0.0), Vector3(4.4, 0.08, 0.14), grey)
    for sx in [-2.4, 0.2, 2.9]:
        for sz in [-1.1, 1.1]:
            _local_box(root, Vector3(float(sx), 0.5, float(sz)), Vector3(1.0, 1.0, 0.35), tire)
    var bar_mat: StandardMaterial3D = _mc_make_light_bar(root, 2.95, 1.8)
    return {"node": root, "bar_mat": bar_mat}

# ---------------------------------------------------------------------------
# Road-following chase AI (cops and responders share it)
# ---------------------------------------------------------------------------

func _mc_best_dir(ix: float, iz: float, tx: float, tz: float) -> Vector2:
    var dirs: Array = [Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0)]
    var best: Vector2 = Vector2(1.0, 0.0)
    var best_d: float = 1.0e9
    for d in dirs:
        var dv: Vector2 = d
        var nx: float = ix + dv.x * MC_PITCH
        var nz: float = iz + dv.y * MC_PITCH
        if absf(nx) > MC_EXT + 0.1 or absf(nz) > MC_EXT + 0.1:
            continue
        var dist: float = Vector2(nx - tx, nz - tz).length()
        if dist < best_d:
            best_d = dist
            best = dv
    return best

func _mc_chase_turn(a: Dictionary, ix: float, iz: float, tx: float, tz: float) -> void:
    var dx: float = a["dx"]
    var dz: float = a["dz"]
    var cand: Array = [Vector2(dx, dz), Vector2(dz, -dx), Vector2(-dz, dx)]
    var choice: Vector2 = Vector2(-dx, -dz)
    var best_d: float = 1.0e9
    for c in cand:
        var cv: Vector2 = c
        var nx: float = ix + cv.x * MC_PITCH
        var nz: float = iz + cv.y * MC_PITCH
        if absf(nx) > MC_EXT + 0.1 or absf(nz) > MC_EXT + 0.1:
            continue
        var dist: float = Vector2(nx - tx, nz - tz).length()
        if dist < best_d:
            best_d = dist
            choice = cv
    _mc_place(a, ix, iz, choice)

func _mc_chase_step(a: Dictionary, dt: float, tx: float, tz: float, v_target: float) -> void:
    var node: Node3D = a["node"]
    var v: float = a["v"]
    v += (v_target - v) * minf(1.0, 3.0 * dt)
    a["v"] = v
    var dx: float = a["dx"]
    var dz: float = a["dz"]
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
        _mc_chase_turn(a, ix, iz, tx, tz)
    node.position = Vector3(float(a["x"]), CAR_Y, float(a["z"]))
    node.rotation.y = atan2(-float(a["dz"]), float(a["dx"]))

func _mc_flash(a: Dictionary) -> void:
    var mat: StandardMaterial3D = a["bar_mat"]
    if mat == null:
        return
    if int(floorf(_mc_time * 6.0)) % 2 == 0:
        mat.albedo_color = Color(1.0, 0.13, 0.13)
    else:
        mat.albedo_color = Color(0.13, 0.33, 1.0)

func _mc_pick_junction(tx: float, tz: float, min_dist: float) -> Vector2:
    for attempt in range(24):
        var ix: float = float(rng.randi_range(-MC_N, MC_N)) * MC_PITCH
        var iz: float = float(rng.randi_range(-MC_N, MC_N)) * MC_PITCH
        if Vector2(ix - tx, iz - tz).length() > min_dist:
            return Vector2(ix, iz)
    return Vector2(-MC_EXT, -MC_EXT)

# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

func _mc_spawn_cop(tx: float, tz: float) -> void:
    var j: Vector2 = _mc_pick_junction(tx, tz, 100.0)
    var d: Vector2 = _mc_best_dir(j.x, j.y, tx, tz)
    var car: Node3D = _make_car(Vector3(0.0, CAR_Y, 0.0), Color("#eef1f3"), 0.0)
    var bar_mat: StandardMaterial3D = _mc_make_light_bar(car, 1.62, 1.3)
    var data: Dictionary = {"node": car, "bar_mat": bar_mat, "x": 0.0, "z": 0.0, "dx": 0.0, "dz": 0.0, "v": 0.0}
    _mc_place(data, j.x, j.y, d)
    car.position = Vector3(float(data["x"]), CAR_Y, float(data["z"]))
    car.rotation.y = atan2(-d.y, d.x)
    _mc_cops.append(data)

func _mc_spawn_responder(kind: String, target: Vector3) -> void:
    var j: Vector2 = _mc_pick_junction(target.x, target.z, 100.0)
    var d: Vector2 = _mc_best_dir(j.x, j.y, target.x, target.z)
    var model: Dictionary = _mc_make_ambulance() if kind == "ambulance" else _mc_make_fire_truck()
    var node: Node3D = model["node"]
    var data: Dictionary = {"node": node, "bar_mat": model["bar_mat"], "x": 0.0, "z": 0.0, "dx": 0.0, "dz": 0.0, "v": 0.0, "target": target, "state": "drive", "t": 0.0}
    _mc_place(data, j.x, j.y, d)
    node.position = Vector3(float(data["x"]), CAR_Y, float(data["z"]))
    node.rotation.y = atan2(-d.y, d.x)
    _mc_responders.append(data)

# ---------------------------------------------------------------------------
# Crimes, busting
# ---------------------------------------------------------------------------

func _mc_check_crashes(veh: Node3D, speed_ms: float) -> void:
    if speed_ms < 3.0:
        return
    var vp: Vector3 = veh.global_position
    for item in traffic:
        var a: Dictionary = item
        if float(a.get("stun", 0.0)) > 0.0:
            continue
        var n: Node3D = a["node"]
        if not is_instance_valid(n):
            continue
        var ddx: float = n.position.x - vp.x
        var ddz: float = n.position.z - vp.z
        if ddx * ddx + ddz * ddz < 3.4 * 3.4:
            _mc_heat = minf(100.0, _mc_heat + 10.0)
            a["stun"] = 1.2
            _mc_say("Crash! Police are on the way")
            if speed_ms > 8.0:
                _mc_crashes.append({"pos": n.position, "t": 0.0})

func _mc_clear_cops() -> void:
    for item in _mc_cops:
        var c: Dictionary = item
        var node: Node3D = c["node"]
        if is_instance_valid(node):
            node.queue_free()
    _mc_cops.clear()

func _mc_busted() -> void:
    _mc_heat = 0.0
    _mc_bust = 0.0
    _mc_clear_cops()
    if _player_ref != null and is_instance_valid(_player_ref):
        if bool(_player_ref.get("in_vehicle")):
            toggle_vehicle(_player_ref)
        _player_ref.global_position = Vector3(MC_START.x, MC_SLAB_TOP + 1.2, MC_START.z)
    _mc_say("BUSTED! You were taken back to the start")

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
    super._process(delta)
    _mc_police_tick(delta)

func _mc_police_tick(delta: float) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        return
    _mc_time += delta
    if _mc_msg_timer > 0.0:
        _mc_msg_timer -= delta
        if _mc_msg_timer <= 0.0:
            _set_hud_label("Top/Status", "ONLINE  •  CITY  •  FREE ROAM")

    var ppos: Vector3 = _player_ref.global_position
    var tx: float = ppos.x
    var tz: float = ppos.z
    var sp: float = 0.0
    if bool(_player_ref.get("in_vehicle")):
        var veh: Object = _player_ref.get("vehicle")
        if veh != null and is_instance_valid(veh):
            sp = float(veh.get("speed_kmh")) / 3.6
            _mc_check_crashes(veh as Node3D, sp)
    else:
        var vel: Vector3 = _player_ref.get("velocity")
        sp = Vector2(vel.x, vel.z).length()

    _mc_heat = clampf(_mc_heat, 0.0, 100.0)
    var stars: int = mini(5, int(ceilf(_mc_heat / 20.0)))
    _mc_update_wanted_hud(stars)

    if stars > 0 and _mc_cops.size() < stars + 1 and rng.randf() < delta * 2.0:
        _mc_spawn_cop(tx, tz)

    var nearest: float = 999.0
    for i in range(_mc_cops.size() - 1, -1, -1):
        var c: Dictionary = _mc_cops[i]
        var cnode: Node3D = c["node"]
        if not is_instance_valid(cnode):
            _mc_cops.remove_at(i)
            continue
        var d: float = Vector2(float(c["x"]) - tx, float(c["z"]) - tz).length()
        nearest = minf(nearest, d)
        if stars == 0 and d > 25.0:
            cnode.queue_free()
            _mc_cops.remove_at(i)
            continue
        var stop_near: bool = d < 12.0 and sp < 9.0
        var v_target: float = 0.0
        if stars > 0 and not stop_near:
            v_target = 18.0 + float(stars) * 3.0
        _mc_chase_step(c, delta, tx, tz, v_target)
        _mc_flash(c)

    var decay: float = 1.5 if nearest < 45.0 else 5.0
    _mc_heat = maxf(0.0, _mc_heat - decay * delta)

    if stars > 0 and nearest < 6.0 and sp < 4.0:
        _mc_bust += delta
    else:
        _mc_bust = maxf(0.0, _mc_bust - delta)
    if _mc_bust > 2.2:
        _mc_busted()

    _mc_responder_tick(delta)

func _mc_responder_tick(delta: float) -> void:
    for i in range(_mc_crashes.size() - 1, -1, -1):
        var crash: Dictionary = _mc_crashes[i]
        crash["t"] = float(crash["t"]) + delta
        if float(crash["t"]) >= MC_CRASH_RESPONSE_DELAY:
            var pos: Vector3 = crash["pos"]
            _mc_spawn_responder("ambulance", pos)
            _mc_spawn_responder("fire", pos)
            _mc_crashes.remove_at(i)

    for i in range(_mc_responders.size() - 1, -1, -1):
        var r: Dictionary = _mc_responders[i]
        var node: Node3D = r["node"]
        if not is_instance_valid(node):
            _mc_responders.remove_at(i)
            continue
        var target: Vector3 = r["target"]
        var d: float = Vector2(float(r["x"]) - target.x, float(r["z"]) - target.z).length()
        var v_target: float = 14.0
        if str(r["state"]) == "wait":
            v_target = 0.0
            r["t"] = float(r["t"]) + delta
            if float(r["t"]) > MC_RESPONDER_WAIT:
                node.queue_free()
                _mc_responders.remove_at(i)
                continue
        elif d < 14.0:
            r["state"] = "wait"
            r["t"] = 0.0
        _mc_chase_step(r, delta, target.x, target.z, v_target)
        _mc_flash(r)
