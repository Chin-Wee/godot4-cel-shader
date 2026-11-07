extends SceneTree

const Ground = preload("res://ground/ground_demo.tscn")
const Motion = preload("res://ground/ground_motion.gd")
const U := Motion.U
var scene
var mech
var motion
var failures := PackedStringArray()
var capture := false
var output := ""
var frames := 0
var max_plant_error := 0.0
var max_heading_error := 0.0
var max_tilt := 0.0
var samples := 0
var observe_plants := true
var camera_previous := Vector2.ZERO
var camera_has_sample := false
var max_camera_motion := 0.0
var camera_position := Vector3.ZERO
var max_camera_step := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures: failures.append(message)

func _sample() -> void:
	_check(motion.supported or (motion.traction[0].is_zero_approx() and motion.traction[1].is_zero_approx()),"Airborne traction")
	var loaded: int = int(motion.loaded[0])+int(motion.loaded[1])
	var mu := Motion.SKID if motion.slip>0.0 else Motion.GRIP
	for force in motion.traction:
		_check(force.length()<=motion.load_budget*mu/maxi(1,loaded)+1.0,"Traction exceeds support budget")
	var fc = mech.controller
	for index in fc.motor_forces.size():
		_check(fc.motor_forces[index].length()<=fc.hot_max_thrust(index)+1.0,"Hot outlet exceeds rating")
	# Sample the same speed used by the solver and allow for the intervening
	# native gravity/contact update before the next physics_frame signal.
	var speed: float = maxf(motion.velocity.length(),fc.velocity.length())
	var fraction := lerpf(0.15,1.0,clampf(speed/40.0,0,1))
	for index in fc.cold_forces.size():
		_check(fc.cold_forces[index].length()<=fc.cold_max_thrust(index)*fraction+1.0,"Cold outlet exceeds speed cap")
	max_tilt = maxf(max_tilt,rad_to_deg(acos(clampf(mech.global_basis.y.y,-1,1))))
	if not observe_plants or not motion.supported or motion.slip>0.0 or motion.pivot_steps>0 or motion.catch_time>0.0: return
	var scale_factor: float = mech.skeleton.global_basis.get_scale().x
	for side in 2:
		if not motion.loaded[side] or mech.rig.contacts.weights[side].value.x<0.98: continue
		var bone: int = mech.skeleton.find_bone(mech.rig.profile.foot_bones[side])
		var pose: Transform3D = mech.skeleton.global_transform*mech.bone_poses[bone]
		var offset: float = Motion.TOE if motion.rock[side]<0 else Motion.HEEL if motion.rock[side]>0 else 0.0
		var anchor: Vector3 = pose*(mech.rig.profile.sole_offset+Vector3(0,offset/scale_factor,0))
		max_plant_error = maxf(max_plant_error,anchor.distance_to(motion.sole_anchor(side))/U)
		var forward: Vector3 = pose.basis.y.slide(motion.foot_normals[side]).normalized()
		max_heading_error = maxf(max_heading_error,rad_to_deg(forward.angle_to(motion.foot_headings[side])))
		samples += 1

func _step(input: Dictionary = {}) -> void:
	mech.controls = input
	await physics_frame
	frames += 1
	_sample()

func _ticks(count: int, input: Dictionary = {}) -> void:
	for tick in count: await _step(input)

func _sample_camera() -> void:
	if paused or frames<30 or not scene.camera.current: return
	var rendered: Vector3 = mech.get_global_transform_interpolated().origin
	var point: Vector2 = scene.camera.unproject_position(rendered)/Vector2(root.size)
	_check(Rect2(0.08,0.08,0.84,0.84).has_point(point),"Mech escaped the chase frame")
	if camera_has_sample:
		max_camera_motion = maxf(max_camera_motion,point.distance_to(camera_previous))
		max_camera_step = maxf(max_camera_step,scene.camera.global_position.distance_to(camera_position)/U)
	camera_position = scene.camera.global_position
	camera_previous = point
	camera_has_sample = true

func _shot(name: String) -> void:
	if not capture: return
	# Freeze the replay clock for both exposures and viewpoints.
	paused = true
	scene.label.hide()
	for light in [true,false]:
		scene.set_daylight(light)
		for camera in [scene.camera,scene.witness]:
			camera.make_current()
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var palette := "day" if light else "dusk"
			_check(image.save_png(output.path_join("%s-%s-%s.png"%[name,palette,camera.name]))==OK,"Capture save failed")
	scene.camera.make_current()
	paused = false
	camera_has_sample = false

func _reset(position: Vector3, speed := Vector3.ZERO) -> void:
	await process_frame
	scene.reset_trial(position,Quaternion.IDENTITY,speed)
	motion = scene.motion
	camera_has_sample = false

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): push_error("Ground replay timed out"); quit(1))
	var args := OS.get_cmdline_user_args()
	output = "/tmp/ground-v1-captures" if args.is_empty() else args[0]
	var visual := DisplayServer.get_name()!="headless" and "--metrics-only" not in args
	var witness_only := "--witness" in args
	capture = visual and not witness_only and "--chase" not in args
	if visual:
		root.size = Vector2i(1120,720)
		DirAccess.make_dir_recursive_absolute(output)
		observe_plants = false # Completed bones are sampled on the render clock.
	scene = Ground.instantiate()
	scene.player_controlled = false
	root.add_child(scene)
	mech = scene.mech
	motion = scene.motion
	if visual:
		scene.label.hide()
		scene.set_daylight("--day" in args)
		if witness_only: scene.witness.make_current()
		else: RenderingServer.frame_pre_draw.connect(_sample_camera)
	await _ticks(90)
	_check(motion.supported and mech.controller.velocity.length()<=0.10,"Unstable initial stance")
	var toe := false
	var heel := false
	var start: Vector3 = mech.position
	for tick in 96:
		await _step({"move":Vector2(0,1)} if tick<55 else {})
		if not toe and motion.loaded[motion.swing] and motion.rock[motion.swing]<-0.15:
			toe = true
			await _shot("01-toe-off")
		if not heel and motion.steps==1:
			heel = true
			await _shot("02-heel-catch")
	_check(motion.steps==2 and toe and heel and (start.z-mech.position.z)/U>1.0,"Forward stride sequence failed")
	await _ticks(110)
	_check(mech.controller.velocity.length()<=0.10,"Walk release did not settle")
	var before: Vector3 = motion.heading
	await _ticks(340,{"turn":1})
	var yaw := rad_to_deg(before.signed_angle_to(motion.heading,Vector3.UP))
	_check(motion.pivots==1 and motion.steps==4 and absf(yaw-90.0)<=5.0,"Pivot did not complete two steps within 5 degrees")
	await _shot("03-pivot")
	var launch_origin: Vector3 = mech.position
	var highest := launch_origin.y
	var traveled := 0.0
	var had_air := false
	var catch := false
	var catch_shot := false
	var slid := false
	var apex_shot := false
	var ignition_shot := false
	var touched: int = motion.touchdowns
	await _step({"hop":true,"move":Vector2.RIGHT})
	for tick in 215:
		await _step({"hop":true})
		highest = maxf(highest,mech.position.y)
		if not motion.supported and motion.launches==1:
			had_air = true
			if not ignition_shot and mech.controller.motor_forces.any(func(force: Vector3): return force.length()>20000.0):
				ignition_shot = true
				await _shot("03b-ignition")
			if not apex_shot and motion.velocity.y<0.0:
				apex_shot = true
				await _shot("04-hop-apex")
		if motion.touchdowns>touched and not catch:
			traveled = (mech.position-launch_origin).slide(Vector3.UP).length()/U
			catch = motion.loaded[0] and not motion.loaded[1]
		if catch and not catch_shot and motion.catch_time<0.07:
			catch_shot = true
			await _shot("05-landing")
		if not slid and motion.slip>1.0 and motion.catch_time<=0.0:
			slid = true
			await _shot("06-skid")
	var rise := (highest-launch_origin.y)/U
	_check(motion.launches==1 and had_air and catch and slid and motion.cushions==1,"Hop, cushion, one-foot catch or skid missing")
	_check(rise>=0.8 and rise<=1.6 and traveled>=3.0 and traveled<=6.0,"Hop outside height or travel target")
	await _ticks(36,{"guard":true})
	await _shot("07-guard")
	_check(motion.guard and motion.supported and mech.controller.velocity.length()<=0.10,"Guard did not settle")
	_check(max_tilt<8.0,"Chassis tipped during flat replay")
	if observe_plants:
		_check(samples>40 and max_plant_error<=0.10 and max_heading_error<=3.0,"Planted boot drift exceeds limit")
	print("Ground replay: %d ticks, yaw %.2f°, hop %.2f m high / %.2f m travel, tilt %.2f°, plant %.3f m / %.2f° (%d samples)"%
		[frames,yaw,rise,traveled,max_tilt,max_plant_error,max_heading_error,samples])

	if visual and not witness_only:
		_check(max_camera_motion<0.045,"Chase framing jumped between rendered frames")
		_check(max_camera_step<0.50,"Chase position jumped between rendered frames")
		print("Peak chase frame movement: %.2f%%, camera travel %.3f m/frame" % [max_camera_motion*100.0,max_camera_step])
	if not visual:
		observe_plants = false
		await _reset(Vector3(0,5.50,-12.4))
		await _ticks(130)
		_check(motion.supported and motion.support_normal.y>0.98 and motion.support_normal.y<0.999,"8° ramp lost support")
		var ramp_origin: Vector3 = mech.position
		await _ticks(70,{"move":Vector2(0,1)})
		_check(mech.position.z<ramp_origin.z-0.4*U and mech.position.y>ramp_origin.y,"Ramp traversal failed")
		await _reset(Vector3(7.0,4.49,7))
		await _ticks(40)
		await _ticks(160,{"move":Vector2.RIGHT})
		_check(mech.position.x/U<=8.05 and motion.step_time<0.0,"Blocked stride kept driving into a wall")
		scene.camera.yaw = PI/2
		scene.camera.update_view(0.0)
		_check(scene.camera.wall_fraction<0.5,"Chase camera did not pull inside the wall")
		await _reset(Vector3(0,6.6,9),Vector3(0,-5.5,0))
		for valve in mech.controller.hot_valves: valve.restart_remaining = 1.0
		var recovering := false
		var tried_hop := false
		for tick in 100:
			var tap: bool = not tried_hop and motion.recovery>0.38 and motion.recovery<0.42
			tried_hop = tried_hop or tap
			await _step({"hop":tap})
			if motion.touchdowns>0 and motion.recovery>0.42: recovering = true
		print("Hard landing: sink %.2f, misses %d, recovering %s, launches %d" % [motion.last_sink,motion.missed_cushions,recovering,motion.launches])
		_check(motion.missed_cushions==1 and recovering and tried_hop and motion.launches==0,"Failed cushion or hard landing gate failed")

	if not failures.is_empty():
		for message in failures: push_error(message)
		quit(1)
		return
	print("Ground movement checks passed.")
	quit()
