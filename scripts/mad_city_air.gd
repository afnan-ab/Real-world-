extends "res://scripts/mad_city_combat.gd"

# Mad City port - Phase 6: helicopter on a helipad (stacked on Phase 5).
# Walk to the helipad in the park block east-north of the start (x 120, z -40),
# press DRIVE next to the helicopter. GAS = climb, BRAKE = descend, joystick =
# fly / turn, EXIT to get out. Flying speed and handling are my own values.
# Not in this phase: jet, boat, tank, rocket launcher (they need the bigger
# Mad City map: lake, desert, highways).

const MC_HELIPAD := Vector3(120.0, 0.0, -40.0)

func _ready() -> void:
    super._ready()
    _mc_build_helipad()

func _mc_build_helipad() -> void:
    var top: float = 0.4
    var pad := MeshInstance3D.new()
    var cm := CylinderMesh.new()
    cm.top_radius = 9.0
    cm.bottom_radius = 9.0
    cm.height = 0.06
    pad.mesh = cm
    pad.material_override = _mat(Color("#3c4046"), 0.9)
    pad.position = Vector3(MC_HELIPAD.x, top, MC_HELIPAD.z)
    pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(pad)
    var white: StandardMaterial3D = _mat(Color("#f2f2ee"), 0.7)
    for part in [[Vector3(-2.2, 0.0, 0.0), Vector3(0.8, 0.05, 5.6)], [Vector3(2.2, 0.0, 0.0), Vector3(0.8, 0.05, 5.6)], [Vector3(0.0, 0.0, 0.0), Vector3(4.4, 0.05, 0.8)]]:
        var pp: Array = part
        var offset: Vector3 = pp[0]
        var size: Vector3 = pp[1]
        _box(Vector3(MC_HELIPAD.x + offset.x, top + 0.05, MC_HELIPAD.z + offset.z), size, white, false)
    _mc_label("HELIPAD  -  DRIVE to fly", Vector3(MC_HELIPAD.x, top + 2.4, MC_HELIPAD.z + 10.5), PI, 40)

    var heli := CharacterBody3D.new()
    heli.name = "Helicopter"
    heli.set_script(load("res://scripts/heli_mc.gd"))
    heli.position = Vector3(MC_HELIPAD.x, top + 0.5, MC_HELIPAD.z)
    add_child(heli)
    heli.call("set_vehicle_color", Color("#c9362d"))
    driveable_vehicles.append(heli)

# Flying high above traffic must not count as hitting cars.
func _mc_check_crashes(veh: Node3D, speed_ms: float) -> void:
    if bool(veh.get("is_heli")) and veh.global_position.y > 3.0:
        return
    super._mc_check_crashes(veh, speed_ms)
