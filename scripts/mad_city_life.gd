extends "res://scripts/mad_city_police.gd"

# Mad City port - Phase 3: cash, save game, home, hospital, jail.
# Stacked on Phase 2. Ported rules from Mad_City.html:
#   BUSTED -> cash x 0.75 and 14 s in jail, then released at the police door;
#   home: bed = sleep (morning, heat cleared, game saved), desk = save;
#   hospital: green circle heals for $60 (there is no health bar yet, so it
#   says "You are healthy" until the health system arrives with weapons);
#   mission rewards now pay cash; heat drops 8/s while inside a building.
# Interiors are small rooms built far outside the map (x = 2000..2200) and the
# player is moved there, like the HTML does with its off-map interiors.
# Not in this phase: 24/7 mart + weapons/ammo (Phase 4), job board, garages.

const MC_INTERIOR_X: Array = [2000.0, 2100.0, 2200.0]
const MC_ROOM_W := 16.0
const MC_ROOM_D := 12.0
const MC_ROOM_H := 4.0
const MC_JAIL_TIME := 14.0
const MC_JAIL_EXIT := Vector3(-40.0, 1.4, -28.0)
const MC_SAVE_PATH := "user://madcity_godot.json"
const MC_DOORS: Array = [
    {"name": "HOME", "pos": Vector3(40.0, 0.0, 16.8), "exit": Vector3(40.0, 1.4, 14.2), "interior": 0, "msg": "HOME - sleep on the bed, save at the desk"},
    {"name": "HOSPITAL", "pos": Vector3(-40.0, 0.0, 21.2), "exit": Vector3(-40.0, 1.4, 18.8), "interior": 1, "msg": "HOSPITAL - heal at the green circle ($60)"}
]

var _mc_money: int = 0
var _mc_inside: int = -1
var _mc_door_idx: int = -1
var _mc_jail_t: float = 0.0
var _mc_cd: float = 0.0
var _mc_save_t: float = 0.0
var _mc_cash_label: Label

func _ready() -> void:
    super._ready()
    _mc_load_game()
    _mc_make_cash_label()
    _mc_build_home()
    _mc_build_hospital()
    _mc_build_police()
    _mc_build_door_markers()
    _mc_make_room(0, Color("#9a7b5a"), Color("#d9d2c2"))
    _mc_make_room(1, Color("#cfd6d8"), Color("#e8eef0"))
    _mc_make_room(2, Color("#55585b"), Color("#8b8f93"))
    _mc_build_interior_props()
    _mc_update_cash()

# Far-away interior rooms must not inherit the hill height of the outer terrain.
func _height(x: float, z: float) -> float:
    if maxf(absf(x), absf(z)) > 900.0:
        return 0.0
    return super._height(x, z)

# ---------------------------------------------------------------------------
# Cash, save game
# ---------------------------------------------------------------------------

func _mc_make_cash_label() -> void:
    var hud: Node = get_node_or_null("HUD")
    if hud == null:
        return
    _mc_cash_label = Label.new()
    _mc_cash_label.name = "Cash"
    _mc_cash_label.position = Vector2(455.0, 112.0)
    _mc_cash_label.add_theme_font_size_override("font_size", 18)
    _mc_cash_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
    hud.add_child(_mc_cash_label)

func _mc_update_cash() -> void:
    if _mc_cash_label != null:
        _mc_cash_label.text = "CASH  $%d" % _mc_money

func _mc_save_game() -> void:
    var f: FileAccess = FileAccess.open(MC_SAVE_PATH, FileAccess.WRITE)
    if f == null:
        return
    f.store_string(JSON.stringify({"money": _mc_money, "version": 1}))
    f.close()

func _mc_load_game() -> void:
    if not FileAccess.file_exists(MC_SAVE_PATH):
        return
    var f: FileAccess = FileAccess.open(MC_SAVE_PATH, FileAccess.READ)
    if f == null:
        return
    var parsed: Variant = JSON.parse_string(f.get_as_text())
    f.close()
    if parsed is Dictionary:
        var dict: Dictionary = parsed
        _mc_money = int(dict.get("money", 0))

# Missions now pay cash.
func get_mission_status(player_position: Vector3) -> String:
    var was_active: bool = mission_active
    var status: String = super.get_mission_status(player_position)
    if was_active and not mission_active:
        _mc_money += mission_reward
        _mc_update_cash()
        _mc_save_game()
    return status

# ---------------------------------------------------------------------------
# Exteriors: home cottage, hospital, police station
# ---------------------------------------------------------------------------

func _mc_label(text_value: String, pos: Vector3, yaw: float, font_px: int) -> void:
    var l := Label3D.new()
    l.text = text_value
    l.font_size = font_px
    l.pixel_size = 0.01
    l.outline_size = 8
    l.modulate = Color("#f4f1e6")
    l.position = pos
    l.rotation.y = yaw
    add_child(l)

func _mc_build_home() -> void:
    var wall: StandardMaterial3D = _mat(Color("#d8c9a8"), 0.9)
    var roof: StandardMaterial3D = _mat(Color("#7a2f27"), 0.85)
    var wood: StandardMaterial3D = _mat(Color("#5a3c24"), 0.8)
    var glass: StandardMaterial3D = _mat(Color("#2a4658"), 0.15, 0.3)
    var base: float = MC_SLAB_TOP
    _box(Vector3(40.0, base + 2.0, 24.0), Vector3(14.0, 4.0, 10.0), wall, true)
    _box(Vector3(40.0, base + 4.25, 24.0), Vector3(15.4, 0.5, 11.4), roof, false)
    _box(Vector3(43.0, base + 5.2, 26.0), Vector3(1.0, 1.6, 1.0), _mat(Color("#6a4a3e"), 0.9), false)
    _box(Vector3(40.0, base + 1.3, 18.9), Vector3(1.7, 2.6, 0.2), wood, false)
    _box(Vector3(35.5, base + 2.2, 18.95), Vector3(2.2, 1.5, 0.15), glass, false)
    _box(Vector3(44.5, base + 2.2, 18.95), Vector3(2.2, 1.5, 0.15), glass, false)
    _mc_label("HOME", Vector3(40.0, base + 3.4, 18.7), PI, 40)

func _mc_build_hospital() -> void:
    var wall: StandardMaterial3D = _mat(Color("#e9eef0"), 0.85)
    var red: StandardMaterial3D = _mat(Color("#c4231c"), 0.6)
    var glass: StandardMaterial3D = _mat(Color("#2a4658"), 0.15, 0.3)
    var base: float = MC_SLAB_TOP
    _box(Vector3(-40.0, base + 5.0, 28.5), Vector3(22.0, 10.0, 12.0), wall, true)
    _box(Vector3(-40.0, base + 10.25, 28.5), Vector3(22.8, 0.5, 12.8), _mat(Color("#8b8f93"), 0.9), false)
    _box(Vector3(-40.0, base + 7.2, 22.4), Vector3(1.0, 4.0, 0.2), red, false)
    _box(Vector3(-40.0, base + 7.2, 22.4), Vector3(4.0, 1.0, 0.2), red, false)
    _box(Vector3(-40.0, base + 1.4, 22.45), Vector3(2.4, 2.8, 0.2), glass, false)
    for wx in [-47.0, -33.0]:
        for wy in [3.5, 6.5]:
            _box(Vector3(float(wx), base + float(wy), 22.45), Vector3(2.4, 1.6, 0.15), glass, false)
    _mc_label("HOSPITAL", Vector3(-40.0, base + 9.2, 22.3), PI, 48)

func _mc_build_police() -> void:
    var wall: StandardMaterial3D = _mat(Color("#5d6c80"), 0.85)
    var glass: StandardMaterial3D = _mat(Color("#2a4658"), 0.15, 0.3)
    var base: float = MC_SLAB_TOP
    _box(Vector3(-40.0, base + 5.0, -38.0), Vector3(22.0, 10.0, 12.0), wall, true)
    _box(Vector3(-40.0, base + 10.25, -38.0), Vector3(22.8, 0.5, 12.8), _mat(Color("#2b3038"), 0.9), false)
    _box(Vector3(-40.0, base + 1.4, -31.9), Vector3(2.4, 2.8, 0.2), glass, false)
    for wx in [-47.0, -33.0]:
        for wy in [3.5, 6.5]:
            _box(Vector3(float(wx), base + float(wy), -31.9), Vector3(2.4, 1.6, 0.15), glass, false)
    _mc_label("POLICE", Vector3(-40.0, base + 9.2, -31.7), 0.0, 48)

func _mc_build_door_markers() -> void:
    for item in MC_DOORS:
        var d: Dictionary = item
        var dp: Vector3 = d["pos"]
        var m := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(2.2, 0.06, 2.2)
        m.mesh = bm
        m.material_override = _mat(Color("#37d5e8"), 0.3, 0.0, Color("#37d5e8"))
        m.position = Vector3(dp.x, MC_SLAB_TOP + 0.05, dp.z)
        m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(m)

# ---------------------------------------------------------------------------
# Interiors (small rooms far outside the map)
# ---------------------------------------------------------------------------

func _mc_solid(pos: Vector3, size: Vector3, mat: Material) -> void:
    _box(pos, size, mat, false)
    var body := StaticBody3D.new()
    body.position = pos
    var cs := CollisionShape3D.new()
    var shp := BoxShape3D.new()
    shp.size = size
    cs.shape = shp
    body.add_child(cs)
    add_child(body)

func _mc_make_room(idx: int, floor_col: Color, wall_col: Color) -> void:
    var cx: float = float(MC_INTERIOR_X[idx])
    var floor_mat: StandardMaterial3D = _mat(floor_col, 0.8)
    var wall_mat: StandardMaterial3D = _mat(wall_col, 0.9)
    var hw: float = MC_ROOM_W * 0.5
    var hd: float = MC_ROOM_D * 0.5
    _mc_solid(Vector3(cx, 0.1, 0.0), Vector3(MC_ROOM_W, 0.2, MC_ROOM_D), floor_mat)
    _mc_solid(Vector3(cx, MC_ROOM_H + 0.3, 0.0), Vector3(MC_ROOM_W, 0.2, MC_ROOM_D), wall_mat)
    _mc_solid(Vector3(cx, 2.3, -hd), Vector3(MC_ROOM_W, 4.2, 0.3), wall_mat)
    _mc_solid(Vector3(cx, 2.3, hd), Vector3(MC_ROOM_W, 4.2, 0.3), wall_mat)
    _mc_solid(Vector3(cx - hw, 2.3, 0.0), Vector3(0.3, 4.2, MC_ROOM_D), wall_mat)
    _mc_solid(Vector3(cx + hw, 2.3, 0.0), Vector3(0.3, 4.2, MC_ROOM_D), wall_mat)
    var lamp := OmniLight3D.new()
    lamp.position = Vector3(cx, 3.4, 0.0)
    lamp.omni_range = 14.0
    lamp.light_energy = 1.3
    add_child(lamp)
    # Exit marker next to the door wall.
    var exit_mark := MeshInstance3D.new()
    var em := BoxMesh.new()
    em.size = Vector3(2.4, 0.05, 1.6)
    exit_mark.mesh = em
    exit_mark.material_override = _mat(Color("#37d5e8"), 0.3, 0.0, Color("#37d5e8"))
    exit_mark.position = Vector3(cx, 0.22, hd - 0.9)
    add_child(exit_mark)
    _mc_label("EXIT  (ACTION)", Vector3(cx, 2.2, hd - 0.25), PI, 36)

func _mc_circle(pos: Vector3, col: Color, caption: String) -> void:
    var m := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 1.2
    cm.bottom_radius = 1.2
    cm.height = 0.05
    m.mesh = cm
    m.material_override = _mat(col, 0.3, 0.0, col)
    m.position = pos
    add_child(m)
    _mc_label(caption, pos + Vector3(0.0, 1.4, 0.0), 0.0, 36)

func _mc_build_interior_props() -> void:
    var home_x: float = float(MC_INTERIOR_X[0])
    var bed_mat: StandardMaterial3D = _mat(Color("#c98aa0"), 0.8)
    var desk_mat: StandardMaterial3D = _mat(Color("#6b4a2f"), 0.8)
    _mc_solid(Vector3(home_x - 5.0, 0.55, -4.2), Vector3(2.4, 0.7, 3.6), bed_mat)
    _mc_solid(Vector3(home_x + 5.0, 0.7, -4.6), Vector3(3.2, 1.0, 1.4), desk_mat)
    _mc_circle(Vector3(home_x - 5.0, 0.25, -2.0), Color("#ff8fb8"), "BED - SLEEP")
    _mc_circle(Vector3(home_x + 5.0, 0.25, -2.0), Color("#6ab0ff"), "DESK - SAVE")
    var hosp_x: float = float(MC_INTERIOR_X[1])
    _mc_solid(Vector3(hosp_x - 5.0, 0.5, -3.5), Vector3(2.0, 0.6, 3.8), _mat(Color("#dfe7ea"), 0.8))
    _mc_circle(Vector3(hosp_x + 3.2, 0.25, -3.6), Color("#58e07a"), "HEAL $60")
    var jail_x: float = float(MC_INTERIOR_X[2])
    _mc_solid(Vector3(jail_x - 5.5, 0.4, -4.0), Vector3(2.0, 0.5, 3.6), _mat(Color("#7b6a55"), 0.9))
    _mc_label("JAIL CELL", Vector3(jail_x, 3.0, -5.7), 0.0, 48)

# ---------------------------------------------------------------------------
# Entering, leaving, busted -> jail
# ---------------------------------------------------------------------------

func _mc_nearest_door(p: Vector3) -> int:
    for i in range(MC_DOORS.size()):
        var d: Dictionary = MC_DOORS[i]
        var dp: Vector3 = d["pos"]
        if Vector2(p.x - dp.x, p.z - dp.z).length() < 3.2:
            return i
    return -1

func _mc_teleport_player(pos: Vector3) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        return
    _player_ref.global_position = pos
    _player_ref.set("velocity", Vector3.ZERO)

func _mc_enter_building(idx: int) -> void:
    var d: Dictionary = MC_DOORS[idx]
    _mc_door_idx = idx
    _mc_inside = int(d["interior"])
    _mc_teleport_player(Vector3(float(MC_INTERIOR_X[_mc_inside]), 1.4, 3.4))
    _mc_say(String(d["msg"]))

func _mc_leave_building() -> void:
    var target: Vector3 = MC_JAIL_EXIT
    if _mc_door_idx >= 0:
        var d: Dictionary = MC_DOORS[_mc_door_idx]
        target = d["exit"]
    _mc_inside = -1
    _mc_door_idx = -1
    _mc_teleport_player(target)

func _on_hud_action_pressed() -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        super._on_hud_action_pressed()
        return
    if _mc_inside >= 0:
        if _mc_inside == 2:
            _mc_say("Serving time: %ds" % int(ceilf(_mc_jail_t)))
            return
        var cx: float = float(MC_INTERIOR_X[_mc_inside])
        var p: Vector3 = _player_ref.global_position
        if Vector2(p.x - cx, p.z - (MC_ROOM_D * 0.5 - 0.9)).length() < 3.5:
            _mc_leave_building()
        else:
            _mc_say("Walk to the cyan exit at the door")
        return
    var door: int = _mc_nearest_door(_player_ref.global_position)
    if door >= 0 and not bool(_player_ref.get("in_vehicle")):
        _mc_enter_building(door)
        return
    super._on_hud_action_pressed()

func _mc_busted() -> void:
    super._mc_busted()
    _mc_money = int(floorf(float(_mc_money) * 0.75))
    _mc_update_cash()
    _mc_inside = 2
    _mc_door_idx = -1
    _mc_jail_t = MC_JAIL_TIME
    _mc_teleport_player(Vector3(float(MC_INTERIOR_X[2]), 1.4, 2.0))
    _mc_say("BUSTED! -25% cash. Serving time...")
    _mc_save_game()

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
    super._process(delta)
    _mc_life_tick(delta)

func _mc_life_tick(delta: float) -> void:
    _mc_save_t += delta
    if _mc_save_t > 5.0:
        _mc_save_t = 0.0
        _mc_save_game()
    _mc_cd = maxf(0.0, _mc_cd - delta)
    if _mc_inside < 0 or _player_ref == null or not is_instance_valid(_player_ref):
        return
    _mc_heat = maxf(0.0, _mc_heat - 8.0 * delta)
    var cx: float = float(MC_INTERIOR_X[_mc_inside])
    var p: Vector3 = _player_ref.global_position
    var local := Vector2(p.x - cx, p.z)
    if _mc_inside == 0 and _mc_cd <= 0.0:
        if local.distance_to(Vector2(-5.0, -2.0)) < 1.4:
            _mc_cd = 3.0
            time_of_day = 5.3
            _mc_heat = 0.0
            _mc_save_game()
            _mc_say("Good morning! Game saved")
        elif local.distance_to(Vector2(5.0, -2.0)) < 1.4:
            _mc_cd = 3.0
            _mc_save_game()
            _mc_say("Game saved")
    elif _mc_inside == 1 and _mc_cd <= 0.0:
        if local.distance_to(Vector2(3.2, -3.6)) < 1.4:
            _mc_cd = 3.0
            _mc_say("You are healthy")
    elif _mc_inside == 2:
        _mc_jail_t -= delta
        _set_hud_label("Mission", "SERVING TIME  •  %ds" % int(ceilf(maxf(_mc_jail_t, 0.0))))
        if _mc_jail_t <= 0.0:
            _mc_inside = -1
            _mc_teleport_player(MC_JAIL_EXIT)
            _mc_say("Released! Stay out of trouble")
