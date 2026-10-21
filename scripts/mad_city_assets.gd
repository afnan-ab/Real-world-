extends "res://scripts/mad_city_perf.gd"

# Asset hook (stacked on the performance layer). If you upload files into
# res://assets/ the game uses them, otherwise it keeps the procedural look.
# File names are listed in assets/README.md. Models are auto-fitted (scale,
# direction, centre), so you normally do not have to touch anything.
# Set MC_CAR_FLIP to true if the cars drive backwards.

const AssetFit := preload("res://scripts/asset_fit.gd")

const MC_CAR_PATHS: Array = [
    "res://assets/models/car_1.glb",
    "res://assets/models/car_2.glb",
    "res://assets/models/car_3.glb",
    "res://assets/models/car_4.glb",
    "res://assets/models/car_5.glb",
    "res://assets/models/car_6.glb"
]
const MC_AMBULANCE_PATH := "res://assets/models/ambulance.glb"
const MC_FIRE_TRUCK_PATH := "res://assets/models/fire_truck.glb"
const MC_CAR_LENGTH := 4.4
const MC_CAR_FLIP := false
const MC_TEX_BRIGHTNESS := 1.6

var _mc_car_paths_found: Array = []
var _mc_car_pick: int = 0

func _ready() -> void:
    # Must be known before the parent builds the traffic.
    for p in MC_CAR_PATHS:
        if ResourceLoader.exists(String(p)):
            _mc_car_paths_found.append(String(p))
    super._ready()
    _mc_apply_textures()

# Every car built by the world (AI traffic, cop cars) can use your car models.
func _make_car(pos: Vector3, body_color: Color, rotation_y: float = 0.0) -> Node3D:
    var root: Node3D = super._make_car(pos, body_color, rotation_y)
    if _mc_car_paths_found.is_empty():
        return root
    var path: String = _mc_car_paths_found[_mc_car_pick % _mc_car_paths_found.size()]
    _mc_car_pick += 1
    var model: Node3D = AssetFit.load_model(path, MC_CAR_LENGTH, true, MC_CAR_FLIP)
    if model == null:
        return root
    for child in root.get_children():
        if child is MeshInstance3D:
            (child as MeshInstance3D).visible = false
    root.add_child(model)
    return root

func _mc_swap_model(d: Dictionary, path: String, length: float) -> void:
    if not ResourceLoader.exists(path):
        return
    var node: Node3D = d["node"]
    var bar_mat: StandardMaterial3D = d["bar_mat"]
    var model: Node3D = AssetFit.load_model(path, length, true, MC_CAR_FLIP)
    if model == null:
        return
    for child in node.get_children():
        var mi: MeshInstance3D = child as MeshInstance3D
        if mi != null and mi.material_override != bar_mat:
            mi.visible = false
    node.add_child(model)

func _mc_make_ambulance() -> Dictionary:
    var d: Dictionary = super._mc_make_ambulance()
    _mc_swap_model(d, MC_AMBULANCE_PATH, 5.2)
    return d

func _mc_make_fire_truck() -> Dictionary:
    var d: Dictionary = super._mc_make_fire_truck()
    _mc_swap_model(d, MC_FIRE_TRUCK_PATH, 7.0)
    return d

func _mc_tex_material(albedo: Texture2D, normal: Texture2D, tile: float, with_vertex_colors: bool) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_texture = albedo
    m.vertex_color_use_as_albedo = with_vertex_colors
    if with_vertex_colors:
        m.albedo_color = Color(MC_TEX_BRIGHTNESS, MC_TEX_BRIGHTNESS, MC_TEX_BRIGHTNESS)
    m.roughness = 0.9
    if normal != null:
        m.normal_enabled = true
        m.normal_texture = normal
    m.uv1_triplanar = true
    m.uv1_world_triplanar = true
    m.uv1_scale = Vector3(tile, tile, tile)
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    return m

func _mc_apply_textures() -> void:
    var ground_a: Texture2D = AssetFit.load_texture("res://assets/textures/ground_albedo")
    var ground_n: Texture2D = AssetFit.load_texture("res://assets/textures/ground_normal")
    if ground_a != null:
        var terrain: MeshInstance3D = get_node_or_null("WorldTerrain") as MeshInstance3D
        if terrain != null:
            terrain.material_override = _mc_tex_material(ground_a, ground_n, 0.12, false)
    var city_a: Texture2D = AssetFit.load_texture("res://assets/textures/city_albedo")
    var city_n: Texture2D = AssetFit.load_texture("res://assets/textures/city_normal")
    if city_a != null:
        var city: MeshInstance3D = get_node_or_null("MC_CityBlocks") as MeshInstance3D
        if city != null:
            city.material_override = _mc_tex_material(city_a, city_n, 0.25, true)
