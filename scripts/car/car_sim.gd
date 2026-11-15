extends RefCounted
## Drift model: one rigid body on a flat plane with a front and a rear axle.
##
## What makes it behave like a rear-wheel-drive car:
## - Weight moves with acceleration. Power squats the car onto the rear tyres;
##   lifting or braking pitches it onto the fronts and leaves the rear light.
## - The rear wheels have their own spin speed. The tyre's force points against
##   the way its contact patch is slipping over the road, so the harder the
##   wheels spin, the more of the grip goes into pushing and the less is left to
##   hold the tail in line. Lifting lets the wheels slow to road speed, and the
##   sideways grip comes straight back.
## - A sliding tyre grips less than one at its peak, so a slide lets go with a
##   snap and has to be caught.
## - The front wheels counter-steer by themselves, but only so fast. Throw the
##   car around quicker than they can follow and it spins.
##
## Sim frame: x forward, y left, yaw positive to the left (counter-clockwise from above).
## To place it in Godot: position = Vector3(-pos.y, 0, -pos.x), rotation.y = psi.
##
## Inputs per step: throttle (bool), lean (-1 right .. +1 left), handbrake (bool).
## There is no steering input. The lean keys throw the car's weight sideways,
## which steers; the front wheels self-align with the direction of travel.

const G := 9.81

# --- Body ---
var mass := 1200.0            ## kg
var inertia := 1500.0         ## kg m^2, yaw. Lower = snappier rotation.
var cg_to_front := 1.2        ## m
var cg_to_rear := 1.3         ## m
var cg_height := 0.5          ## m. Higher = more weight moves under power and on a lift.

# --- Tyres ---
var mu_front := 1.5
var mu_rear := 1.45
var peak_front := 0.14        ## rad of slip where the front grips hardest
var peak_rear := 0.17         ## rad of slip where the rear grips hardest
var peak_spin := 0.12         ## wheelspin, as a share of road speed, where the rear pushes hardest
var slide_grip := 0.85        ## share of its peak grip the rear keeps once properly sliding or spinning
var slide_full := 0.6         ## rad of slip by which it has dropped to that

# --- Weight ---
var lat_freq := 1.3           ## Hz. Lower = more lag between key and turn. The car's tempo.
var lat_damping := 0.3        ## under 1 = overshoot, which is what makes a flick work
var long_freq := 2.0          ## Hz, how quickly the car pitches when power comes on or off
var long_damping := 0.7
var w_break := 1.6            ## a sideways weight swing past this counts as a well-timed throw
var k_feint := 4.0            ## how quickly swing past w_break fills the kick (1 / excess needed for a full kick)
var kick_gain := 0.0          ## extra lean steer at full kick. 0 = off: a flick then pays only through real momentum.
var kick_time := 2.5          ## s for a kick to fade

# --- Steering (automatic) ---
var d_frac := 0.95             ## lean steer as a fraction of peak_front. How hard the front bites when you lean.
var k_caster := 1.0           ## front self-align strength
var steer_lock := 1.0         ## rad
var steer_rate := 2.3         ## rad/s the front wheels can swing. Finite, so a violent swap outruns the catch.
var steer_lead := 0.06         ## s. How far ahead the hands react to a growing slide. The driver's skill at catching it.
var lead_from := 0.17         ## rad of drift angle where the hands start reacting
var lead_full := 0.45         ## rad where they react fully
var low_speed_steer := 0.5    ## rad of plain steering at parking speed. More = tighter donuts.
var plain_steer_from := 3.0   ## m/s. Below this the lean keys steer the front wheels directly.
var plain_steer_to := 10.0    ## m/s. Above this the wheels self-align and the lean keys only nudge them.

# --- Drive ---
var engine_power := 199000.0  ## W. With the drag below this sets top speed.
var engine_force := 11000.0    ## N, the most the engine can push at low speed
var wheel_mass := 100.0       ## kg. How heavy the rear wheels and driveline feel to the engine. Higher = wheelspin builds slower.
var rev_limit := 45.0         ## m/s of wheel speed where the engine runs out of revs
var engine_brake := 1500.0    ## N
var handbrake_force := 14000.0 ## N, enough to lock the rear wheels
var c_drag := 7.0
var c_roll := 50.0
var yaw_damp := 500.0         ## N m s

# --- Assists. assist = 0 switches them all off, 1 is full strength. ---
var assist := 0.0
var slip_damp := 2500.0       ## N m s, resists the drift angle changing. Makes a held slide steady.
var slip_damp_from := 0.17    ## rad of drift angle where that damping starts
var slip_damp_full := 0.45    ## rad where it is at full strength
var angle_soft_cap := 1.05    ## rad (~60 deg). Past this the car resists rotating further.
var angle_cap_gain := 9000.0  ## N m per rad past the cap
var spin_guard_angle := 1.25  ## rad (~72 deg)
var spin_guard_time := 0.15   ## s past that angle before the guard pulls the car back
var spin_guard_gain := 14000.0

# --- State ---
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var psi := 0.0
var yaw_rate := 0.0
var wy := 0.0                 ## sideways weight throw, -1 right .. +1 left (can overshoot)
var wy_v := 0.0
var wx := 0.0                 ## share of the car's weight moved onto the rear axle (negative = onto the front)
var wx_v := 0.0
var ws := 0.0                 ## m/s, speed of the rear tyres' surface. Above the car's forward speed = wheelspin.
var hbk := 0.0                ## handbrake amount 0..1
var pw := 0.0                 ## power amount 0..1
var kick := 0.0               ## 0..1, charged by a well-timed weight throw, fades over kick_time
var spin_timer := 0.0
var steer := 0.0              ## rad, front wheel angle

# --- Outputs (read-only, refreshed each step) ---
var speed := 0.0
var vx := 0.0                 ## forward speed in the body frame
var vy := 0.0                 ## leftward speed in the body frame
var slip_angle := 0.0         ## rad, angle between heading and travel. + = sliding left.
var beta_front := 0.0
var beta_rear := 0.0
var load_front := 0.0         ## N
var load_rear := 0.0          ## N
var lat_accel := 0.0          ## m/s^2 in the body frame, + = left
var long_accel := 0.0         ## m/s^2 in the body frame, + = forward
var wheelspin := 0.0          ## 0..1, how hard the rear wheels are spinning (or locked) against the road
var rear_grip_share := 1.0    ## share of rear cornering grip left after wheelspin or a locked wheel
var drive_force := 0.0        ## N, push from the rear tyres along the car
var guard_active := false
var slide := 0.0              ## 0..1, how hard the car is sliding. Smoke, skid marks and (later) score all key off this.
var slip_rate := 0.0          ## rad/s, how fast the drift angle is changing


func reset(at: Vector2 = Vector2.ZERO, heading: float = 0.0) -> void:
	pos = at
	vel = Vector2.ZERO
	psi = heading
	yaw_rate = 0.0
	wy = 0.0
	wy_v = 0.0
	wx = 0.0
	wx_v = 0.0
	ws = 0.0
	hbk = 0.0
	pw = 0.0
	kick = 0.0
	spin_timer = 0.0
	steer = 0.0
	slip_rate = 0.0
	speed = 0.0
	vx = 0.0
	vy = 0.0
	slip_angle = 0.0
	long_accel = 0.0
	lat_accel = 0.0
	wheelspin = 0.0
	rear_grip_share = 1.0
	slide = 0.0
	guard_active = false


func step(dt: float, throttle: bool, lean: float, handbrake: bool) -> void:
	var a := cg_to_front
	var b := cg_to_rear
	var wheelbase := a + b

	# Sideways weight throw follows the lean keys, on a bouncy spring.
	var wn_y := TAU * lat_freq
	wy_v += (wn_y * wn_y * (lean - wy) - 2.0 * lat_damping * wn_y * wy_v) * dt
	wy += wy_v * dt

	# Front-to-back weight follows the car's real acceleration (from the last
	# tick), through the pitch of the body. Accelerating loads the rear; lifting
	# or braking loads the front.
	var wn_x := TAU * long_freq
	var wx_target := cg_height / wheelbase * long_accel / G
	wx_v += (wn_x * wn_x * (wx_target - wx) - 2.0 * long_damping * wn_x * wx_v) * dt
	wx += wx_v * dt
	load_front = mass * G * maxf(0.05, b / wheelbase - wx)
	load_rear = mass * G * maxf(0.05, a / wheelbase + wx)

	hbk = clampf(hbk + (5.0 if handbrake else -2.0) * dt, 0.0, 1.0)
	pw = clampf(pw + (4.0 if throttle else -3.0) * dt, 0.0, 1.0)

	# Body-frame velocity.
	var fwd := Vector2(cos(psi), sin(psi))
	var left := Vector2(-sin(psi), cos(psi))
	vx = vel.dot(fwd)
	vy = vel.dot(left)
	speed = vel.length()

	# A weight swing past w_break is a well-timed throw. It charges a kick that
	# makes the front bite harder for a couple of seconds, so the slide that follows is bigger.
	var excess := maxf(0.0, absf(wy) - w_break)
	kick = maxf(kick * exp(-dt / kick_time), minf(1.0, k_feint * excess))

	# Slip angles at each axle.
	var vx_floor := maxf(absf(vx), 1.0)
	var vy_front := vy + a * yaw_rate
	var vy_rear := vy - b * yaw_rate

	# Rear wheel speed. The engine (or the handbrake) turns the wheels and the
	# road pushes back through the tyres. Solved implicitly so it stays stable
	# at any speed: find the wheel speed that is consistent with this tick's forces.
	var grip_rear := mu_rear * load_rear
	var lo := minf(minf(vx, 0.0) - 5.0, ws - 1.0)
	var hi := maxf(maxf(vx, rev_limit) + 5.0, ws + 1.0)
	for i in 24:
		var mid := 0.5 * (lo + hi)
		var net := _engine_force(mid) - _rear_force(mid, vx, vy_rear, grip_rear).x
		if mid - ws - dt / wheel_mass * net > 0.0:
			hi = mid
		else:
			lo = mid
	ws = 0.5 * (lo + hi)
	var rear := _rear_force(ws, vx, vy_rear, grip_rear)
	drive_force = rear.x
	var spin_slip := (ws - vx) / (vx_floor * peak_spin)
	rear_grip_share = 2.0 / sqrt(4.0 + spin_slip * spin_slip)
	wheelspin = clampf((absf(ws - vx) - 1.5) / 6.0, 0.0, 1.0)
	beta_front = atan2(vy_front, vx_floor)
	beta_rear = atan2(vy_rear, vx_floor)

	# Automatic steering: plain steering when crawling, caster plus lean at speed.
	# The wheels swing toward that at a limited rate.
	var k := smoothstep(plain_steer_from, plain_steer_to, speed)
	# Only weight up to the key's own target steers; any swing past it feeds the kick instead.
	var steer_weight := clampf(wy, -1.0, 1.0)
	var lean_steer := minf(d_frac * (1.0 + kick_gain * kick), 1.0) * peak_front
	var cmd := lerpf(low_speed_steer, lean_steer, k) * steer_weight * (1.0 if vx >= 0.0 else -1.0)
	# The hands also react to how fast the slide is growing or collapsing, which
	# is what settles it. They can only do as much as the front tyres' grip allows.
	# They do nothing until there is a slide to catch.
	var catching := smoothstep(lead_from, lead_full, absf(slip_angle))
	var steer_target := clampf(k_caster * k * beta_front + cmd + steer_lead * catching * k * slip_rate, -steer_lock, steer_lock)
	steer = move_toward(steer, steer_target, steer_rate * dt)

	# Tyre forces.
	var fy_front := -clampf((beta_front - steer) / peak_front, -1.0, 1.0) * mu_front * load_front
	var fy_rear := rear.y

	# Never push harder than what cancels the axle's sideways speed this tick.
	# This is what stops low-speed jitter.
	var m_front := 1.0 / (1.0 / mass + a * a / inertia)
	var m_rear := 1.0 / (1.0 / mass + b * b / inertia)
	var lat_front := -vx * sin(steer) + vy_front * cos(steer)
	var cap_front := 0.6 * m_front * absf(lat_front) / dt
	var cap_rear := 0.6 * m_rear * absf(vy_rear) / dt
	fy_front = clampf(fy_front, -cap_front, cap_front)
	fy_rear = clampf(fy_rear, -cap_rear, cap_rear)

	# Push from the rear tyres (drive, engine braking and handbrake all act
	# through them), minus rolling drag.
	var fx := drive_force - c_roll * vx

	# Air drag acts against the direction of travel, whichever way the car points.
	# A car going sideways gets no shelter from it, so a slide costs speed.
	var f_body := Vector2(
		fx - fy_front * sin(steer) - c_drag * speed * vx,
		fy_front * cos(steer) + fy_rear - c_drag * speed * vy
	)
	var torque := a * fy_front * cos(steer) - b * fy_rear - yaw_damp * yaw_rate

	slip_angle = atan2(vy, maxf(absf(vx), 1.0)) if speed > 1.0 else 0.0
	if vx < 0.0 and speed > 1.0:
		slip_angle = atan2(vy, vx)  # past 90 degrees, keep the true angle
	var abs_slip := absf(slip_angle)

	# How fast the drift angle is changing, from this tick's forces.
	slip_rate = 0.0
	if speed > 1.0:
		var accel_now := f_body / mass
		slip_rate = (vx * accel_now.y - vy * accel_now.x) / (speed * speed) - yaw_rate

	# Assists, all scaled by `assist`.
	guard_active = false
	if assist > 0.0 and speed > 1.0:
		torque += assist * slip_damp * slip_rate * smoothstep(slip_damp_from, slip_damp_full, abs_slip) * k
		if abs_slip > angle_soft_cap:
			# Soft ceiling: resist rotating further into the slide.
			torque += assist * signf(slip_angle) * angle_cap_gain * (abs_slip - angle_soft_cap) * k
		if abs_slip > spin_guard_angle:
			spin_timer += dt
			if spin_timer > spin_guard_time:
				guard_active = true
				torque += assist * signf(slip_angle) * spin_guard_gain * k
		else:
			spin_timer = 0.0

	# Integrate (semi-implicit Euler).
	var accel := f_body / mass
	long_accel = accel.x
	lat_accel = accel.y
	vel += (fwd * accel.x + left * accel.y) * dt
	yaw_rate += torque / inertia * dt
	pos += vel * dt
	psi += yaw_rate * dt

	if not throttle and vel.length() < 0.5:
		vel = Vector2.ZERO
		yaw_rate = 0.0
		ws = 0.0

	speed = vel.length()
	# Starts at 10 degrees of drift angle, the same point where a slide will start to score.
	slide = maxf(smoothstep(0.175, 0.5, absf(slip_angle)), 0.8 * hbk) * smoothstep(4.0, 9.0, speed)


## What the engine, engine braking and handbrake put through the rear wheels
## when they turn at surface speed `w`. The engine makes a fixed power, so its
## push falls as the wheels spin faster, and stops at the rev limit.
func _engine_force(w: float) -> float:
	var revs := 1.0 - smoothstep(0.92 * rev_limit, rev_limit, w)
	var turning := clampf(w / 0.5, -1.0, 1.0)
	return pw * minf(engine_force, engine_power / maxf(absf(w), 3.0)) * revs \
		- ((1.0 - pw) * engine_brake + hbk * handbrake_force) * turning


## Force from the rear tyres, x along the car and y to its left, when the wheels
## turn at surface speed `w`. The contact patch slips forward (wheelspin) and
## sideways (the slide) at once; the force points against that slip and its
## size follows one curve. So wheelspin and cornering draw on the same grip.
func _rear_force(w: float, forward: float, sideways: float, grip: float) -> Vector2:
	var road := maxf(absf(forward), 1.0)
	var spin := (w - forward) / (road * peak_spin)
	var side := sideways / (road * peak_rear)
	var slip := sqrt(spin * spin + side * side)
	if slip < 0.000001:
		return Vector2.ZERO
	var size := grip * _tyre_curve(slip)
	return Vector2(size * spin / slip, -size * side / slip)


## Grip against slip, where 1 is the slip the tyre grips hardest at. It climbs
## to that peak, then falls away to slide_grip. The fall is what makes a slide
## let go with a snap.
func _tyre_curve(slip: float) -> float:
	var full := slide_full / peak_rear
	if slip < 1.0:
		return slip
	if slip < full:
		return lerpf(1.0, slide_grip, (slip - 1.0) / (full - 1.0))
	return slide_grip
