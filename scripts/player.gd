extends CharacterBody3D

# Third-person player for the mobile open world.
# Fixes in this pass:
#  - jump actually works (buffered + coyote time, no air-jumping)
#  - model is human sized, stands on the ground and faces the walking direction
#  - limbs are pivoted at shoulders/hips so they swing properly
#  - player follows the vehicle while driving and its collider is disabled
#  - player is kept inside the world bounds

@export var speed: float = 5.8
@export var sprint_speed: float = 9.5
@export var acceleration: float = 18.0
@export var gravity: float = 20.0
@export var jump_velocity: float = 7.5
@export var camera_distance: float = 7.5
@export var look_sensitivity: float = 0.010

const WORLD_LIMIT := 208.0
const VISUAL_SCALE := 0.70
const VISUAL_Y := -0.20
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.15

var joystick: Vector2 = Vector2.ZERO
var sprint_touch: bool = false
var camera_yaw: float = 0.0
var camera_pitch: float = -0.34
var walk_time: float = 0.0
var in_vehicle: bool = false
var vehicle: CharacterBody3D = null
var jump_buffer: float = 0.0
var coyote_timer: float = 0.0

var camera_pivot: Node3D
var camera: Camera3D
var collision_shape: CollisionShape3D
var visual: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D

func _ready() -> void:
    collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.8
    if collision_shape != null:
        collision_shape.shape = capsule
    floor_snap_length = 0.45
    floor_max_angle = deg_to_rad(52.0)
    safe_margin = 0.04
    camera_pivot = get_node_or_null("CameraPivot") as Node3D
    camera = get_node_or_null("CameraPivot/Camera3D") as Camera3D
    if camera_pivot != null:
        camera_pivot.position = Vector3(0.0, 1.0, 0.0)
    if camera != null:
        camera.position = Vector3(0.0, 1.4, camera_distance)
        camera.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
        camera.fov = 68.0
        camera.current = true
    _build_human()
    _apply_camera()

func _part(parent: Node3D, pos: Vector3, scale_v: Vector3, material: Material, sphere: bool = false) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    if sphere:
        mi.mesh = SphereMesh.new()
    else:
        mi.mesh = BoxMesh.new()
    mi.position = pos
    mi.scale = scale_v
    mi.material_override = material
    parent.add_child(mi)
    return mi

func _material(color: Color, roughness: float = 0.72) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = roughness
    return m

func _make_arm(pivot_pos: Vector3, arm_mat: Material, hand_mat: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.position = pivot_pos
    visual.add_child(pivot)
    _part(pivot, Vector3(0.0, -0.36, 0.0), Vector3(0.16, 0.72, 0.17), arm_mat)
    _part(pivot, Vector3(0.0, -0.75, -0.01), Vector3(0.17, 0.22, 0.18), hand_mat, true)
    return pivot

func _make_leg(pivot_pos: Vector3, pants_mat: Material, shoe_mat: Material, sole_mat: Material) -> Node3D:
    var pivot := Node3D.new()
    pivot.position = pivot_pos
    visual.add_child(pivot)
    _part(pivot, Vector3(0.0, -0.44, 0.0), Vector3(0.19, 0.88, 0.19), pants_mat)
    _part(pivot, Vector3(0.0, -0.94, -0.07), Vector3(0.25, 0.14, 0.46), shoe_mat)
    _part(pivot, Vector3(0.0, -1.02, -0.07), Vector3(0.27, 0.05, 0.48), sole_mat)
    return pivot

func _build_human() -> void:
    visual = Node3D.new()
    visual.name = "PlayerVisual"
    visual.scale = Vector3.ONE * VISUAL_SCALE
    visual.position = Vector3(0.0, VISUAL_Y, 0.0)
    add_child(visual)

    var skin := _material(Color("#c98f67"), 0.62)
    var shirt := _material(Color("#2f8f58"), 0.70)
    var shirt_dark := _material(Color("#1f6f43"), 0.74)
    var pants := _material(Color("#22345f"), 0.78)
    var shoes := _material(Color("#17191c"), 0.66)
    var sole := _material(Color("#eceae0"), 0.58)
    var hair := _material(Color("#2a1a12"), 0.82)
    var eye := _material(Color("#111111"), 0.35)

    # Torso + shoulder band
    _part(visual, Vector3(0.0, 0.55, 0.0), Vector3(0.54, 0.90, 0.38), shirt)
    _part(visual, Vector3(0.0, 1.02, 0.0), Vector3(0.60, 0.18, 0.42), shirt_dark)
    # Head (face is on -Z, the forward direction)
    _part(visual, Vector3(0.0, 1.34, 0.0), Vector3(0.40, 0.42, 0.40), skin, true)
    _part(visual, Vector3(0.0, 1.50, 0.02), Vector3(0.43, 0.20, 0.43), hair, true)
    _part(visual, Vector3(-0.08, 1.35, -0.18), Vector3(0.045, 0.045, 0.02), eye, true)
    _part(visual, Vector3(0.08, 1.35, -0.18), Vector3(0.045, 0.045, 0.02), eye, true)

    left_arm = _make_arm(Vector3(-0.36, 0.90, 0.0), shirt, skin)
    right_arm = _make_arm(Vector3(0.36, 0.90, 0.0), shirt, skin)
    left_leg = _make_leg(Vector3(-0.20, 0.04, 0.0), pants, shoes, sole)
    right_leg = _make_leg(Vector3(0.20, 0.04, 0.0), pants, shoes, sole)

func set_joystick(value: Vector2) -> void:
    joystick = value

func set_sprint(value: bool) -> void:
    sprint_touch = value

func jump() -> void:
    jump_buffer = JUMP_BUFFER_TIME

func look_camera(delta_look: Vector2) -> void:
    camera_yaw -= delta_look.x * look_sensitivity
    camera_pitch = clampf(camera_pitch - delta_look.y * look_sensitivity, -0.62, 0.12)
    _apply_camera()

func reset_camera_look() -> void:
    camera_yaw = 0.0
    camera_pitch = -0.34
    _apply_camera()

func _apply_camera() -> void:
    if camera_pivot != null:
        camera_pivot.rotation.y = camera_yaw
    if camera != null:
        camera.rotation.x = camera_pitch

func enter_vehicle(target_vehicle: CharacterBody3D) -> void:
    in_vehicle = true
    vehicle = target_vehicle
    visible = false
    velocity = Vector3.ZERO
    if collision_shape != null:
        collision_shape.set_deferred("disabled", true)
    if is_instance_valid(vehicle):
        global_position = vehicle.global_position

func exit_vehicle() -> void:
    if vehicle != null and is_instance_valid(vehicle):
        var exit_pos: Vector3 = vehicle.global_position + vehicle.global_transform.basis.x * 2.8
        var world_root := get_parent()
        if world_root != null and world_root.has_method("_height"):
            exit_pos.y = float(world_root.call("_height", exit_pos.x, exit_pos.z)) + 0.95
        else:
            exit_pos.y = vehicle.global_position.y + 0.4
        global_position = exit_pos
    in_vehicle = false
    vehicle = null
    visible = true
    velocity = Vector3.ZERO
    if collision_shape != null:
        collision_shape.set_deferred("disabled", false)
    if camera != null:
        camera.current = true

func _physics_process(delta: float) -> void:
    if in_vehicle:
        velocity = Vector3.ZERO
        # Keep the (invisible) player on the car so distance based systems
        # (missions, LOD, traffic, culling) track the real position.
        if vehicle != null and is_instance_valid(vehicle):
            global_position = vehicle.global_position
        return

    # --- jump (buffered, with coyote time) ---
    if is_on_floor():
        coyote_timer = COYOTE_TIME
    else:
        coyote_timer = maxf(0.0, coyote_timer - delta)
    jump_buffer = maxf(0.0, jump_buffer - delta)
    if Input.is_action_just_pressed("ui_accept"):
        jump_buffer = JUMP_BUFFER_TIME

    if jump_buffer > 0.0 and coyote_timer > 0.0:
        velocity.y = jump_velocity
        jump_buffer = 0.0
        coyote_timer = 0.0
    elif not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = 0.0

    # --- movement ---
    var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if joystick.length() > input_vec.length():
        input_vec = joystick

    var local_dir := Vector3(input_vec.x, 0.0, input_vec.y)
    var dir := Vector3.ZERO
    if local_dir.length() > 0.01:
        dir = (Basis(Vector3.UP, camera_yaw) * local_dir).normalized()

    var sprinting: bool = sprint_touch or Input.is_physical_key_pressed(KEY_SHIFT)
    var current_speed: float = sprint_speed if sprinting else speed
    var target_velocity: Vector3 = dir * current_speed * minf(1.0, input_vec.length())
    velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

    if dir.length() > 0.01 and visual != null:
        # The face is on -Z, so rotate -Z (not +Z) toward the walking direction.
        var yaw: float = atan2(-dir.x, -dir.z)
        visual.rotation.y = lerp_angle(visual.rotation.y, yaw, minf(1.0, delta * 12.0))

    move_and_slide()
    _animate_walk(delta)
    _recover_ground()
    _clamp_to_world()

func _animate_walk(delta: float) -> void:
    var planar_speed: float = Vector2(velocity.x, velocity.z).length()
    var moving: bool = planar_speed > 0.15 and is_on_floor()
    if moving:
        walk_time += delta * (6.0 + planar_speed * 0.9)
    var stride: float = sin(walk_time) if moving else 0.0
    var arm_stride: float = stride * 0.62
    var leg_stride: float = stride * 0.70
    var weight: float = minf(1.0, delta * 12.0)
    if left_arm != null:
        left_arm.rotation.x = lerpf(left_arm.rotation.x, arm_stride, weight)
        right_arm.rotation.x = lerpf(right_arm.rotation.x, -arm_stride, weight)
        left_leg.rotation.x = lerpf(left_leg.rotation.x, -leg_stride, weight)
        right_leg.rotation.x = lerpf(right_leg.rotation.x, leg_stride, weight)
    if visual != null:
        visual.position.y = VISUAL_Y + absf(stride) * 0.028

func _recover_ground() -> void:
    # Safety net: if the collider ever misses a frame, put the capsule back
    # on the procedural terrain height.
    var world_root := get_parent()
    if world_root == null or not world_root.has_method("_height"):
        return
    var ground_y: float = float(world_root.call("_height", global_position.x, global_position.z))
    var standing_y: float = ground_y + 0.92
    if global_position.y < standing_y - 0.35:
        global_position.y = standing_y
        velocity.y = maxf(velocity.y, 0.0)

func _clamp_to_world() -> void:
    var p: Vector3 = global_position
    p.x = clampf(p.x, -WORLD_LIMIT, WORLD_LIMIT)
    p.z = clampf(p.z, -WORLD_LIMIT, WORLD_LIMIT)
    if p != global_position:
        global_position = p
