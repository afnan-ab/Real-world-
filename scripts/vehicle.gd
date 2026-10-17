extends CharacterBody3D

# Driveable car.
# Fixes in this pass:
#  - wheels have their axle along X and spin/steer through pivots
#  - steering direction of the front wheels matches the car
#  - vertical velocity is preserved (gravity works) and parked cars settle on the ground
#  - body/trim colour is applied through stored materials (tail lights keep their colour)
#  - ground recovery + world bounds

@export var max_speed: float = 18.0
@export var reverse_speed: float = 7.0
@export var acceleration: float = 10.0
@export var braking: float = 18.0
@export var steering_speed: float = 1.9

const WHEEL_RADIUS := 0.46
const WORLD_LIMIT := 210.0
const GRAVITY := 20.0

var joystick: Vector2 = Vector2.ZERO
var driving: bool = false
var visual: Node3D
var camera: Camera3D
var wheels: Array[Node3D] = []
var front_pivots: Array[Node3D] = []
var speed_kmh: float = 0.0
var setup_color: Color = Color("#b52f32")
var suspension_phase: float = 0.0
var mobile_drive: float = 0.0
var mobile_gas: bool = false
var mobile_brake: bool = false
var body_material: StandardMaterial3D
var trim_material: StandardMaterial3D
var _settled: bool = false

func _ready() -> void:
    floor_snap_length = 0.5
    var body_shape := BoxShape3D.new()
    body_shape.size = Vector3(2.0, 1.45, 4.4)
    var collision := CollisionShape3D.new()
    collision.shape = body_shape
    collision.position.y = 0.72
    add_child(collision)

    _build_vehicle()

    camera = Camera3D.new()
    camera.position = Vector3(0.0, 3.2, 7.2)
    camera.rotation_degrees = Vector3(-11.0, 0.0, 0.0)
    camera.fov = 72.0
    add_child(camera)

func set_vehicle_color(color: Color) -> void:
    setup_color = color
    if body_material != null:
        body_material.albedo_color = color
    if trim_material != null:
        trim_material.albedo_color = color.darkened(0.40)

func _mat(color: Color, roughness: float = 0.55, metallic: float = 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = roughness
    m.metallic = metallic
    return m

func _part(pos: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mi.mesh = bm
    mi.position = pos
    mi.material_override = material
    visual.add_child(mi)
    return mi

func _wheel_mesh(parent: Node3D, radius: float, height: float, segments: int, material: Material) -> void:
    var mi := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = radius
    cyl.bottom_radius = radius
    cyl.height = height
    cyl.radial_segments = segments
    mi.mesh = cyl
    # CylinderMesh axis is Y; rotate so the axle runs along X (sideways).
    mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
    mi.material_override = material
    parent.add_child(mi)

func _build_vehicle() -> void:
    visual = Node3D.new()
    visual.name = "VehicleVisual"
    add_child(visual)

    body_material = _mat(setup_color, 0.24, 0.55)
    trim_material = _mat(setup_color.darkened(0.40), 0.30, 0.45)
    var glass := _mat(Color("#10252b"), 0.08, 0.1)
    var tire := _mat(Color("#101113"), 0.82)
    var chrome := _mat(Color("#c8cdd0"), 0.20, 0.8)
    var rubber := _mat(Color("#2b2d30"), 0.70)
    var headlight := _mat(Color("#fff2c4"), 0.18)
    var tail := _mat(Color("#d21f2f"), 0.30)

    # Front of the car is -Z.
    _part(Vector3(0.0, 0.62, 0.0), Vector3(1.95, 0.62, 4.25), body_material)
    _part(Vector3(0.0, 0.34, 0.0), Vector3(2.02, 0.20, 4.30), trim_material)
    _part(Vector3(0.0, 1.10, 0.18), Vector3(1.62, 0.52, 2.15), body_material)
    _part(Vector3(0.0, 1.14, -0.88), Vector3(1.50, 0.38, 0.62), glass)
    _part(Vector3(0.0, 1.14, 1.20), Vector3(1.50, 0.38, 0.55), glass)
    _part(Vector3(-0.83, 1.12, 0.18), Vector3(0.04, 0.34, 1.65), glass)
    _part(Vector3(0.83, 1.12, 0.18), Vector3(0.04, 0.34, 1.65), glass)
    _part(Vector3(-0.62, 0.72, -2.16), Vector3(0.36, 0.17, 0.08), headlight)
    _part(Vector3(0.62, 0.72, -2.16), Vector3(0.36, 0.17, 0.08), headlight)
    _part(Vector3(-0.64, 0.70, 2.16), Vector3(0.36, 0.17, 0.08), tail)
    _part(Vector3(0.64, 0.70, 2.16), Vector3(0.36, 0.17, 0.08), tail)
    _part(Vector3(0.0, 0.56, -2.18), Vector3(1.20, 0.22, 0.06), chrome)
    _part(Vector3(0.0, 0.34, -2.21), Vector3(1.80, 0.18, 0.12), chrome)
    _part(Vector3(0.0, 0.34, 2.21), Vector3(1.80, 0.18, 0.12), chrome)

    for sx in [-1.0, 1.0]:
        for sz in [-1.38, 1.38]:
            var pivot := Node3D.new()
            pivot.position = Vector3(float(sx) * 0.98, 0.48, float(sz))
            visual.add_child(pivot)
            var spin := Node3D.new()
            pivot.add_child(spin)
            _wheel_mesh(spin, WHEEL_RADIUS, 0.30, 20, tire)
            _wheel_mesh(spin, 0.20, 0.32, 16, chrome)
            _wheel_mesh(spin, 0.08, 0.34, 12, rubber)
            wheels.append(spin)
            if float(sz) < 0.0:
                front_pivots.append(pivot)

func enter() -> void:
    driving = true
    _settled = false
    if camera != null:
        camera.current = true

func exit() -> void:
    driving = false
    _settled = false
    joystick = Vector2.ZERO
    mobile_drive = 0.0
    mobile_gas = false
    mobile_brake = false
    if camera != null:
        camera.current = false

func is_driving() -> bool:
    return driving

func set_joystick(value: Vector2) -> void:
    joystick = value

func set_mobile_pedals(gas: bool, brake: bool, drive_axis: float = 0.0) -> void:
    mobile_gas = gas
    mobile_brake = brake
    mobile_drive = drive_axis

func _physics_process(delta: float) -> void:
    if not driving:
        # Parked: let the car settle onto the ground once, then stay idle.
        if _settled:
            return
        velocity.x = 0.0
        velocity.z = 0.0
        velocity.y -= GRAVITY * delta
        move_and_slide()
        if is_on_floor():
            velocity = Vector3.ZERO
            _settled = true
        _recover_ground()
        return

    var input_vec: Vector2 = joystick
    var kb: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if kb.length() > input_vec.length():
        input_vec = kb

    var throttle: float = clampf(-input_vec.y, -1.0, 1.0)
    if mobile_gas:
        throttle = 1.0
    elif mobile_brake:
        throttle = 0.0
    elif absf(mobile_drive) > 0.01:
        throttle = clampf(mobile_drive, -1.0, 1.0)
    var steer: float = clampf(input_vec.x, -1.0, 1.0)

    var vertical: float = velocity.y
    var hv := Vector3(velocity.x, 0.0, velocity.z)
    var forward: Vector3 = -global_transform.basis.z
    forward.y = 0.0
    forward = forward.normalized()
    var current_forward_speed: float = hv.dot(forward)

    var top_speed: float = max_speed if throttle >= 0.0 else reverse_speed
    var target_speed: float = throttle * top_speed
    if mobile_brake:
        hv = hv.move_toward(Vector3.ZERO, braking * 1.45 * delta)
    elif absf(throttle) > 0.08:
        var rate: float = acceleration if absf(target_speed) > absf(current_forward_speed) else braking
        var new_speed: float = move_toward(current_forward_speed, target_speed, rate * delta)
        hv = forward * new_speed
    else:
        hv = hv.move_toward(Vector3.ZERO, braking * 0.5 * delta)

    var steering_factor: float = clampf(absf(current_forward_speed) / 3.0, 0.0, 1.0)
    var direction_sign: float = 1.0 if current_forward_speed >= -0.1 else -1.0
    rotation.y -= steer * steering_speed * steering_factor * direction_sign * delta

    velocity.x = hv.x
    velocity.z = hv.z
    if is_on_floor():
        velocity.y = 0.0
    else:
        velocity.y = vertical - GRAVITY * delta

    move_and_slide()
    _recover_ground()
    _clamp_to_world()

    var planar_speed: float = Vector2(velocity.x, velocity.z).length()
    speed_kmh = planar_speed * 3.6
    var signed_speed: float = Vector3(velocity.x, 0.0, velocity.z).dot(-global_transform.basis.z)
    _animate(delta, signed_speed, steer)

func _animate(delta: float, forward_speed: float, steer: float) -> void:
    for spin in wheels:
        # Rolling forward (-Z) turns the wheel about -X.
        spin.rotation.x = wrapf(spin.rotation.x - forward_speed * delta / WHEEL_RADIUS, -TAU, TAU)
    for pivot in front_pivots:
        # Steering right (steer > 0) turns the car clockwise, i.e. negative yaw.
        pivot.rotation.y = lerpf(pivot.rotation.y, -steer * 0.45, minf(1.0, delta * 8.0))
    if visual != null:
        suspension_phase += delta * (4.0 + absf(forward_speed))
        visual.position.y = sin(suspension_phase) * minf(absf(forward_speed) / 18.0, 1.0) * 0.018
    if camera != null:
        var target_fov: float = 70.0 + clampf(speed_kmh / 12.0, 0.0, 10.0)
        camera.fov = lerpf(camera.fov, target_fov, minf(1.0, delta * 3.0))

func _recover_ground() -> void:
    var world_root := get_parent()
    if world_root == null or not world_root.has_method("_height"):
        return
    var ground_y: float = float(world_root.call("_height", global_position.x, global_position.z))
    if global_position.y < ground_y - 0.8:
        global_position.y = ground_y + 0.3
        velocity.y = 0.0

func _clamp_to_world() -> void:
    var p: Vector3 = global_position
    p.x = clampf(p.x, -WORLD_LIMIT, WORLD_LIMIT)
    p.z = clampf(p.z, -WORLD_LIMIT, WORLD_LIMIT)
    if p != global_position:
        global_position = p
