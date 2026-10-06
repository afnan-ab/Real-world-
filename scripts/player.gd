extends CharacterBody3D

@export var speed: float = 5.8
@export var sprint_speed: float = 9.5
@export var acceleration: float = 18.0
@export var gravity: float = 20.0
@export var camera_distance: float = 6.5
@export var look_sensitivity: float = 0.010

var joystick := Vector2.ZERO
var visual: Node3D
var left_arm: MeshInstance3D
var right_arm: MeshInstance3D
var left_leg: MeshInstance3D
var right_leg: MeshInstance3D
var camera: Camera3D
var walk_time: float = 0.0
var sprint_touch := false
var camera_yaw: float = 0.0
var camera_pitch: float = -0.16
var in_vehicle: bool = false
var vehicle: CharacterBody3D

func _ready() -> void:
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.8
    $CollisionShape3D.shape = capsule

    camera = $CameraPivot/Camera3D
    camera.position = Vector3(0.0, 2.6, camera_distance)
    camera.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
    camera.current = true

    _build_human()

func _build_human() -> void:
    # STEP 17: improved low-poly player character.
    # Keeps the existing lightweight procedural approach and walking animation,
    # but adds better proportions, layered clothing, rounded head and shoes.
    visual = Node3D.new()
    visual.name = "PlayerVisual"
    visual.position.y = 0.9
    add_child(visual)

    var skin := _mat(Color("#b97858"), 0.68)
    var skin_dark := _mat(Color("#8e5a46"), 0.76)
    var shirt := _mat(Color("#263b52"), 0.82)
    var shirt_dark := _mat(Color("#1d2d40"), 0.88)
    var pants := _mat(Color("#24282d"), 0.92)
    var shoes := _mat(Color("#111315"), 0.96)
    var sole := _mat(Color("#25282a"), 0.88)
    var hair := _mat(Color("#16181a"), 0.94)
    var eye := _mat(Color("#202020"), 0.35)

    _part(BoxMesh.new(), Vector3(0,0.55,0), Vector3(0.54,0.90,0.38), shirt)
    _part(BoxMesh.new(), Vector3(0,1.02,0), Vector3(0.60,0.18,0.42), shirt_dark)
    left_arm = _part(BoxMesh.new(), Vector3(-0.36,0.54,0), Vector3(0.16,0.72,0.17), shirt)
    right_arm = _part(BoxMesh.new(), Vector3(0.36,0.54,0), Vector3(0.16,0.72,0.17), shirt)
    _part(SphereMesh.new(), Vector3(-0.36,0.15,-0.01), Vector3(0.17,0.22,0.18), skin, true)
    _part(SphereMesh.new(), Vector3(0.36,0.15,-0.01), Vector3(0.17,0.22,0.18), skin, true)

    left_leg = _part(BoxMesh.new(), Vector3(-0.20,-0.40,0), Vector3(0.19,0.88,0.19), pants)
    right_leg = _part(BoxMesh.new(), Vector3(0.20,-0.40,0), Vector3(0.19,0.88,0.19), pants)
    _part(BoxMesh.new(), Vector3(-0.20,-0.90,-0.07), Vector3(0.25,0.14,0.46), shoes)
    _part(BoxMesh.new(), Vector3(0.20,-0.90,-0.07), Vector3(0.25,0.14,0.46), shoes)
    _part(BoxMesh.new(), Vector3(-0.20,-0.98,-0.07), Vector3(0.27,0.05,0.48), sole)
    _part(BoxMesh.new(), Vector3(0.20,-0.98,-0.07), Vector3(0.27,0.05,0.48), sole)

    _part(SphereMesh.new(), Vector3(0,1.34,0), Vector3(0.40,0.40,0.40), skin, true)
    _part(SphereMesh.new(), Vector3(0,1.55,0.01), Vector3(0.41,0.18,0.41), hair, true)
    _part(SphereMesh.new(), Vector3(0,1.27,-0.19), Vector3(0.13,0.08,0.06), skin_dark, true)
    _part(SphereMesh.new(), Vector3(-0.13,1.37,-0.18), Vector3(0.04,0.04,0.04), eye, true)
    _part(SphereMesh.new(), Vector3(0.13,1.37,-0.18), Vector3(0.04,0.04,0.04), eye, true)

func _part(mesh: Mesh, pos: Vector3, scale_v: Vector3, material: Material, sphere: bool = false) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    if sphere:
        var sm := SphereMesh.new()
        sm.radial_segments = 16
        sm.rings = 10
        mi.mesh = sm
    else:
        mi.mesh = mesh
    mi.position = pos
    mi.scale = scale_v
    mi.material_override = material
    visual.add_child(mi)
    return mi

func _mat(color: Color, rough: float = 0.8) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    return m

func enter_vehicle(target: CharacterBody3D) -> void:
    vehicle = target
    in_vehicle = true
    visible = false
    velocity = Vector3.ZERO

func exit_vehicle() -> void:
    if vehicle and is_instance_valid(vehicle):
        global_position = vehicle.global_position + vehicle.global_transform.basis.x * 2.8 + Vector3(0,0.2,0)
    visible = true
    in_vehicle = false
    vehicle = null
    reset_camera_look()
    camera.current = true

func set_joystick(v: Vector2) -> void:
    joystick = v

func set_sprint(enabled: bool) -> void:
    sprint_touch = enabled

func look_camera(delta_screen: Vector2) -> void:
    camera_yaw -= delta_screen.x * look_sensitivity
    camera_pitch = clamp(camera_pitch - delta_screen.y * look_sensitivity, -0.45, 0.12)
    $CameraPivot.rotation.y = camera_yaw
    camera.rotation.x = camera_pitch

func reset_camera_look() -> void:
    camera_yaw = 0.0
    camera_pitch = -0.16
    $CameraPivot.rotation.y = 0.0
    camera.rotation.x = camera_pitch

func _physics_process(delta: float) -> void:
    if in_vehicle:
        velocity = Vector3.ZERO
        return

    var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if joystick.length() > 0.08:
        input_vec = joystick

    var local_dir := Vector3(input_vec.x, 0.0, input_vec.y)
    if local_dir.length() > 1.0:
        local_dir = local_dir.normalized()

    var dir := Vector3.ZERO
    if local_dir.length() > 0.08:
        dir = Basis(Vector3.UP, camera_yaw) * local_dir
        dir.y = 0.0
        dir = dir.normalized()

    var current_speed := sprint_speed if (Input.is_action_pressed("ui_accept") or sprint_touch) else speed
    velocity.x = move_toward(velocity.x, dir.x * current_speed, acceleration * delta)
    velocity.z = move_toward(velocity.z, dir.z * current_speed, acceleration * delta)

    if dir.length() > 0.08:
        var yaw := atan2(dir.x, dir.z)
        visual.rotation.y = lerp_angle(visual.rotation.y, yaw, min(1.0, delta * 9.0))
        walk_time += delta * (11.0 if current_speed > speed else 7.5)
        var stride := sin(walk_time)
        var arm_stride := stride * 0.62
        var leg_stride := stride * 0.72
        left_arm.rotation.x = lerp(left_arm.rotation.x, arm_stride, delta * 12.0)
        right_arm.rotation.x = lerp(right_arm.rotation.x, -arm_stride, delta * 12.0)
        left_leg.rotation.x = lerp(left_leg.rotation.x, -leg_stride, delta * 12.0)
        right_leg.rotation.x = lerp(right_leg.rotation.x, leg_stride, delta * 12.0)
        visual.position.y = 0.9 + abs(stride) * 0.028
    else:
        visual.position.y = move_toward(visual.position.y, 0.9, delta * 4.0)
        left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 10.0)
        right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 10.0)
        left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 10.0)
        right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 10.0)

    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = 0.0

    move_and_slide()
