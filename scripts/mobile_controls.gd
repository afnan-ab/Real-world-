extends CanvasLayer

# Step 13: mobile-safe input layer.
# Gameplay touch zones use GUI input so joystick/look stay independent from
# action buttons. Buttons are connected only here to avoid duplicate signals.

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
var drive_button: Button
var action_button: Button
var gas_button: Button
var brake_button: Button
var exit_car_button: Button
var run_touch := false
var gas_touch := false
var brake_touch := false

const LOOK_SENSITIVITY := 0.72
const INPUT_DEADZONE := 0.08

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
    drive_button = get_node_or_null("Drive") as Button
    action_button = get_node_or_null("Action") as Button
    gas_button = get_node_or_null("Gas") as Button
    brake_button = get_node_or_null("Brake") as Button
    exit_button = get_node_or_null("ExitCar") as Button
    gas_button = get_node_or_null("Gas") as Button
    brake_button = get_node_or_null("Brake") as Button
    exit_car_button = get_node_or_null("ExitCar") as Button

    _style_mobile_button(run_button)
    _style_mobile_button(jump_button)
    _style_mobile_button(drive_button)
    _style_mobile_button(action_button)
    _style_mobile_button(gas_button)
    _style_mobile_button(brake_button)
    _style_mobile_button(exit_button)
    _style_mobile_button(gas_button)
    _style_mobile_button(brake_button)
    _style_mobile_button(exit_car_button)

    # Buttons support multitouch on touch input in Godot, so keep them as
    # normal Buttons while routing all gameplay actions through this layer.
    if run_button:
        run_button.focus_mode = Control.FOCUS_NONE
        run_button.mouse_filter = Control.MOUSE_FILTER_STOP
        run_button.button_down.connect(_on_run_down)
        run_button.button_up.connect(_on_run_up)

    if act_button:
        act_button.focus_mode = Control.FOCUS_NONE
        act_button.mouse_filter = Control.MOUSE_FILTER_STOP
        act_button.pressed.connect(_on_act_pressed)

    if jump_button:
        jump_button.focus_mode = Control.FOCUS_NONE
        jump_button.mouse_filter = Control.MOUSE_FILTER_STOP
        jump_button.pressed.connect(_on_jump_pressed)

    if drive_button:
        drive_button.focus_mode = Control.FOCUS_NONE
        drive_button.mouse_filter = Control.MOUSE_FILTER_STOP
        drive_button.pressed.connect(_on_drive_pressed)

    if action_button:
        action_button.focus_mode = Control.FOCUS_NONE
        action_button.mouse_filter = Control.MOUSE_FILTER_STOP
        action_button.pressed.connect(_on_action_pressed)
    if gas_button:
        gas_button.focus_mode = Control.FOCUS_NONE
        gas_button.button_down.connect(_on_gas_down)
        gas_button.button_up.connect(_on_gas_up)
    if brake_button:
        brake_button.focus_mode = Control.FOCUS_NONE
        brake_button.button_down.connect(_on_brake_down)
        brake_button.button_up.connect(_on_brake_up)
    if exit_button:
        exit_button.focus_mode = Control.FOCUS_NONE
        exit_button.pressed.connect(_on_exit_pressed)

    _connect_hold_button(gas_button, true, false)
    _connect_hold_button(brake_button, false, true)
    if exit_car_button:
        exit_car_button.focus_mode = Control.FOCUS_NONE
        exit_car_button.mouse_filter = Control.MOUSE_FILTER_STOP
        exit_car_button.pressed.connect(_on_exit_car_pressed)

func _process(_delta: float) -> void:
    if player == null or not is_instance_valid(player):
        player = world.get_node_or_null("Player")
        if player == null:
            return

    _update_context_controls()
    _apply_joystick()

func _update_context_controls() -> void:
    var in_car := player != null and is_instance_valid(player) and player.in_vehicle
    if run_button: run_button.visible = not in_car
    if jump_button: jump_button.visible = not in_car
    if action_button: action_button.visible = not in_car
    if drive_button: drive_button.visible = not in_car
    if gas_button: gas_button.visible = in_car
    if brake_button: brake_button.visible = in_car
    if exit_car_button: exit_car_button.visible = in_car
    if drive_button: drive_button.text = "ENTER" if not in_car else "DRIVE"

func _connect_hold_button(button: Button, gas: bool, brake: bool) -> void:
    if button == null: return
    button.focus_mode = Control.FOCUS_NONE
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.button_down.connect(func(): gas_touch = gas; brake_touch = brake; _apply_vehicle_pedals())
    button.button_up.connect(func(): gas_touch = false; brake_touch = false; _apply_vehicle_pedals())

func _apply_vehicle_pedals() -> void:
    if player == null or not is_instance_valid(player) or not player.in_vehicle or player.vehicle == null: return
    var car = player.vehicle
    if is_instance_valid(car) and car.has_method("set_mobile_pedals"):
        car.set_mobile_pedals(gas_touch, brake_touch)

func _on_exit_car_pressed() -> void:
    if world and world.has_method("_on_hud_act_pressed"):
        world.call("_on_hud_act_pressed")
    gas_touch = false
    brake_touch = false

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
        var delta_look := (event.position - look_last) * LOOK_SENSITIVITY
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
        player.look_camera((event.position - look_last) * LOOK_SENSITIVITY)
        look_last = event.position
        look_zone.accept_event()

func _set_joystick_from_local(pos: Vector2) -> void:
    var center := joystick_zone.size * 0.5
    var radius := min(joystick_zone.size.x, joystick_zone.size.y) * 0.5
    var v := (pos - center) / max(radius, 1.0)
    joystick = Vector2(clamp(v.x, -1.0, 1.0), clamp(v.y, -1.0, 1.0))
    if joystick.length() > 1.0:
        joystick = joystick.normalized()
    if joystick.length() < INPUT_DEADZONE:
        joystick = Vector2.ZERO
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
    if run_touch and applied.length() < INPUT_DEADZONE:
        applied = Vector2(0.0, -1.0)

    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        player.vehicle.set_joystick(applied)
        _apply_vehicle_pedals()
    else:
        player.set_joystick(applied)

func _on_run_down() -> void:
    run_touch = true
    if player and is_instance_valid(player):
        player.set_sprint(true)
    if run_button:
        run_button.text = "STOP"
    _apply_joystick()

func _on_run_up() -> void:
    run_touch = false
    if player and is_instance_valid(player):
        player.set_sprint(false)
    if run_button:
        run_button.text = "RUN"
    _apply_joystick()


func _style_mobile_button(button: Button) -> void:
    if button == null:
        return
    button.add_theme_font_size_override("font_size", 15)
    button.add_theme_constant_override("outline_size", 2)
    button.add_theme_color_override("font_color", Color("#eaf4f5"))
    button.add_theme_color_override("font_hover_color", Color("#ffffff"))
    button.add_theme_color_override("font_pressed_color", Color("#ffffff"))

func _on_drive_pressed() -> void:
    if world and world.has_method("_on_hud_act_pressed"):
        world.call("_on_hud_act_pressed")

func _on_action_pressed() -> void:
    if world and world.has_method("_on_hud_action_pressed"):
        world.call("_on_hud_action_pressed")

func _on_act_pressed() -> void:
    if world and world.has_method("_on_hud_act_pressed"):
        world.call("_on_hud_act_pressed")

func _on_jump_pressed() -> void:
    if world and world.has_method("_on_hud_jump_pressed"):
        world.call("_on_hud_jump_pressed")
