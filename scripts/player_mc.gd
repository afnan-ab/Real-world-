extends "res://scripts/player.gd"

# Same player as player.gd (that file is untouched). The only change is a wider
# world boundary so the player can walk the whole Mad City sized map.

const MC_PLAYER_LIMIT := 345.0

func _clamp_to_world() -> void:
    var p: Vector3 = global_position
    p.x = clampf(p.x, -MC_PLAYER_LIMIT, MC_PLAYER_LIMIT)
    p.z = clampf(p.z, -MC_PLAYER_LIMIT, MC_PLAYER_LIMIT)
    if p != global_position:
        global_position = p
