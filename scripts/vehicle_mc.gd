extends "res://scripts/vehicle.gd"

# Same driveable car as vehicle.gd (that file is untouched). Changes:
#  - wider world boundary for the Mad City sized map
#  - if res://assets/models/car_1.glb (or sedan.glb from the Kenney Car Kit)
#    exists it replaces the procedural body (auto-fitted; set MC_CAR_FLIP to
#    true if it drives backwards). If the model has no colour texture it is
#    painted with the car's colour.
#  - GTA-style chase camera: the camera no longer sticks rigidly to the car,
#    it follows behind and lags a little when the car turns (the speed FOV
#    from vehicle.gd still applies).
#  - tail lights and head lights glow (emission) so they stand out at night.

const AssetFit := preload("res://scripts/asset_fit.gd")
const MC_VEHICLE_LIMIT := 345.0
const MC_PLAYER_CAR_PATHS: Array = ["res://assets/models/car_1.glb", "res://assets/models/sedan.glb"]
const MC_CAR_FLIP := false

const MC_CAM_BACK := 7.2
const MC_CAM_UP := 3.2
const MC_CAM_LAG := 3.5
const MC_CAM_LOOK_UP := 1.4

var _mc_cam_yaw: float = 0.0

func _ready() -> void:
    super._ready()
    if camera != null:
        camera.top_level = true

func _build_vehicle() -> void:
    super._build_vehicle()
    _mc_glow_lights()
    var path: String = ""
    for p in MC_PLAYER_CAR_PATHS:
        if ResourceLoader.exists(String(p)):
            path = String(p)
            break
    if path == "":
        return
    var model: Node3D = AssetFit.load_model(path, 4.4, false, MC_CAR_FLIP, setup_color)
    if model == null or visual == null:
        return
    for child in visual.get_children():
        var n3: Node3D = child as Node3D
        if n3 != null:
            n3.visible = false
    visual.add_child(model)

# Make the red tail lights and the pale head lights emissive.
func _mc_glow_lights() -> void:
    if visual == null:
        return
    var tail_col := Color("#d21f2f")
    var head_col := Color("#fff2c4")
    for child in visual.get_children():
        var mi: MeshInstance3D = child as MeshInstance3D
        if mi == null:
            continue
        var m: StandardMaterial3D = mi.material_override as StandardMaterial3D
        if m == null:
            continue
        if m.albedo_color == tail_col:
            m.emission_enabled = true
            m.emission = tail_col
            m.emission_energy_multiplier = 1.8
        elif m.albedo_color == head_col:
            m.emission_enabled = true
            m.emission = head_col
            m.emission_energy_multiplier = 1.3

func enter() -> void:
    super.enter()
    _mc_cam_yaw = rotation.y
    _mc_update_chase_cam(1.0)

func _physics_process(delta: float) -> void:
    super._physics_process(delta)
    if driving:
        _mc_update_chase_cam(delta)

# Camera sits behind the car; its heading follows the car with a small lag.
func _mc_update_chase_cam(delta: float) -> void:
    if camera == null or not camera.is_inside_tree():
        return
    var t: float = minf(1.0, delta * MC_CAM_LAG)
    _mc_cam_yaw = lerp_angle(_mc_cam_yaw, rotation.y, t)
    var behind := Vector3(sin(_mc_cam_yaw), 0.0, cos(_mc_cam_yaw))
    camera.global_position = global_position + behind * MC_CAM_BACK + Vector3(0.0, MC_CAM_UP, 0.0)
    camera.look_at(global_position + Vector3(0.0, MC_CAM_LOOK_UP, 0.0), Vector3.UP)

func _clamp_to_world() -> void:
    var p: Vector3 = global_position
    p.x = clampf(p.x, -MC_VEHICLE_LIMIT, MC_VEHICLE_LIMIT)
    p.z = clampf(p.z, -MC_VEHICLE_LIMIT, MC_VEHICLE_LIMIT)
    if p != global_position:
        global_position = p
