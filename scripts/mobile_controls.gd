extends CanvasLayer

var world: Node
var player: Node
var joystick := Vector2.ZERO
var joystick_center := Vector2(118, 590)
var joystick_touch_id := -1
var look_touch_id := -1
var look_last := Vector2.ZERO
var knob: ColorRect

func _ready() -> void:
    layer = 220
    world = get_parent()
    player = world.get_node_or_null("Player")
    var base := get_node_or_null("Joystick")
    if base:
        base.mouse_filter = Control.MOUSE_FILTER_IGNORE
        knob = ColorRect.new()
        knob.position = Vector2(98, 570)
        knob.size = Vector2(40, 40)
        knob.color = Color(0.85, 0.92, 0.95, 0.52)
        knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(knob)

func _process(_delta: float) -> void:
    if player == null or not is_instance_valid(player):
        return
    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        player.vehicle.set_joystick(joystick)
    else:
        player.set_joystick(joystick)

func _is_action_button(pos: Vector2) -> bool:
    return pos.x >= 1035.0 and pos.y >= 545.0

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var pos := event.position
        if event.pressed:
            if joystick_touch_id == -1 and pos.x < 330.0 and pos.y > 430.0:
                joystick_touch_id = event.index
                joystick_center = Vector2(118, 590)
                _set_joystick_from_position(pos)
                get_viewport().set_input_as_handled()
                return
            if look_touch_id == -1 and pos.x >= 700.0 and pos.x < 1035.0 and pos.y > 180.0 and pos.y < 720.0:
                look_touch_id = event.index
                look_last = pos
                get_viewport().set_input_as_handled()
                return
        else:
            if event.index == joystick_touch_id:
                joystick_touch_id = -1
                joystick = Vector2.ZERO
                _apply_joystick()
                if knob:
                    knob.position = joystick_center - Vector2(20,20)
                get_viewport().set_input_as_handled()
                return
            if event.index == look_touch_id:
                look_touch_id = -1
                get_viewport().set_input_as_handled()
                return

    elif event is InputEventScreenDrag:
        if event.index == joystick_touch_id:
            _set_joystick_from_position(event.position)
            get_viewport().set_input_as_handled()
            return
        if event.index == look_touch_id:
            var delta_look := event.position - look_last
            if player:
                player.look_camera(delta_look)
            look_last = event.position
            get_viewport().set_input_as_handled()

func _set_joystick_from_position(pos: Vector2) -> void:
    var v := (pos - joystick_center) / 68.0
    joystick = Vector2(clamp(v.x, -1.0, 1.0), clamp(v.y, -1.0, 1.0))
    _apply_joystick()
    if knob:
        knob.position = joystick_center + joystick * 46.0 - Vector2(20,20)

func _apply_joystick() -> void:
    if player == null:
        return
    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        player.vehicle.set_joystick(joystick)
    else:
        player.set_joystick(joystick)
