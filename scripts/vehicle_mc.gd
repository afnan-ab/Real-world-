extends "res://scripts/vehicle.gd"

# Same driveable car as vehicle.gd (that file is untouched). The only change is
# a wider world boundary so cars can use the whole Mad City sized map.

const MC_VEHICLE_LIMIT := 345.0

func _clamp_to_world() -> void:
    var p: Vector3 = global_position
    p.x = clampf(p.x, -MC_VEHICLE_LIMIT, MC_VEHICLE_LIMIT)
    p.z = clampf(p.z, -MC_VEHICLE_LIMIT, MC_VEHICLE_LIMIT)
    if p != global_position:
        global_position = p
