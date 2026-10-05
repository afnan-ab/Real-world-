extends CanvasLayer

var player: Node
var world: Node
var speed_label: Label
var vehicle_label: Label

func _ready() -> void:
    player = get_parent().get_node_or_null("Player")
    world = get_parent()

    var title := Label.new()
    title.text = "REAL WORLD  •  FREE ROAM"
    title.position = Vector2(28, 24)
    title.add_theme_font_size_override("font_size", 24)
    add_child(title)

    var info := Label.new()
    info.text = "ONLINE  •  CITY"
    info.position = Vector2(30, 58)
    info.add_theme_font_size_override("font_size", 15)
    add_child(info)

    var map := ColorRect.new()
    map.position = Vector2(1050, 22)
    map.size = Vector2(190, 125)
    map.color = Color(0.02, 0.06, 0.07, 0.84)
    add_child(map)

    var map_text := Label.new()
    map_text.text = "CITY MAP\n\n       YOU\n    ---+---\n       |"
    map_text.position = Vector2(1070, 40)
    map_text.add_theme_font_size_override("font_size", 14)
    add_child(map_text)

    vehicle_label = Label.new()
    vehicle_label.text = "VEHICLE  •  WALK TO CAR"
    vehicle_label.position = Vector2(470, 82)
    vehicle_label.add_theme_font_size_override("font_size", 15)
    add_child(vehicle_label)

    speed_label = Label.new()
    speed_label.text = "0 km/h"
    speed_label.position = Vector2(580, 625)
    speed_label.add_theme_font_size_override("font_size", 28)
    add_child(speed_label)

    var action := Button.new()
    action.text = "ACT"
    action.position = Vector2(1170, 585)
    action.size = Vector2(78, 78)
    add_child(action)
    action.pressed.connect(_action_pressed)

func _process(_delta: float) -> void:
    if player == null:
        return
    if player.in_vehicle and player.vehicle and is_instance_valid(player.vehicle):
        speed_label.text = "%d km/h" % int(player.vehicle.speed_kmh)
        vehicle_label.text = "VEHICLE  •  DRIVING"
    else:
        speed_label.text = "0 km/h"
        vehicle_label.text = "VEHICLE  •  DRIVE"

func _action_pressed() -> void:
    if player and world:
        world.toggle_vehicle(player)
