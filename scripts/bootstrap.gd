extends Node3D

# Safe boot. main.tscn starts this script. It tries the full game layers from the
# top one, and if a layer has a script error and cannot be compiled, it falls
# back to the next lower one, down to the original world.gd. So one broken
# layer no longer means a black screen: the game opens with fewer features and
# says which layer it loaded (small text under the top panel).
# Layers that compile but crash while running are NOT caught here (the CI smoke
# test and its log on the ci-logs branch are for those).

const LAYERS: Array = [
    "res://scripts/mad_city_stream.gd",
    "res://scripts/mad_city_services.gd",
    "res://scripts/mad_city_opt.gd",
    "res://scripts/mad_city_assets.gd",
    "res://scripts/mad_city_perf.gd",
    "res://scripts/mad_city_air.gd",
    "res://scripts/mad_city_combat.gd",
    "res://scripts/mad_city_graphics.gd",
    "res://scripts/mad_city_life.gd",
    "res://scripts/mad_city_police.gd",
    "res://scripts/mad_city_world.gd",
    "res://scripts/world.gd"
]

func _enter_tree() -> void:
    var chosen: String = ""
    for p in LAYERS:
        var path: String = String(p)
        if not ResourceLoader.exists(path):
            continue
        var res: Resource = load(path)
        var gd: GDScript = res as GDScript
        if gd != null and gd.can_instantiate():
            chosen = path
            set_script(gd)
            break
        print("MC boot: layer unusable, trying the next one: ", path)
    print("MC boot layer: ", chosen)
    var hud: Node = get_node_or_null("HUD")
    if hud != null:
        var tag := Label.new()
        tag.name = "BootLayer"
        tag.text = "layer: %s" % chosen.get_file().get_basename()
        tag.position = Vector2(20.0, 110.0)
        tag.add_theme_font_size_override("font_size", 12)
        tag.add_theme_color_override("font_color", Color(0.7, 0.8, 0.8))
        hud.add_child(tag)
    # CI only: drive the game through its features (see smoke_scenario.gd).
    if OS.get_environment("MC_SMOKE") == "1":
        var scenario_script: GDScript = load("res://scripts/smoke_scenario.gd") as GDScript
        if scenario_script != null and scenario_script.can_instantiate():
            var scenario := Node.new()
            scenario.name = "SmokeScenario"
            scenario.set_script(scenario_script)
            call_deferred("add_child", scenario)
        else:
            print("MC boot: smoke scenario script could not be loaded")
