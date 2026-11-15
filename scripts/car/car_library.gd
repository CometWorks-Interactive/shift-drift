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

## Kinds of part that come as alternatives on cars with tuning kits.
const OPTION_STEMS: PackedStringArray = ["hood", "spoiler", "bumper", "rear bumper", "lower lip bumper", "tuning", "wheel", "brake disk", "roof", "exhaust", "stock"]

## Cars whose default paint is a livery drawn for the tuned body. On the stock
## body it lands in the wrong places, so the stock look uses the plain paint.
const STOCK_PAINT := {
	"sedan_11": "LP_Veh_Sedan_11_Material_002",
	"sedan_12": "LP_Veh_Sedan_12_Material_002",
	"sedan_14": "LP_Veh_Sedan_14_Material_002",
	"sedan_15": "LP_Veh_Sedan_15_Material_002",
	"sedan_20": "LP_Veh_Sedan_20_Material_002",
}

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
##
## About 20 cars carry a whole tuning kit in the same model (alternative hoods,
## bumpers, spoilers, wheels, sometimes a second body), all switched on at once.
## variant picks one clean look: "stock" or "tuned".
static func instantiate(id: String, variant := "stock") -> Node3D:
	_load()
	if not _models.has(id):
		return null
	var entry: Dictionary = _models[id]
	var scene: PackedScene = load(ROOT + entry["file"])
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D

	var wanted := {}
	var tally := {}
	for part in entry["parts"]:
		wanted[String(part[0]).validate_node_name()] = part[1]
		if part[1] != null and not String(part[1]).containsn("glass"):
			tally[part[1]] = tally.get(part[1], 0) + 1
	# The car's paint is whichever material most of its parts use.
	var paint := "LP_Cars"
	for material_name in tally:
		if tally[material_name] > tally.get(paint, 0):
			paint = material_name
	var repaint := ""
	if variant == "stock" and STOCK_PAINT.has(id):
		repaint = STOCK_PAINT[id]

	var parts: Array[Dictionary] = []
	_apply(node, wanted, paint, repaint, Transform3D.IDENTITY, parts)
	if entry["category"] in CAR_CATEGORIES:
		_resolve_kit(parts, variant)
	return node


static func _apply(node: Node, wanted: Dictionary, paint: String, repaint: String, parent_place: Transform3D, parts: Array[Dictionary]) -> void:
	var place := parent_place
	if node is Node3D:
		place = parent_place * (node as Node3D).transform
	var mesh_node := node as MeshInstance3D
	if mesh_node and mesh_node.mesh:
		var key := String(mesh_node.name)
		var material_name = wanted.get(key)
		if material_name == null:
			# Not listed, or the pack left it on a material embedded in the model:
			# glass by name, the car's paint otherwise.
			material_name = "LP_Glass_01" if key.containsn("glass") else paint
		if repaint != "" and material_name == paint:
			material_name = repaint
		var mat := material(material_name)
		if mat:
			for i in mesh_node.mesh.get_surface_count():
				mesh_node.set_surface_override_material(i, mat)
		parts.append({"node": mesh_node, "name": key, "box": place * mesh_node.mesh.get_aabb()})
	for child in node.get_children():
		_apply(child, wanted, paint, repaint, place, parts)


## Hides parts so that exactly one option of each kit piece is left showing.
static func _resolve_kit(parts: Array[Dictionary], variant: String) -> void:
	var has_stock_marks := false
	var has_stock_body := false
	var has_tuned := false
	for part in parts:
		var tokens := _tokens(part["name"])
		part["stem"] = _stem(tokens)
		part["kit"] = ""
		for token in tokens:
			if token == "St" or token == "Stock":
				part["kit"] = "stock"
			elif token == "Tuning" or token == "T2" or token == "T3" or (token.begins_with("TT") and token.length() <= 3):
				part["kit"] = "tuned"
			elif token == "T1":
				part["kit"] = "base"
		has_stock_marks = has_stock_marks or part["kit"] == "stock"
		has_stock_body = has_stock_body or part["stem"] == "stock"
		has_tuned = has_tuned or part["kit"] == "tuned"

	for part in parts:
		var kit: String = part["kit"]
		if kit == "base":  # T1 is the plain set on cars that have no St set
			kit = "" if has_stock_marks else "stock"
		var hide := false
		if variant == "tuned":
			hide = kit == "stock" and has_tuned
		elif kit == "tuned":
			# "Tuning" pieces with no stock twin (a hood, say) are options, not a kit.
			hide = not (part["stem"] == "tuning" and not has_stock_body)
		if hide:
			(part["node"] as Node3D).visible = false

	# Among what is left, pieces of the same kind that sit in the same place are
	# alternatives: keep the first for stock, the last for tuned.
	var order := parts.duplicate()
	order.sort_custom(func(a, b): return a["name"] < b["name"] if variant != "tuned" else a["name"] > b["name"])
	var kept := {}
	var crowded := {}
	for part in order:
		var stem: String = part["stem"]
		if not (part["node"] as Node3D).visible or not stem in OPTION_STEMS:
			continue
		var box: AABB = part["box"]
		var clash := false
		for other in kept.get(stem, []):
			var other_box: AABB = other["box"]
			if box.grow(0.05).intersects(other_box) and box.get_center().distance_to(other_box.get_center()) < 0.9:
				clash = true
				break
		if clash:
			(part["node"] as Node3D).visible = false
			crowded[stem] = true
		else:
			if not kept.has(stem):
				kept[stem] = []
			kept[stem].append(part)
	# A stock car has no wing: where spoilers were options, drop them all.
	var spoilers: Array = kept.get("spoiler", [])
	if variant != "tuned" and (crowded.has("spoiler") or (has_tuned and spoilers.size() > 1)):
		for part in spoilers:
			(part["node"] as Node3D).visible = false


## "LP_Veh_Sedan_Brake disk_TT1_001_07" -> ["Brake disk", "TT1", "001", "07"]
static func _tokens(part_name: String) -> PackedStringArray:
	var tokens := part_name.replace("'", "").strip_edges().split("_")
	if tokens.size() > 3 and tokens[0] == "LP" and tokens[1] == "Veh":
		tokens = tokens.slice(3)
	return tokens


static func _stem(tokens: PackedStringArray) -> String:
	if tokens.is_empty() or tokens[0].is_valid_int():
		return "body"
	return tokens[0].strip_edges().to_lower().rstrip("0123456789")


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
