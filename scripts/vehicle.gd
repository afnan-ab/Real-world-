extends CharacterBody3D

@export var max_speed: float = 18.0
@export var reverse_speed: float = 7.0
@export var acceleration: float = 10.0
@export var braking: float = 18.0
@export var steering_speed: float = 1.9
@export var grip: float = 7.0

var joystick := Vector2.ZERO
var driving := false
var visual: Node3D
var camera: Camera3D
var wheels: Array[MeshInstance3D] = []
var speed_kmh: float = 0.0

func _ready() -> void:
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
    camera.fov = 70.0
    camera.current = false
    add_child(camera)

func _mat(color: Color, rough: float = 0.6, metallic: float = 0.0) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    m.metallic = metallic
    return m

func _part(pos: Vector3, size: Vector3, mat: Material) -> void:
    var mi := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mi.mesh = box
    mi.position = pos
    mi.material_override = mat
    visual.add_child(mi)

func _build_vehicle() -> void:
    visual = Node3D.new()
    visual.name = "DriveableCarVisual"
    add_child(visual)

    var body := _mat(Color("#b52f32"),0.24,0.55)
    var body_dark := _mat(Color("#7f1f24"),0.30,0.45)
    var glass := _mat(Color("#142833"),0.08,0.65)
    var tire := _mat(Color("#0c0e10"),0.95)
    var rubber := _mat(Color("#181a1d"),0.88)
    var chrome := _mat(Color("#bfc4c8"),0.18,0.82)
    var light := _mat(Color("#fff3c7"),0.10,0.35)
    var tail := _mat(Color("#d21f2f"),0.18,0.25)
    var black := _mat(Color("#090b0d"),0.82,0.1)

    # Low-poly sedan proportions: length runs along the driving axis (-Z).
    _part(Vector3(0,0.62,0),Vector3(2.0,0.72,4.35),body)
    _part(Vector3(0,0.98,-0.62),Vector3(1.82,0.18,1.18),body_dark)
    _part(Vector3(0,1.13,0.22),Vector3(1.72,0.62,2.15),body)

    # Roof and dark glasshouse.
    _part(Vector3(0,1.38,0.10),Vector3(1.55,0.12,1.95),body)
    _part(Vector3(0,1.39,-0.64),Vector3(1.47,0.42,0.72),glass)
    _part(Vector3(0,1.39,0.64),Vector3(1.47,0.42,0.72),glass)
    _part(Vector3(0,1.39,0.00),Vector3(1.48,0.43,0.30),glass)

    # Bumpers, grille and lower trim.
    _part(Vector3(0,0.52,-2.16),Vector3(1.86,0.30,0.18),black)
    _part(Vector3(0,0.53,2.16),Vector3(1.86,0.30,0.18),body_dark)
    _part(Vector3(0,0.70,-2.27),Vector3(0.92,0.20,0.06),chrome)
    _part(Vector3(0,0.72,-2.30),Vector3(0.58,0.10,0.04),black)

    # Four wheels with visible hubs.
    for sx in [-1.0,1.0]:
        for sz in [-1.38,1.38]:
            var wheel := MeshInstance3D.new()
            var cyl := CylinderMesh.new()
            cyl.top_radius = 0.46
            cyl.bottom_radius = 0.46
            cyl.height = 0.30
            cyl.radial_segments = 20
            wheel.mesh = cyl
            wheel.position = Vector3(sx*0.98,0.48,sz)
            wheel.rotation_degrees = Vector3(90,0,0)
            wheel.material_override = tire
            visual.add_child(wheel)
            wheels.append(wheel)

            var hub := MeshInstance3D.new()
            var hm := CylinderMesh.new()
            hm.top_radius = 0.20
            hm.bottom_radius = 0.20
            hm.height = 0.32
            hm.radial_segments = 16
            hub.mesh = hm
            hub.position = wheel.position + Vector3(0,0.01,0)
            hub.rotation_degrees = Vector3(90,0,0)
            hub.material_override = chrome
            visual.add_child(hub)

            var cap := MeshInstance3D.new()
            var cm := CylinderMesh.new()
            cm.top_radius = 0.08
            cm.bottom_radius = 0.08
            cm.height = 0.34
            cm.radial_segments = 12
            cap.mesh = cm
            cap.position = wheel.position + Vector3(0,0.02,0)
            cap.rotation_degrees = Vector3(90,0,0)
            cap.material_override = rubber
            visual.add_child(cap)

    # Front/rear lighting and side mirrors.
    _part(Vector3(-0.62,0.78,-2.16),Vector3(0.42,0.22,0.10),light)
    _part(Vector3(0.62,0.78,-2.16),Vector3(0.42,0.22,0.10),light)
    _part(Vector3(-0.62,0.78,2.16),Vector3(0.42,0.22,0.10),tail)
    _part(Vector3(0.62,0.78,2.16),Vector3(0.42,0.22,0.10),tail)
    _part(Vector3(-0.98,1.18,-0.58),Vector3(0.16,0.14,0.28),black)
    _part(Vector3(0.98,1.18,-0.58),Vector3(0.16,0.14,0.28),black)

    # Door handles and a subtle belt line.
    for sx in [-1.0,1.0]:
        _part(Vector3(sx*0.91,1.03,-0.05),Vector3(0.035,0.08,0.32),chrome)
        _part(Vector3(sx*0.91,1.03,0.62),Vector3(0.035,0.08,0.32),chrome)
        _part(Vector3(sx*0.91,0.93,0.10),Vector3(0.035,0.06,1.55),body_dark)

func set_joystick(v: Vector2) -> void:
    joystick = v

func enter() -> void:
    driving = true
    camera.current = true

func exit() -> void:
    driving = false
    camera.current = false
    velocity = Vector3.ZERO

func is_driving() -> bool:
    return driving

func _physics_process(delta: float) -> void:
    if not driving:
        return

    var input_vec := joystick
    if input_vec.length() < 0.08:
        input_vec = Input.get_vector("move_left","move_right","move_forward","move_back")

    var throttle := clamp(-input_vec.y, -1.0, 1.0)
    var steer := clamp(input_vec.x, -1.0, 1.0)
    var forward := -global_transform.basis.z
    var current_forward_speed := velocity.dot(forward)
    var target_speed := throttle * (max_speed if throttle >= 0.0 else reverse_speed)

    if abs(throttle) > 0.08:
        var rate := acceleration if abs(target_speed) > abs(current_forward_speed) else braking
        var new_speed := move_toward(current_forward_speed,target_speed,rate * delta)
        velocity = forward * new_speed
    else:
        velocity = velocity.move_toward(Vector3.ZERO,braking * delta)

    var steering_factor := clamp(abs(current_forward_speed) / 3.0,0.0,1.0)
    var direction_sign := 1.0 if current_forward_speed >= -0.1 else -1.0
    rotation.y -= steer * steering_speed * steering_factor * direction_sign * delta

    var lateral := velocity - forward * velocity.dot(forward)
    velocity -= lateral * min(1.0, grip * delta)

    for wheel in wheels:
        wheel.rotation.x -= current_forward_speed * delta * 1.7

    if not is_on_floor():
        velocity.y -= 20.0 * delta
    else:
        velocity.y = 0.0

    move_and_slide()
    speed_kmh = abs(velocity.dot(-global_transform.basis.z)) * 3.6

    var target_fov := 70.0 + clamp(speed_kmh / 12.0,0.0,10.0)
    camera.fov = lerp(camera.fov,target_fov,delta * 4.0)
