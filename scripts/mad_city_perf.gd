extends "res://scripts/mad_city_air.gd"

# Performance layer (stacked on Phase 6). Turns off the expensive parts of the
# graphics pass so the game runs on phones:
#   - 3D render resolution 70% (the HUD stays sharp)
#   - no MSAA, no glow, no fog
#   - no relief (normal / roughness) textures on city and terrain
#   - no directional shadows
# To get the nicer look back on a strong phone, set MC_LOW_QUALITY to false.
# Not measured: I cannot run Godot here, these are the usual mobile savers.

const MC_LOW_QUALITY := true
const MC_RENDER_SCALE := 0.7

func _ready() -> void:
    super._ready()
    if MC_LOW_QUALITY:
        _mc_apply_low_quality()

func _mc_apply_low_quality() -> void:
    var vp: Viewport = get_viewport()
    vp.msaa_3d = Viewport.MSAA_DISABLED
    vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
    vp.scaling_3d_scale = MC_RENDER_SCALE

    if _mc_env != null:
        _mc_env.glow_enabled = false
        _mc_env.fog_enabled = false

    # Plain vertex-colour materials instead of the relief ones.
    var city: MeshInstance3D = get_node_or_null("MC_CityBlocks") as MeshInstance3D
    if city != null:
        city.material_override = _mc_vertex_material(0.85, 0.0, false)
    var terrain: MeshInstance3D = get_node_or_null("WorldTerrain") as MeshInstance3D
    if terrain != null:
        var tm := StandardMaterial3D.new()
        tm.vertex_color_use_as_albedo = true
        tm.roughness = 0.92
        tm.cull_mode = BaseMaterial3D.CULL_DISABLED
        terrain.material_override = tm

    var sun: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D
    if sun != null:
        sun.shadow_enabled = false
    var city_blocks: MeshInstance3D = get_node_or_null("MC_CityBlocks") as MeshInstance3D
    if city_blocks != null:
        city_blocks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
