extends SceneTree
## Renders a labelled contact sheet of every imported model, one image per category,
## so cars can be picked by eye. Needs a window (not --headless):
##   godot --path . --script res://tools/car_gallery.gd -- --out=/some/folder
## Add --only=sports to render a single category, and --variant=tuned to show
## cars that have tuning kits with the kit fitted.

const CarLibrary := preload("res://scripts/car/car_library.gd")
const COLUMNS := 10
const SPACING := Vector2(4.0, 6.8)

var _out := "user://"
var _only := ""
var _variant := "stock"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--variant="):
			_variant = arg.trim_prefix("--variant=")
	if not CarLibrary.available():
		print("The car pack is not imported. Run tools/import_pack.py first.")
		quit()
		return
	DisplayServer.window_set_size(Vector2i(1800, 1100))
	_run()


func _run() -> void:
	var categories: Array = [_only] if _only != "" else Array(CarLibrary.CAR_CATEGORIES) + ["wheels", "props", "track"]
	for category in categories:
		var ids := CarLibrary.ids(category)
		if ids.is_empty():
			continue
		var stage := _build(ids, category)
		root.add_child(stage)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := _out.path_join("gallery_%s%s.png" % [category, "" if _variant == "stock" else "_" + _variant])
		root.get_texture().get_image().save_png(path)
		print("saved ", path, "  (", ids.size(), " models)")
		stage.queue_free()
		await process_frame
	quit()


func _build(ids: PackedStringArray, category: String) -> Node3D:
	var stage := Node3D.new()

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.56, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.75
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 150.0, 0.0)
	sun.shadow_enabled = true
	stage.add_child(sun)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(400.0, 400.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.42, 0.45, 0.5)
	floor_mat.roughness = 1.0
	floor_mesh.material = floor_mat
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	stage.add_child(floor_node)

	# Props and track pieces vary a lot in size, so give them more room.
	var spacing := SPACING if category in CarLibrary.CAR_CATEGORIES else Vector2(9.0, 9.0)
	if category == "wheels":
		spacing = Vector2(1.6, 1.8)
	var columns := mini(COLUMNS, ids.size())
	var rows := ceili(float(ids.size()) / columns)
	for i in ids.size():
		var model := CarLibrary.instantiate(ids[i], _variant)
		if model == null:
			continue
		var col := i % columns
		var row := i / columns
		model.position = Vector3((col - (columns - 1) * 0.5) * spacing.x, 0.0, (row - (rows - 1) * 0.5) * spacing.y)
		model.rotation.y = deg_to_rad(25.0)
		stage.add_child(model)
		var label := Label3D.new()
		# Cars are labelled by number only; the category is in the file name.
		label.text = ids[i].get_slice("_", ids[i].get_slice_count("_") - 1) if category in CarLibrary.CAR_CATEGORIES else ids[i]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.011 * (spacing.x / 4.0)
		label.font_size = 64 if category in CarLibrary.CAR_CATEGORIES else 28
		label.outline_size = 16
		label.position = model.position + Vector3(0.0, 0.4, spacing.y * 0.46)
		stage.add_child(label)

	var camera := Camera3D.new()
	camera.fov = 28.0
	var width := columns * spacing.x
	var depth := rows * spacing.y
	var distance := maxf(width * 1.3, depth * 1.9) + 4.0
	stage.add_child(camera)
	camera.position = Vector3(0.0, distance * 0.78, distance * 0.62)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.0, depth * 0.04), Vector3.UP)
	camera.current = true
	return stage
