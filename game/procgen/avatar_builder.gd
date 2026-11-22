class_name AvatarBuilder
## Builds a little low-poly wanderer from an appearance seed: tunic colour, hood or hat,
## and a name tag. Faces local +Z.


static func build(display_name: String, appearance_seed: int, is_self: bool) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed
	var tunic := Palette.from_seed(appearance_seed)
	var skin := Color.from_hsv(0.07 + rng.randf() * 0.04, 0.35 + rng.randf() * 0.25, 0.55 + rng.randf() * 0.4)
	var root := Node3D.new()

	var body := CapsuleMesh.new()
	body.radius = 0.32
	body.height = 1.2
	body.radial_segments = 8
	body.rings = 2
	root.add_child(_part(body, tunic, Vector3(0, 0.6, 0)))

	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.48
	head.radial_segments = 8
	head.rings = 4
	root.add_child(_part(head, skin, Vector3(0, 1.42, 0)))

	var eye := BoxMesh.new()
	eye.size = Vector3(0.06, 0.08, 0.04)
	root.add_child(_part(eye, Color(0.1, 0.1, 0.12), Vector3(-0.09, 1.46, 0.21)))
	root.add_child(_part(eye, Color(0.1, 0.1, 0.12), Vector3(0.09, 1.46, 0.21)))

	var style := rng.randi() % 3
	if style == 0: # pointed hat
		var hat := CylinderMesh.new()
		hat.top_radius = 0.0
		hat.bottom_radius = 0.32
		hat.height = 0.5
		hat.radial_segments = 8
		root.add_child(_part(hat, tunic.darkened(0.35), Vector3(0, 1.82, 0)))
	elif style == 1: # flat cap
		var cap := CylinderMesh.new()
		cap.top_radius = 0.22
		cap.bottom_radius = 0.27
		cap.height = 0.12
		cap.radial_segments = 8
		root.add_child(_part(cap, tunic.lightened(0.3), Vector3(0, 1.64, 0)))
	# style 2: bare-headed

	var tag := Label3D.new()
	tag.text = display_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0, 2.2, 0)
	tag.font_size = 40
	tag.pixel_size = 0.006
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.95, 0.7) if is_self else Color.WHITE
	tag.no_depth_test = false
	root.add_child(tag)
	return root


static func _part(mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi
