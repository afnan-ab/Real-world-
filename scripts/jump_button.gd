extends Button

func _ready() -> void:
    pressed.connect(_on_pressed)

func _on_pressed() -> void:
    var player := get_parent().get_parent().get_node_or_null("Player")
    if player and not player.in_vehicle and player.is_on_floor():
        player.velocity.y = 7.0
