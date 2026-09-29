extends Node3D

var rng := RandomNumberGenerator.new()

func _ready():
    rng.seed = 20260929
    _build_environment()
    _build_city()
    _build_player()
    _build_ui()

func mat(c: Color, rough := 0.75, metallic := 0.0):
    var m = StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    m.metallic = metallic
    return m

func box(pos: Vector3, size: Vector3, material: Material, parent=self) -> MeshInstance3D:
    var n=MeshInstance3D.new()
    var b=BoxMesh.new()
    b.size=size
    n.mesh=b
    n.position=pos
    n.material_override=material
    parent.add_child(n)
    return n

func cyl(pos: Vector3, radius: float, height: float, material: Material, parent=self) -> MeshInstance3D:
    var n=MeshInstance3D.new()
    var c=CylinderMesh.new()
    c.top_radius=radius
    c.bottom_radius=radius
    c.height=height
    n.mesh=c
    n.position=pos
    n.material_override=material
    parent.add_child(n)
    return n

func _build_environment():
    var env=WorldEnvironment.new()
    var e=Environment.new()
    e.background_mode=Environment.BG_COLOR
    e.background_color=Color("#7ca7c8")
    e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    e.ambient_light_color=Color("#d8e6ef")
    e.ambient_light_energy=0.65
    e.tonemap_mode=Environment.TONE_MAPPER_FILMIC
    e.glow_enabled=true
    e.glow_intensity=0.55
    env.environment=e
    add_child(env)

    var sun=DirectionalLight3D.new()
    sun.rotation_degrees=Vector3(-52,-28,0)
    sun.light_energy=1.35
    sun.shadow_enabled=true
    add_child(sun)

func _build_city():
    var asphalt=mat(Color("#25272a"),0.9)
    var concrete=mat(Color("#a7a7a2"),0.92)
    var grass=mat(Color("#405b35"),0.98)
    var white=mat(Color("#e5e1d7"),0.65)
    var glass=mat(Color("#31566b"),0.18,0.15)
    var dark=mat(Color("#15181b"),0.32,0.25)
    var green=mat(Color("#35552f"),1.0)

    # Ground
    box(Vector3(0,-0.6,0),Vector3(180,1,180),grass)

    # Road grid and sidewalks
    for z in [-60.0,-30.0,0.0,30.0,60.0]:
        box(Vector3(0,0,z),Vector3(180,0.18,11),asphalt)
        for x in range(-85,86,10):
            box(Vector3(x,0.12,z),Vector3(4.5,0.025,0.16),white)
    for x in [-60.0,-30.0,0.0,30.0,60.0]:
        box(Vector3(x,0,0),Vector3(11,0.18,180),asphalt)
        for z in range(-85,86,10):
            box(Vector3(x,0.12,z),Vector3(0.16,0.025,4.5),white)

    # Blocks with varied buildings
    for bx in range(-4,5):
        for bz in range(-4,5):
            if abs(bx) <= 1 and abs(bz) <= 1: continue
            var h=rng.randf_range(8.0,24.0)
            var w=rng.randf_range(7.0,13.0)
            var d=rng.randf_range(7.0,13.0)
            var p=Vector3(bx*20+rng.randf_range(-2,2),h/2,bz*20+rng.randf_range(-2,2))
            var facade=mat(Color.from_hsv(rng.randf(),0.12, rng.randf_range(0.45,0.72)),0.78)
            box(p,Vector3(w,h,d),facade)
            # glass/window bands
            for yy in range(2,int(h),3):
                box(p+Vector3(0,yy-h/2,d/2+0.015),Vector3(w*0.72,0.72,0.03),glass)
                box(p+Vector3(w/2+0.015,yy-h/2,0),Vector3(0.03,0.72,d*0.72),glass)

    # Trees
    for i in range(55):
        var x=rng.randf_range(-82,82)
        var z=rng.randf_range(-82,82)
        if abs(fmod(x,30.0))<8 and abs(fmod(z,30.0))<8: continue
        cyl(Vector3(x,2,z),0.28,4.0,dark)
        var crown=MeshInstance3D.new()
        var s=SphereMesh.new()
        s.radius=rng.randf_range(1.5,2.3)
        s.height=s.radius*2
        crown.mesh=s
        crown.position=Vector3(x,4.3,z)
        crown.material_override=green
        add_child(crown)

    # Cars parked along roads
    for i in range(18):
        var x=rng.randi_range(-4,4)*20+rng.randf_range(-4,4)
        var z=rng.randi_range(-4,4)*20+rng.randf_range(-4,4)
        _make_car(Vector3(x,0.65,z), i%2==0)

func _make_car(p:Vector3, rotated:bool):
    var dark=mat(Color("#15181b"),0.32,0.25)
    var car=Node3D.new()
    car.position=p
    if rotated: car.rotation_degrees.y=90
    add_child(car)
    var body=mat(Color.from_hsv(rng.randf(),0.62,0.72),0.28,0.25)
    box(Vector3(0,0,0),Vector3(3.6,0.75,1.8),body,car)
    box(Vector3(0,0.62,0),Vector3(1.8,0.55,1.5),mat(Color("#222c34"),0.12,0.1),car)
    for x in [-1.25,1.25]:
        for z in [-1.02,1.02]:
            cyl(Vector3(x,-0.35,z*0.5),0.34,0.18,dark,car).rotation_degrees.x=90

func _build_player():
    var p=CharacterBody3D.new()
    p.name="Player"
    p.position=Vector3(0,1.2,8)
    add_child(p)
    var body=MeshInstance3D.new()
    var capsule=CapsuleMesh.new()
    capsule.radius=0.42
    capsule.height=1.5
    body.mesh=capsule
    body.material_override=mat(Color("#b7a58e"),0.7)
    p.add_child(body)

    var cam=Camera3D.new()
    cam.position=Vector3(0,3.4,6.5)
    cam.rotation_degrees.x=-14
    p.add_child(cam)
    cam.current=true

func _build_ui():
    var layer=CanvasLayer.new()
    add_child(layer)
    var label=Label.new()
    label.text="REALWORLD V5  •  REALISTIC OPEN-WORLD FOUNDATION"
    label.position=Vector2(28,24)
    label.add_theme_font_size_override("font_size",22)
    layer.add_child(label)
