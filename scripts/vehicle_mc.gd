extends "res://scripts/vehicle.gd"

# Same driveable car as vehicle.gd (that file is untouched). Changes:
#  - wider world boundary for the Mad City sized map
#  - if res://assets/models/car_1.glb exists it replaces the procedural body
#    (auto-fitted; set MC_CAR_FLIP to true if it drives backwards)

const AssetFit := preload("res://scripts/asset_fit.gd")
const MC_VEHICLE_LIMIT := 345.0
const MC_PLAYER_CAR_MODEL := "res://assets/models/car_1.glb"
const MC_CAR_FLIP := false

func _build_vehicle() -> void:
    super._build_vehicle()
    var model: Node3D = AssetFit.load_model(MC_PLAYER_CAR_MODEL, 4.4, false, MC_CAR_FLIP)
    if model == null or visual == null:
        return
    for child in visual.get_children():
        var n3: Node3D = child as Node3D
        if n3 != null:
            n3.visible = false
    visual.add_child(model)

func _clamp_to_world() -> void:
    var p: Vector3 = global_position
    p.x = clampf(p.x, -MC_VEHICLE_LIMIT, MC_VEHICLE_LIMIT)
    p.z = clampf(p.z, -MC_VEHICLE_LIMIT, MC_VEHICLE_LIMIT)
    if p != global_position:
        global_position = p
