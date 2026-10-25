extends Node

# CI-only scenario. It is attached by bootstrap.gd only when the environment
# variable MC_SMOKE is 1 (the smoke test step of the workflow sets it). It
# drives the game through its main features without a screen, so runtime script
# errors show up in the log. Lines starting with "SMOKE" are progress markers.

var _world: Node
var _player: Node3D
var _vehicle: Node3D
var _heli: Node3D

func _ready() -> void:
    _world = get_parent()
    _player = _world.get_node_or_null("Player") as Node3D

func _tp(pos: Vector3) -> void:
    if _player != null:
        _player.global_position = pos
        _player.set("velocity", Vector3.ZERO)

func _process(_delta: float) -> void:
    if _world == null or _player == null:
        return
    var f: int = Engine.get_process_frames()
    match f:
        30:
            print("SMOKE start mission")
            _world.call("_on_hud_action_pressed")
        60:
            print("SMOKE wanted level 5")
            _world.set("_mc_heat", 100.0)
        150:
            print("SMOKE cops=", (_world.get("_mc_cops") as Array).size())
        200:
            var vs: Array = _world.get("driveable_vehicles")
            print("SMOKE driveable vehicles=", vs.size())
            for v in vs:
                var vn: Node3D = v as Node3D
                if vn != null and String(vn.name).begins_with("DriveableVehicle"):
                    _vehicle = vn
                elif vn != null and String(vn.name) == "Helicopter":
                    _heli = vn
            if _vehicle != null:
                _tp(_vehicle.global_position + Vector3(2.5, 0.5, 0.0))
                _world.call("_on_hud_act_pressed")
                print("SMOKE in_vehicle=", _player.get("in_vehicle"))
        230:
            if _vehicle != null:
                _vehicle.set("mobile_gas", true)
        330:
            print("SMOKE car speed=", _vehicle.get("speed_kmh") if _vehicle != null else "n/a")
        360:
            _world.call("_on_hud_act_pressed")
            print("SMOKE on foot=", not bool(_player.get("in_vehicle")))
        380:
            _world.set("_mc_heat", 0.0)
            _tp(Vector3(-100.0, 1.4, -100.0))
            _world.call("_mc_fire")
            print("SMOKE ammo=", (_world.get("_mc_ammo") as Array))
        420:
            _tp(Vector3(40.0, 1.4, 17.5))
            _world.call("_on_hud_action_pressed")
            print("SMOKE inside=", _world.get("_mc_inside"))
        470:
            _tp(Vector3(2000.0 - 5.0, 1.4, -2.0))
        520:
            print("SMOKE after bed, time=", _world.get("time_of_day"))
            _tp(Vector3(2000.0, 1.4, 5.3))
            _world.call("_on_hud_action_pressed")
            print("SMOKE inside after exit=", _world.get("_mc_inside"))
        560:
            _world.set("time_of_day", 22.0)
        600:
            print("SMOKE busted")
            _world.call("_mc_busted")
            print("SMOKE inside (jail)=", _world.get("_mc_inside"))
        640:
            _world.set("_mc_jail_t", 0.1)
        700:
            if _heli != null:
                _tp(_heli.global_position + Vector3(2.5, 0.5, 0.0))
                _world.call("_on_hud_act_pressed")
                _heli.set("mobile_gas", true)
                print("SMOKE heli driving")
        780:
            if _heli != null:
                print("SMOKE heli height=", _heli.global_position.y)
                _world.call("_on_hud_act_pressed")
        800:
            var crashes: Array = _world.get("_mc_crashes")
            crashes.append({"pos": Vector3(0.0, 0.0, 0.0), "t": 10.0})
            print("SMOKE crash event queued")
        850:
            print("SMOKE responders=", (_world.get("_mc_responders") as Array).size())
        900:
            _world.set("_mc_heat", 50.0)
            _world.set("_mc_money", 5000)
            _tp(Vector3(-56.0, 1.4, -24.0))
        950:
            print("SMOKE after fixer, heat=", _world.get("_mc_heat"), " money=", _world.get("_mc_money"))
            _tp(Vector3(54.0, 1.4, 15.5))
        1010:
            print("SMOKE after kiosk, money=", _world.get("_mc_money"))
            _world.call("_svc_cycle_quality")
            _world.call("_svc_cycle_quality")
            _world.call("_svc_cycle_quality")
        1100:
            _world.set("time_of_day", 12.0)
        1250:
            print("SMOKE traffic=", (_world.get("traffic") as Array).size(), " npcs=", (_world.get("npcs") as Array).size())
            print("SMOKE DONE")
            get_tree().quit()
