extends CanvasLayer

var player: Node
var world: Node
var run_button: Button
var act_button: Button
var jump_button: Button
var joy_center := Vector2(118,590)
var joy_active := false

func _ready() -> void:
    player = get_parent().get_node_or_null("Player")
    world = get_parent()
    run_button = get_node_or_null("Run")
    act_button = get_node_or_null("Act")
    jump_button = get_node_or_null("Jump")

    if run_button:
        run_button.button_down.connect(_run_down)
        run_button.button_up.connect(_run_up)
    if act_button:
        act_button.pressed.connect(_act_pressed)
    if jump_button:
        jump_button.pressed.connect(_jump_pressed)

func _run_down() -> void:
    if player:
        player.set_sprint(true)

func _run_up() -> void:
    if player:
        player.set_sprint(false)

func _act_pressed() -> void:
    if player and world:
        world.toggle_vehicle(player)

func _jump_pressed() -> void:
    if player and not player.in_vehicle and player.is_on_floor():
        player.velocity.y = 7.0

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.position.x < 250.0 and event.position.y > 450.0:
            joy_active = event.pressed
            if not joy_active and player:
                player.set_joystick(Vector2.ZERO)
            get_viewport().set_input_as_handled()
        elif event.pressed and event.position.x > 720.0 and event.position.y < 570.0:
            _start_camera_drag(event.position)
    elif event is InputEventScreenDrag:
        if joy_active and event.position.x < 260.0 and event.position.y > 440.0:
            var v := (event.position - joy_center) / 70.0
            var joy := Vector2(clamp(v.x,-1.0,1.0), clamp(v.y,-1.0,1.0))
            if player:
                player.set_joystick(joy)
            get_viewport().set_input_as_handled()

var camera_dragging := false
var last_look := Vector2.ZERO

func _start_camera_drag(p: Vector2) -> void:
    camera_dragging = true
    last_look = p

func _process(_delta: float) -> void:
    if player and act_button:
        act_button.text = "EXIT" if player.in_vehicle else "ACT"
    if player and camera_dragging:
        pass
