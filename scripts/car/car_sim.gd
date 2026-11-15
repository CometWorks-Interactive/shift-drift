extends RefCounted
## Arcade drift model: one rigid body on a flat plane, one tyre curve per axle,
## and the car's "weight" as two key-driven springs.
##
## Sim frame: x forward, y left, yaw positive to the left (counter-clockwise from above).
## To place it in Godot: position = Vector3(-pos.y, 0, -pos.x), rotation.y = psi.
##
## Inputs per step: throttle (bool), lean (-1 right .. +1 left), handbrake (bool).
## There is no steering input. The front wheels self-align with the direction of
## travel (caster) and the lean adds a small steer on top.

const G := 9.81

# --- Body ---
var mass := 1200.0            ## kg
var inertia := 1500.0         ## kg m^2, yaw. Lower = snappier rotation.
var cg_to_front := 1.2        ## m
var cg_to_rear := 1.3         ## m

# --- Grip ---
var mu_front := 1.7
var mu_rear := 1.95
var peak_front := 0.14        ## rad of slip where the front saturates
var peak_rear := 0.17         ## rad where the rear reaches its knee
var knee_rear := 0.45         ## fraction of full rear grip at the knee
var full_rear := 1.0          ## rad where the rear reaches full grip (rising curve = progressive)
var power_grip := 0.4        ## rear grip multiplier on full throttle. THE drift-angle dial.
var handbrake_grip := 0.35    ## rear grip multiplier on handbrake
var slide_speed_from := 4.0   ## m/s. Below this, power does not loosen the rear (no donuts from a standstill).
var slide_speed_full := 11.0  ## m/s. Above this, power loosens the rear fully.

# --- Weight springs ---
var lat_freq := 1.3           ## Hz. Lower = more lag between key and turn.
var lat_damping := 0.3       ## under 1 = overshoot, which is what makes a flick work
var long_freq := 2.0          ## Hz
var long_damping := 0.7
var k_long := 0.05            ## share of axle load moved by throttle on/off
var w_break := 1.6            ## a weight swing past this counts as a well-timed throw
var k_feint := 4.0            ## how quickly swing past w_break fills the kick (1 / excess needed for a full kick)
var kick_gain := 0.5           ## extra lean steer at full kick. Sets how much bigger a timed slide is.
var kick_time := 2.5          ## s for a kick to fade

# --- Steering (automatic) ---
var d_frac := 0.5            ## lean steer as a fraction of peak_front
var k_caster := 1.0           ## front self-align strength. THE forgiveness dial.
var steer_lock := 1.0         ## rad
var low_speed_steer := 0.35   ## rad of plain steering at parking speed

# --- Drive ---
var engine_force := 7000.0    ## N
var engine_brake := 1500.0    ## N
var handbrake_force := 3000.0 ## N
var c_drag := 7.0
var c_roll := 50.0
var yaw_damp := 500.0         ## N m s
var yaw_damp_fast := 0.0      ## N m s^2, grows with the square of yaw rate. Tames violent transitions only.
var slip_damp := 2500.0          ## N m s, resists the drift angle changing. Makes a held slide steady.
var slip_damp_from := 0.17    ## rad of drift angle where that damping starts
var slip_damp_full := 0.45    ## rad where it is at full strength

# --- Assists ---
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
var wy := 0.0                 ## lateral weight, -1 right .. +1 left (can overshoot)
var wy_v := 0.0
var wx := 0.0                 ## longitudinal weight, + = rearward
var wx_v := 0.0
var hbk := 0.0                ## handbrake amount 0..1
var pw := 0.0                 ## power amount 0..1
var kick := 0.0               ## 0..1, charged by a well-timed weight throw, fades over kick_time
var spin_timer := 0.0

# --- Outputs (read-only, refreshed each step) ---
var speed := 0.0
var vx := 0.0                 ## forward speed in the body frame
var vy := 0.0                 ## leftward speed in the body frame
var slip_angle := 0.0         ## rad, angle between heading and travel. + = sliding left.
var beta_front := 0.0
var beta_rear := 0.0
var steer := 0.0              ## rad, front wheel angle
var rear_slip := 0.0          ## 0..1, how far past its knee the rear is
var load_front := 0.0         ## N
var load_rear := 0.0          ## N
var lat_accel := 0.0          ## m/s^2 in the body frame, + = left
var long_accel := 0.0         ## m/s^2 in the body frame, + = forward
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
	hbk = 0.0
	pw = 0.0
	kick = 0.0
	spin_timer = 0.0
	speed = 0.0
	vx = 0.0
	vy = 0.0
	slip_angle = 0.0
	steer = 0.0
	rear_slip = 0.0
	slide = 0.0
	guard_active = false


func step(dt: float, throttle: bool, lean: float, handbrake: bool) -> void:
	var a := cg_to_front
	var b := cg_to_rear
	var wheelbase := a + b

	# Weight springs. Lateral follows the lean keys, longitudinal follows the throttle.
	var wn_y := TAU * lat_freq
	wy_v += (wn_y * wn_y * (lean - wy) - 2.0 * lat_damping * wn_y * wy_v) * dt
	wy += wy_v * dt
	var wn_x := TAU * long_freq
	var wx_target := 1.0 if throttle else -1.0
	wx_v += (wn_x * wn_x * (wx_target - wx) - 2.0 * long_damping * wn_x * wx_v) * dt
	wx += wx_v * dt

	hbk = clampf(hbk + (5.0 if handbrake else -2.0) * dt, 0.0, 1.0)
	pw = clampf(pw + (4.0 if throttle else -3.0) * dt, 0.0, 1.0)

	# Body-frame velocity.
	var fwd := Vector2(cos(psi), sin(psi))
	var left := Vector2(-sin(psi), cos(psi))
	vx = vel.dot(fwd)
	vy = vel.dot(left)
	speed = vel.length()
	var dir := clampf(vx / 0.5, -1.0, 1.0)  # smooth sign of forward speed

	# Axle loads.
	load_front = mass * G * (b / wheelbase) * (1.0 - k_long * wx)
	load_rear = mass * G * (a / wheelbase) * (1.0 + k_long * wx)

	# A weight swing past w_break is a well-timed throw. It charges a kick that
	# makes the front bite harder for a couple of seconds, so the slide that follows is bigger.
	var excess := maxf(0.0, absf(wy) - w_break)
	kick = maxf(kick * exp(-dt / kick_time), minf(1.0, k_feint * excess))

	# Rear grip: power and handbrake cut it.
	var can_slide := smoothstep(slide_speed_from, slide_speed_full, speed)
	var mu_r := mu_rear * lerpf(1.0, power_grip, pw * can_slide) * lerpf(1.0, handbrake_grip, hbk)

	# Slip angles at each axle.
	var vx_floor := maxf(absf(vx), 1.0)
	var vy_front := vy + a * yaw_rate
	var vy_rear := vy - b * yaw_rate
	beta_front = atan2(vy_front, vx_floor)
	beta_rear = atan2(vy_rear, vx_floor)

	# Automatic steering: plain steering when crawling, caster plus lean at speed.
	var k := smoothstep(3.0, 10.0, speed)
	# Only weight up to the key's own target steers; any swing past it feeds the kick instead.
	var steer_weight := clampf(wy, -1.0, 1.0)
	var lean_steer := minf(d_frac * (1.0 + kick_gain * kick), 1.0) * peak_front
	var cmd := lerpf(low_speed_steer, lean_steer, k) * steer_weight * (1.0 if vx >= 0.0 else -1.0)
	steer = clampf(k_caster * k * beta_front + cmd, -steer_lock, steer_lock)

	# Tyre forces.
	var fy_front := -clampf((beta_front - steer) / peak_front, -1.0, 1.0) * mu_front * load_front
	var fy_rear := -_rear_curve(beta_rear) * mu_r * load_rear

	# Never push harder than what cancels the axle's sideways speed this tick.
	# This is what stops low-speed jitter.
	var m_front := 1.0 / (1.0 / mass + a * a / inertia)
	var m_rear := 1.0 / (1.0 / mass + b * b / inertia)
	var lat_front := -vx * sin(steer) + vy_front * cos(steer)
	var cap_front := 0.6 * m_front * absf(lat_front) / dt
	var cap_rear := 0.6 * m_rear * absf(vy_rear) / dt
	fy_front = clampf(fy_front, -cap_front, cap_front)
	fy_rear = clampf(fy_rear, -cap_rear, cap_rear)

	# Drive, drag and brakes.
	var fx := 0.0
	if throttle:
		fx += engine_force * pw
	else:
		fx -= engine_brake * dir
	fx -= c_roll * vx + c_drag * vx * absf(vx) + hbk * handbrake_force * dir

	var f_body := Vector2(
		fx - fy_front * sin(steer),
		fy_front * cos(steer) + fy_rear
	)
	var torque := a * fy_front * cos(steer) - b * fy_rear - yaw_damp * yaw_rate
	torque -= yaw_damp_fast * yaw_rate * absf(yaw_rate)

	# Assists.
	slip_angle = atan2(vy, maxf(absf(vx), 1.0)) if speed > 1.0 else 0.0
	if vx < 0.0 and speed > 1.0:
		slip_angle = atan2(vy, vx)  # past 90 degrees, keep the true angle
	var abs_slip := absf(slip_angle)
	guard_active = false
	if slip_damp > 0.0 and speed > 1.0:
		# Rate of change of the drift angle, from this tick's forces.
		var accel_now := f_body / mass
		slip_rate = (vx * accel_now.y - vy * accel_now.x) / (speed * speed) - yaw_rate
		torque += slip_damp * slip_rate * smoothstep(slip_damp_from, slip_damp_full, abs_slip) * k
	if abs_slip > angle_soft_cap:
		# Soft ceiling: resist rotating further into the slide.
		torque += signf(slip_angle) * angle_cap_gain * (abs_slip - angle_soft_cap) * k
	if abs_slip > spin_guard_angle:
		spin_timer += dt
		if spin_timer > spin_guard_time:
			guard_active = true
			torque += signf(slip_angle) * spin_guard_gain * k
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

	speed = vel.length()
	# Starts at 10 degrees of drift angle, the same point where a slide will start to score.
	slide = maxf(smoothstep(0.175, 0.5, absf(slip_angle)), 0.8 * hbk) * smoothstep(4.0, 9.0, speed)
	rear_slip = clampf((absf(beta_rear) - peak_rear) / (full_rear - peak_rear), 0.0, 1.0) * k


func _rear_curve(beta: float) -> float:
	var x := absf(beta)
	var y := 1.0
	if x < peak_rear:
		y = knee_rear * x / peak_rear
	elif x < full_rear:
		y = lerpf(knee_rear, 1.0, (x - peak_rear) / (full_rear - peak_rear))
	return y * signf(beta)
