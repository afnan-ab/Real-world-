extends "res://scripts/mad_city_opt.gd"

# MadOut2-style services (stacked on the optimization layer):
#  - Safe zones (police station, hospital, the start block, inside buildings):
#    no shooting and no damage there, like MadOut2's invincible zones.
#  - Fixer: stand on the purple pad next to the police station while wanted
#    and pay to clear your record. MadOut2 charges 500 to 30,000 coins by
#    wanted level; the per-star prices below are my own steps in that range.
#  - QUALITY button: AUTO (dynamic resolution), LOW, HIGH. MadOut2 also lets the
#    player pick resolution, shadows and other effects by hand.
# Not in this phase: garages (repair / nitro need a car damage system), taxi and
# delivery jobs, hideouts, drone mode.

# x, z, radius
const MC_SAFE_ZONES: Array = [
    [-40.0, -38.0, 34.0],
    [-40.0, 28.0, 30.0],
    [40.0, 40.0, 34.0]
]
const MC_FIXER_PAD := Vector3(-56.0, 0.0, -24.0)
const MC_FIXER_PRICES: Array = [500, 2500, 7500, 15000, 30000]

var _svc_in_safe: bool = false
var _svc_fixer_cd: float = 0.0
var _svc_quality: int = 0
var _svc_quality_btn: Button

func _ready() -> void:
    super._ready()
    _mc_pad(MC_FIXER_PAD, Color("#b36bff"))
    _mc_label("FIXER  $500 - $30000", Vector3(MC_FIXER_PAD.x, MC_SLAB_TOP + 1.9, MC_FIXER_PAD.z), 0.0, 32)
    _svc_quality_btn = _mc_make_button("Q: AUTO", 0.80, 0.42, 0.89, 0.54)
    if _svc_quality_btn != null:
        _svc_quality_btn.pressed.connect(_svc_cycle_quality)

# ---------------------------------------------------------------------------
# Safe zones
# ---------------------------------------------------------------------------

func _svc_is_safe(p: Vector3) -> bool:
    if _mc_inside >= 0:
        return true
    for item in MC_SAFE_ZONES:
        var z: Array = item
        if Vector2(p.x - float(z[0]), p.z - float(z[1])).length() < float(z[2]):
            return true
    return false

func _mc_fire() -> void:
    if _player_ref != null and is_instance_valid(_player_ref) and _svc_is_safe(_player_ref.global_position):
        if _mc_fcd <= 0.0:
            _mc_fcd = 0.6
            _mc_say("Safe zone: no shooting")
        return
    super._mc_fire()

func _mc_hurt(amount: float) -> void:
    if _player_ref != null and is_instance_valid(_player_ref) and _svc_is_safe(_player_ref.global_position):
        return
    super._mc_hurt(amount)

# ---------------------------------------------------------------------------
# Fixer
# ---------------------------------------------------------------------------

func _svc_fixer_tick(delta: float) -> void:
    _svc_fixer_cd = maxf(0.0, _svc_fixer_cd - delta)
    if _svc_fixer_cd > 0.0 or _player_ref == null or not is_instance_valid(_player_ref):
        return
    var p: Vector3 = _player_ref.global_position
    if Vector2(p.x - MC_FIXER_PAD.x, p.z - MC_FIXER_PAD.z).length() > 1.7:
        return
    var stars: int = mini(5, int(ceilf(_mc_heat / 20.0)))
    _svc_fixer_cd = 2.5
    if stars <= 0:
        _mc_say("You are not wanted")
        return
    var price: int = int(MC_FIXER_PRICES[stars - 1])
    if _mc_money < price:
        _mc_say("Fixer needs $%d" % price)
        return
    _mc_money -= price
    _mc_heat = 0.0
    _mc_bust = 0.0
    _mc_clear_cops()
    _mc_update_cash()
    _mc_save_game()
    _mc_say("Record cleared  -$%d" % price)

# ---------------------------------------------------------------------------
# Quality button
# ---------------------------------------------------------------------------

func _svc_cycle_quality() -> void:
    _svc_quality = (_svc_quality + 1) % 3
    var names: Array = ["AUTO", "LOW", "HIGH"]
    if _svc_quality_btn != null:
        _svc_quality_btn.text = "Q: %s" % String(names[_svc_quality])
    _mc_say("Quality: %s" % String(names[_svc_quality]))

func _svc_enforce_quality() -> void:
    if _svc_quality == 0:
        return
    var vp: Viewport = get_viewport()
    var sun: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D
    if _svc_quality == 1:
        vp.scaling_3d_scale = 0.6
        if sun != null:
            sun.shadow_enabled = false
        if _mc_env != null:
            _mc_env.fog_enabled = false
    else:
        vp.scaling_3d_scale = 0.9
        if sun != null:
            sun.shadow_enabled = true
            sun.directional_shadow_max_distance = 60.0
        if _mc_env != null:
            _mc_env.fog_enabled = true

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
    super._process(delta)
    if _player_ref != null and is_instance_valid(_player_ref):
        var safe_now: bool = _svc_is_safe(_player_ref.global_position)
        if safe_now != _svc_in_safe:
            _svc_in_safe = safe_now
            if _mc_inside < 0:
                _mc_say("SAFE ZONE" if safe_now else "Leaving the safe zone")
    _svc_fixer_tick(delta)
    _svc_enforce_quality()
