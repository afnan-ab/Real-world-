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
var joystick_visual: Control
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
    joystick_visual = get_node_or_null("Joystick") as Control

    if joystick_visual:
        joystick_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
        joystick_visual.modulate = Color(1, 1, 1, 0)
        _build_joystick_visual()

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
    exit_car_button = get_node_or_null("ExitCar") as Button

    _style_mobile_button(run_button)
    _style_mobile_button(jump_button)
    _style_mobile_button(drive_button)
    _style_mobile_button(action_button)
    _style_mobile_button(gas_button)
    _style_mobile_button(brake_button)
    _style_mobile_button(exit_car_button)

    # Preserve the full control set while allowing responsive sizing.
    for button in [run_button, jump_button, drive_button, action_button, gas_button, brake_button, exit_car_button]:
        if button:
            button.custom_minimum_size = Vector2.ZERO

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
    _connect_hold_button(gas_button, true, false)
    _connect_hold_button(brake_button, false, true)
    if exit_car_button:
        exit_car_button.focus_mode = Control.FOCUS_NONE
        exit_car_button.mouse_filter = Control.MOUSE_FILTER_STOP
        exit_car_button.pressed.connect(_on_exit_car_pressed)

func _layout_mobile_hud() -> void:
    var size := get_viewport().get_visible_rect().size
    var short_side := min(size.x, size.y)
    var button_h := clamp(short_side * 0.105, 58.0, 86.0)
    var button_w := clamp(short_side * 0.145, 82.0, 118.0)
    var margin := clamp(short_side * 0.026, 16.0, 28.0)
    if run_button and not player.in_vehicle:
        run_button.custom_minimum_size = Vector2.ZERO
        run_button.size = Vector2(button_w, button_h)
        run_button.position = Vector2(size.x - button_w * 2.05 - margin, size.y - button_h - margin)
    if jump_button and not player.in_vehicle:
        jump_button.custom_minimum_size = Vector2.ZERO
        jump_button.size = Vector2(button_w, button_h)
        jump_button.position = Vector2(size.x - button_w - margin, size.y - button_h - margin)
    if action_button and not player.in_vehicle:
        action_button.custom_minimum_size = Vector2.ZERO
        action_button.size = Vector2(button_w, button_h)
        action_button.position = Vector2(size.x - button_w * 2.05 - margin, size.y - button_h * 2.15 - margin)
    if drive_button and not player.in_vehicle:
        drive_button.custom_minimum_size = Vector2.ZERO
        drive_button.size = Vector2(button_w, button_h)
        drive_button.position = Vector2(size.x - button_w - margin, size.y - button_h * 2.15 - margin)
    if gas_button and player.in_vehicle:
        gas_button.custom_minimum_size = Vector2.ZERO
        gas_button.size = Vector2(button_w, button_h)
        gas_button.position = Vector2(size.x - button_w * 2.05 - margin, size.y - button_h * 2.15 - margin)
    if brake_button and player.in_vehicle:
        brake_button.custom_minimum_size = Vector2.ZERO
        brake_button.size = Vector2(button_w, button_h)
        brake_button.position = Vector2(size.x - button_w - margin, size.y - button_h * 2.15 - margin)
    if exit_car_button and player.in_vehicle:
        exit_car_button.custom_minimum_size = Vector2.ZERO
        exit_car_button.size = Vector2(button_w, button_h)
        exit_car_button.position = Vector2(size.x - button_w - margin, size.y - button_h - margin)

    for button in [run_button, jump_button, action_button, drive_button, action_button, gas_button, brake_button, exit_car_button]:
        if button:
            button.pivot_offset = button.size * 0.5

func _process(_delta: float) -> void:
    if player == null or not is_instance_valid(player):
        player = world.get_node_or_null("Player")
        if player == null:
            return

    _update_context_controls()
    _layout_mobile_hud()
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

    if run_button:
        run_button.text = "↗  RUN"
    if jump_button:
        jump_button.text = "↑  JUMP"
    if action_button:
        action_button.text = "✦  ACTION"
    if drive_button:
        drive_button.text = "▸  DRIVE"
    if gas_button:
        gas_button.text = "●  GAS"
    if brake_button:
        brake_button.text = "■  BRAKE"
    if exit_car_button:
        exit_car_button.text = "↩  EXIT"

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


func _build_joystick_visual() -> void:
    if joystick_zone == null:
        return
    var ring := Panel.new()
    ring.name = "JoystickGlassRing"
    ring.position = Vector2(8, 8)
    ring.size = Vector2(134, 134)
    ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var ring_style := StyleBoxFlat.new()
    ring_style.bg_color = Color(0.02, 0.05, 0.065, 0.30)
    ring_style.border_color = Color(0.58, 0.82, 0.84, 0.36)
    ring_style.set_border_width_all(2)
    ring_style.set_corner_radius_all(67)
    ring_style.anti_aliasing = true
    ring.add_theme_stylebox_override("panel", ring_style)
    joystick_zone.add_child(ring)

func _style_mobile_button(button: Button) -> void:
    if button == null:
        return

    # Glass/HUD control language: large hit areas, high contrast and a clear
    # pressed state. The actual action remains readable without relying on color.
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 15)
    button.add_theme_constant_override("outline_size", 1)
    button.add_theme_color_override("font_color", Color("#edf7f8"))
    button.add_theme_color_override("font_hover_color", Color("#ffffff"))
    button.add_theme_color_override("font_pressed_color", Color("#ffffff"))
    button.add_theme_color_override("font_outline_color", Color("#071116"))

    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.025, 0.055, 0.07, 0.78)
    normal.border_color = Color(0.48, 0.78, 0.82, 0.55)
    normal.set_border_width_all(1)
    normal.corner_radius_top_left = 22
    normal.corner_radius_top_right = 22
    normal.corner_radius_bottom_left = 22
    normal.corner_radius_bottom_right = 22
    normal.anti_aliasing = true
    normal.shadow_color = Color(0,0,0,0.30)
    normal.shadow_size = 7
    normal.shadow_offset = Vector2(0, 2)
    normal.content_margin_left = 10
    normal.content_margin_right = 10
    normal.content_margin_top = 8
    normal.content_margin_bottom = 8

    var hover := normal.duplicate()
    hover.bg_color = Color(0.06, 0.15, 0.18, 0.90)
    hover.border_color = Color(0.58, 0.88, 0.90, 0.78)

    var pressed := normal.duplicate()
    pressed.bg_color = Color(0.12, 0.30, 0.34, 0.96)
    pressed.border_color = Color(0.70, 0.94, 0.95, 0.95)
    pressed.shadow_size = 2
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_stylebox_override("focus", pressed)

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
