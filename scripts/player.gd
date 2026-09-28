extends CharacterBody3D

@export var speed := 6.5
@export var sprint_speed := 10.0
@export var acceleration := 22.0
@export var gravity := 20.0
var joystick := Vector2.ZERO
var target_yaw := 0.0
var visual: Node3D

func _ready():
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.8
    $CollisionShape3D.shape = capsule
    _build_human()

func _build_human():
    visual = Node3D.new()
    visual.position.y = 0.9
    add_child(visual)
    var skin := _mat(Color("#b97755"), 0.72)
    var shirt := _mat(Color("#26384a"), 0.86)
    var pants := _mat(Color("#24272b"), 0.92)
    _part(CylinderMesh.new(), Vector3(0,0.55,0), Vector3(0.42,0.95,0.42), shirt)
    _part(SphereMesh.new(), Vector3(0,1.25,0), Vector3(0.38,0.38,0.38), skin)
    _part(CylinderMesh.new(), Vector3(-0.22,-0.45,0), Vector3(0.15,0.9,0.15), pants)
    _part(CylinderMesh.new(), Vector3(0.22,-0.45,0), Vector3(0.15,0.9,0.15), pants)
    _part(CylinderMesh.new(), Vector3(-0.55,0.35,0), Vector3(0.13,0.65,0.13), skin)
    _part(CylinderMesh.new(), Vector3(0.55,0.35,0), Vector3(0.13,0.65,0.13), skin)

func _part(mesh: Mesh, pos: Vector3, scale_v: Vector3, material: Material):
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.position = pos
    mi.scale = scale_v
    mi.material_override = material
    visual.add_child(mi)

func _mat(color: Color, rough := 0.8) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = rough
    return m

func set_joystick(v: Vector2):
    joystick = v

func _physics_process(delta):
    var input_vec := Input.get_vector("move_left","move_right","move_forward","move_back")
    if joystick.length() > 0.08:
        input_vec = joystick
    var dir := Vector3(input_vec.x,0,input_vec.y)
    if dir.length() > 1.0: dir = dir.normalized()
    var current_speed := sprint_speed if Input.is_action_pressed("ui_accept") else speed
    velocity.x = move_toward(velocity.x, dir.x * current_speed, acceleration * delta)
    velocity.z = move_toward(velocity.z, dir.z * current_speed, acceleration * delta)
    if dir.length() > 0.08:
        target_yaw = atan2(dir.x, dir.z)
        visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, min(1.0, delta * 10.0))
    if not is_on_floor(): velocity.y -= gravity * delta
    else: velocity.y = 0.0
    move_and_slide()
