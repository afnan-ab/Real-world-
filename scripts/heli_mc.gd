extends "res://scripts/vehicle.gd"

# Flyable helicopter. It reuses the car's driving plumbing (enter / exit,
# joystick, GAS / BRAKE pedals) so the existing DRIVE and EXIT buttons work.
#   joystick up / down  = fly forward / backward
#   joystick left/right = turn
#   GAS                 = climb
#   BRAKE               = descend
# vehicle.gd itself is not modified.

const HELI_SPEED := 30.0
const HELI_CLIMB := 11.0
const HELI_YAW := 1.5
const HELI_MAX_ALT := 200.0

var is_heli: bool = true
var rotor: Node3D
var tail_rotor: Node3D
var rotor_speed: float = 0.0
var _heli_planar: Vector3 = Vector3.ZERO

func _ready() -> void:
    super._ready()
    if camera != null:
        camera.position = Vector3(0.0, 4.5, 12.0)
        camera.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
        camera.fov = 75.0

func _blade(parent: Node3D, size: Vector3, material: Material) -> void:
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mi.mesh = bm
    mi.material_override = material
    parent.add_child(mi)

# Front of the helicopter is -Z, like the car.
func _build_vehicle() -> void:
    visual = Node3D.new()
    visual.name = "VehicleVisual"
    add_child(visual)

    body_material = _mat(setup_color, 0.3, 0.4)
    trim_material = _mat(setup_color.darkened(0.40), 0.3, 0.4)
    var glass: StandardMaterial3D = _mat(Color("#14323d"), 0.05, 0.3)
    var dark: StandardMaterial3D = _mat(Color("#1d2024"), 0.6)

    _part(Vector3(0.0, 1.3, 0.0), Vector3(1.9, 1.6, 3.6), body_material)
    _part(Vector3(0.0, 1.5, -1.5), Vector3(1.6, 1.0, 1.0), glass)
    _part(Vector3(0.0, 1.5, 3.3), Vector3(0.5, 0.5, 4.2), trim_material)
    _part(Vector3(0.0, 2.0, 5.1), Vector3(0.2, 1.2, 0.8), trim_material)
    _part(Vector3(-1.0, 0.25, -0.2), Vector3(0.12, 0.12, 3.2), dark)
    _part(Vector3(1.0, 0.25, -0.2), Vector3(0.12, 0.12, 3.2), dark)
    _part(Vector3(-0.9, 0.6, -1.0), Vector3(0.1, 0.7, 0.1), dark)
    _part(Vector3(0.9, 0.6, -1.0), Vector3(0.1, 0.7, 0.1), dark)
    _part(Vector3(-0.9, 0.6, 0.7), Vector3(0.1, 0.7, 0.1), dark)
    _part(Vector3(0.9, 0.6, 0.7), Vector3(0.1, 0.7, 0.1), dark)
    _part(Vector3(0.0, 2.25, 0.0), Vector3(0.22, 0.4, 0.22), dark)

    rotor = Node3D.new()
    rotor.position = Vector3(0.0, 2.5, 0.0)
    visual.add_child(rotor)
    _blade(rotor, Vector3(9.0, 0.06, 0.35), dark)
    _blade(rotor, Vector3(0.35, 0.06, 9.0), dark)

    tail_rotor = Node3D.new()
    tail_rotor.position = Vector3(0.3, 2.0, 5.2)
    visual.add_child(tail_rotor)
    _blade(tail_rotor, Vector3(0.06, 1.3, 0.2), dark)
    _blade(tail_rotor, Vector3(0.06, 0.2, 1.3), dark)

func _spin(delta: float, target_speed: float) -> void:
    rotor_speed = lerpf(rotor_speed, target_speed, minf(1.0, delta * 1.5))
    if rotor != null:
        rotor.rotation.y += rotor_speed * delta
    if tail_rotor != null:
        tail_rotor.rotation.x += rotor_speed * 1.6 * delta

func _physics_process(delta: float) -> void:
    if not driving:
        super._physics_process(delta)
        _spin(delta, 0.0)
        return

    var input_vec: Vector2 = joystick
    var kb: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    if kb.length() > input_vec.length():
        input_vec = kb
    var fwd_in: float = clampf(-input_vec.y, -1.0, 1.0)
    var steer: float = clampf(input_vec.x, -1.0, 1.0)
    var climb: float = 0.0
    if mobile_gas:
        climb = 1.0
    elif mobile_brake:
        climb = -1.0

    rotation.y -= steer * HELI_YAW * delta

    var forward: Vector3 = -global_transform.basis.z
    forward.y = 0.0
    forward = forward.normalized()
    _heli_planar = _heli_planar.move_toward(forward * fwd_in * HELI_SPEED, 14.0 * delta)
    velocity.x = _heli_planar.x
    velocity.z = _heli_planar.z
    velocity.y = move_toward(velocity.y, climb * HELI_CLIMB, 12.0 * delta)
    move_and_slide()

    if global_position.y > HELI_MAX_ALT:
        global_position.y = HELI_MAX_ALT
        velocity.y = minf(velocity.y, 0.0)
    _recover_ground()
    _clamp_to_world()

    speed_kmh = Vector2(velocity.x, velocity.z).length() * 3.6
    if visual != null:
        visual.rotation.x = lerpf(visual.rotation.x, -fwd_in * 0.18, minf(1.0, delta * 3.0))
        visual.rotation.z = lerpf(visual.rotation.z, -steer * 0.2, minf(1.0, delta * 3.0))
    _spin(delta, 36.0)
