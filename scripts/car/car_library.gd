extends RefCounted
## Loads models from the purchased car pack and gives each part its material.
##
## The pack lives in assets/vendor/ and is not in the repository (its licence
## does not allow that). tools/import_pack.py copies it in and writes
## manifest.json, which lists every model and the material each part uses.
## Everything here is optional: if the pack is missing, available() is false
## and the game falls back to placeholder shapes.

const ROOT := "res://assets/vendor/low_poly_racing_pack/"
const CAR_CATEGORIES: PackedStringArray = ["hatchback", "luxury", "muscle", "pickup", "sedan", "sports", "suv"]

static var _loaded := false
static var _models := {}      ## id -> manifest entry
static var _order: Array[String] = []
static var _material_info := {}
static var _materials := {}   ## name -> Material, built on first use


static func available() -> bool:
	_load()
	return not _models.is_empty()


## Model ids, optionally limited to one category ("sports", "wheels", "track", ...).
static func ids(category := "") -> PackedStringArray:
	_load()
	var out := PackedStringArray()
	for id in _order:
		if category == "" or _models[id]["category"] == category:
			out.append(id)
	return out


static func category_of(id: String) -> String:
	_load()
	return _models[id]["category"] if _models.has(id) else ""


## A new instance of the model with its materials applied, or null if it is missing.
## Car models face +Z and are about 25% larger than life; the caller turns and scales them.
static func instantiate(id: String) -> Node3D:
	_load()
	if not _models.has(id):
		return null
	var entry: Dictionary = _models[id]
	var scene: PackedScene = load(ROOT + entry["file"])
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	var wanted := {}
	var hidden := {}
	for part in entry["parts"]:
		var key := String(part[0]).validate_node_name()
		wanted[key] = part[1]
		if not part[2]:
			hidden[key] = true
	_apply(node, wanted, hidden)
	return node


static func _apply(node: Node, wanted: Dictionary, hidden: Dictionary) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node and mesh_node.mesh:
		var key := String(mesh_node.name)
		# Cars with tuning kits carry every option in one model, all switched on.
		# Show the stock look by default.
		if hidden.has(key) or _is_tuning_part(key):
			mesh_node.visible = false
		var material_name = wanted.get(key, "?")
		if material_name == "?":
			# Not listed (a model without a prefab): glass by name, paint otherwise.
			material_name = "LP_Glass_01" if key.containsn("glass") else "LP_Cars"
		if material_name != null:
			var mat := material(material_name)
			if mat:
				for i in mesh_node.mesh.get_surface_count():
					mesh_node.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply(child, wanted, hidden)


## Tuning-kit parts are marked in their names: TT, TT1..TT3, T2 (T1 is the base
## set on cars that have no stock set) and Tuning.
static func _is_tuning_part(part_name: String) -> bool:
	for token in part_name.split("_"):
		if token == "Tuning" or token == "T2" or token == "T3" or (token.begins_with("TT") and token.length() <= 3):
			return true
	return false


static func material(material_name: String) -> Material:
	_load()
	if _materials.has(material_name):
		return _materials[material_name]
	if not _material_info.has(material_name):
		return null
	var info: Dictionary = _material_info[material_name]
	var mat := StandardMaterial3D.new()
	mat.resource_name = material_name
	var c: Array = info["color"]
	mat.albedo_color = Color(c[0], c[1], c[2], c[3])
	if info["texture"] != null:
		mat.albedo_texture = load(ROOT + info["texture"])
		# These are colour-swatch sheets: mipmaps would bleed neighbouring swatches together.
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.metallic = info["metallic"]
	mat.roughness = 1.0 - float(info["smoothness"])
	if info["transparent"]:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if info["emission"] != null:
		var e: Array = info["emission"]
		mat.emission_enabled = true
		mat.emission = Color(e[0], e[1], e[2])
	_materials[material_name] = mat
	return mat


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var path := ROOT + "manifest.json"
	if not FileAccess.file_exists(path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return
	_material_info = data.get("materials", {})
	for entry in data.get("models", []):
		_models[entry["id"]] = entry
		_order.append(entry["id"])
