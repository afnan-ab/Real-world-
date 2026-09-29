extends CharacterBody3D

@export var speed: float = 5.8
@export var sprint_speed: float = 9.5
@export var acceleration: float = 18.0
@export var gravity: float = 20.0
var joystick := Vector2.ZERO
var visual: Node3D
var camera: Camera3D
var walk_time: float = 0.0
var camera_target: Vector3

func _ready() -> void:
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.8
    $CollisionShape3D.shape = capsule
    camera = $CameraPivot/Camera3D
    camera_target = camera.position
    _build_human()

func _build_human() -> void:
    visual = Node3D.new()
    visual.position.y = 0.9
    add_child(visual)

    var skin := _mat(Color("#b97858"), 0.62)
    var shirt := _mat(Color("#263b52"), 0.78)
    var pants := _mat(Color("#24282d"), 0.9)
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

func _physics_process(delta: float) -> void:
    var input_vec := Input.get_vector("move_left","move_right","move_forward","move_back")
    if joystick.length() > 0.08:
        input_vec = joystick

    var dir := Vector3(input_vec.x,0,input_vec.y)
    if dir.length() > 1.0:
        dir = dir.normalized()

    var current_speed := sprint_speed if Input.is_action_pressed("ui_accept") else speed
    velocity.x = move_toward(velocity.x, dir.x * current_speed, acceleration * delta)
    velocity.z = move_toward(velocity.z, dir.z * current_speed, acceleration * delta)

    if dir.length() > 0.08:
        var yaw := atan2(dir.x,dir.z)
        visual.rotation.y = lerp_angle(visual.rotation.y,yaw,min(1.0,delta*9.0))
        walk_time += delta * (8.0 if current_speed > speed else 5.0)
        visual.position.y = 0.9 + sin(walk_time) * 0.035
        visual.rotation.z = sin(walk_time * 0.5) * 0.018
    else:
        visual.position.y = move_toward(visual.position.y,0.9,delta*4.0)

    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = 0.0
    move_and_slide()

    # Smooth third-person camera follow for a more cinematic feel.
    camera.position = camera.position.lerp(camera_target, min(1.0, delta * 5.5))
