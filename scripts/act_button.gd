extends Button

func _ready() -> void:
    pressed.connect(_on_pressed)

func _on_pressed() -> void:
    var root := get_parent().get_parent()
    var player := root.get_node_or_null("Player")
    if player:
        root.toggle_vehicle(player)
        text = "EXIT" if player.in_vehicle else "ACT"
