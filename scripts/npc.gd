extends Node3D

# Lightweight pedestrian AI for the mobile open world.
# Uses a small state machine so nearby NPCs feel alive without expensive
# per-frame pathfinding. World sectors decide how often this actor is ticked.

enum State { WANDER, PAUSE, WALK_TO_POINT }

var state: State = State.WANDER
var phase := 0.0
var walk_speed := 1.15
var wander_radius := 5.0
var origin := Vector3.ZERO
var target := Vector3.ZERO
var state_time := 0.0
var visual_root: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D

func _ready() -> void:
    origin = global_position
    phase = randf() * TAU
    walk_speed = randf_range(0.8, 1.35)
    wander_radius = randf_range(3.0, 7.0)
    state_time = randf_range(0.0, 2.0)
    visual_root = self
    _cache_limbs()

func _cache_limbs() -> void:
    var meshes := []
    for child in get_children():
        if child is MeshInstance3D:
            meshes.append(child)
    if meshes.size() >= 5:
        left_arm = meshes[3]
        right_arm = meshes[4]
        if meshes.size() >= 7:
            left_leg = meshes[5]
            right_leg = meshes[6]

func ai_tick(delta: float, player_position: Vector3, reduced: bool = false) -> void:
    var distance := global_position.distance_to(player_position)
    if distance > 150.0:
        return

    state_time += delta
    if state == State.PAUSE:
        _animate_idle(delta)
        if state_time > randf_range(1.0, 2.8):
            _choose_target()
        return

    if state == State.WANDER or state == State.WALK_TO_POINT:
        var to_target := target - global_position
        to_target.y = 0.0
        if to_target.length() < 0.8 or state_time > 8.0:
            if randf() < 0.28:
                state = State.PAUSE
                state_time = 0.0
                _animate_idle(delta)
                return
            _choose_target()
            to_target = target - global_position
            to_target.y = 0.0

        if to_target.length() > 0.05:
            var dir := to_target.normalized()
            var step := walk_speed * (0.55 if reduced else 1.0) * delta
            global_position += dir * step
            rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), min(1.0, delta * 6.0))
            _animate_walk(delta, reduced)

func _choose_target() -> void:
    var angle := randf() * TAU
    var radius := randf_range(1.5, wander_radius)
    target = origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
    state = State.WALK_TO_POINT
    state_time = 0.0

func _animate_walk(delta: float, reduced: bool) -> void:
    phase += delta * (7.0 if not reduced else 4.0)
    var swing := sin(phase) * 0.48
    if left_arm: left_arm.rotation.x = lerp(left_arm.rotation.x, swing, delta * 8.0)
    if right_arm: right_arm.rotation.x = lerp(right_arm.rotation.x, -swing, delta * 8.0)
    if left_leg: left_leg.rotation.x = lerp(left_leg.rotation.x, -swing * 0.9, delta * 8.0)
    if right_leg: right_leg.rotation.x = lerp(right_leg.rotation.x, swing * 0.9, delta * 8.0)

func _animate_idle(delta: float) -> void:
    phase += delta * 1.8
    var sway := sin(phase) * 0.025
    if left_arm: left_arm.rotation.x = lerp(left_arm.rotation.x, sway, delta * 4.0)
    if right_arm: right_arm.rotation.x = lerp(right_arm.rotation.x, -sway, delta * 4.0)
    if left_leg: left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
    if right_leg: right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
