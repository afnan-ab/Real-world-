extends "res://scripts/mad_city_graphics.gd"

# Mad City port - Phase 5: health, weapons, shooting, cops shoot back, WASTED,
# hospital heal ($60) and an Ammu-Nation kiosk. Stacked on the graphics pass.
# Weapon numbers (damage, fire rate, heat, range) come from Mad_City.html's WP
# table. Simplifications: no magazines / reload (ammo only), shop prices and
# the sniper / shotgun spread are my own values, hits are tested along the
# camera ray (no bullet physics). Rocket launcher, tank, helicopter, jet and
# boat are NOT in this phase.

const MC_WEAPONS: Array = [
    {"n": "PISTOL", "d": 35.0, "cd": 0.28, "h": 5.0, "r": 45.0, "cone": 0.0, "price": 0},
    {"n": "SMG", "d": 20.0, "cd": 0.08, "h": 3.0, "r": 50.0, "cone": 0.0, "price": 250},
    {"n": "SHOTGUN", "d": 70.0, "cd": 0.8, "h": 10.0, "r": 22.0, "cone": 0.1, "price": 400},
    {"n": "ASSAULT RIFLE", "d": 30.0, "cd": 0.095, "h": 4.0, "r": 60.0, "cone": 0.0, "price": 800},
    {"n": "SNIPER", "d": 220.0, "cd": 1.1, "h": 14.0, "r": 280.0, "cone": 0.03, "price": 1500}
]
const MC_AMMO_PACK := 30
const MC_AMMO_PRICE := 40
const MC_AMMO_CAP := 240
const MC_HEAL_PRICE := 60
const MC_WASTED_FEE := 300
const MC_AMMO_PAD := Vector3(54.0, 0.0, 15.5)
const MC_GUN_PAD := Vector3(62.0, 0.0, 15.5)

var _mc_hp: float = 100.0
var _mc_wi: int = 0
var _mc_owned: Array = [true, false, false, false, false]
var _mc_ammo: Array = [36, 0, 0, 0, 0]
var _mc_fcd: float = 0.0
var _mc_fire_held: bool = false
var _mc_shop_cd: float = 0.0
var _mc_combat_label: Label

func _ready() -> void:
    super._ready()
    _mc_make_combat_hud()
    _mc_build_kiosk()
    _mc_update_combat_label()

# ---------------------------------------------------------------------------
# Save game now also stores weapons and ammo (Phase 3 stored cash only)
# ---------------------------------------------------------------------------

func _mc_save_game() -> void:
    var f: FileAccess = FileAccess.open(MC_SAVE_PATH, FileAccess.WRITE)
    if f == null:
        return
    f.store_string(JSON.stringify({"money": _mc_money, "owned": _mc_owned, "ammo": _mc_ammo, "version": 2}))
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
        var owned_v: Variant = dict.get("owned", null)
        var ammo_v: Variant = dict.get("ammo", null)
        if owned_v is Array and (owned_v as Array).size() == MC_WEAPONS.size():
            var oa: Array = owned_v
            for i in range(oa.size()):
                _mc_owned[i] = bool(oa[i])
        if ammo_v is Array and (ammo_v as Array).size() == MC_WEAPONS.size():
            var aa: Array = ammo_v
            for i in range(aa.size()):
                _mc_ammo[i] = int(aa[i])

# ---------------------------------------------------------------------------
# HUD: HP / weapon label, FIRE and WEAPON buttons
# ---------------------------------------------------------------------------

func _mc_make_button(text_value: String, al: float, at: float, ar: float, ab: float) -> Button:
    var hud: Node = get_node_or_null("HUD")
    if hud == null:
        return null
    var b := Button.new()
    b.text = text_value
    b.anchor_left = al
    b.anchor_top = at
    b.anchor_right = ar
    b.anchor_bottom = ab
    b.offset_left = 0.0
    b.offset_top = 0.0
    b.offset_right = 0.0
    b.offset_bottom = 0.0
    b.add_theme_font_size_override("font_size", 15)
    hud.add_child(b)
    return b

func _mc_make_combat_hud() -> void:
    var hud: Node = get_node_or_null("HUD")
    if hud == null:
        return
    _mc_combat_label = Label.new()
    _mc_combat_label.name = "Combat"
    _mc_combat_label.position = Vector2(455.0, 138.0)
    _mc_combat_label.add_theme_font_size_override("font_size", 16)
    _mc_combat_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.9))
    hud.add_child(_mc_combat_label)
    var fire_btn: Button = _mc_make_button("FIRE", 0.80, 0.56, 0.89, 0.68)
    if fire_btn != null:
        fire_btn.button_down.connect(func() -> void: _mc_fire_held = true)
        fire_btn.button_up.connect(func() -> void: _mc_fire_held = false)
    var weapon_btn: Button = _mc_make_button("WEAPON", 0.90, 0.56, 0.99, 0.68)
    if weapon_btn != null:
        weapon_btn.pressed.connect(_mc_next_weapon)

func _mc_update_combat_label() -> void:
    if _mc_combat_label == null:
        return
    var w: Dictionary = MC_WEAPONS[_mc_wi]
    _mc_combat_label.text = "HP %d   %s  %d" % [int(ceilf(_mc_hp)), String(w["n"]), int(_mc_ammo[_mc_wi])]

func _mc_next_weapon() -> void:
    for step in range(1, MC_WEAPONS.size() + 1):
        var idx: int = (_mc_wi + step) % MC_WEAPONS.size()
        if bool(_mc_owned[idx]):
            _mc_wi = idx
            break
    _mc_update_combat_label()

# ---------------------------------------------------------------------------
# Kiosk (Ammu-Nation) near the start
# ---------------------------------------------------------------------------

func _mc_pad(pos: Vector3, col: Color) -> void:
    var m := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 1.3
    cm.bottom_radius = 1.3
    cm.height = 0.05
    m.mesh = cm
    m.material_override = _mat(col, 0.3, 0.0, col)
    m.position = Vector3(pos.x, MC_SLAB_TOP + 0.04, pos.z)
    m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(m)

func _mc_build_kiosk() -> void:
    var base: float = MC_SLAB_TOP
    _box(Vector3(58.0, base + 0.6, 17.4), Vector3(14.0, 1.2, 1.2), _mat(Color("#2b2f35"), 0.7), true)
    _box(Vector3(58.0, base + 3.2, 17.8), Vector3(14.0, 0.5, 0.3), _mat(Color("#b8442e"), 0.6), false)
    _mc_label("AMMU-NATION", Vector3(58.0, base + 3.2, 17.6), PI, 40)
    _mc_pad(MC_AMMO_PAD, Color("#6ab0ff"))
    _mc_pad(MC_GUN_PAD, Color("#ff9a3c"))
    _mc_label("AMMO  $%d" % MC_AMMO_PRICE, Vector3(MC_AMMO_PAD.x, base + 1.9, MC_AMMO_PAD.z), PI, 32)
    _mc_label("NEW GUN", Vector3(MC_GUN_PAD.x, base + 1.9, MC_GUN_PAD.z), PI, 32)

func _mc_shop_tick(p: Vector3) -> void:
    if _mc_shop_cd > 0.0 or _mc_inside >= 0:
        return
    if Vector2(p.x - MC_AMMO_PAD.x, p.z - MC_AMMO_PAD.z).length() < 1.6:
        _mc_shop_cd = 2.0
        if int(_mc_ammo[_mc_wi]) >= MC_AMMO_CAP:
            _mc_say("Ammo is full")
        elif _mc_money < MC_AMMO_PRICE:
            _mc_say("Not enough cash ($%d)" % MC_AMMO_PRICE)
        else:
            _mc_money -= MC_AMMO_PRICE
            _mc_ammo[_mc_wi] = mini(MC_AMMO_CAP, int(_mc_ammo[_mc_wi]) + MC_AMMO_PACK)
            _mc_update_cash()
            _mc_update_combat_label()
            _mc_save_game()
            _mc_say("+%d ammo" % MC_AMMO_PACK)
    elif Vector2(p.x - MC_GUN_PAD.x, p.z - MC_GUN_PAD.z).length() < 1.6:
        _mc_shop_cd = 2.0
        var next_idx: int = -1
        for i in range(MC_WEAPONS.size()):
            if not bool(_mc_owned[i]):
                next_idx = i
                break
        if next_idx < 0:
            _mc_say("You own every gun")
            return
        var w: Dictionary = MC_WEAPONS[next_idx]
        var price: int = int(w["price"])
        if _mc_money < price:
            _mc_say("%s costs $%d" % [String(w["n"]), price])
        else:
            _mc_money -= price
            _mc_owned[next_idx] = true
            _mc_ammo[next_idx] = int(_mc_ammo[next_idx]) + 60
            _mc_wi = next_idx
            _mc_update_cash()
            _mc_update_combat_label()
            _mc_save_game()
            _mc_say("Bought %s" % String(w["n"]))

# ---------------------------------------------------------------------------
# Shooting
# ---------------------------------------------------------------------------

func _mc_tracer(from: Vector3, to: Vector3) -> void:
    var length: float = from.distance_to(to)
    if length < 0.2:
        return
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(0.05, 0.05, length)
    mi.mesh = bm
    var mat := StandardMaterial3D.new()
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.albedo_color = Color(1.0, 0.9, 0.45)
    mi.material_override = mat
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)
    mi.global_position = (from + to) * 0.5
    mi.look_at(to, Vector3.UP)
    get_tree().create_timer(0.06).timeout.connect(mi.queue_free)

func _mc_find_target(origin: Vector3, dir: Vector3, max_len: float, cone: float) -> Dictionary:
    var best: Dictionary = {}
    var best_t: float = max_len
    var cand: Array = []
    for c in _mc_cops:
        cand.append([c, "cop", 2.0])
    for c in traffic:
        cand.append([c, "car", 2.0])
    for c in npcs:
        cand.append([c, "ped", 0.7])
    for item in cand:
        var data: Dictionary = item[0]
        var node: Node3D = data["node"]
        if not is_instance_valid(node):
            continue
        if float(data.get("hp", 1.0)) <= 0.0:
            continue
        var v: Vector3 = node.global_position + Vector3(0.0, 1.0, 0.0) - origin
        var along: float = v.dot(dir)
        if along < 1.0 or along > best_t:
            continue
        var perp: float = (v - dir * along).length()
        if perp < float(item[2]) + along * cone:
            best_t = along
            best = {"data": data, "kind": String(item[1]), "t": along}
    return best

func _mc_remove_from(list: Array, data: Dictionary) -> void:
    for i in range(list.size() - 1, -1, -1):
        var d: Dictionary = list[i]
        if d["node"] == data["node"]:
            list.remove_at(i)
            return

func _mc_apply_hit(hit: Dictionary, dmg: float) -> void:
    var data: Dictionary = hit["data"]
    var kind: String = hit["kind"]
    var base_hp: float = 60.0 if kind == "ped" else 100.0
    var hp: float = float(data.get("hp", base_hp)) - dmg
    data["hp"] = hp
    if hp > 0.0:
        return
    var node: Node3D = data["node"]
    if kind == "cop":
        if is_instance_valid(node):
            node.queue_free()
        _mc_remove_from(_mc_cops, data)
        _mc_heat = minf(100.0, _mc_heat + 15.0)
        _mc_say("Cop down!")
    elif kind == "car":
        data["stun"] = 99999.0
        data["wreck_t"] = 0.0
        _mc_heat = minf(100.0, _mc_heat + 15.0)
        if is_instance_valid(node):
            _mc_crashes.append({"pos": node.position, "t": 0.0})
        _mc_say("Car wrecked!")
    else:
        if is_instance_valid(node):
            node.queue_free()
        _mc_remove_from(npcs, data)
        _mc_heat = minf(100.0, _mc_heat + 10.0)

func _mc_fire() -> void:
    if _mc_fcd > 0.0 or _player_ref == null or not is_instance_valid(_player_ref):
        return
    if _mc_inside >= 0:
        return
    if bool(_player_ref.get("in_vehicle")):
        _mc_fcd = 0.5
        _mc_say("Get out of the car to shoot")
        return
    var w: Dictionary = MC_WEAPONS[_mc_wi]
    if int(_mc_ammo[_mc_wi]) <= 0:
        _mc_fcd = 0.4
        _mc_say("No ammo! Buy at AMMU-NATION")
        return
    _mc_ammo[_mc_wi] = int(_mc_ammo[_mc_wi]) - 1
    _mc_fcd = float(w["cd"])
    var cam: Camera3D = get_viewport().get_camera_3d()
    if cam == null:
        return
    var origin: Vector3 = cam.global_position
    var dir: Vector3 = -cam.global_transform.basis.z
    var reach: float = float(w["r"])
    var muzzle: Vector3 = _player_ref.global_position + Vector3(0.0, 1.3, 0.0)
    var hit: Dictionary = _mc_find_target(origin, dir, reach + 8.0, float(w["cone"]))
    var end_point: Vector3 = origin + dir * reach
    if not hit.is_empty():
        end_point = origin + dir * float(hit["t"])
        _mc_apply_hit(hit, float(w["d"]))
    _mc_tracer(muzzle, end_point)
    _mc_heat = minf(100.0, _mc_heat + float(w["h"]))
    _mc_update_combat_label()

# ---------------------------------------------------------------------------
# Damage to the player, WASTED, hospital heal
# ---------------------------------------------------------------------------

func _mc_hurt(amount: float) -> void:
    var scaled: float = amount
    if bool(_player_ref.get("in_vehicle")):
        scaled *= 0.5
    _mc_hp -= scaled
    if _mc_hp <= 0.0:
        _mc_wasted()
    _mc_update_combat_label()

func _mc_wasted() -> void:
    _mc_hp = 100.0
    _mc_heat = 0.0
    _mc_clear_cops()
    _mc_money = maxi(0, _mc_money - MC_WASTED_FEE)
    _mc_update_cash()
    if _player_ref != null and is_instance_valid(_player_ref):
        if bool(_player_ref.get("in_vehicle")):
            toggle_vehicle(_player_ref)
        _mc_inside = -1
        _mc_door_idx = -1
        _mc_teleport_player(Vector3(-40.0, 1.4, 18.8))
    _mc_save_game()
    _mc_say("WASTED! Hospital bill -$%d" % MC_WASTED_FEE)

func _mc_life_tick(delta: float) -> void:
    # Hospital heal first, so the Phase 3 "You are healthy" message does not fire.
    if _mc_inside == 1 and _mc_cd <= 0.0 and _player_ref != null and is_instance_valid(_player_ref):
        var p: Vector3 = _player_ref.global_position
        var cx: float = float(MC_INTERIOR_X[1])
        if Vector2(p.x - cx, p.z).distance_to(Vector2(3.2, -3.6)) < 1.4:
            _mc_cd = 3.0
            if _mc_hp >= 100.0:
                _mc_say("You are healthy")
            elif _mc_money < MC_HEAL_PRICE:
                _mc_say("Heal costs $%d" % MC_HEAL_PRICE)
            else:
                _mc_money -= MC_HEAL_PRICE
                _mc_hp = 100.0
                _mc_update_cash()
                _mc_update_combat_label()
                _mc_say("Healed  -$%d" % MC_HEAL_PRICE)
    super._mc_life_tick(delta)

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
    super._process(delta)
    _mc_combat_tick(delta)

func _mc_combat_tick(delta: float) -> void:
    if _player_ref == null or not is_instance_valid(_player_ref):
        return
    _mc_fcd = maxf(0.0, _mc_fcd - delta)
    _mc_shop_cd = maxf(0.0, _mc_shop_cd - delta)
    if _mc_fire_held:
        _mc_fire()
    var p: Vector3 = _player_ref.global_position
    _mc_shop_tick(p)

    var stars: int = mini(5, int(ceilf(_mc_heat / 20.0)))
    # Cops with 2+ stars shoot when they are close.
    if stars >= 2 and _mc_inside < 0:
        for item in _mc_cops:
            var c: Dictionary = item
            var node: Node3D = c["node"]
            if not is_instance_valid(node):
                continue
            var d: float = Vector2(float(c["x"]) - p.x, float(c["z"]) - p.z).length()
            if d > 28.0:
                continue
            var t: float = float(c.get("shoot_t", 0.5)) - delta
            if t <= 0.0:
                t = 0.9 + rng.randf() * 0.6
                if rng.randf() < 0.45:
                    _mc_hurt(4.0 + float(stars) * 2.0)
            c["shoot_t"] = t

    # Wrecked traffic cars come back as new cars after a while.
    for item in traffic:
        var a: Dictionary = item
        if float(a.get("hp", 100.0)) > 0.0:
            continue
        var wt: float = float(a.get("wreck_t", 0.0)) + delta
        a["wreck_t"] = wt
        if wt > 12.0:
            var j: Vector2 = _mc_pick_junction(p.x, p.z, 120.0)
            var dv: Vector2 = _mc_best_dir(j.x, j.y, 0.0, 0.0)
            _mc_place(a, j.x, j.y, dv)
            a["hp"] = 100.0
            a["stun"] = 0.0
            a["wreck_t"] = 0.0
