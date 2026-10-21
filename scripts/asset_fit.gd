extends RefCounted

# Helpers that load optional art from res://assets/ and fit it to the game.
# Nothing here is required: when a file is missing the callers keep the
# procedural look.

static func load_texture(base_path: String) -> Texture2D:
    for ext in ["jpg", "png", "webp"]:
        var p: String = "%s.%s" % [base_path, ext]
        if ResourceLoader.exists(p):
            var res: Resource = load(p)
            if res is Texture2D:
                return res as Texture2D
    return null

static func _aabb_of(node: Node, xf: Transform3D) -> AABB:
    var result := AABB()
    var has: bool = false
    var cur: Transform3D = xf
    if node is Node3D:
        cur = xf * (node as Node3D).transform
    if node is MeshInstance3D:
        var mi: MeshInstance3D = node as MeshInstance3D
        if mi.mesh != null:
            result = cur * mi.get_aabb()
            has = true
    for child in node.get_children():
        var sub: AABB = _aabb_of(child, cur)
        if sub.size != Vector3.ZERO:
            if has:
                result = result.merge(sub)
            else:
                result = sub
                has = true
    return result

# Loads a .glb / .gltf / .tscn model, scales it so its longest horizontal side is
# target_length metres, turns that long side towards the game's forward axis
# (X when forward_is_x, otherwise Z), centres it on x / z and puts its bottom on
# y = 0. flip turns it 180 degrees if the model drives backwards.
static func load_model(path: String, target_length: float, forward_is_x: bool, flip: bool) -> Node3D:
    if not ResourceLoader.exists(path):
        return null
    var res: Resource = load(path)
    var scene: PackedScene = res as PackedScene
    if scene == null:
        return null
    var inst: Node = scene.instantiate()
    var inst3: Node3D = inst as Node3D
    if inst3 == null:
        inst.queue_free()
        return null
    inst3.transform = Transform3D.IDENTITY
    var aabb: AABB = _aabb_of(inst3, Transform3D.IDENTITY)
    var long_x: bool = aabb.size.x >= aabb.size.z
    var length: float = aabb.size.x if long_x else aabb.size.z
    if length < 0.01:
        inst3.queue_free()
        return null
    var s: float = target_length / length
    var yaw: float = 0.0
    if forward_is_x and not long_x:
        yaw = PI * 0.5
    elif (not forward_is_x) and long_x:
        yaw = -PI * 0.5
    if flip:
        yaw += PI
    var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
    var box: AABB = Transform3D(basis, Vector3.ZERO) * aabb
    var center: Vector3 = box.position + box.size * 0.5
    inst3.transform = Transform3D(basis, Vector3(-center.x, -box.position.y, -center.z))
    var holder := Node3D.new()
    holder.name = "AssetModel"
    holder.add_child(inst3)
    return holder
