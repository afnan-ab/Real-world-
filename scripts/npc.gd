extends Node3D

# Lightweight pedestrian AI for the mobile open world.
# The limb pivots (left_arm, right_arm, left_leg, right_leg) are assigned by
# world.gd after the body is built, so the walk animation actually plays.

enum State { WANDER, PAUSE, WALK_TO_POINT }

var state: int = State.WANDER
var phase: float = 0.0
var walk_speed: float = 1.15
var wander_radius: float = 5.0
var origin: Vector3 = Vector3.ZERO
var target: Vector3 = Vector3.ZERO
var state_time: float = 0.0
var pause_duration: float = 1.5
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D

func _ready() -> void:
    origin = global_position
    # Start with a local target. Previously target was (0,0,0), so every
    # pedestrian first walked toward the world origin.
    target = origin
    phase = randf() * TAU
    walk_speed = randf_range(0.8, 1.35)
    wander_radius = randf_range(3.0, 7.0)
    state_time = randf_range(0.0, 2.0)

func ai_tick(delta: float, player_position: Vector3, reduced: bool = false) -> void:
    if global_position.distance_to(player_position) > 150.0:
        return

    state_time += delta
    if state == State.PAUSE:
        _animate_idle(delta)
        if state_time > pause_duration:
            _choose_target()
        return

    var to_target: Vector3 = target - global_position
    to_target.y = 0.0
    if to_target.length() < 0.8 or state_time > 8.0:
        if randf() < 0.28:
            state = State.PAUSE
            state_time = 0.0
            pause_duration = randf_range(1.0, 2.8)
            _animate_idle(delta)
            return
        _choose_target()
        to_target = target - global_position
        to_target.y = 0.0

    if to_target.length() > 0.05:
        var dir: Vector3 = to_target.normalized()
        var speed_scale: float = 0.55 if reduced else 1.0
        global_position += dir * walk_speed * speed_scale * delta
        rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), minf(1.0, delta * 6.0))
        _animate_walk(delta, reduced)

func _choose_target() -> void:
    var angle: float = randf() * TAU
    var radius: float = randf_range(1.5, wander_radius)
    target = origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
    state = State.WALK_TO_POINT
    state_time = 0.0

func _animate_walk(delta: float, reduced: bool) -> void:
    phase += delta * (4.0 if reduced else 7.0)
    var swing: float = sin(phase) * 0.48
    if left_arm:
        left_arm.rotation.x = lerpf(left_arm.rotation.x, swing, minf(1.0, delta * 8.0))
    if right_arm:
        right_arm.rotation.x = lerpf(right_arm.rotation.x, -swing, minf(1.0, delta * 8.0))
    if left_leg:
        left_leg.rotation.x = lerpf(left_leg.rotation.x, -swing * 0.9, minf(1.0, delta * 8.0))
    if right_leg:
        right_leg.rotation.x = lerpf(right_leg.rotation.x, swing * 0.9, minf(1.0, delta * 8.0))

func _animate_idle(delta: float) -> void:
    phase += delta * 1.8
    var sway: float = sin(phase) * 0.025
    if left_arm:
        left_arm.rotation.x = lerpf(left_arm.rotation.x, sway, minf(1.0, delta * 4.0))
    if right_arm:
        right_arm.rotation.x = lerpf(right_arm.rotation.x, -sway, minf(1.0, delta * 4.0))
    if left_leg:
        left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, minf(1.0, delta * 5.0))
    if right_leg:
        right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, minf(1.0, delta * 5.0))
