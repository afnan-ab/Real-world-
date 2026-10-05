extends Button

var sprint_on := false
var player: Node

func _ready() -> void:
    player = get_tree().current_scene.get_node_or_null("Player")
    pressed.connect(_on_pressed)

func _on_pressed() -> void:
    if player:
        sprint_on = not sprint_on
        player.set_sprint(sprint_on)
        text = "RUN ON" if sprint_on else "RUN"
        modulate = Color(0.65, 1.0, 0.75, 1.0) if sprint_on else Color.WHITE
