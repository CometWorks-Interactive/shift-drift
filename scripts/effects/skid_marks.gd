extends MultiMeshInstance3D
## Skid marks under the rear tyres, drawn as a pool of flat strips on the ground.
## The browser renderer has no decals, so each strip is one MultiMesh instance and
## the oldest strips are reused once the pool is full.

@export var car_path: NodePath = ^"../Car"

const POOL := 4096            ## strips kept, shared by both tyres (about 600 m each)
const SEGMENT := 0.3          ## m of travel per strip
const WIDTH := 0.26           ## m
const LIFT := 0.02            ## m above the ground, to avoid flicker
const HIDDEN := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0.0, -100.0, 0.0))

var _car: Node3D
var _next := 0
var _last := [Vector3.ZERO, Vector3.ZERO]      ## last point per tyre (0 left, 1 right)
var _was_sliding := [false, false]
var _last_alpha := [0.0, 0.0]


func _ready() -> void:
	_car = get_node(car_path)
	_car.was_reset.connect(clear)
	# Strips are placed once and never move, so they must not be interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-5000.0, -1.0, -5000.0), Vector3(10000.0, 2.0, 10000.0))

	var strip := PlaneMesh.new()
	strip.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.02, 0.02, 0.025)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -1  # draw under the smoke
	strip.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = strip
	mm.instance_count = POOL
	multimesh = mm
	clear()


func clear() -> void:
	for i in POOL:
		multimesh.set_instance_transform(i, HIDDEN)
	_next = 0
	_was_sliding = [false, false]


func _physics_process(_delta: float) -> void:
	var slide: float = _car.sim.slide
	for tyre in 2:
		var point: Vector3 = _car.rear_contact(-1.0 if tyre == 0 else 1.0)
		if slide <= 0.0:
			_was_sliding[tyre] = false
			continue
		if not _was_sliding[tyre]:
			# A slide has just started: begin a new mark here.
			_was_sliding[tyre] = true
			_last[tyre] = point
			_last_alpha[tyre] = 0.0
			continue
		var along: Vector3 = point - _last[tyre]
		var length := along.length()
		if length < SEGMENT:
			continue
		# Faint at the 10-degree threshold, solid in a deep slide.
		var alpha := lerpf(0.25, 0.8, slide)
		_add_strip(_last[tyre], along / length, length, 0.5 * (alpha + _last_alpha[tyre]))
		_last[tyre] = point
		_last_alpha[tyre] = alpha


func _add_strip(from: Vector3, dir: Vector3, length: float, alpha: float) -> void:
	var right := dir.cross(Vector3.UP).normalized()
	var basis := Basis(right * WIDTH, Vector3.UP, dir * length)
	var origin := from + dir * (length * 0.5) + Vector3.UP * LIFT
	multimesh.set_instance_transform(_next, Transform3D(basis, origin))
	multimesh.set_instance_color(_next, Color(1.0, 1.0, 1.0, alpha))
	_next = (_next + 1) % POOL
