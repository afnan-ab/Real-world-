extends CanvasLayer

var player
var world
var joystick_center := Vector2.ZERO
var dragging := false
var joystick := Vector2.ZERO
var weather_label: Label

func _ready():
    player = get_parent().get_node("Player")
    world = get_parent()
    _build_ui()

func _label(text, pos, size=22):
    var l=Label.new()
    l.text=text
    l.position=pos
    l.add_theme_font_size_override("font_size",size)
    add_child(l)
    return l

func _build_ui():
    _label("REAL WORLD", Vector2(28,24), 28)
    _label("Mountain • Forest • Lake • Beach", Vector2(30,58), 16)
    weather_label = _label("Weather: Clear", Vector2(30,88), 16)

    var info = _label("WASD / Touch joystick • Explore the world", Vector2(30,680), 17)
    info.modulate = Color(1,1,1,0.75)

    var clear = Button.new()
    clear.text="☀ Clear"
    clear.position=Vector2(1030,30)
    clear.size=Vector2(105,48)
    clear.pressed.connect(func(): world.set_weather("clear"); weather_label.text="Weather: Clear")
    add_child(clear)

    var rain = Button.new()
    rain.text="☔ Rain"
    rain.position=Vector2(1030,85)
    rain.size=Vector2(105,48)
    rain.pressed.connect(func(): world.set_weather("rain"); weather_label.text="Weather: Rain")
    add_child(rain)

    var snow = Button.new()
    snow.text="❄ Snow"
    snow.position=Vector2(1030,140)
    snow.size=Vector2(105,48)
    snow.pressed.connect(func(): world.set_weather("snow"); weather_label.text="Weather: Snow")
    add_child(snow)

    # Simple touch joystick
    var base = ColorRect.new()
    base.position=Vector2(55,505)
    base.size=Vector2(150,150)
    base.color=Color(1,1,1,0.12)
    add_child(base)
    var knob=ColorRect.new()
    knob.name="Knob"
    knob.position=Vector2(105,555)
    knob.size=Vector2(50,50)
    knob.color=Color(1,1,1,0.35)
    add_child(knob)

func _unhandled_input(event):
    if event is InputEventScreenTouch:
        if event.position.x < 240 and event.position.y > 450:
            dragging = event.pressed
            if dragging:
                joystick_center = Vector2(130,580)
            else:
                joystick = Vector2.ZERO
                player.set_joystick(joystick)
    elif event is InputEventScreenDrag and dragging:
        var v=(event.position-joystick_center)/70.0
        joystick=Vector2(clamp(v.x,-1,1),clamp(v.y,-1,1))
        player.set_joystick(joystick)
