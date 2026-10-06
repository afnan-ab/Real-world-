extends CanvasLayer

# Single mobile input layer.
# Buttons are handled here, while touch zones use Control._gui_input so
# Android GUI input is not mixed with hard-coded 1280x720 screen coordinates.

var world: Node
var player: Node
var joystick := Vector2.ZERO
var joystick_touch_id := -1
var look_touch_id := -1
var look_last := Vector2.ZERO
var joystick_zone: Control
var look_zone: Control
var knob: ColorRect
var run_button: Button
var act_button: Button
var jump_button: Button
var run_touch := false

func _ready() -> void:
    layer = 220
    world = get_parent()
    player = world.get_node_or_null("Player")

    joystick_zone = get_node_or_null("JoystickZone") as Control
    look_zone = get_node_or_null("LookZone") as Control

    if joystick_zone:
        joystick_zone.mouse_filter = Control.MOUSE_FILTER_STOP
        joystick_zone.gui_input.connect(_on_joystick_gui_input)

        knob = ColorRect.new()
        knob.size = Vector2(40, 40)
        knob.color = Color(0.85, 0.92, 0.95, 0.52)
        knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
        joystick_zone.add_child(knob)
        _reset_joystick()

    if look_zone:
        look_zone.mouse_filter = Control.MOUSE_FILTER_STOP
        look_zone.gui_input.connect(_on_look_gui_input)

    run_button = get_node_or_null("Run") as Button
    act_button = get_node_or_null("Act") as Button
    jump_button = get_node_or_null("Jump") as Button

    # All action buttons are owned by this layer. This removes the old split
    # path where scene connections and touch code could compete.
    if run_button:
        run_button.focus_mode = Control.FOCUS_NONE
        run_button.button_down.connect(_on_run_down)
        run_button.button_up.connect(_on_run_up)

    if act_button:
        act_button.focus_mode = Control.FOCUS_NONE
        act_button.pressed.connect(_on_act_pressed)

    if jump_button:
        jump_button.focus_mode = Control.FOCUS_NONE
        jump_button.pressed.connect(_on_jump_pressed)

func _process(_delta: float) -> void:
    if player == null or not is_instance_valid(player):
        player = world.get_node_or_null("Player")
        if player == null:
            return

    var applied := joystick
    if run_touch and applied.length() < 0.08:
        applied = Vector2(0.0, -1.0)

    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        player.vehicle.set_joystick(applied)
    else:
        player.set_joystick(applied)

func _on_joystick_gui_input(event: InputEvent) -> void:
    if joystick_zone == null:
        return

    if event is InputEventScreenTouch:
        if event.pressed and joystick_touch_id == -1:
            joystick_touch_id = event.index
            _set_joystick_from_local(event.position)
            joystick_zone.accept_event()
        elif not event.pressed and event.index == joystick_touch_id:
            joystick_touch_id = -1
            joystick = Vector2.ZERO
            _reset_joystick()
            _apply_joystick()
            joystick_zone.accept_event()

    elif event is InputEventScreenDrag and event.index == joystick_touch_id:
        _set_joystick_from_local(event.position)
        joystick_zone.accept_event()

    # Desktop testing fallback: mouse acts like one joystick finger.
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            joystick_touch_id = -2
            _set_joystick_from_local(event.position)
        elif joystick_touch_id == -2:
            joystick_touch_id = -1
            joystick = Vector2.ZERO
            _reset_joystick()
            _apply_joystick()
        joystick_zone.accept_event()

    elif event is InputEventMouseMotion and joystick_touch_id == -2:
        _set_joystick_from_local(event.position)
        joystick_zone.accept_event()

func _on_look_gui_input(event: InputEvent) -> void:
    if player == null:
        return

    if event is InputEventScreenTouch:
        if event.pressed and look_touch_id == -1:
            look_touch_id = event.index
            look_last = event.position
            look_zone.accept_event()
        elif not event.pressed and event.index == look_touch_id:
            look_touch_id = -1
            look_zone.accept_event()

    elif event is InputEventScreenDrag and event.index == look_touch_id:
        var delta_look := event.position - look_last
        player.look_camera(delta_look)
        look_last = event.position
        look_zone.accept_event()

    # Desktop testing fallback.
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            look_touch_id = -2
            look_last = event.position
        elif look_touch_id == -2:
            look_touch_id = -1
        look_zone.accept_event()

    elif event is InputEventMouseMotion and look_touch_id == -2:
        player.look_camera(event.position - look_last)
        look_last = event.position
        look_zone.accept_event()

func _set_joystick_from_local(pos: Vector2) -> void:
    var center := joystick_zone.size * 0.5
    var radius := min(joystick_zone.size.x, joystick_zone.size.y) * 0.5
    var v := (pos - center) / max(radius, 1.0)
    joystick = Vector2(clamp(v.x, -1.0, 1.0), clamp(v.y, -1.0, 1.0))
    if joystick.length() > 1.0:
        joystick = joystick.normalized()
    _move_knob()
    _apply_joystick()

func _move_knob() -> void:
    if knob == null or joystick_zone == null:
        return
    var center := joystick_zone.size * 0.5
    var travel := min(joystick_zone.size.x, joystick_zone.size.y) * 0.34
    knob.position = center + joystick * travel - knob.size * 0.5

func _reset_joystick() -> void:
    joystick = Vector2.ZERO
    _move_knob()

func _apply_joystick() -> void:
    if player == null or not is_instance_valid(player):
        return
    var applied := joystick
    if run_touch and applied.length() < 0.08:
        applied = Vector2(0.0, -1.0)

    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        player.vehicle.set_joystick(applied)
    else:
        player.set_joystick(applied)

func _on_run_down() -> void:
    run_touch = true
    if player:
        player.set_sprint(true)
    if run_button:
        run_button.text = "STOP"
    _apply_joystick()

func _on_run_up() -> void:
    run_touch = false
    if player:
        player.set_sprint(false)
    if run_button:
        run_button.text = "RUN"
    _apply_joystick()

func _on_act_pressed() -> void:
    if world and world.has_method("_on_hud_act_pressed"):
        world.call("_on_hud_act_pressed")

func _on_jump_pressed() -> void:
    if world and world.has_method("_on_hud_jump_pressed"):
        world.call("_on_hud_jump_pressed")
