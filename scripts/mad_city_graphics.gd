extends "res://scripts/mad_city_life.gd"

# Mad City port - graphics pass (stacked on Phase 3).
# Code-only realism upgrade for the gl_compatibility renderer: filmic tone
# mapping, glow, distance fog that follows the time of day, surface relief on
# roads / buildings / terrain (world-space triplanar noise normal + roughness
# maps, no UVs needed), glass-like reflective windows and 2x MSAA.
# This is a "better looking" pass, not photo-real: real 3D models and textures
# have to be added to the repo as assets for that.

var _mc_env: Environment
var _mc_fog_timer: float = 0.0

func _ready() -> void:
    super._ready()
    _mc_apply_graphics()

func _mc_noise_tex(freq: float, as_normal: bool, bump: float, seed_v: int, low: float) -> NoiseTexture2D:
    var n := FastNoiseLite.new()
    n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    n.frequency = freq
    n.seed = seed_v
    n.fractal_type = FastNoiseLite.FRACTAL_FBM
    n.fractal_octaves = 4
    var t := NoiseTexture2D.new()
    t.noise = n
    t.width = 512
    t.height = 512
    t.seamless = true
    t.as_normal_map = as_normal
    if as_normal:
        t.bump_strength = bump
    else:
        var ramp := Gradient.new()
        ramp.set_color(0, Color(low, low, low))
        ramp.set_color(1, Color(1.0, 1.0, 1.0))
        t.color_ramp = ramp
    return t

func _mc_detail_material(rough_low: float, normal_scale: float, tile: float, seed_v: int) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.roughness = 1.0
    m.roughness_texture = _mc_noise_tex(0.04, false, 0.0, seed_v, rough_low)
    m.normal_enabled = true
    m.normal_texture = _mc_noise_tex(0.05, true, 3.0, seed_v + 7, 0.0)
    m.normal_scale = normal_scale
    m.uv1_triplanar = true
    m.uv1_world_triplanar = true
    m.uv1_scale = Vector3(tile, tile, tile)
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m

func _mc_apply_graphics() -> void:
    # Surface relief.
    var city: MeshInstance3D = get_node_or_null("MC_CityBlocks") as MeshInstance3D
    if city != null:
        city.material_override = _mc_detail_material(0.72, 0.7, 0.35, 11)
    var terrain: MeshInstance3D = get_node_or_null("WorldTerrain") as MeshInstance3D
    if terrain != null:
        terrain.material_override = _mc_detail_material(0.8, 0.9, 0.18, 23)

    # Glass-like windows (the material instance belongs to this world only).
    var glass: MeshInstance3D = get_node_or_null("MC_WindowsDark") as MeshInstance3D
    if glass != null:
        var gm: StandardMaterial3D = glass.material_override as StandardMaterial3D
        if gm != null:
            gm.metallic = 0.6
            gm.roughness = 0.06

    # Environment: tone mapping, glow, fog.
    var we: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
    if we != null and we.environment != null:
        _mc_env = we.environment
        _mc_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
        _mc_env.tonemap_exposure = 1.0
        _mc_env.tonemap_white = 6.0
        _mc_env.glow_enabled = true
        _mc_env.glow_intensity = 0.45
        _mc_env.glow_strength = 0.9
        _mc_env.glow_bloom = 0.04
        _mc_env.glow_hdr_threshold = 1.1
        _mc_env.fog_enabled = true
        _mc_env.fog_density = 0.0011
        _mc_env.fog_light_color = Color("#b4c6d0")

    # Smoother edges.
    get_viewport().msaa_3d = Viewport.MSAA_2X

func _process(delta: float) -> void:
    super._process(delta)
    _mc_fog_timer += delta
    if _mc_fog_timer < 0.5 or _mc_env == null:
        return
    _mc_fog_timer = 0.0
    # Day factor 0..1 from the in-game hour: dark fog at night, pale haze by day.
    var day: float = clampf(sin((time_of_day - 6.0) / 24.0 * TAU) * 2.0 + 0.3, 0.0, 1.0)
    _mc_env.fog_light_color = Color("#0a1018").lerp(Color("#b4c6d0"), day)
    _mc_env.fog_density = lerpf(0.0016, 0.0011, day)
