extends CanvasLayer

var player: Node
var world: Node
var root: Control
var speed_label: Label
var vehicle_label: Label
var mission_label: Label
var weather_label: Label
var action_button: Button
var joystick_center := Vector2.ZERO
var joystick := Vector2.ZERO
var dragging := false
var look_dragging := false
var look_last := Vector2.ZERO
var joy_base: Panel
var joy_knob: Panel

func _ready() -> void:
    player = get_parent().get_node_or_null("Player")
    world = get_parent()

    root = Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_PASS
    add_child(root)
    _build_hud()
    get_viewport().size_changed.connect(_layout)

func _panel(pos: Vector2, size: Vector2, alpha := 0.72) -> Panel:
    var p := Panel.new()
    p.position = pos
    p.size = size
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0.015,0.025,0.03,alpha)
    s.border_width_left = 1
    s.border_width_top = 1
    s.border_width_right = 1
    s.border_width_bottom = 1
    s.border_color = Color(0.65,0.78,0.80,0.28)
    s.corner_radius_top_left = 12
    s.corner_radius_top_right = 12
    s.corner_radius_bottom_left = 12
    s.corner_radius_bottom_right = 12
    p.add_theme_stylebox_override("panel",s)
    root.add_child(p)
    return p

func _label(text_value: String, pos: Vector2, font_size := 16) -> Label:
    var l := Label.new()
    l.text = text_value
    l.position = pos
    l.add_theme_font_size_override("font_size",font_size)
    l.add_theme_color_override("font_color",Color("#edf3f2"))
    root.add_child(l)
    return l

func _button(text_value: String, pos: Vector2, size: Vector2) -> Button:
    var b := Button.new()
    b.text = text_value
    b.position = pos
    b.size = size
    b.add_theme_font_size_override("font_size",16)
    var s := StyleBoxFlat.new()
    s.bg_color = Color(0.02,0.04,0.05,0.78)
    s.border_width_left=1; s.border_width_top=1; s.border_width_right=1; s.border_width_bottom=1
    s.border_color=Color(0.75,0.84,0.84,0.35)
    s.corner_radius_top_left=16; s.corner_radius_top_right=16
    s.corner_radius_bottom_left=16; s.corner_radius_bottom_right=16
    b.add_theme_stylebox_override("normal",s)
    b.add_theme_stylebox_override("hover",s)
    root.add_child(b)
    return b

func _build_hud() -> void:
    _panel(Vector2(20,20),Vector2(360,86),0.80)
    _label("REAL WORLD",Vector2(36,29),25)
    _label("ONLINE  •  CITY  •  FREE ROAM",Vector2(37,61),13)

    var wanted := _label("WANTED  ☆ ☆ ☆ ☆ ☆",Vector2(455,28),17)
    wanted.add_theme_color_override("font_color",Color("#f2d47c"))
    mission_label = _label("MISSION  •  FREE ROAM",Vector2(455,58),14)
    vehicle_label = _label("VEHICLE  •  WALK TO CAR",Vector2(455,82),14)

    var map := _panel(Vector2(1045,20),Vector2(215,145),0.84)
    var mt := Label.new()
    mt.text="CITY MAP\n\n       • YOU\n    ───┼───\n       │\n   CIVIC   LAKE"
    mt.position=Vector2(16,12)
    mt.add_theme_font_size_override("font_size",13)
    mt.add_theme_color_override("font_color",Color("#dfe9e7"))
    map.add_child(mt)

    weather_label = _label("CLEAR  •  08:00",Vector2(38,116),13)

    joy_base = _panel(Vector2(42,500),Vector2(150,150),0.30)
    joy_base.modulate=Color(1,1,1,0.75)
    joy_knob = _panel(Vector2(92,550),Vector2(50,50),0.55)
    joy_knob.modulate=Color(0.85,0.93,0.95,0.9)

    speed_label = _label("0 km/h",Vector2(575,625),28)
    speed_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
    speed_label.size=Vector2(140,42)

    var run := _button("RUN",Vector2(1060,625),Vector2(82,58))
    run.button_down.connect(func(): if player: player.set_sprint(true))
    run.button_up.connect(func(): if player: player.set_sprint(false))

    action_button = _button("ACT",Vector2(1168,575),Vector2(82,82))
    action_button.pressed.connect(_action_pressed)

    var jump := _button("JUMP",Vector2(1168,665),Vector2(82,48))
    jump.pressed.connect(func(): if player and player.is_on_floor(): player.velocity.y=7.0)

    _layout()

func _layout() -> void:
    if not root: return
    var size := get_viewport().get_visible_rect().size
    var sx: float = size.x / 1280.0
    var sy: float = size.y / 720.0
    root.scale = Vector2(min(sx,sy),min(sx,sy))
    var s := root.scale.x
    root.position = Vector2((size.x-1280.0*s)*0.5,(size.y-720.0*s)*0.5)

func _process(_delta: float) -> void:
    if not player: return
    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        speed_label.text="%d km/h" % int(player.vehicle.speed_kmh)
        vehicle_label.text="VEHICLE  •  DRIVING"
        action_button.text="EXIT"
    else:
        speed_label.text="0 km/h"
        vehicle_label.text="VEHICLE  •  DRIVE"
        action_button.text="DRIVE"
    if world:
        mission_label.text="MISSION  •  " + ("ACTIVE" if world.mission_active else "FREE ROAM")
        weather_label.text="%s  •  %02d:%02d" % [str(world.weather).to_upper(),int(world.time_of_day),int((world.time_of_day-int(world.time_of_day))*60.0)]

func _action_pressed() -> void:
    if player and world:
        world.toggle_vehicle(player)

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var p:=event.position
        if p.x < 250.0 and p.y > 440.0:
            dragging=event.pressed
            if dragging:
                joystick_center=Vector2(117,575)
            else:
                joystick=Vector2.ZERO
                if player: player.set_joystick(Vector2.ZERO)
            get_viewport().set_input_as_handled()
        elif p.x > 700.0 and p.y > 180.0:
            look_dragging=event.pressed
            if look_dragging: look_last=p
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag:
        if dragging:
            var v:Vector2=(event.position-joystick_center)/72.0
            joystick=Vector2(clamp(v.x,-1.0,1.0),clamp(v.y,-1.0,1.0))
            if player: player.set_joystick(joystick)
            if joy_knob: joy_knob.position=joystick_center+joystick*48.0-Vector2(25,25)
            get_viewport().set_input_as_handled()
        elif look_dragging:
            var dl:=event.position-look_last
            if player: player.look_camera(dl)
            look_last=event.position
            get_viewport().set_input_as_handled()
