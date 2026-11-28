extends SkeletonModifier3D

# Skydiver silhouettes with Titanfall's deliberate, heavy Titan articulation.
# Retain Overgrowth's authored poses + directional corrections; no passive limbs.
const RigProfile = preload("res://aerial/mech_rig_profile.gd")
const Spring = preload("res://aerial/pose_servo.gd")
const Articulation = preload("res://aerial/poses/articulation_poses.gd")
const ArmPose = preload("res://aerial/arm_pose.gd")
const ContactPose = preload("res://aerial/contact_pose.gd")
const MechanicalResponse = preload("res://aerial/mechanical_response.gd")
const FlightPoseFrame = preload("res://aerial/flight_pose_frame.gd")
@export var profile: RigProfile = preload("res://aerial/mech_rig_profile.tres")
var chest := Spring.new()
var hips := Spring.new()
var head := Spring.new()
var com := Spring.new()
var regimes := Spring.new()
var launch := Spring.new()
var legs: Array = []
var arms: RefCounted
var contacts: RefCounted
var mechanical := MechanicalResponse.new()
var mechanical_joint_loads: Dictionary = {}
var bones := {}
var clock := 0.0 # Shared exhaust clock; not a pose oscillator.
var root_angles := Vector3.ZERO
# hover, streamlined, spread, coast, landing; normalized, never flight modes.
var posture_weights := PackedFloat32Array([1,0,0,0,0])
# Upright support, powered aerodynamic flight, independent coast, falling.
# These are continuous influences, not movement modes or an attitude controller.
var behavior_weights := PackedFloat32Array([1,0,0,0])
var motion := {}
var last_brake := 0.0
var arrest := 0.0
var recovery := 0.0
var effort_phase: StringName:
	get: return &"arrest" if arrest>0.25 else (&"recovery" if recovery>0.25 else (&"brace" if effort.y>0.25 else (&"drive" if effort.z>0.25 else (&"prepare" if effort.x>0.25 else &"rest"))))
var effort := Vector3.ZERO # Prepare, opposing thrust, outgoing acceleration.
var lead_side := 1.0
var lead_time := 0.0
var layout := 0.0 # Air-supported extended-body alternative to compact actuator flips.
var ground_animation_active := false
var gaze_heading := Vector3.ZERO
var stress := Vector2.ZERO
var previous_intent := Vector3.ZERO
var stroke_direction := Vector3.ZERO
var stroke_age := 1.0
var stroke_duration := 0.5
var gesture_count := 0
var tested_gesture := -1
var leg_stroke_available := false
var primary_trim := Vector3.ZERO
var trim_clock := 0.0
var trim_axis := 0

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
	mechanical.reset()
	mechanical_joint_loads.clear()
	regimes.reset(Vector3(1,0,0))
	launch.reset()
	behavior_weights = PackedFloat32Array([1,0,0,0])
	root_angles = Vector3.ZERO
	var neutral := Articulation.angles("Neutral_Flight") if contacts.body.controller.articulated_flight else PackedVector3Array()
	for side in 2:
		for joint in 3:
			var angle := profile.leg_target(PackedFloat32Array([1,0,0,0,0]),side,joint) if neutral.is_empty() else neutral[side*3+joint]
			legs[side*3+joint].reset(angle)
	arms.reset(contacts.body.controller.articulated_flight)
	last_brake = 0.0
	effort = Vector3.ZERO
	arrest = 0.0
	recovery = 0.0
	lead_side = 1.0
	lead_time = 0.0
	layout = 0.0
	ground_animation_active = false
	gaze_heading = Vector3.ZERO
	stress = Vector2.ZERO
	previous_intent = Vector3.ZERO
	stroke_direction = Vector3.ZERO
	stroke_age = 1.0
	gesture_count = 0
	tested_gesture = -1
	leg_stroke_available = false
	primary_trim = Vector3.ZERO
	trim_clock = 0.0
	trim_axis = 0
	contacts.reset()

func update(delta: float, controller) -> void:
	contacts.update(delta,controller)
	var frame := FlightPoseFrame.capture(controller,mechanical_joint_loads,delta)
	clock = frame.clock
	motion = _sample_motion(frame,controller)
	_sample_effort(frame,delta)
	var mechanical_sample := {
		"local_acceleration":frame.local_acceleration*Vector3(-1,1,-1),
		"local_jerk":frame.local_jerk*Vector3(-1,1,-1),
		"local_angular_acceleration":Basis(frame.attitude).inverse()*frame.angular_acceleration,
		"g_load":frame.g_load,"brake":maxf(frame.brake_amount,frame.brake_request),
		"retro":motion.get("retro",0.0),"motor_forces":frame.motor_forces,
		"motor_ratings":frame.motor_ratings,"pressure_scales":frame.engine_pressure_scales,
		"joint_moments":frame.joint_moments,"arrest":arrest,
		"weight":frame.body_mass*frame.gravity
	}
	motion.merge(mechanical.step(mechanical_sample,delta),true)
	_choose_posture(frame,delta)
	motion["spread"] = posture_weights[2]
	motion["stream"] = posture_weights[1]
	motion["launch"] = launch.value.x
	motion["land"] = contacts.preparation
	_prepare_directional_pose(frame)
	_prepare_maneuver_pose(frame,delta)
	if frame.articulated_flight: _sample_articulation(frame,delta)
	var ground = contacts.body.ground_motion
	if ground:
		var grounded_pose_available: bool = (
			ground.supported and not ground.hot_enabled and not ground.braking
			and not ground.skidding and ground.pivot_steps==0 and ground.hop_load<=0.0
			and ground.catch_time<=0.0 and ground.recovery<=0.0
		)
		motion["ground_guard"] = float(ground.guard and grounded_pose_available)
		motion["ground_run"] = float(grounded_pose_available and (ground.step_running or ground.running))
		motion["ground_phase"] = clampf(ground.step_time/maxf(ground.step_duration,0.01),0.0,1.0) if ground.step_time>=0.0 else 0.0
		motion["ground_swing"] = ground.swing
		motion["ground_load"] = float(ground.hop_load>0.0) + ground.landing_load
		motion["ground_skid"] = clampf(ground.slip/4.0,0,1)
		motion["ground_tuck"] = float(not ground.supported and not ground.hot_enabled)*smoothstep(0.0,2.0,ground.velocity.y)
	motion.make_read_only()
	_update_body(delta)
	_update_legs(delta,frame,controller)
	arms.update(delta,motion)
	if ground_animation_active:
		root_angles = Vector3.ZERO
		com.reset()

func _sample_motion(frame, controller) -> Dictionary:
	var basis := Basis(frame.attitude)
	var pilot: Basis = frame.pilot_frame
	var flow: Vector3 = frame.local_airflow*Vector3(-1,1,-1)
	var pressure := clampf(0.5*frame.air_density*flow.length_squared()/3000.0,0,1)
	var omega: Vector3 = basis.inverse()*frame.angular_velocity
	var alpha: Vector3 = basis.inverse()*frame.angular_acceleration
	var pilot_rates: Vector3 = pilot.inverse()*frame.angular_velocity
	var intent: Vector3 = frame.pilot_rotation_intent
	if intent.is_zero_approx(): intent = frame.rotation_request
	var target_rates: Vector3 = frame.effective_rates
	var rate_scale: Vector3 = frame.max_rate.max(target_rates.abs())
	var steer: Vector3 = ((target_rates-pilot_rates)/rate_scale*0.7+intent*0.65).clamp(-Vector3.ONE,Vector3.ONE)
	var load := clampf((frame.g_load-1.0)/3.0,0,1.2)
	var acceleration: Vector3 = frame.local_acceleration
	var compression := clampf(load*0.75+alpha.length()*0.028+clampf(-acceleration.z/30.0,0,1)*0.25+contacts.impact*0.4,0,1.3)
	var speed: float = frame.velocity.length()
	var slowing: float = maxf(0,-(basis*acceleration).dot(frame.velocity.normalized()))
	var retro := Articulation.retrograde_weight(frame.velocity,frame.main_force,
		frame.requested_main_force,frame.body_mass*frame.gravity,frame.detent>0 or frame.jump_remaining>0)
	var brake_rate := clampf((frame.brake_amount-last_brake)/frame.delta,-3,3) if frame.delta>0 else 0.0
	last_brake = frame.brake_amount
	var roll_stop := clampf(pilot_rates.z/frame.max_rate.z-intent.z,-1,1)*(1.0-absf(intent.z))
	var gyro: Vector3 = basis.inverse()*frame.rcs_torque.normalized()*clampf(frame.torque_fraction,0,1)
	var trim := gyro if gyro.length()>0.08 else Vector3.ZERO
	trim *= 1.0-minf(maxf(intent.length(),steer.length()),1)
	var look := Vector3.ZERO
	var gaze: Vector3 = _articulated_gaze(frame,controller,basis,intent,frame.delta) if frame.articulated_flight else frame.gaze_direction
	if not gaze.is_zero_approx():
		var mech = controller.body
		var sk: Skeleton3D = mech.skeleton
		var torso := sk.find_bone("Torso")
		var pose: Basis = sk.global_basis.orthonormalized()*mech.bone_poses[torso].basis.orthonormalized()*sk.get_bone_global_rest(torso).basis.orthonormalized().inverse()
		var direction: Vector3 = pose.inverse()*gaze.normalized()
		var yaw := atan2(direction.x,direction.z)
		if direction.z<0 and absf(direction.x)<0.15: yaw = PI*signf(head.value.y if absf(head.value.y)>0.05 else 1.0)
		look = Vector3(-atan2(direction.y,Vector2(direction.x,direction.z).length()),yaw,0)
	return {"flow":flow.normalized(),"pressure":pressure,"omega":omega,"alpha":alpha,
		"translate":frame.hover_actuation*Vector3(-1,1,-1),
		"move_intent":frame.translation_request*Vector3(-1,1,-1),
		"acceleration":acceleration,"compression":compression,"g_load":frame.g_load,
		"look_angles":look,"look_weight":float(not gaze.is_zero_approx()),"target_rates":target_rates,"pilot_rates":pilot_rates,
		"side_load":clampf(acceleration.x/22.0,-1,1),"pitch":intent.x,"yaw":intent.y,
		"roll":clampf(intent.z*0.7+pilot_rates.z/frame.max_rate.z*0.3,-1,1),"roll_stop":roll_stop,
		"up":basis.inverse()*Vector3.UP,"trim":trim,"gyro":gyro,
		"steer":steer,"body_steer":(basis.inverse()*pilot*steer)*Vector3(-1,1,-1),
		"retro":retro,"brake_rate":brake_rate,"deceleration":smoothstep(2,12,slowing)*smoothstep(6,25,speed)*smoothstep(0.15,0.65,frame.g_load)*maxf(retro,maxf(frame.brake_request,frame.brake_amount))}

func _sample_effort(frame, delta: float) -> void:
	var basis := Basis(frame.attitude)
	var output: float = frame.detent_output
	var requested: Vector3 = frame.requested_main_force
	var thrust: Vector3 = frame.main_force
	var axis := thrust.normalized() if thrust.length_squared()>1 else basis.y
	var request_axis := requested.normalized() if requested.length_squared()>1 else axis
	var velocity: Vector3 = frame.velocity
	var speed := velocity.length()
	var travel := velocity/maxf(speed,0.001)
	var delivered: float = smoothstep(0.1,0.8,frame.thrust_level)
	var along := axis.dot(travel)
	var opposition: float = motion.retro
	var across := (axis-travel*along)*delivered*smoothstep(2,12,speed)
	var specific: Vector3 = basis.inverse()*(thrust+frame.aero_force+frame.cold_force)/(frame.body_mass*frame.gravity)
	var acceleration: Vector3 = basis*frame.local_acceleration
	var acceleration_load := smoothstep(2,18,acceleration.dot(axis))*smoothstep(0.8,1.8,frame.thrust_level)
	var spool := clampf((output-frame.thrust_level-0.08)/2.0,0,1)
	var prepare := spool
	prepare = maxf(prepare,maxf(0,-request_axis.dot(travel)-opposition)*delivered*0.35)
	var drive := maxf(spool*0.85,acceleration_load)*(1.0-opposition)
	var target := Vector3(prepare,opposition,drive)
	var pilot_rates: Vector3 = motion.pilot_rates
	var pilot_intent: Vector3 = frame.pilot_rotation_intent
	if pilot_intent.is_zero_approx(): pilot_intent = frame.rotation_request
	var rotational_arrest := 0.0
	for axis_index in 3:
		if absf(pilot_intent[axis_index])>0.1 and pilot_intent[axis_index]*pilot_rates[axis_index]<0.0:
			rotational_arrest = maxf(rotational_arrest,smoothstep(0.05,0.55,absf(pilot_rates[axis_index])/maxf(frame.max_rate[axis_index],0.001)))
	var brake_event := smoothstep(0.08,0.55,maxf(frame.brake_amount,frame.brake_request))*smoothstep(2.0,18.0,speed)*smoothstep(1.0,2.2,frame.g_load)
	var reversal_event := smoothstep(0.10,0.55,opposition)*smoothstep(1.0,2.4,frame.g_load)
	var arrest_target := maxf(rotational_arrest,maxf(brake_event*0.8,reversal_event*0.55))
	arrest = lerpf(arrest,arrest_target,1.0-exp(-delta/(0.055 if arrest_target>arrest else 0.18)))
	var recovery_target := 1.0 if arrest_target<0.06 and arrest>0.15 else 0.0
	recovery = lerpf(recovery,recovery_target,1.0-exp(-delta/(0.16 if recovery_target>recovery else 0.32)))
	for channel in 3:
		var tau: float = (0.10 if channel==1 else profile.effort_response[channel]) if target[channel]>effort[channel] else 0.28
		var decay := 1.0-exp(-delta/maxf(tau,0.001))
		effort[channel] = lerpf(effort[channel],target[channel],decay)
	var local_across := basis.inverse()*across
	var local_travel := basis.inverse()*travel
	var lateral: float = motion.move_intent.x*1.5-local_across.x*0.8-specific.x*0.25+motion.steer.z*0.7+motion.steer.y*0.45
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
	role *= 1.0-frame.hover_assist*0.75
	role = maxf(role,motion.move_intent.length())
	motion.merge({"prepare":effort.x,"retro":effort.y,"drive":effort.z,
		"powered":delivered,"arrest":arrest,"recovery":recovery,
		"redirect":clampf(across.length(),0,1),"load_direction":specific*Vector3(-1,1,-1),
		"slip":slip,"lead":lead_side,"asymmetry":role,"alignment":alignment,
		"request_alignment":request_axis.dot(travel),"effort_phase":effort_phase},true)
	motion.trim *= 1.0-role

func _choose_posture(frame, delta: float) -> void:
	var landing: float = contacts.preparation
	var airload := smoothstep(0.02,0.20,motion.pressure)
	var powered := smoothstep(0.1,0.95,frame.thrust_level)
	var hover: float = clampf(frame.hover_assist,0,1)
	var fighter: float = frame.aero_authority*powered*(1.0-hover)
	var downward: float = maxf(0,frame.velocity.dot(Vector3.DOWN))
	var descent := smoothstep(2,12,downward)*smoothstep(0.1,0.65,downward/maxf(frame.velocity.length(),1))
	var falling := (1.0-hover-fighter)*(1.0-powered)*descent*airload
	var weights := regimes.step(Vector3(hover,fighter,falling),delta,0.24).clamp(Vector3.ZERO,Vector3.ONE)
	var total := weights.x+weights.y+weights.z
	if total>1: weights /= total
	behavior_weights = PackedFloat32Array([weights.x,weights.y,maxf(0,1-weights.x-weights.y-weights.z),weights.z])
	for index in 4: motion[["hover","fighter","coast","fall"][index]] = behavior_weights[index]*(1.0-landing)
	motion["track"] = airload*maxf(motion.fighter,smoothstep(0.55,0.9,absf(motion.flow.y))*(motion.coast+motion.fall))
	motion["air_control"] = airload*(1.0-hover)*(1.0-landing)
	motion["box"] = motion.fall*smoothstep(0.25,0.75,absf(motion.flow.z))
	motion["belly"] = motion.box*smoothstep(-0.2,0.2,-motion.flow.z)
	motion["back"] = motion.box-motion.belly
	motion["brake"] = maxf(frame.brake_request,frame.brake_amount)*lerpf(0.2,1,airload)*(1.0-landing)
	motion["flare"] = maxf(motion.brake,motion.deceleration)*(1.0-landing)
	motion["brake_turn"] = frame.rotation_request*Vector3(1,-1,1)*motion.brake
	var spread: float = maxf(motion.flare,motion.box)
	hover = motion.hover*(1.0-landing-spread)
	var stream: float = motion.track*maxf(0,1.0-landing-spread-hover)
	posture_weights = PackedFloat32Array([hover,stream,spread,maxf(0,1.0-landing-spread-hover-stream),landing])
	var pushing: bool = frame.jump_remaining>0 and frame.thrust_level>1.0
	launch.step(Vector3(float(pushing),0,0),delta,0.06 if pushing else 0.18)

func _prepare_directional_pose(frame) -> void:
	var reach: Vector3 = motion.move_intent if not motion.move_intent.is_zero_approx() else motion.translate
	reach = reach.limit_length(1.0)*(1.0-motion.land)*(1.0-motion.launch)
	var strength := smoothstep(0.10,0.85,reach.length())
	var side: float = signf(reach.x) if absf(reach.x)>0.1 else lead_side
	var loaded_scale: float = lerpf(1.0,0.45,smoothstep(2,4,frame.thrust_level))
	var knees := Vector2(profile.slide_knees.x,profile.slide_knees.y) if side>0 else Vector2(profile.slide_knees.y,profile.slide_knees.x)
	knees *= strength
	var turn: float = (motion.steer.z*0.9+motion.steer.y*0.4)*profile.role_stagger*(1.0-motion.land)*(1.0-motion.launch)
	knees += Vector2(turn,-turn)
	motion["reach"] = reach
	motion["gather"] = knees*loaded_scale

func _prepare_maneuver_pose(frame, delta: float) -> void:
	var weight: Vector2 = frame.maneuver_strength
	var sum := weight.x+weight.y
	if sum>1.0: weight /= sum
	var recovery: Vector2 = frame.maneuver_recovery
	var signs: Vector2 = frame.maneuver_direction
	var travel: Vector2 = frame.maneuver_travel*signs
	var rolling := smoothstep(deg_to_rad(55),deg_to_rad(140),maxf(travel.y,0))
	var bank: float = signs.y*weight.y*(1.0-rolling)
	var held_bank: float = frame.pilot_frame.x.y*maxf(motion.fighter,motion.air_control)*smoothstep(0.1,0.8,motion.g_load)*0.55
	bank = lerpf(held_bank,bank,minf(frame.maneuver_strength.y,1.0))
	weight.y *= rolling
	var available: float = (1.0-motion.land)*(1.0-motion.launch)
	weight *= available
	recovery *= available
	var error: float = absf(motion.target_rates.x-motion.pilot_rates.x)
	var long_body: float = motion.pressure*(1.0-smoothstep(0.6,1.5,error))*(1.0-motion.brake*0.65)
	layout = lerpf(layout,long_body,1.0-exp(-delta/0.24))
	motion["layout"] = layout
	var flip := profile.maneuver_shape(maxf(travel.x,0.0))
	var roll := profile.maneuver_shape(maxf(travel.y,0.0))
	flip = flip.lerp(Vector3(0,0,1),recovery.x)
	roll = roll.lerp(Vector3(0,0,1),recovery.y)
	motion.merge({"bank_gesture":bank*available,"acro":weight,"acro_recovery":recovery,"acro_sign":signs,
		"flip_shape":flip,"roll_shape":roll},true)

func _update_body(delta: float) -> void:
	var omega: Vector3 = motion.omega
	var alpha: Vector3 = motion.alpha
	var acceleration: Vector3 = motion.acceleration
	var intent: Vector3 = motion.body_steer
	var lag := Vector3(omega.x*0.025+alpha.x*0.002,omega.y*0.015,omega.z*0.025+alpha.z*0.002)
	lag += Vector3(acceleration.z*0.001,-acceleration.x*0.0005,-acceleration.x*0.001)
	var arrest: float = motion.get("arrest",0.0)
	var recovery: float = motion.get("recovery",0.0)
	var brace: Vector3 = motion.body_steer*Vector3(0.50,0.22,-0.20)*motion.brake
	brace += Vector3(motion.brake*0.12+motion.retro*0.16+arrest*0.18,0,motion.side_load*0.06+arrest*0.05)
	brace += Vector3(motion.drive*0.07, motion.lead*motion.asymmetry*0.04,motion.load_direction.x*0.025)*(1.0-motion.hover)
	# Present the chest into yawing airflow; this calibrates armor incidence,
	# while the controller retains its fixed pilot axes.
	intent.z *= lerpf(1.0,-1.0,motion.fighter)
	var intent_gain: float = motion.hover*0.5+motion.fighter*0.75+motion.coast+motion.fall*0.9
	var powered: float = motion.hover+motion.fighter
	var anticipation := intent*Vector3(0.22,0.24,0.28).lerp(Vector3(0.15,0.14,0.16),powered)*intent_gain
	anticipation.x *= lerpf(1.0,0.4,motion.fighter*(1.0-motion.brake))
	# Armored Core VI slide language: a small committed lean over staggered legs,
	# while the physical hover chassis stays upright and the hands balance it.
	var move: Vector3 = motion.reach
	anticipation += Vector3(move.z*profile.slide_lean.x,0,move.x*profile.slide_lean.y)
	var hover: Vector3 = Vector3(motion.trim.z*0.015,motion.trim.x*0.018,motion.trim.y*0.012)*motion.hover
	var supported := Vector3(-motion.land*0.035,0,0)
	var acro: Vector2 = motion.get("acro",Vector2.ZERO)
	var signs: Vector2 = motion.get("acro_sign",Vector2.ZERO)
	var flip: Vector3 = motion.get("flip_shape",Vector3.ZERO)
	var roll: Vector3 = motion.get("roll_shape",Vector3.ZERO)
	var bank: float = motion.get("bank_gesture",0.0)
	var front: float = maxf(-signs.x,0.0)
	var back: float = maxf(signs.x,0.0)
	var swing_pitch: float = front*0.20-back*0.24
	anticipation.x += acro.x*(swing_pitch*flip.x+0.32*flip.y-0.12*flip.z)
	anticipation.y += bank*0.14+signs.y*acro.y*(0.14*roll.x-0.12*roll.y)
	anticipation.z += signs.y*acro.y*(0.08*roll.x-0.08*roll.y)
	var pelvic := Vector3(acro.x*(-swing_pitch*flip.x+0.26*flip.y),-bank*0.12-signs.y*acro.y*roll.x*0.12,acro.y*signs.y*0.08)
	hips.step((pelvic-anticipation*lerpf(0.25,0.15,powered)+lag*0.2+hover+supported).limit_length(lerpf(0.07,0.20,minf(acro.length()+absf(bank)*0.4,1.0))),delta,0.30,0.5)
	root_angles = (hips.value+motion.get("mechanical_pelvis",Vector3.ZERO))*Vector3(-1,1,1)
	var displacement := Vector3(-acceleration.x*0.001,-clampf(motion.g_load-1,0,3)*0.012,acceleration.z*0.001)
	displacement += Vector3(motion.trim.x*0.012,motion.trim.y*0.008,0)*motion.hover
	displacement.z -= motion.land*0.02
	displacement.y -= (motion.retro*0.055+motion.drive*0.025)*(1.0-motion.land)*(1.0-motion.hover)
	com.step(displacement.limit_length(0.08),delta,0.30,0.4)
	# Chest establishes the arch and leads the shoulder press. Load lag stays
	# secondary so the upper body looks piloted rather than pulled by inertia.
	var arch := Vector3(-0.16*motion.get("belly",motion.box)+0.12*motion.get("back",0.0)+0.04*motion.track-motion.launch*0.06,0,0)
	arch.x += motion.land*(0.10+motion.compression*0.08)
	arch.x += motion.get("ground_load",0.0)*0.15+motion.get("ground_skid",0.0)*0.18
	arch += motion.gyro*Vector3(0.018,0.012,0.018)*motion.hover
	# Critically damped powered articulation: commit, decelerate, hold. No spring
	# overshoot through the torso after a command stops (Titanfall Titan reference).
	var chest_target := lag*0.2+anticipation+brace*0.6+arch-hover*0.5
	if motion.get("authored",false):
		var stroke: Vector3 = motion.stroke
		chest_target = Articulation.torso_target(motion)+lag*0.45+Vector3(stroke.x*0.12,stroke.z*0.10,stroke.y*0.09)
	chest_target += Vector3(arrest*0.045-recovery*0.025,0,0)
	chest.step(chest_target.clamp(Vector3(-0.45,-0.30,-0.45),Vector3(0.45,0.30,0.45)),delta,0.30,0.9)
	_update_head(delta)

func _update_head(delta: float) -> void:
	# Intention leads the shoulders; neutral airflow changes the sight line.
	# No idle oscillator, perfect world-level lock, or head-to-chassis feedback.
	var look_weight: float = motion.get("look_weight",0.0)
	var intent: Vector3 = motion.body_steer
	var acro: Vector2 = motion.get("acro",Vector2.ZERO)
	var signs: Vector2 = motion.get("acro_sign",Vector2.ZERO)
	var flip: Vector3 = motion.get("flip_shape",Vector3.ZERO)
	var bank: float = motion.get("bank_gesture",0.0)
	var base := Vector3(-motion.track*0.72-motion.get("belly",motion.box)*0.30-motion.get("back",0.0)*0.18,0,0)
	base.x += motion.land*0.12-motion.launch*0.08
	var wanted: Vector3 = base.lerp(motion.get("look_angles",Vector3.ZERO),look_weight)
	var arrest: float = motion.get("arrest",0.0)
	var lead := Vector3(intent.x*0.15-motion.reach.z*0.08,intent.y*0.26+motion.reach.x*0.16+bank*0.14,0)
	lead *= 1.0-arrest*0.35
	lead.x += acro.x*(-signs.x*0.14)*flip.x
	wanted += lead*lerpf(1.0,0.2,look_weight)
	if motion.get("authored",false) and wanted.distance_to(head.value)<deg_to_rad(2.0):
		wanted = head.value
	wanted.z = -chest.value.z*0.2-motion.up.x*0.10
	head.step(profile.limit_head(wanted),delta,profile.head_response,profile.head_speed)
	head.value = profile.limit_head(head.value)

func _update_legs(delta: float, frame, controller) -> void:
	if motion.get("authored",false):
		_update_authored_legs(delta,frame,controller)
		return
	var flow: Vector3 = motion.flow*motion.pressure
	var omega: Vector3 = motion.omega
	var compression: float = motion.compression*0.35*(1.0-motion.launch)
	var articulation := lerpf(1.0,0.35,clampf(frame.thrust_level,0,1)*float(frame.motor_saturated))
	var move: Vector3 = motion.get("translate",Vector3.ZERO)
	var thrust_tuck: float = smoothstep(2,4,frame.thrust_level)*profile.high_thrust_tuck
	thrust_tuck *= 1.0-maxf(maxf(motion.flare,motion.retro),maxf(motion.land,motion.launch))
	thrust_tuck *= 1.0-move.length()
	var reverse_slide: float = minf(move.z,0)*profile.high_thrust_reverse*smoothstep(2,4,frame.thrust_level)
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var role: float = sx*(motion.lead*(0.06+motion.flare*0.5)+motion.steer.z*0.6+motion.steer.y*(0.45+motion.hover*0.20)+motion.lead*motion.asymmetry*0.3+move.x*0.55+motion.get("bank_gesture",0.0)*0.3)*(1.0-motion.land)
		var stagger: float = profile.role_stagger*lerpf(articulation,1.0,motion.flare)
		var brace := clampf(sx*motion.side_load+omega.z*0.25,-1,1)
		var extras := [Vector3(flow.z*profile.leg_airflow_gain-compression*0.32+brace*0.22,-flow.x*0.22+omega.y*0.12,-flow.x*0.28-motion.side_load*0.12+sx*compression*0.10),
			Vector3(0.85*compression+brace*0.28,0,0),Vector3(-compression*0.30-brace*0.15,-flow.x*0.12,0)]
		var hover_shift: float = sx*motion.trim.x*profile.hover_leg_motion*motion.hover
		var leg_intent: Vector3 = motion.steer
		var leg_gain: float = motion.hover*0.4+motion.fighter*0.6+motion.coast+motion.fall
		var steer: float = sx*(leg_intent.z*0.18+leg_intent.y*0.12)*profile.maneuver_leg_motion/0.22*leg_gain
		extras[0] += Vector3(steer+move.z*0.14,motion.yaw*(sx*0.06+motion.hover*0.10),move.x*0.10)
		extras[1].x -= move.z*0.14
		extras[1] += Vector3(-steer*0.65+motion.brake_rate*0.04,0,0)
		extras[1].x -= sx*motion.steer.z*lerpf(0.035,0.18,motion.brake)*motion.track
		extras[2] += Vector3(0,0,motion.roll_stop*0.06)
		extras[2].x += move.z*(0.36 if move.z<0 else 0.18)
		var targets: Array[Vector3] = []
		for joint in 3:
			var target: Vector3 = profile.leg_target(posture_weights,side,joint)+extras[joint]*articulation
			var ground_guard: float = motion.get("ground_guard",0.0)
			if joint==0: target.x -= 0.08*ground_guard
			elif joint==1: target.x += 0.32*ground_guard
			else: target.x -= 0.06*ground_guard
			var working: Vector3 = target.lerp(profile.drive_pose[joint]*Vector3(1,1,sx),motion.drive)
			working = working.lerp(profile.retro_pose[joint]*Vector3(1,1,sx),motion.retro)
			target = target.lerp(working,(1.0-motion.land)*(1.0-motion.launch)*(1.0-motion.hover))
			var falling: Vector3 = profile.fall_pose[joint]*Vector3(1,1,sx)+extras[joint]*articulation
			target = target.lerp(falling,motion.get("belly",motion.box)*(1.0-motion.brake))
			target = target.lerp(profile.back_fall_pose[joint]*Vector3(1,1,sx)+extras[joint]*articulation,motion.get("back",0.0)*(1.0-motion.brake))
			var braking: Vector3 = profile.spread_pose[joint]*Vector3(1,1,sx)
			var turn: Vector3 = motion.brake_turn
			if joint==0: braking += Vector3(turn.x*0.25+sx*turn.z*0.18,turn.y*0.22,sx*absf(turn.x)*0.12)
			if joint==1: braking.x += -turn.x*0.20+sx*(turn.z*0.32+turn.y*0.18)
			target = target.lerp(braking,motion.flare*(1.0-motion.land))
			var extension: Vector3 = profile.launch_pose[joint]*Vector3(1,1,sx)
			target = target.lerp(extension,motion.launch)
			target = target.lerp(profile.hover_pose[joint]*Vector3(1,1,sx),motion.get("ground_tuck",0.0))
			if joint==0: target.x += reverse_slide
			if joint==2: target.x -= reverse_slide
			var acro: Vector2 = motion.get("acro",Vector2.ZERO)
			var signs: Vector2 = motion.get("acro_sign",Vector2.ZERO)
			var flip: Vector3 = motion.get("flip_shape",Vector3.ZERO)
			var roll: Vector3 = motion.get("roll_shape",Vector3.ZERO)
			var lead: float = sx*motion.lead
			var front: float = maxf(-signs.x,0.0)
			var hip := -0.20-lead*0.32-front*0.12
			var knee := 0.35+lead*0.28+front*0.10
			var flip_target := Vector3.ZERO
			if joint==0: flip_target = Vector3(hip*flip.x-0.95*flip.y-0.12*flip.z,0,sx*0.14)
			elif joint==1: flip_target.x = knee*flip.x+1.40*flip.y+0.18*flip.z
			else: flip_target.x = -0.18*flip.x-0.28*flip.y+0.12*flip.z
			flip_target = flip_target.lerp(profile.layout_pose[joint]*Vector3(1,1,sx),motion.get("layout",0.0)*(1.0-flip.z))
			var roll_target: Vector3 = target
			if joint==0: roll_target += Vector3(-0.35*roll.y-sx*signs.y*0.24*(roll.x-roll.z),signs.y*0.12*roll.x,0)
			if joint==1: roll_target.x += 0.50*roll.y+sx*signs.y*0.22*(roll.x-roll.z)
			var pitch_weight: float = acro.x*lerpf(1.0,0.65,motion.brake)
			target = target*(1.0-pitch_weight-acro.y)+flip_target*pitch_weight+roll_target*acro.y
			targets.append(profile.limit_joint(target,side,joint))
		var gather: float = motion.gather[side]+motion.pitch*motion.fighter*0.12*(1.0-motion.land)*(1.0-motion.launch)
		var flexion: float = role*stagger+thrust_tuck+gather-hover_shift
		var lower: float = maxf(targets[0].x-profile.joint_max[0].x,profile.joint_min[1].x-targets[1].x)
		var upper: float = minf(targets[0].x-profile.joint_min[0].x,profile.joint_max[1].x-targets[1].x)
		flexion = clampf(flexion,lower,upper)
		targets[0].x -= flexion
		targets[1].x += flexion
		for joint in 3:
			var servo = legs[side*3+joint]
			var response: float = profile.slide_response if motion.move_intent.length()>0.1 else profile.leg_response[joint]
			servo.step(targets[joint],delta,lerpf(response+motion.hover*side*0.025+maxf(-role,0)*0.05,0.08,motion.launch),profile.joint_speed[joint])
			servo.value = profile.limit_joint(servo.value,side,joint)

func _articulated_gaze(frame, controller, basis: Basis, intent: Vector3, delta: float) -> Vector3:
	var direct: Vector3 = frame.gaze_direction
	if not direct.is_zero_approx():
		gaze_heading = direct.normalized()
		return gaze_heading
	var travel: Vector3 = frame.velocity
	var target := gaze_heading
	var nose: Vector3 = controller.body.actor.global_basis.z.normalized()
	if travel.length()>4.0: target = travel.normalized()
	var desired_force: Vector3 = frame.requested_main_force
	var turning: Vector3 = basis*Vector3(-intent.y,intent.x,0)
	if turning.length()>0.1: target = (nose+turning*0.65).normalized()
	elif desired_force.length()>1.0 and frame.translation_request.length()>0.13 and motion.get("retro",0.0)<0.35:
		target = (nose+desired_force.normalized()*0.55).normalized()
	if contacts.preparation>0.1 and not frame.grounded:
		for hit in contacts.hits:
			if not hit.is_empty():
				target = (hit.position-controller.body.global_position).normalized()
				break
	if target.is_zero_approx(): return Vector3.ZERO
	var weight := 1.0-exp(-delta/0.15)
	if gaze_heading.is_zero_approx(): gaze_heading = target
	elif gaze_heading.dot(target)<-0.999:
		var axis := basis.z if absf(gaze_heading.dot(basis.z))<0.9 else basis.y
		gaze_heading = gaze_heading.rotated(axis,PI*weight).normalized()
	else: gaze_heading = gaze_heading.slerp(target,weight).normalized()
	return gaze_heading

func _sample_articulation(frame, delta: float) -> void:
	var reported_force: Vector3 = frame.main_force
	var demand_force: Vector3 = frame.requested_main_force
	var residual: Vector3 = frame.control_torque-frame.main_torque-frame.rcs_torque-frame.aero_torque
	var weight: float = frame.body_mass*frame.gravity
	var torque_reference: float = maxf(frame.torque_limits.length(),weight)
	var demand: Vector3 = frame.rotation_request
	var change := (demand-previous_intent).length()
	previous_intent = demand
	var net_load := smoothstep(0.7,3.5,frame.g_load)
	var effort_load: float = maxf(net_load*0.55,frame.delivered_thrust/(weight*4.0))
	var steady := clampf(maxf(motion.pressure*0.55,effort_load)+motion.redirect*0.22,0,1)
	var transient := clampf(maxf(change,residual.length()/torque_reference)+frame.angular_acceleration.length()*0.025,0,1)
	transient = maxf(transient,clampf((demand_force-reported_force).length()/(weight*3.0),0,1)*0.7)
	stress.x = lerpf(stress.x,steady,1.0-exp(-delta/0.28))
	stress.y = maxf(transient,stress.y*exp(-delta/0.34))
	var intensity := clampf(stress.x*0.55+stress.y*0.65,0,1)
	var rates: Vector3 = motion.target_rates-motion.pilot_rates
	var direction: Vector3 = motion.steer*0.65+rates*0.35
	direction += frame.pilot_frame.inverse()*residual/torque_reference*0.4
	var translation: Vector3 = motion.reach
	direction += Vector3(translation.z,translation.x,0)*0.6
	stroke_age += delta/maxf(stroke_duration,0.01)
	var interrupted := stroke_age>0.55 and change>0.45 and transient>0.65
	if (stroke_age>=1.0 or interrupted) and intensity>0.22 and direction.length()>0.14:
		stroke_age = 0.0
		stroke_duration = lerpf(0.87,0.38,intensity)
		stroke_direction = direction.limit_length(1.0)
		gesture_count += 1
	var envelope := smoothstep(0.0,0.23,stroke_age)*(1.0-smoothstep(0.48,1.0,stroke_age))
	var stroke := stroke_direction*envelope*intensity
	var sides := Vector2.ZERO
	for i in frame.motor_forces.size():
		var force: Vector3 = frame.motor_forces[i]
		var side: int = i%2 if i<6 else int(i>=8)
		sides[side] += force.length()
	var differential := (sides.x-sides.y)/maxf(sides.x+sides.y,1.0)
	motion.merge({"authored":true,"stress":intensity,"stroke":stroke,
		"stroke_direction":stroke_direction,"stroke_phase":stroke_age,"differential":differential,
		"hand_time":frame.clock,"impact":contacts.impact},true)

func _update_authored_legs(delta: float, frame, controller) -> void:
	var power: float = maxf(frame.thrust_level,float(frame.detent>0))
	var steer: Vector3 = motion.steer
	var intent: Vector3 = frame.pilot_rotation_intent
	if intent.is_zero_approx(): intent = frame.rotation_request
	for axis in 3:
		if absf(intent[axis])>0.10: steer[axis] = intent[axis]
	var move: Vector3 = motion.reach*Vector3(-1,1,-1)
	var lateral_balance: float = smoothstep(0.25,0.9,absf(motion.side_load))*(1.0-absf(steer.z))*0.55
	var bracing: float = maxf(motion.retro,maxf(motion.flare*0.85,maxf(lateral_balance,motion.get("arrest",0.0)*0.70)))
	var yaw_arrest: float = smoothstep(0.05,0.45,absf(motion.pilot_rates.y))*float(intent.y*motion.pilot_rates.y<0.0)
	bracing = maxf(bracing,yaw_arrest*0.55)
	var hover_weight := clampf(motion.hover*(1.0-motion.track)*0.88,0.0,0.88)
	var target := Articulation.select(steer,move,power,bracing,hover_weight)
	var land: float = motion.land
	var takeoff: float = motion.launch
	var acro: Vector2 = motion.acro
	var flip: Vector3 = motion.flip_shape
	var roll: Vector3 = motion.roll_shape
	var throttle_load: float = smoothstep(0.1,0.8,frame.thrust_level)
	var powered_pull: float = smoothstep(0.25,0.85,steer.x)*throttle_load*(1.0-motion.hover)*(1.0-bracing)
	var trim_allowed: bool = frame.hover_assist>0.5 and power>0.04 and land<0.1 and takeoff<0.1 and bracing<0.7
	if trim_allowed:
		trim_clock -= delta
		if trim_clock<=0.0:
			primary_trim = controller.body.calibrate_primary_pose(target,primary_trim,trim_axis)
			trim_axis = (trim_axis+1)%3
			trim_clock = 0.10
		target = controller.body.apply_primary_trim(target,primary_trim)
	else:
		primary_trim = Vector3.ZERO
		trim_clock = 0.0
	var stroke: Vector3 = motion.stroke
	var alternative := target.duplicate()
	for side in 2:
		var sx := 1.0 if side==0 else -1.0
		var mirror := Vector3(1,1,sx)
		var exposed: float = (1.0-land)*(1.0-takeoff)*(1.0-maxf(sx*motion.differential,0.0)*0.6)
		var gesture := (stroke.y+0.55*stroke.z)*sx*exposed*0.18
		for joint in 3:
			var index := side*3+joint
			var aim := target[index]
			if joint==2: aim.x -= 0.52*powered_pull
			aim = aim.lerp(Articulation.BELLY_LEGS[joint]*mirror,motion.belly*(1.0-bracing))
			aim = aim.lerp(Articulation.BACK_LEGS[joint]*mirror,motion.back*(1.0-bracing))
			var tuck: Vector3 = profile.fall_pose[joint]*mirror
			tuck = tuck.lerp(profile.layout_pose[joint]*mirror,motion.layout)
			aim = aim.lerp(tuck,(acro.x*flip.y+acro.y*roll.y)*(1.0-throttle_load*0.45)*(1.0-bracing))
			aim = aim.lerp(profile.launch_pose[joint]*mirror,takeoff)
			aim = aim.lerp(profile.landing_pose[joint]*mirror,land)
			target[index] = aim
			if joint==0: aim.x -= gesture
			if joint==1: aim.x += gesture
			if joint==2: aim += Vector3(stroke.x*0.055,0,stroke.z*sx*0.035)*exposed
			alternative[index] = aim
	if motion.stroke_phase>0.23 and motion.stroke_phase<0.65 and tested_gesture!=gesture_count:
		tested_gesture = gesture_count
		leg_stroke_available = controller.body.leg_gesture_feasible(target,alternative) if power>0.04 else true
	var can_correct := power<=0.04 or (tested_gesture==gesture_count and leg_stroke_available)
	for index in legs.size():
		var servo = legs[index]
		var aim := alternative[index] if can_correct else target[index]
		servo.step(profile.limit_joint(aim,index/3,index%3),delta,profile.leg_response[index%3],profile.joint_speed[index%3])
		servo.value = profile.limit_joint(servo.value,index/3,index%3)

func _rotate(bone: String, angles: Vector3) -> void:
	var sk := get_skeleton()
	var index: int = bones[bone]
	var rest := sk.get_bone_global_rest(index).basis.orthonormalized()
	var offset := rest.inverse()*Basis.from_euler(angles)*rest
	var base := sk.get_bone_rest(index).basis.get_rotation_quaternion() if motion.get("authored",false) else sk.get_bone_pose_rotation(index)
	sk.set_bone_pose_rotation(index,(base*offset.get_rotation_quaternion()).normalized())

func _process_modification() -> void:
	if ground_animation_active:
		var ground_run: float = motion.get("ground_run",0.0)
		var ground_guard: float = motion.get("ground_guard",0.0)
		_apply_ground_animation_pose(ground_run,ground_guard)
		if ground_run>0.0 or ground_guard>0.0:
			arms.apply(get_skeleton(),_rotate)
		contacts.prepare_targets()
		return
	var pelvis_offset: Vector3 = motion.get("mechanical_pelvis",Vector3.ZERO)
	var torso_offset: Vector3 = motion.get("mechanical_torso",Vector3.ZERO)
	var difference := (chest.value+torso_offset-hips.value-pelvis_offset).clamp(
		Vector3(-0.55,-0.35,-0.55),Vector3(0.55,0.35,0.55))
	for part in profile.torso_bones.size():
		_rotate(profile.torso_bones[part],difference*Vector3(1,1,-1)*profile.torso_weights[part])
	var head_target: Vector3 = profile.limit_head(head.value+motion.get("mechanical_head",Vector3.ZERO))
	_rotate("Neck",head_target)
	var structural_legs: PackedVector3Array = motion.get("mechanical_legs",PackedVector3Array())
	for side in 2:
		for joint in 3:
			var index := side*3+joint
			var target: Vector3 = legs[index].value
			if structural_legs.size()==6: target += structural_legs[index]
			target = profile.limit_joint(target,side,joint)
			var bone: String = [profile.thigh_bones[side],profile.knee_bones[side],profile.foot_bones[side]][joint]
			_rotate(bone,target)
	arms.apply(get_skeleton(),_rotate)
	_apply_ground_torso_lean(0.12*float(motion.get("ground_guard",0.0)))
	contacts.prepare_targets()

func _apply_ground_animation_pose(run_weight: float, guard_weight: float) -> void:
	if run_weight>0.0:
		_apply_ground_torso_lean(0.34*run_weight)
		for side in 2:
			_rotate(profile.thigh_bones[side],Vector3(-0.10*run_weight,0,0))
			_rotate(profile.knee_bones[side],Vector3(0.16*run_weight,0,0))
	if guard_weight>0.0:
		_apply_ground_torso_lean(0.12*guard_weight)
		for side in 2:
			_rotate(profile.thigh_bones[side],Vector3(-0.08*guard_weight,0,0))
			_rotate(profile.knee_bones[side],Vector3(0.32*guard_weight,0,0))


func _apply_ground_torso_lean(angle: float) -> void:
	if angle<=0.0: return
	for part in profile.torso_bones.size():
		_rotate(profile.torso_bones[part],Vector3(angle*profile.torso_weights[part],0,0))
