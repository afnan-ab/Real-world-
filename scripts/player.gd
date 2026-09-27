extends CharacterBody3D

@export var speed := 7.0
@export var acceleration := 18.0
@export var gravity := 18.0

var joystick := Vector2.ZERO
var yaw := 0.0

func _ready():
    var capsule = CapsuleShape3D.new()
    capsule.radius = 0.45
    capsule.height = 1.8
    $CollisionShape3D.shape = capsule

    var body = MeshInstance3D.new()
    var cm = CapsuleMesh.new()
    cm.radius = 0.45
    cm.height = 1.8
    body.mesh = cm
    var m = StandardMaterial3D.new()
    m.albedo_color = Color("#c9835a")
    body.material_override = m
    body.position.y = 1.0
    add_child(body)

func set_joystick(v: Vector2):
    joystick = v

func _physics_process(delta):
    var input_vec = Input.get_vector("move_left","move_right","move_forward","move_back")
    if joystick.length() > 0.08:
        input_vec = joystick
    var dir = Vector3(input_vec.x,0,input_vec.y)
    if dir.length() > 1.0: dir = dir.normalized()
    velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
    velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = 0
    move_and_slide()
