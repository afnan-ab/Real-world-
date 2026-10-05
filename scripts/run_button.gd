extends Button

var sprint_on := false

func _ready() -> void:
    pressed.connect(_on_pressed)

func _on_pressed() -> void:
    var player := get_parent().get_parent().get_node_or_null("Player")
    if player:
        sprint_on = not sprint_on
        player.set_sprint(sprint_on)
        text = "RUN ON" if sprint_on else "RUN"
