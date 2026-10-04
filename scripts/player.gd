extends CharacterBody3D

@export var speed: float = 5.8
@export var sprint_speed: float = 9.5
@export var acceleration: float = 18.0
@export var gravity: float = 20.0
@export var camera_distance: float = 6.5
@export var look_sensitivity: float = 0.010

var joystick := Vector2.ZERO
var visual: Node3D
var camera: Camera3D
var walk_time: float = 0.0
var sprint_touch := false
var camera_yaw: float = 0.0
var camera_pitch: float = -0.16

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
    visual = Node3D.new()
    visual.name = "PlayerVisual"
    visual.position.y = 0.9
    add_child(visual)

    var skin := _mat(Color("#b97858"), 0.62)
    var shirt := _mat(Color("#263b52"), 0.78)
    var pants := _mat(Color("#24282d"), 0.90)
    var shoes := _mat(Color("#111315"), 0.94)
    var hair := _mat(Color("#16181a"), 0.92)

    _part(BoxMesh.new(), Vector3(0,0.55,0), Vector3(0.52,0.9,0.34), shirt)
    _part(SphereMesh.new(), Vector3(0,1.25,0), Vector3(0.38,0.38,0.38), skin, true)
    _part(SphereMesh.new(), Vector3(0,1.45,0), Vector3(0.39,0.16,0.39), hair, true)
    _part(BoxMesh.new(), Vector3(-0.20,-0.45,0), Vector3(0.16,0.9,0.16), pants)
    _part(BoxMesh.new(), Vector3(0.20,-0.45,0), Vector3(0.16,0.9,0.16), pants)
    _part(BoxMesh.new(), Vector3(-0.53,0.35,0), Vector3(0.14,0.68,0.14), skin)
    _part(BoxMesh.new(), Vector3(0.53,0.35,0), Vector3(0.14,0.68,0.14), skin)
    _part(BoxMesh.new(), Vector3(-0.20,-0.92,-0.06), Vector3(0.22,0.13,0.42), shoes)
    _part(BoxMesh.new(), Vector3(0.20,-0.92,-0.06), Vector3(0.22,0.13,0.42), shoes)

func _part(mesh: Mesh, pos: Vector3, scale_v: Vector3, material: Material, sphere: bool = false) -> void:
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

func _mat(color: Color, rough: float = 0.8) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    return m

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
        walk_time += delta * (8.0 if current_speed > speed else 5.0)
        visual.position.y = 0.9 + sin(walk_time) * 0.035
    else:
        visual.position.y = move_toward(visual.position.y, 0.9, delta * 4.0)

    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = 0.0

    move_and_slide()
