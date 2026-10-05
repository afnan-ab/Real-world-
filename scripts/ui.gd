extends CanvasLayer

var player: Node
var world: Node
var joystick_center := Vector2.ZERO
var dragging := false
var look_dragging := false
var look_last := Vector2.ZERO
var joystick := Vector2.ZERO
var knob: Panel
var joystick_base: Panel
var sprint_button: Button
var action_button: Button
var jump_button: Button
var joy_center := Vector2(129,587)
var viewport_size := Vector2(1280,720)
var weather_label: Label
var clock_label: Label
var location_label: Label
var wanted_label: Label
var job_label: Label
var mission_label: Label
var vehicle_label: Label
var speed_label: Label
var hud_status: Label

func _ready() -> void:
    player = get_parent().get_node("Player")
    world = get_parent()
    viewport_size = get_viewport().get_visible_rect().size
    _build_ui()

func _label(text: String, pos: Vector2, size: int = 20) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", Color("#f2f4f3"))
    add_child(l)
    return l

func _round_panel(pos: Vector2, size: Vector2, color: Color, radius: int = 60) -> Panel:
    var p := Panel.new()
    p.position = pos
    p.size = size
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    p.add_theme_stylebox_override("panel", style)
    add_child(p)
    return p

func _panel(pos: Vector2, size: Vector2, alpha: float = 0.26) -> ColorRect:
    var p := ColorRect.new()
    p.position = pos
    p.size = size
    p.color = Color(0.03,0.05,0.06,alpha)
    add_child(p)
    return p

func _button(text: String, pos: Vector2) -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = Vector2(116,48)
    b.add_theme_font_size_override("font_size",17)
    add_child(b)
    return b

func _build_ui() -> void:
    _panel(Vector2(18,18),Vector2(360,96),0.48)
    _label("REAL WORLD",Vector2(32,24),26)
    _label("CITY  •  FREE ROAM",Vector2(34,56),14)
    weather_label = _label("CLEAR  •  08:00",Vector2(34,78),13)
    clock_label = _label("08:00",Vector2(302,25),18)

    hud_status = _label("● ONLINE",Vector2(1030,224),13)
    hud_status.add_theme_color_override("font_color",Color("#a9e6c2"))

    var stars := _label("WANTED  ☆ ☆ ☆ ☆ ☆",Vector2(470,24),17)
    stars.add_theme_color_override("font_color",Color("#f0d58a"))
    wanted_label = stars

    location_label = _label("DOWNTOWN",Vector2(470,50),16)

    _panel(Vector2(1000,18),Vector2(250,205),0.48)
    var clear := _button("☀  Clear",Vector2(1010,30))
    clear.pressed.connect(func(): world.set_weather("clear"); weather_label.text="WEATHER  •  CLEAR")
    var rain := _button("☔  Rain",Vector2(1010,85))
    rain.pressed.connect(func(): world.set_weather("rain"); weather_label.text="WEATHER  •  RAIN")
    var snow := _button("❄  Snow",Vector2(1010,140))
    snow.pressed.connect(func(): world.set_weather("snow"); weather_label.text="WEATHER  •  SNOW")

    # Mobile shooter-style virtual joystick: soft circular base + springy knob.
    joystick_base = _round_panel(Vector2(54,512),Vector2(150,150),Color(0.10,0.14,0.16,0.22),75)
    joystick_base.pivot_offset = Vector2(75,75)
    knob = _round_panel(Vector2(104,562),Vector2(50,50),Color(0.85,0.92,0.95,0.42),25)
    knob.pivot_offset = Vector2(25,25)
    knob.modulate = Color(1,1,1,0.82)

    _build_minimap()
    _build_jobs_panel()
    mission_label = _label("MISSION  •  PRESS ACT TO START",Vector2(470,82),14)
    vehicle_label = _label("VEHICLE  •  WALK TO CAR",Vector2(470,108),14)
    _build_sprint_button()
    _build_action_button()
    _build_jump_button()
    speed_label = _label("0 km/h",Vector2(575,625),28)
    speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    speed_label.size = Vector2(130,40)
    speed_label.add_theme_color_override("font_color",Color("#f3f5f4"))
    _label("KM/H",Vector2(612,656),11).modulate = Color(1,1,1,0.55)
    _label("DRAG TO LOOK",Vector2(1035,455),13).modulate = Color(1,1,1,0.55)
    var hint := _label("LEFT STICK  MOVE   •   RIGHT DRAG  CAMERA",Vector2(28,686),13)
    hint.modulate = Color(1,1,1,0.72)


func _build_minimap() -> void:
    _panel(Vector2(1000,235),Vector2(250,185),0.48)
    _label("CITY MAP",Vector2(1018,262),15)
    var map_bg := ColorRect.new()
    map_bg.position=Vector2(1015,287)
    map_bg.size=Vector2(220,130)
    map_bg.color=Color(0.06,0.09,0.10,0.88)
    add_child(map_bg)
    # Main roads.
    var road_h:=ColorRect.new()
    road_h.position=Vector2(1025,342); road_h.size=Vector2(200,8)
    road_h.color=Color("#6e7476"); add_child(road_h)
    var road_v:=ColorRect.new()
    road_v.position=Vector2(1110,296); road_v.size=Vector2(8,112)
    road_v.color=Color("#6e7476"); add_child(road_v)
    # Lake.
    var lake:=ColorRect.new()
    lake.position=Vector2(1160,300); lake.size=Vector2(60,38)
    lake.color=Color("#1b6677"); add_child(lake)
    # Player marker.
    var player_dot:=ColorRect.new()
    player_dot.position=Vector2(1111,338); player_dot.size=Vector2(7,7)
    player_dot.color=Color("#f4d35e"); add_child(player_dot)
    # Civic markers.
    for p in [Vector2(1060,325),Vector2(1165,325),Vector2(1060,375),Vector2(1165,375)]:
        var dot:=ColorRect.new()
        dot.position=p; dot.size=Vector2(6,6)
        dot.color=Color("#d66a61"); add_child(dot)
    _label("● YOU   ● CIVIC   ▰ LAKE",Vector2(1020,418),11)

func _build_jobs_panel() -> void:
    _panel(Vector2(870,490),Vector2(300,150),0.42)
    _label("AVAILABLE LOCATIONS",Vector2(888,500),16)
    job_label=_label("CITY HOSPITAL\nPOLICE HQ\nFIRE STATION\nBANK  •  MARINA",Vector2(888,528),14)
    job_label.add_theme_color_override("font_color",Color("#dce5e4"))


func _circle_button(text: String, center: Vector2, size: float) -> Button:
    var b := Button.new()
    b.text = text
    b.position = center - Vector2(size * 0.5, size * 0.5)
    b.size = Vector2(size, size)
    b.pivot_offset = Vector2(size * 0.5, size * 0.5)
    b.add_theme_font_size_override("font_size", 16)
    var normal := StyleBoxFlat.new()
    normal.bg_color = Color(0.04,0.06,0.08,0.70)
    normal.border_width_left = 2
    normal.border_width_top = 2
    normal.border_width_right = 2
    normal.border_width_bottom = 2
    normal.border_color = Color(0.80,0.88,0.92,0.50)
    normal.corner_radius_top_left = int(size * 0.5)
    normal.corner_radius_top_right = int(size * 0.5)
    normal.corner_radius_bottom_left = int(size * 0.5)
    normal.corner_radius_bottom_right = int(size * 0.5)
    var pressed := normal.duplicate()
    pressed.bg_color = Color(0.18,0.28,0.32,0.92)
    b.add_theme_stylebox_override("normal", normal)
    b.add_theme_stylebox_override("hover", normal)
    b.add_theme_stylebox_override("pressed", pressed)
    add_child(b)
    return b

func _build_sprint_button() -> void:
    sprint_button = _circle_button("RUN", Vector2(1120,650), 82)
    sprint_button.button_down.connect(func():
        player.set_sprint(true)
        _press_anim(sprint_button)
    )
    sprint_button.button_up.connect(func():
        player.set_sprint(false)
        _release_anim(sprint_button)
    )

func _build_action_button() -> void:
    action_button = _circle_button("ACT", Vector2(1215,590), 70)
    action_button.button_down.connect(func(): _press_anim(action_button))
    action_button.button_up.connect(func(): _release_anim(action_button))
    action_button.pressed.connect(func():
        if player.in_vehicle:
            vehicle_label.text = "VEHICLE  •  " + world.toggle_vehicle(player)
            action_button.text = "ACT"
            return
        var vehicle_distance := player.global_position.distance_to(world.driveable_vehicle.global_position)
        if vehicle_distance < 5.0:
            vehicle_label.text = "VEHICLE  •  " + world.toggle_vehicle(player)
            action_button.text = "EXIT"
            return
        player.reset_camera_look()
        if world.mission_active:
            mission_label.text = "MISSION  •  " + world.get_mission_status(player.global_position)
        else:
            world.start_next_mission()
            mission_label.text = "MISSION  •  " + world.get_mission_status(player.global_position)
    )

func _build_jump_button() -> void:
    jump_button = _circle_button("JUMP", Vector2(1215,680), 74)
    jump_button.button_down.connect(func():
        _press_anim(jump_button)
        if player.is_on_floor():
            player.velocity.y = 7.0
    )
    jump_button.button_up.connect(func(): _release_anim(jump_button))

func _press_anim(control: Control) -> void:
    var t := create_tween()
    t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    t.tween_property(control, "scale", Vector2(0.88,0.88), 0.07)

func _release_anim(control: Control) -> void:
    var t := create_tween()
    t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    t.tween_property(control, "scale", Vector2.ONE, 0.15)

func _process(_delta: float) -> void:
    if world and clock_label:
        var hour: float = world.time_of_day
        var h := int(hour)
        var m := int((hour - h) * 60.0)
        clock_label.text = "%02d:%02d" % [h,m]
        if player.in_vehicle:
            vehicle_label.text = "VEHICLE  •  DRIVING  •  STEER + THROTTLE"
            action_button.text = "EXIT"
        elif world.driveable_vehicle and player.global_position.distance_to(world.driveable_vehicle.global_position) < 5.0:
            vehicle_label.text = "VEHICLE  •  PRESS ACT TO DRIVE"
            action_button.text = "DRIVE"
        else:
            vehicle_label.text = "VEHICLE  •  WALK TO CAR"
            action_button.text = "ACT"
        if speed_label:
            if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
                speed_label.text = "%d km/h" % int(player.vehicle.speed_kmh)
            else:
                speed_label.text = "0 km/h"
        if mission_label and world.mission_active:
            mission_label.text = "MISSION  •  " + world.get_mission_status(player.global_position)

func _input(event: InputEvent) -> void:
    # Read touch before CanvasLayer controls consume it.
    if event is InputEventScreenTouch:
        var pos := event.position
        if pos.x < 330.0 and pos.y > 430.0:
            dragging = event.pressed
            if dragging:
                joystick_center = joy_center
                _joystick_touch_anim(true)
            else:
                joystick = Vector2.ZERO
                player.set_joystick(Vector2.ZERO)
                _joystick_touch_anim(false)
            get_viewport().set_input_as_handled()
            return

        # Right half is the free camera-look area; avoid the top HUD.
        if pos.x > 700.0 and pos.y > 210.0 and pos.y < 690.0:
            look_dragging = event.pressed
            if look_dragging:
                look_last = pos
            get_viewport().set_input_as_handled()
            return

    elif event is InputEventScreenDrag:
        if dragging:
            var v: Vector2 = (event.position - joystick_center) / 72.0
            joystick = Vector2(clamp(v.x,-1.0,1.0), clamp(v.y,-1.0,1.0))
            player.set_joystick(joystick)
            if knob:
                knob.position = joystick_center + joystick * 48.0 - Vector2(25,25)
            get_viewport().set_input_as_handled()
        elif look_dragging:
            var delta_look: Vector2 = event.position - look_last
            player.look_camera(delta_look)
            look_last = event.position
            get_viewport().set_input_as_handled()


func _joystick_touch_anim(active: bool) -> void:
    if not joystick_base or not knob:
        return
    var t := create_tween()
    t.set_parallel(true)
    if active:
        t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        t.tween_property(joystick_base, "scale", Vector2(1.08,1.08), 0.12)
        t.tween_property(knob, "scale", Vector2(1.12,1.12), 0.10)
        t.tween_property(joystick_base, "modulate", Color(1,1,1,0.95), 0.10)
    else:
        t.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
        t.tween_property(joystick_base, "scale", Vector2.ONE, 0.18)
        t.tween_property(knob, "scale", Vector2.ONE, 0.16)
        t.tween_property(joystick_base, "modulate", Color(1,1,1,0.72), 0.16)
        t.chain().tween_property(knob, "position", joy_center - Vector2(25,25), 0.16)
