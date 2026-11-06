extends SceneTree

# Read the completed native skeleton. Optional captures show the exact same
# output under neutral light, with no AnimationPlayer studies or target proxies.
var mech
var viewport: SubViewport
var camera: Camera3D
var output := ""

func _initialize() -> void: call_deferred("_run")

func _pose(name: String, controls := Vector3.ZERO) -> Dictionary:
	mech.reset_flight(Vector3.ZERO)
	var fc = mech.controller
	fc.detent = 0
	fc.engine_level = 0
	fc.thrust_level = 0
	fc.main_force = Vector3.ZERO
	fc.aero_force = Vector3.ZERO
	fc.requested_main_force = Vector3.ZERO
	fc.hover_assist = 0
	fc.brake_amount = 0
	fc.aero_authority = 0
	fc.air_density = 1.225
	fc.local_acceleration = Vector3.ZERO
	fc.angular_acceleration = Vector3.ZERO
	fc.local_airflow = Vector3.ZERO
	fc.rotation_command = controls
	fc.rotation_request = controls
	fc.effective_rates = controls*fc.MAX_RATE
	fc.g_load = 0
	if name=="hover" or name.begins_with("turn"):
		fc.engine_level = 1
		fc.thrust_level = 1
		fc.detent = 2
		fc.hover_assist = 1
		fc.g_load = 1
		fc.main_force = Vector3.UP*mech.mass*9.81
	if name.begins_with("fall"):
		mech.quaternion = Quaternion(Vector3.RIGHT,-PI/2) # Actual belly-to-earth orientation.
		mech.linear_velocity = Vector3.DOWN*600
		fc.local_airflow = Vector3(0,0,60)
	if name=="flare" or name=="drive" or name=="stream":
		fc.engine_level = 2
		fc.thrust_level = 2
		fc.detent = 3
		fc.main_force = Vector3.UP*mech.mass*9.81*2
		mech.linear_velocity = Vector3.UP*600
		fc.local_airflow = Vector3(0,-60,0)
		fc.aero_authority = 1
		fc.g_load = 2
	if name=="flare":
		fc.brake_amount = 1
		fc.local_acceleration = Vector3(0,-18,0)
	if name=="drive": fc.local_acceleration = Vector3(0,20,0)
	# Sustained rotation, not merely a short start pulse.
	mech.angular_velocity = fc.pilot_frame()*(controls*fc.MAX_RATE)
	for tick in 150:
		fc.clock += 1.0/60
		mech.update_animation(1.0/60)
		await process_frame
	var result := {"hands":Array(mech.rig.arms.hands),"elbows":Array(mech.rig.arms.elbow_positions),"shoulders":Array(mech.rig.arms.shoulders),"knees":[],"feet":[]}
	var ti: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Torso")].affine_inverse()
	for side in 2: result.knees.append(ti*mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.knee_bones[side])].origin)
	for side in 2: result.feet.append(ti*mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.foot_bones[side])].origin)
	result["flex"] = []
	for side in 2:
		var hip: Vector3 = mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.thigh_bones[side])].origin
		var knee: Vector3 = mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.knee_bones[side])].origin
		var foot: Vector3 = mech.bone_poses[mech.skeleton.find_bone(mech.rig.profile.foot_bones[side])].origin
		result.flex.append((knee-hip).angle_to(foot-knee))
	print(name," ",result)
	if not output.is_empty():
		for view in 3:
			camera.position = [Vector3(-160,35,-170),Vector3(0,15,-220),Vector3(-220,15,0)][view]
			camera.look_at(Vector3.ZERO)
			camera.force_update_transform()
			await process_frame
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			RenderingServer.force_sync()
			RenderingServer.force_draw(false)
			var image := viewport.get_texture().get_image()
			var low := 1.0
			var high := 0.0
			for y in range(0,image.get_height(),12):
				for x in range(0,image.get_width(),12):
					var value := image.get_pixel(x,y).get_luminance()
					low = minf(low,value)
					high = maxf(high,value)
			assert(high-low>0.2,"Capture omitted the rendered mech")
			assert(image.save_png(output.path_join(name+"-"+str(view)+".png"))==OK)
	return result

func _run() -> void:
	create_timer(60).timeout.connect(func():
		push_error("Applied air pose checks did not finish")
		quit(1))
	if DisplayServer.get_name()!="headless" and not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		assert(DirAccess.make_dir_recursive_absolute(output)==OK)
		root.mode = Window.MODE_MINIMIZED
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	mech = load("res://aerial/aerial_mech.gd").new()
	viewport.add_child(mech)
	var surface := ShaderMaterial.new()
	surface.shader = load("res://shaders/aerial/aircraft.gdshader")
	var exhaust := ShaderMaterial.new()
	exhaust.shader = load("res://shaders/aerial/afterburner.gdshader")
	mech.build(surface,exhaust)
	mech.freeze = true
	for flame in mech.flames+mech.gas_jets: flame.hide()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.06,0.08,0.10)
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 0.8
	viewport.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 125
	camera.far = 2000
	camera.current = true
	viewport.add_child(camera)
	var hover: Dictionary = await _pose("hover")
	for side in 2:
		assert(absf(hover.elbows[side].x)-absf(hover.shoulders[side].x)>0.45,"Elbow is tucked against the ribs")
		assert(hover.elbows[side].z>hover.shoulders[side].z-0.45,"Elbow folds behind the torso")
	for tick in 120:
		mech.controller.clock += 1.0/60
		mech.update_animation(1.0/60)
		await process_frame
		for side in 2: assert(mech.rig.arms.hands[side].distance_to(hover.hands[side])<0.01,"Stable hover swims without control effort")
	var fall: Dictionary = await _pose("fall")
	for side in 2:
		var shoulder: Vector3 = fall.shoulders[side]
		var elbow: Vector3 = fall.elbows[side]
		var hand: Vector3 = fall.hands[side]
		assert(elbow.y<shoulder.y-0.5 and elbow.z>shoulder.z,"Freefall upper arm is raised or swept behind the shoulders")
		assert(hand.y>elbow.y+1.5 and hand.y<shoulder.y+1.8 and hand.z>1.5,"Freefall forearm does not bend toward the head and into the wind")
		assert((elbow-shoulder).angle_to(hand-elbow)>1.0,"Freefall elbow is straight")
		assert(fall.feet[side].z<fall.knees[side].z-2.0,"Freefall calves do not fold behind the body")
	var flare: Dictionary = await _pose("flare")
	for side in 2: assert(absf(flare.hands[side].x)>5 and flare.flex[side]>0.8,"Flare lacks displayed hand spread and squat")
	assert(flare.knees[0].distance_to(flare.knees[1]*Vector3(-1,1,1))>0.3,"Flare squat has no visible knee stagger")
	assert(absf(flare.flex[0]-flare.flex[1])>0.15,"Flare knees bend identically")
	var drive: Dictionary = await _pose("drive")
	for side in 2: assert(drive.hands[side].z< -0.8,"Acceleration never sweeps the hands aft")
	var stream: Dictionary = await _pose("stream")
	assert(stream.flex[0]<drive.flex[0]-0.1,"Acceleration squat never lengthens toward cruise")
	var left: Dictionary = await _pose("turn_yaw_left",Vector3(0,1,0))
	var right: Dictionary = await _pose("turn_yaw_right",Vector3(0,-1,0))
	var yaw_left: float = left.hands[0].z-left.hands[1].z
	var yaw_right: float = right.hands[0].z-right.hands[1].z
	assert(absf(yaw_left)>1 and absf(yaw_right)>1 and yaw_left*yaw_right<0,"Held yaw has no opposing hand movement")
	assert(absf(left.flex[0]-left.flex[1])>0.08 and absf(right.flex[0]-right.flex[1])>0.08,"Held yaw knees bend identically")
	for command in [Vector3(0,0,1),Vector3(0,0,-1)]:
		var roll: Dictionary = await _pose("turn_roll_left" if command.z>0 else "turn_roll_right",command)
		assert(roll.hands[0].distance_to(roll.hands[1]*Vector3(-1,1,1))>0.8,"Held roll hands remain mirrored")
		assert(roll.knees[0].distance_to(roll.knees[1]*Vector3(-1,1,1))>0.25,"Held roll legs remain mirrored")
		assert(absf(roll.flex[0]-roll.flex[1])>0.08,"Held roll knees bend identically")
	var falling_turn: Dictionary = await _pose("fall_yaw",Vector3(0,1,0))
	assert(falling_turn.hands[0].distance_to(falling_turn.hands[1]*Vector3(-1,1,1))>1)
	assert(falling_turn.knees[0].distance_to(falling_turn.knees[1]*Vector3(-1,1,1))>0.5,"Freefall overwrote its directional legs")
	assert(absf(falling_turn.flex[0]-falling_turn.flex[1])>0.08,"Freefall turn knees bend identically")
	var modifiers: Array = mech.skeleton.get_children().filter(func(n): return n is SkeletonModifier3D)
	assert(modifiers.size()==4 and not mech.rig.contacts.solvers[0].active and not mech.rig.contacts.solvers[1].active,"Unexpected airborne post-processing pass")
	print("Applied air pose checks passed: natural elbows, held yaw/roll limb asymmetry, freefall box, squat/hand flare, aft acceleration and settled cruise; one airborne pose author.")
	viewport.queue_free()
	await process_frame
	quit()
