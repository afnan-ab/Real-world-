extends CanvasLayer

# Step 13: mobile-safe input layer.
# Gameplay touch zones use GUI input so joystick/look stay independent from
# action buttons. Buttons are connected only here to avoid duplicate signals.
#
# Bug-fix pass: the joystick ring and knob are now laid out from the real size
# of the joystick zone (they used to be off-centre and the knob started in the
# corner), and every Variant-returning call is explicitly typed.

var world: Node
var player: Node
var joystick: Vector2 = Vector2.ZERO
var joystick_touch_id: int = -1
var look_touch_id: int = -1
var look_last: Vector2 = Vector2.ZERO
var joystick_zone: Control
var look_zone: Control
var knob: ColorRect
var joystick_ring: Panel
var ring_style: StyleBoxFlat
var run_button: Button
var act_button: Button
var jump_button: Button
var drive_button: Button
var action_button: Button
var gas_button: Button
var brake_button: Button
var exit_car_button: Button
var joystick_visual: Control
var run_touch: bool = false
var gas_touch: bool = false
var brake_touch: bool = false

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
        joystick_visual.visible = false
        joystick_visual.modulate = Color(1, 1, 1, 0)

    if joystick_zone:
        joystick_zone.mouse_filter = Control.MOUSE_FILTER_STOP
        joystick_zone.gui_input.connect(_on_joystick_gui_input)
        _build_joystick_visual()

        knob = ColorRect.new()
        knob.size = Vector2(40, 40)
        knob.color = Color(0.85, 0.92, 0.95, 0.52)
        knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
        joystick_zone.add_child(knob)
        joystick_zone.resized.connect(_layout_joystick_visuals)
        _reset_joystick()
        _layout_joystick_visuals.call_deferred()

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

    _style_mobile_button(run_button, Color("#35b6a0"))
    _style_mobile_button(jump_button, Color("#4b9bff"))
    _style_mobile_button(drive_button, Color("#38b8d7"))
    _style_mobile_button(action_button, Color("#f0b84b"))
    _style_mobile_button(gas_button, Color("#35c879"))
    _style_mobile_button(brake_button, Color("#ef6868"))
    _style_mobile_button(exit_car_button, Color("#9aa9b5"))

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

func _player_in_car() -> bool:
    if player == null or not is_instance_valid(player):
        return false
    return bool(player.get("in_vehicle"))

func _layout_mobile_hud() -> void:
    var view_size: Vector2 = get_viewport().get_visible_rect().size
    var short_side: float = minf(view_size.x, view_size.y)
    var button_h: float = clampf(short_side * 0.112, 64.0, 88.0)
    var button_w: float = clampf(short_side * 0.150, 88.0, 120.0)
    var margin: float = clampf(short_side * 0.025, 16.0, 26.0)
    var in_car: bool = _player_in_car()
    var bottom_y: float = view_size.y - button_h - margin
    var upper_y: float = view_size.y - button_h * 2.15 - margin
    var right_x: float = view_size.x - button_w - margin
    var left_x: float = view_size.x - button_w * 2.05 - margin

    if not in_car:
        _place_button(run_button, Vector2(button_w, button_h), Vector2(left_x, bottom_y))
        _place_button(jump_button, Vector2(button_w, button_h), Vector2(right_x, bottom_y))
        _place_button(action_button, Vector2(button_w, button_h), Vector2(left_x, upper_y))
        _place_button(drive_button, Vector2(button_w, button_h), Vector2(right_x, upper_y))
    else:
        _place_button(gas_button, Vector2(button_w, button_h), Vector2(left_x, upper_y))
        _place_button(brake_button, Vector2(button_w, button_h), Vector2(right_x, upper_y))
        _place_button(exit_car_button, Vector2(button_w, button_h), Vector2(right_x, bottom_y))

func _place_button(button: Button, button_size: Vector2, button_pos: Vector2) -> void:
    if button == null:
        return
    button.custom_minimum_size = Vector2.ZERO
    button.size = button_size
    button.position = button_pos
    button.pivot_offset = button_size * 0.5

func _process(_delta: float) -> void:
    if player == null or not is_instance_valid(player):
        player = world.get_node_or_null("Player")
        if player == null:
            return

    _update_context_controls()
    _layout_mobile_hud()
    _apply_joystick()

func _update_context_controls() -> void:
    var in_car: bool = _player_in_car()
    if run_button: run_button.visible = not in_car
    if jump_button: jump_button.visible = not in_car
    if action_button: action_button.visible = not in_car
    if drive_button: drive_button.visible = not in_car
    if gas_button: gas_button.visible = in_car
    if brake_button: brake_button.visible = in_car
    if exit_car_button: exit_car_button.visible = in_car

    if run_button:
        run_button.text = "SPRINT" if run_touch else "RUN"
    if jump_button:
        jump_button.text = "JUMP"
    if action_button:
        action_button.text = "ACTION"
    if drive_button:
        drive_button.text = "DRIVE"
    if gas_button:
        gas_button.text = "GAS"
    if brake_button:
        brake_button.text = "BRAKE"
    if exit_car_button:
        exit_car_button.text = "EXIT"

func _connect_hold_button(button: Button, gas: bool, brake: bool) -> void:
    if button == null:
        return
    button.focus_mode = Control.FOCUS_NONE
    button.mouse_filter = Control.MOUSE_FILTER_STOP
    button.button_down.connect(func() -> void:
        gas_touch = gas
        brake_touch = brake
        _apply_vehicle_pedals())
    button.button_up.connect(func() -> void:
        gas_touch = false
        brake_touch = false
        _apply_vehicle_pedals())

func _current_vehicle() -> Object:
    if not _player_in_car():
        return null
    var car: Object = player.get("vehicle")
    if car != null and is_instance_valid(car):
        return car
    return null

func _apply_vehicle_pedals() -> void:
    var car: Object = _current_vehicle()
    if car != null and car.has_method("set_mobile_pedals"):
        car.call("set_mobile_pedals", gas_touch, brake_touch)

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
    if player == null or not is_instance_valid(player):
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
        var delta_look: Vector2 = (event.position - look_last) * LOOK_SENSITIVITY
        player.call("look_camera", delta_look)
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
        player.call("look_camera", (event.position - look_last) * LOOK_SENSITIVITY)
        look_last = event.position
        look_zone.accept_event()

func _joystick_radius() -> float:
    if joystick_zone == null:
        return 60.0
    return maxf(minf(joystick_zone.size.x, joystick_zone.size.y) * 0.38, 1.0)

func _set_joystick_from_local(pos: Vector2) -> void:
    var center: Vector2 = joystick_zone.size * 0.5
    var v: Vector2 = (pos - center) / _joystick_radius()
    joystick = Vector2(clampf(v.x, -1.0, 1.0), clampf(v.y, -1.0, 1.0))
    if joystick.length() > 1.0:
        joystick = joystick.normalized()
    if joystick.length() < INPUT_DEADZONE:
        joystick = Vector2.ZERO
    _move_knob()
    _apply_joystick()

func _move_knob() -> void:
    if knob == null or joystick_zone == null:
        return
    var center: Vector2 = joystick_zone.size * 0.5
    knob.position = center + joystick * _joystick_radius() - knob.size * 0.5

func _layout_joystick_visuals() -> void:
    if joystick_zone == null:
        return
    if joystick_ring != null:
        var diameter: float = maxf(minf(joystick_zone.size.x, joystick_zone.size.y) - 8.0, 20.0)
        joystick_ring.size = Vector2(diameter, diameter)
        joystick_ring.position = (joystick_zone.size - joystick_ring.size) * 0.5
        if ring_style != null:
            ring_style.set_corner_radius_all(int(diameter * 0.5))
    _move_knob()

func _reset_joystick() -> void:
    joystick = Vector2.ZERO
    _move_knob()

func _apply_joystick() -> void:
    if player == null or not is_instance_valid(player):
        return

    var applied: Vector2 = joystick
    if run_touch and applied.length() < INPUT_DEADZONE:
        applied = Vector2(0.0, -1.0)

    var car: Object = _current_vehicle()
    if car != null:
        car.call("set_joystick", applied)
        _apply_vehicle_pedals()
    else:
        player.call("set_joystick", applied)

func _on_run_down() -> void:
    run_touch = true
    if player and is_instance_valid(player):
        player.call("set_sprint", true)
    if run_button:
        run_button.text = "STOP"
    _apply_joystick()

func _on_run_up() -> void:
    run_touch = false
    if player and is_instance_valid(player):
        player.call("set_sprint", false)
    if run_button:
        run_button.text = "RUN"
    _apply_joystick()

func _build_joystick_visual() -> void:
    if joystick_zone == null:
        return
    joystick_ring = Panel.new()
    joystick_ring.name = "JoystickGlassRing"
    joystick_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ring_style = StyleBoxFlat.new()
    ring_style.bg_color = Color(0.02, 0.05, 0.065, 0.30)
    ring_style.border_color = Color(0.58, 0.82, 0.84, 0.36)
    ring_style.set_border_width_all(2)
    ring_style.set_corner_radius_all(67)
    ring_style.anti_aliasing = true
    joystick_ring.add_theme_stylebox_override("panel", ring_style)
    joystick_zone.add_child(joystick_ring)

func _style_mobile_button(button: Button, accent: Color) -> void:
    if button == null:
        return

    # Thumb-friendly arcade HUD: strong contrast, colored edge, translucent fill,
    # large readable labels, and an unmistakable tactile pressed state.
    button.focus_mode = Control.FOCUS_NONE
    button.add_theme_font_size_override("font_size", 17)
    button.add_theme_constant_override("outline_size", 2)
    button.add_theme_color_override("font_color", Color("#f7fbff"))
    button.add_theme_color_override("font_hover_color", Color("#ffffff"))
    button.add_theme_color_override("font_pressed_color", Color("#ffffff"))
    button.add_theme_color_override("font_outline_color", Color("#071116"))
    button.add_theme_color_override("icon_normal_color", Color("#ffffff"))

    var normal := StyleBoxFlat.new()
    # Higher opacity keeps touch controls readable over bright sky, dark roads,
    # and weather effects. The accent edge stays visible without reducing buttons.
    normal.bg_color = Color(accent.r * 0.24, accent.g * 0.24, accent.b * 0.24, 0.97)
    normal.border_color = Color(accent.r, accent.g, accent.b, 1.0)
    normal.set_border_width_all(2)
    normal.set_corner_radius_all(20)
    normal.anti_aliasing = true
    normal.shadow_color = Color(0, 0, 0, 0.62)
    normal.shadow_size = 9
    normal.shadow_offset = Vector2(0, 3)
    normal.content_margin_left = 7
    normal.content_margin_right = 7
    normal.content_margin_top = 6
    normal.content_margin_bottom = 6

    var hover := normal.duplicate() as StyleBoxFlat
    hover.bg_color = Color(accent.r * 0.42, accent.g * 0.42, accent.b * 0.42, 0.99)
    hover.border_color = Color(accent.r, accent.g, accent.b, 1.0)
    hover.shadow_size = 10

    var pressed := normal.duplicate() as StyleBoxFlat
    pressed.bg_color = Color(accent.r * 0.58, accent.g * 0.58, accent.b * 0.58, 1.0)
    pressed.border_color = Color("#ffffff")
    pressed.set_border_width_all(3)
    pressed.shadow_size = 2
    pressed.shadow_offset = Vector2(0, 1)

    button.add_theme_stylebox_override("normal", normal)
    button.add_theme_stylebox_override("hover", hover)
    button.add_theme_stylebox_override("pressed", pressed)
    button.add_theme_stylebox_override("focus", pressed)
    button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

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
