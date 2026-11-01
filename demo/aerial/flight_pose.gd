extends SkeletonModifier3D

# Skydiver silhouettes with Titanfall's deliberate, heavy Titan articulation.
# Retain Overgrowth's authored poses + directional corrections; no passive limbs.
const RigProfile = preload("res://aerial/mech_rig_profile.gd")
const Spring = preload("res://aerial/pose_servo.gd")
const ArmPose = preload("res://aerial/arm_pose.gd")
const ContactPose = preload("res://aerial/contact_pose.gd")
@export var profile: RigProfile = preload("res://aerial/mech_rig_profile.tres")
var blend := Spring.new()
var chest := Spring.new()
var hips := Spring.new()
var head := Spring.new()
var com := Spring.new()
var regimes := Spring.new()
var launch := Spring.new()
var legs: Array = []
var arms: RefCounted
var contacts: RefCounted
var bones := {}
var clock := 0.0 # Shared exhaust clock; not a pose oscillator.
var root_angles := Vector3.ZERO
var air_weight := 1.0
# hover, streamlined, spread, coast, landing; normalized, never flight modes.
var posture_weights := PackedFloat32Array([1,0,0,0,0])
# Upright support, powered aerodynamic flight, independent coast, falling.
# These are continuous influences, not movement modes or an attitude controller.
var behavior_weights := PackedFloat32Array([1,0,0,0])
var motion := {}
var last_brake := 0.0
var effort_phase: StringName:
	get: return &"brace" if effort.y>0.25 else (&"drive" if effort.z>0.25 else (&"prepare" if effort.x>0.25 else &"rest"))
var effort := Vector3.ZERO # Prepare, opposing thrust, outgoing acceleration.
var lead_side := 1.0
var lead_time := 0.0

func configure(player: AnimationPlayer, mech: RigidBody3D) -> void:
	var sk := get_skeleton()
	for bone in Array(profile.torso_bones)+Array(profile.thigh_bones)+Array(profile.knee_bones)+Array(profile.foot_bones)+Array(profile.arm_roots)+Array(profile.arm_middles)+Array(profile.arm_ends)+["Neck"]:
		var index := sk.find_bone(bone)
		assert(index >= 0,"Missing procedural mech bone: "+str(bone))
		bones[bone] = index
	for joint in 6: legs.append(Spring.new())
	arms = ArmPose.new()
	arms.configure(sk,player,profile)
	contacts = ContactPose.new()
	contacts.configure(mech,profile)
	reset()

func reset() -> void:
	for spring in [chest,hips,head,com]: spring.reset()
	blend.reset(Vector3(1,0,0))
	regimes.reset(Vector3(1,0,0))
	launch.reset()
	behavior_weights = PackedFloat32Array([1,0,0,0])
	root_angles = Vector3.ZERO
	for side in 2:
		for joint in 3: legs[side*3+joint].reset(profile.leg_target(PackedFloat32Array([1,0,0,0,0]),side,joint))
	arms.reset()
	last_brake = 0.0
	effort = Vector3.ZERO
	lead_side = 1.0
	lead_time = 0.0
	contacts.reset()

func set_weight(weight: float) -> void:
	air_weight = clampf(weight,0,1)
	# Keep target preparation running over authored walking too. No native
	# influence-zero optimization may silently disable the ground target pass.
	active = true
	influence = 1.0

func update(delta: float, controller) -> void:
	clock = controller.clock
	contacts.update(delta,controller)
	motion = _sample_motion(controller,delta)
	_sample_effort(controller,delta)
	_choose_posture(controller,delta)
	motion["spread"] = posture_weights[2]
	motion["stream"] = posture_weights[1]
	motion["launch"] = launch.value.x
	motion["land"] = contacts.preparation
	motion.make_read_only()
	_update_body(delta)
	_update_legs(delta,controller)
	arms.update(delta,motion)

func _sample_motion(controller, delta: float) -> Dictionary:
	var basis := Basis(controller.attitude)
	var pilot: Basis = controller.pilot_frame()
	var flow: Vector3 = controller.local_airflow*Vector3(-1,1,-1)
	var pressure := clampf(0.5*controller.air_density*flow.length_squared()/3000.0,0,1)
	var omega: Vector3 = basis.inverse()*controller.angular_velocity
	var alpha: Vector3 = basis.inverse()*controller.angular_acceleration
	var pilot_rates: Vector3 = pilot.inverse()*controller.angular_velocity
	# Pose preparation reads the original request. Physics keeps its existing
	# command filter; filtering that result again erased brief animation accents.
	var intent: Vector3 = controller.rotation_request
	# USPA start-coast-stop: command/rate mismatch starts a stroke, sustained
	# rotation relaxes it, releasing input creates an opposing arrest stroke.
	# This is a visual intent signal, not another attitude controller.
	var steer: Vector3 = ((intent-pilot_rates/controller.MAX_RATE)*0.7+intent*0.65).clamp(-Vector3.ONE,Vector3.ONE)
	var load := clampf((controller.g_load-1.0)/3.0,0,1.2)
	var acceleration: Vector3 = controller.local_acceleration
	var compression := clampf(load*0.75+alpha.length()*0.028+clampf(-acceleration.z/30.0,0,1)*0.25+contacts.impact*0.4,0,1.3)
	var speed: float = controller.velocity.length()
	var slowing: float = maxf(0,-(basis*acceleration).dot(controller.velocity.normalized()))
	# Retro means delivered thrust opposing existing travel, not a throttle cut
	# or a velocity rewrite. Gravity and aerodynamic braking stay independent.
	var thrust_direction: Vector3 = controller.main_force.normalized() if controller.main_force.length_squared()>1 else basis.y
	# Prepare while the requested engines spool, then follow their delivered force.
	var next_output: float = move_toward(controller.engine_level,controller.DETENTS[controller.detent],controller.ENGINE_SPOOL_RATE*0.15)
	var retro: float = maxf(0,-thrust_direction.dot(controller.velocity.normalized()))*smoothstep(2,12,speed)*smoothstep(0.1,0.8,maxf(controller.engine_level,next_output))
	var brake_rate := clampf((controller.brake_amount-last_brake)/delta,-3,3) if delta>0 else 0.0
	last_brake = controller.brake_amount
	var roll_stop := clampf(pilot_rates.z/1.2-intent.z,-1,1)*(1.0-absf(intent.z))
	# Powered joints hold a pose. Hover corrections follow actual attitude effort,
	# never a perpetual clock-driven swim while the chassis is stable.
	var gyro: Vector3 = basis.inverse()*controller.rcs_torque.normalized()*clampf(controller.torque_fraction,0,1)
	var trim := gyro if gyro.length()>0.08 else Vector3.ZERO
	# Quiet trim cannot cancel a deliberate shoulder stroke or its arrest phase.
	trim *= 1.0-minf(maxf(intent.length(),steer.length()),1)
	return {"flow":flow.normalized(),"pressure":pressure,"omega":omega,"alpha":alpha,
		"translate":controller.hover_actuation*Vector3(-1,1,-1),
		"acceleration":acceleration,"compression":compression,"g_load":controller.g_load,
		"side_load":clampf(acceleration.x/22.0,-1,1),"pitch":intent.x,"yaw":intent.y,
		"roll":clampf(intent.z*0.7+pilot_rates.z/1.2*0.3,-1,1),"roll_stop":roll_stop,
		"up":basis.inverse()*Vector3.UP,"trim":trim,"gyro":gyro,
		"steer":steer,"body_steer":basis.inverse()*pilot*steer,
		"retro":retro,"brake_rate":brake_rate,"deceleration":smoothstep(2,12,slowing)*smoothstep(6,25,speed)*smoothstep(0.15,0.65,controller.g_load)}

func _sample_effort(controller, delta: float) -> void:
	# Overgrowth's authored directional corrections. This interprets the existing
	# solver; it never applies force or adds a passive body/limb simulation.
	var basis := Basis(controller.attitude)
	var output: float = controller.DETENTS[controller.detent]
	var requested: Vector3 = controller.requested_main_force
	var thrust: Vector3 = controller.main_force
	var axis := thrust.normalized() if thrust.length_squared()>1 else basis.y
	var request_axis := requested.normalized() if requested.length_squared()>1 else axis
	var velocity: Vector3 = controller.velocity
	var speed := velocity.length()
	var travel := velocity/maxf(speed,0.001)
	var delivered: float = smoothstep(0.1,0.8,controller.engine_level)
	var along := axis.dot(travel)
	var opposition: float = motion.retro
	var across := (axis-travel*along)*delivered*smoothstep(2,12,speed)
	var specific: Vector3 = basis.inverse()*(thrust+controller.aero_force+controller.leg_force)/(controller.body.mass*controller.GRAVITY)
	var acceleration: Vector3 = basis*controller.local_acceleration
	var acceleration_load := smoothstep(2,18,acceleration.dot(axis))*smoothstep(0.8,1.8,controller.engine_level)
	var spool := clampf((output-controller.engine_level-0.08)/2.0,0,1)
	var prepare := spool
	prepare = maxf(prepare,maxf(0,-request_axis.dot(travel)-opposition)*delivered*0.35)
	var drive := maxf(spool*0.85,acceleration_load)*(1.0-opposition)
	var target := Vector3(prepare,opposition,drive)
	# One bounded envelope for effort; final limb servos retain their velocities.
	for channel in 3:
		var tau: float = profile.effort_response[channel] if target[channel]>effort[channel] else 0.28
		var decay := 1.0-exp(-delta/maxf(tau,0.001))
		effort[channel] = lerpf(effort[channel],target[channel],decay)
	var local_across := basis.inverse()*across
	var local_travel := basis.inverse()*travel
	var lateral: float = local_across.x*0.8+specific.x*0.25+motion.steer.z*0.7+motion.steer.y*0.45
	if absf(lateral)>0.25 and lateral*lead_side<0:
		lead_time += delta
		if lead_time>0.12:
			lead_side = signf(lateral)
			lead_time = 0.0
	else: lead_time = 0.0
	var alignment := smoothstep(0.7,0.98,basis.y.dot(travel))*smoothstep(0.7,0.98,along)
	alignment = lerpf(1.0,alignment,smoothstep(2,12,speed))
	var slip := Vector3(-local_travel.x,0,-local_travel.z)*smoothstep(2,12,speed)
	var directional := maxf(local_across.length(),maxf(motion.body_steer.length()*0.55,slip.length()*motion.pressure*0.4))
	var role := clampf(maxf(directional,maxf(effort.y*0.65,effort.z*0.5)),0,1)
	role *= 1.0-controller.hover_assist*0.75
	# No fixed clock wobble during a committed maneuver. The retained lead side
	# supplies continuity through zero speed and exactly opposing vector geometry.
	motion.merge({"prepare":effort.x,"retro":effort.y,"drive":effort.z,
		"powered":delivered,
		"redirect":clampf(across.length(),0,1),"load_direction":specific*Vector3(-1,1,-1),
		"slip":slip,"lead":lead_side,"asymmetry":role,"alignment":alignment,
		"request_alignment":request_axis.dot(travel),"effort_phase":effort_phase},true)
	motion.trim *= 1.0-role

func _choose_posture(controller, delta: float) -> void:
	var landing: float = contacts.preparation
	var airload := smoothstep(0.04,0.35,motion.pressure)
	var powered := smoothstep(0.1,0.95,controller.engine_level)
	var hover: float = clampf(controller.hover_assist,0,1)
	var fighter: float = controller.aero_authority*powered*(1.0-hover)
	var downward: float = maxf(0,controller.velocity.dot(Vector3.DOWN))
	# Engine cutoff cannot instantly become a skydiver pose. Descent and useful
	# relative wind must develop; lateral coasting keeps its independent posture.
	var descent := smoothstep(2,12,downward)*smoothstep(0.1,0.65,downward/maxf(controller.velocity.length(),1))
	var falling := (1.0-hover-fighter)*(1.0-powered)*descent*airload
	var weights := regimes.step(Vector3(hover,fighter,falling),delta,0.24).clamp(Vector3.ZERO,Vector3.ONE)
	var total := weights.x+weights.y+weights.z
	if total>1: weights /= total
	behavior_weights = PackedFloat32Array([weights.x,weights.y,maxf(0,1-weights.x-weights.y-weights.z),weights.z])
	for index in 4: motion[["hover","fighter","coast","fall"][index]] = behavior_weights[index]*(1.0-landing)
	motion["track"] = airload*maxf(motion.fighter,smoothstep(0.55,0.9,absf(motion.flow.y))*(motion.coast+motion.fall))
	motion["box"] = motion.fall*smoothstep(0.25,0.75,absf(motion.flow.z))
	motion["brake"] = controller.brake_amount*lerpf(0.2,1,airload)*(1.0-landing)
	motion["flare"] = maxf(motion.brake,motion.deceleration)*(1.0-landing)
	var spread: float = maxf(motion.flare,motion.box)
	hover = motion.hover*(1.0-landing-spread)
	var stream: float = motion.track*maxf(0,1.0-landing-spread-hover)
	posture_weights = PackedFloat32Array([hover,stream,spread,maxf(0,1.0-landing-spread-hover-stream),landing])
	var pushing: bool = controller.leg_force.length()>1
	launch.step(Vector3(float(pushing),0,0),delta,0.06 if pushing else 0.18)

func _update_body(delta: float) -> void:
	var omega: Vector3 = motion.omega
	var alpha: Vector3 = motion.alpha
	var acceleration: Vector3 = motion.acceleration
	var intent: Vector3 = motion.body_steer
	var lag := Vector3(omega.x*0.025+alpha.x*0.002,omega.y*0.015,omega.z*0.025+alpha.z*0.002)
	lag += Vector3(acceleration.z*0.001,-acceleration.x*0.0005,-acceleration.x*0.001)
	var brace := Vector3(motion.brake*0.12+motion.retro*0.16,0,motion.side_load*0.06)
	brace += Vector3(motion.drive*0.07, motion.lead*motion.asymmetry*0.04,motion.load_direction.x*0.025)*(1.0-motion.hover)
	var intent_gain: float = motion.hover*0.5+motion.fighter*0.75+motion.coast+motion.fall*0.9
	var powered: float = motion.hover+motion.fighter
	var anticipation := intent*Vector3(0.22,0.24,0.28).lerp(Vector3(0.15,0.14,0.16),powered)*intent_gain
	# Armored Core VI slide language: a small committed lean over staggered legs,
	# while the physical hover chassis stays upright and the hands balance it.
	var move: Vector3 = motion.get("translate",Vector3.ZERO)
	anticipation += Vector3(move.z*0.10,0,move.x*0.12)
	var hover: Vector3 = Vector3(motion.trim.z*0.015,motion.trim.x*0.018,motion.trim.y*0.012)*motion.hover
	var supported := Vector3(-motion.land*0.035,0,0)
	hips.step((-anticipation*lerpf(0.25,0.15,powered)+lag*0.2+hover+supported).limit_length(0.07),delta,0.30,0.5)
	root_angles = hips.value*Vector3(-1,1,1)
	var displacement := Vector3(-acceleration.x*0.001,-clampf(motion.g_load-1,0,3)*0.012,acceleration.z*0.001)
	displacement += Vector3(motion.trim.x*0.012,motion.trim.y*0.008,0)*motion.hover
	displacement.z -= motion.land*0.02
	displacement.y -= (motion.retro*0.055+motion.drive*0.025)*(1.0-motion.land)*(1.0-motion.hover)
	com.step(displacement.limit_length(0.08),delta,0.30,0.4)
	# Chest establishes the arch and leads the shoulder press. Load lag stays
	# secondary so the upper body looks piloted rather than pulled by inertia.
	var arch := Vector3(-0.16*motion.box+0.04*motion.track-motion.launch*0.06,0,0)
	arch.x += motion.land*(0.10+motion.compression*0.08)
	arch += motion.gyro*Vector3(0.018,0.012,0.018)*motion.hover
	# Critically damped powered articulation: commit, decelerate, hold. No spring
	# overshoot through the torso after a command stops (Titanfall Titan reference).
	chest.step((lag*0.2+anticipation+brace*0.6+arch-hover*0.5).limit_length(lerpf(0.30,0.22,powered)),delta,0.30,0.9)
	# Head leads the maneuver and counter-rolls slightly; mouse look never
	# imposes a weapon-facing pose on the torso or either arm.
	head.step(Vector3(intent.x*0.10,intent.y*0.20,-chest.value.z*0.2),delta,0.22,1.0)

func _update_legs(delta: float, controller) -> void:
	var flow: Vector3 = motion.flow*motion.pressure
	var omega: Vector3 = motion.omega
	var compression: float = motion.compression*0.35*(1.0-motion.launch)
	# Preserve feasible calibrated anchors. When physical vectoring is already
	# at its cone, reduce extra load/airflow articulation rather than bend jets.
	var articulation := lerpf(1.0,0.35,clampf(controller.engine_level,0,1)*float(controller.motor_saturated))
	var move: Vector3 = motion.get("translate",Vector3.ZERO)
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var role: float = sx*(motion.lead*(0.06+motion.flare*0.5)+motion.steer.z*0.6+motion.steer.y*(0.45+motion.hover*0.20)+motion.lead*motion.asymmetry*0.3+move.x*0.55)*(1.0-motion.land)
		var stagger: float = profile.role_stagger*lerpf(articulation,1.0,motion.flare)
		var brace := clampf(sx*motion.side_load+omega.z*0.25,-1,1)
		var extras := [Vector3(flow.z*profile.leg_airflow_gain-compression*0.32+brace*0.22,-flow.x*0.22+omega.y*0.12,-flow.x*0.28-motion.side_load*0.12+sx*compression*0.10),
			Vector3(0.85*compression+brace*0.28,0,0),Vector3(-compression*0.30-brace*0.15,-flow.x*0.12,0)]
		var hover_shift: float = sx*motion.trim.x*profile.hover_leg_motion*motion.hover
		var leg_intent: Vector3 = motion.steer
		var leg_gain: float = motion.hover*0.4+motion.fighter*0.6+motion.coast+motion.fall
		var steer: float = sx*(leg_intent.z*0.18+leg_intent.y*0.12)*profile.maneuver_leg_motion/0.22*leg_gain
		extras[0] += Vector3(steer+move.z*0.14,motion.yaw*(sx*0.06+motion.hover*0.10),move.x*0.10)
		extras[1].x -= move.z*0.14 # Keep the loaded lower-leg nozzle axis coupled.
		extras[1] += Vector3(-steer*0.65+motion.brake_rate*0.04,0,0)
		extras[2] += Vector3(0,0,motion.roll_stop*0.06)
		extras[2].x += move.z*0.18 # Ankle points the physical heel thrust into the slide.
		for joint in 3:
			var target: Vector3 = profile.leg_target(posture_weights,side,joint)+extras[joint]*articulation
			var working: Vector3 = target.lerp(profile.drive_pose[joint]*Vector3(1,1,sx),motion.drive)
			working = working.lerp(profile.retro_pose[joint]*Vector3(1,1,sx),motion.retro)
			# Preserve the calibrated support pose; knee/hip changes compensate
			# each other rather than yawing a heavily loaded heel nozzle sideways.
			target = target.lerp(working,(1.0-motion.land)*(1.0-motion.launch)*(1.0-motion.hover))
			# A skydiver arches through the hips with the calves folded up. The
			# powered braking brace remains a separate pose for feasible nozzles.
			var falling: Vector3 = profile.fall_pose[joint]*Vector3(1,1,sx)+extras[joint]*articulation
			target = target.lerp(falling,motion.box*(1.0-motion.brake))
			target = target.lerp(profile.spread_pose[joint]*Vector3(1,1,sx),motion.flare*(1.0-motion.land))
			var extension: Vector3 = profile.launch_pose[joint]*Vector3(1,1,sx)
			target = target.lerp(extension,motion.launch)
			# Final directional correction survives every base-pose blend.
			if joint==0: target.x -= role*stagger
			if joint==1: target.x += role*stagger
			if joint==0: target.x += hover_shift
			if joint==1: target.x -= hover_shift
			target = profile.limit_joint(target,side,joint)
			var servo = legs[side*3+joint]
			servo.step(target,delta,lerpf(profile.leg_response[joint]+motion.hover*side*0.025+maxf(-role,0)*0.05,0.08,motion.launch),profile.joint_speed[joint])
			servo.value = profile.limit_joint(servo.value,side,joint)

func _rotate(bone: String, angles: Vector3) -> void:
	angles *= air_weight
	var sk := get_skeleton()
	var index: int = bones[bone]
	var rest := sk.get_bone_global_rest(index).basis.orthonormalized()
	var offset := rest.inverse()*Basis.from_euler(angles)*rest
	sk.set_bone_pose_rotation(index,(sk.get_bone_pose_rotation(index)*offset.get_rotation_quaternion()).normalized())

func _process_modification() -> void:
	if air_weight>0.0001:
		var difference := chest.value-hips.value
		for part in profile.torso_bones.size(): _rotate(profile.torso_bones[part],difference*Vector3(1,1,-1)*profile.torso_weights[part])
		_rotate("Neck",head.value)
		for side in 2:
			_rotate(profile.thigh_bones[side],legs[side*3].value)
			_rotate(profile.knee_bones[side],legs[side*3+1].value)
			_rotate(profile.foot_bones[side],legs[side*3+2].value)
		arms.apply(get_skeleton(),_rotate,air_weight)
	contacts.prepare_targets()
