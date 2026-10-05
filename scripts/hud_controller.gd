extends CanvasLayer

var player: CharacterBody3D
var world: Node3D
var run_button: Button
var act_button: Button
var jump_button: Button
var vehicle_label: Label
var speed_label: Label
var message_label: Label
var sprint_on := false
var camera_dragging := false
var last_look := Vector2.ZERO
var joy_active := false
var joy_center := Vector2(118,590)

func _ready() -> void:
    player = get_parent().get_node_or_null("Player") as CharacterBody3D
    world = get_parent() as Node3D

    run_button = get_node_or_null("Run") as Button
    act_button = get_node_or_null("Act") as Button
    jump_button = get_node_or_null("Jump") as Button
    vehicle_label = get_node_or_null("Vehicle") as Label
    speed_label = get_node_or_null("Speed") as Label
    message_label = get_node_or_null("Mission") as Label

    if run_button:
        run_button.mouse_filter = Control.MOUSE_FILTER_STOP
        run_button.focus_mode = Control.FOCUS_NONE
        run_button.pressed.connect(_run_pressed)
    if act_button:
        act_button.mouse_filter = Control.MOUSE_FILTER_STOP
        act_button.focus_mode = Control.FOCUS_NONE
        act_button.pressed.connect(_act_pressed)
    if jump_button:
        jump_button.mouse_filter = Control.MOUSE_FILTER_STOP
        jump_button.focus_mode = Control.FOCUS_NONE
        jump_button.pressed.connect(_jump_pressed)

func _run_pressed() -> void:
    sprint_on = not sprint_on
    if player:
        player.set_sprint(sprint_on)
    if run_button:
        run_button.text = "RUN ON" if sprint_on else "RUN"

func _act_pressed() -> void:
    if not player or not world:
        return
    var result := world.toggle_vehicle(player)
    if vehicle_label:
        vehicle_label.text = "VEHICLE  •  " + result
    if message_label:
        message_label.text = "MISSION  •  " + result

func _jump_pressed() -> void:
    if player and not player.in_vehicle:
        if player.is_on_floor():
            player.velocity.y = 7.0
            if message_label:
                message_label.text = "ACTION  •  JUMP"
        else:
            if message_label:
                message_label.text = "ACTION  •  LAND FIRST"

func _process(_delta: float) -> void:
    if not player:
        return
    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        if speed_label:
            speed_label.text = "%d km/h" % int(player.vehicle.speed_kmh)
        if vehicle_label:
            vehicle_label.text = "VEHICLE  •  DRIVING"
        if act_button:
            act_button.text = "EXIT"
    else:
        if speed_label:
            speed_label.text = "0 km/h"
        if vehicle_label and not vehicle_label.text.begins_with("VEHICLE  •  WALK"):
            vehicle_label.text = "VEHICLE  •  ON FOOT"
        if act_button:
            act_button.text = "ACT"

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.position.x < 250.0 and event.position.y > 450.0:
            joy_active = event.pressed
            if not joy_active and player:
                player.set_joystick(Vector2.ZERO)
            get_viewport().set_input_as_handled()
            return

        if event.pressed and event.position.x > 720.0 and event.position.y < 560.0:
            camera_dragging = true
            last_look = event.position
            get_viewport().set_input_as_handled()
            return

        if not event.pressed:
            camera_dragging = false

    elif event is InputEventScreenDrag:
        if joy_active and event.position.x < 270.0 and event.position.y > 430.0:
            var v := (event.position - joy_center) / 70.0
            var joy := Vector2(clamp(v.x,-1.0,1.0), clamp(v.y,-1.0,1.0))
            if player:
                player.set_joystick(joy)
            get_viewport().set_input_as_handled()
        elif camera_dragging:
            var delta_screen := event.position - last_look
            if player:
                player.look_camera(delta_screen)
            last_look = event.position
            get_viewport().set_input_as_handled()
