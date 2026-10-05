extends Button

var player: Node
var world: Node

func _ready() -> void:
    world = get_tree().current_scene
    player = world.get_node_or_null("Player")
    pressed.connect(_on_pressed)

func _on_pressed() -> void:
    if player and world:
        var result: String = world.toggle_vehicle(player)
        text = "EXIT" if player.in_vehicle else "ACT"
        modulate = Color(0.65, 1.0, 0.75, 1.0) if player.in_vehicle else Color.WHITE
        if result != "":
            tooltip_text = result
