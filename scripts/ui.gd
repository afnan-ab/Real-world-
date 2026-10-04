extends CanvasLayer

var player: Node
var world: Node
var joystick_center := Vector2.ZERO
var dragging := false
var joystick := Vector2.ZERO
var knob: ColorRect
var weather_label: Label
var clock_label: Label
var location_label: Label
var wanted_label: Label
var job_label: Label

func _ready() -> void:
    player = get_parent().get_node("Player")
    world = get_parent()
    _build_ui()

func _label(text: String, pos: Vector2, size: int = 20) -> Label:
    var l := Label.new()
    l.text = text
    l.position = pos
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", Color("#f2f4f3"))
    add_child(l)
    return l

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
    _panel(Vector2(18,18),Vector2(360,112),0.28)
    _label("REAL WORLD",Vector2(32,26),30)
    _label("Open World • City • Forest • Lake",Vector2(34,61),15)
    weather_label = _label("WEATHER  •  CLEAR",Vector2(34,88),14)
    clock_label = _label("08:00",Vector2(302,28),17)

    location_label = _label("DOWNTOWN",Vector2(470,24),18)
    wanted_label = _label("● WANTED  0",Vector2(470,52),15)
    wanted_label.add_theme_color_override("font_color",Color("#f0d58a"))

    _panel(Vector2(1020,20),Vector2(138,174),0.28)
    var clear := _button("☀  Clear",Vector2(1031,31))
    clear.pressed.connect(func(): world.set_weather("clear"); weather_label.text="WEATHER  •  CLEAR")
    var rain := _button("☔  Rain",Vector2(1031,86))
    rain.pressed.connect(func(): world.set_weather("rain"); weather_label.text="WEATHER  •  RAIN")
    var snow := _button("❄  Snow",Vector2(1031,141))
    snow.pressed.connect(func(): world.set_weather("snow"); weather_label.text="WEATHER  •  SNOW")

    _panel(Vector2(44,502),Vector2(170,170),0.18)
    var base := ColorRect.new()
    base.position = Vector2(54,512)
    base.size = Vector2(150,150)
    base.color = Color(0.8,0.9,0.92,0.09)
    add_child(base)

    knob = ColorRect.new()
    knob.position = Vector2(104,562)
    knob.size = Vector2(50,50)
    knob.color = Color(0.9,0.95,0.95,0.35)
    add_child(knob)

    _build_minimap()
    _build_jobs_panel()
    _build_sprint_button()
    var hint := _label("TOUCH / WASD  •  EXPLORE",Vector2(28,686),15)
    hint.modulate = Color(1,1,1,0.72)


func _build_minimap() -> void:
    _panel(Vector2(1000,250),Vector2(250,185),0.30)
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
    _panel(Vector2(870,490),Vector2(300,150),0.28)
    _label("AVAILABLE LOCATIONS",Vector2(888,500),16)
    job_label=_label("CITY HOSPITAL\nPOLICE HQ\nFIRE STATION\nBANK  •  MARINA",Vector2(888,528),14)
    job_label.add_theme_color_override("font_color",Color("#dce5e4"))


func _build_sprint_button() -> void:
    var b := Button.new()
    b.text = "SPRINT"
    b.position = Vector2(1060,650)
    b.size = Vector2(110,48)
    b.add_theme_font_size_override("font_size",16)
    add_child(b)
    b.button_down.connect(func(): player.set_sprint(true))
    b.button_up.connect(func(): player.set_sprint(false))

func _process(_delta: float) -> void:
    if world and clock_label:
        var hour: float = world.time_of_day
        var h := int(hour)
        var m := int((hour - h) * 60.0)
        clock_label.text = "%02d:%02d" % [h,m]

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.position.x < 240 and event.position.y > 470:
            dragging = event.pressed
            if dragging:
                joystick_center = Vector2(129,587)
            else:
                joystick = Vector2.ZERO
                player.set_joystick(joystick)
                if knob:
                    knob.position = Vector2(104,562)
    elif event is InputEventScreenDrag and dragging:
        var v := (event.position - joystick_center) / 72.0
        joystick = Vector2(clamp(v.x,-1.0,1.0),clamp(v.y,-1.0,1.0))
        player.set_joystick(joystick)
        if knob:
            knob.position = joystick_center + joystick * 48.0 - Vector2(25,25)
