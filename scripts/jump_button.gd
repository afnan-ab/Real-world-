extends Button

var player: Node

func _ready() -> void:
    player = get_tree().current_scene.get_node_or_null("Player")
    pressed.connect(_on_pressed)

func _on_pressed() -> void:
    if player and not player.in_vehicle and player.is_on_floor():
        player.velocity.y = 7.0
        modulate = Color(0.75, 0.9, 1.0, 1.0)
