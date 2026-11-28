extends SceneTree

const Fixture = preload("res://aerial/articulation_fixture.gd")
const Poses = preload("res://aerial/poses/articulation_poses.gd")
const Lab = preload("res://aerial/flight_articulation_lab.tscn")
const GIMBAL_REFERENCE_CONE := PI/6.0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var lab := Lab.instantiate()
	root.add_child(lab)
	lab.set_physics_process(false)
	lab.set_process(false)
	var fixture: Fixture = lab.fixture
	assert(Fixture.MAIN_MOUNT_ORDER==[0,2,4,1,3,5],"Fixture must use left/right groups of the six live main hardpoints")
	assert(Poses.AUTHORED.size()==15 and Poses.MIRRORED.size()==5)
	for pair in Poses.MIRRORED:
		var left := Poses.angles(Poses.MIRRORED[pair])
		var right := Poses.angles(pair)
		for i in 3: assert(right[i].is_equal_approx(left[3+i]*Poses.REFLECT))
	for name in Poses.AUTHORED.keys()+Poses.MIRRORED.keys():
		for i in 5:
			fixture.key = name
			fixture.intensity = i/4.0
			fixture.set_pose(fixture.targets())
			assert(fixture.ports.size()==6)
			for port in fixture.ports:
				assert(port.basis.is_finite() and absf(port.basis.z.length()-1.0)<0.0001)
			for joint in fixture.joints.size():
				assert(fixture.joints[joint].value.is_equal_approx(Fixture.Profile.limit_joint(fixture.joints[joint].value,joint/3,joint%3)))
	_authority(fixture)
	assert(await _check_dynamics(fixture))
	print("Articulation lab checks passed. 20 targets, 100 sampled blends, six fixed-axis outlets.")
	quit()

func _authority(f: Fixture) -> void:
	var weight := Fixture.WEIGHT
	var pilot := Fixture.Flight.PILOT_AXES
	f.intensity = 1.0
	print("pose | fixed force error kN / moment error kNm | 30-degree cone force / moment | fixed F xyz | fixed pilot M xyz")
	for name: String in Poses.AUTHORED.keys()+Poses.MIRRORED.keys():
		f.key = name
		f.power = 0.0 if name=="Unpowered_Coast" else 1.0
		f.steer = Vector3.ZERO
		f.move = Vector3.ZERO
		if name.begins_with("Pitch"): f.steer.x = 1.0 if "_Up_" in name else -1.0
		if name.begins_with("Yaw"): f.steer.y = 1.0 if "_Left_" in name else -1.0
		if name.begins_with("Roll"): f.steer.z = 1.0 if "_Left_" in name else -1.0
		if name.ends_with("_Soft"): f.steer *= 0.5
		match name:
			"Forward_Boost": f.move.z = 0.5
			"Backward_Boost", "Retrograde_Brake": f.move.z = -0.5
			"Lateral_Boost_Left": f.move.x = -0.5
			"Lateral_Boost_Right": f.move.x = 0.5
			"Vertical_Ascent": f.power = 2.0
		f.tick(1.0/60,true)
		var fixed := f.wrench_plan(f.ports,f.requested_force,f.requested_moment)
		var gimballed := f.wrench_plan(f.ports,f.requested_force,f.requested_moment,GIMBAL_REFERENCE_CONE)
		for i in fixed.size():
			assert(fixed[i].length()<=f.ports[i].cap+0.00001)
			assert(fixed[i].cross(-f.ports[i].basis.z).length()<0.00001,"Nozzle independently steered")
		var wrench := f.measure(fixed,f.ports)
		var baseline := f.measure(gimballed,f.ports)
		print("%s | %.1f / %.1f | %.1f / %.1f | %s | %s"%[name,
			wrench[0].distance_to(f.requested_force)/1000,wrench[1].distance_to(f.requested_moment)/1000,
			baseline[0].distance_to(f.requested_force)/1000,baseline[1].distance_to(f.requested_moment)/1000,
			str(wrench[0]/1000).replace(".000000",""),str(pilot.inverse()*wrench[1]/1000)])
		if not f.steer.is_zero_approx():
			var axis := f.steer.abs().max_axis_index()
			var arm := pilot[axis]*signf(f.steer[axis])
			assert(wrench[1].dot(arm)>1000.0,"Wrong signed moment for "+name)
		if name=="Neutral_Flight":
			assert(wrench[0].distance_to(Vector3.UP*weight)<2000.0 and wrench[1].length()<6000.0)
		if name=="Roll_Left_Hard":
			var ceiling := 0.0
			for port in f.ports:
				ceiling += maxf(0.0,port.lever.cross(-port.basis.z).dot(pilot.z))*port.cap*weight*Fixture.LENGTH
			print("Hard-left-roll absolute moment ceiling (kN m), before requiring support: %.1f"%(ceiling/1000.0))
		if name=="Unpowered_Coast": assert(wrench[0].is_zero_approx() and wrench[1].is_zero_approx())

func _check_dynamics(f: Fixture) -> bool:
	f.reset_lab()
	f.key = "Pilot_Blend"
	f.intensity = 1
	f.power = 1.0
	f.move = Vector3(0.4,0,0.4)
	f.steer = Vector3(0.2,0.5,0.1)
	var previous: Array[Vector3] = []
	for joint in f.joints: previous.append(joint.value)
	for i in 128:
		if i==50: f.move *= -1
		if i==60: f.steer *= -1
		if i==80: f.power = 0
		f.tick(1.0/60)
		for joint in f.joints.size():
			var angle: Vector3 = f.joints[joint].value
			assert(previous[joint].distance_to(angle)<=Fixture.Profile.joint_speed[joint%3]/60.0+0.0001)
			previous[joint] = angle
		if i==0: assert(f.force.is_zero_approx(),"Valves bypassed ignition")
		if i==79: assert(f.force.length()>1000,"Fixture failed to ignite")
		if i==80: assert(f.force.length()>0.0,"Cutoff skipped the valve tail")
	assert(f.force.length()<0.01,"Engines fail to shut down")
	f.power = 1
	for i in 60:
		f.tick(1.0/60)
		if i==0: assert(f.force.is_zero_approx(),"Relight skipped ignition")
	assert(f.force.length()>1000.0,"Fixture failed to relight")
	f.power = 1
	f.side_power = Vector2(0.4,0.9)
	f.key = "Neutral_Flight"
	f.steer = Vector3.ZERO
	f.move = Vector3.ZERO
	f.reset_lab()
	for i in 60: f.tick(1.0/60)
	assert(f.side_output.x<=3*65000*0.4+0.5 and f.side_output.y<=3*65000*0.9+0.5)
	var upright_force := f.force
	f.basis = Basis(Vector3.FORWARD,PI)
	for i in 60: f.tick(1.0/60)
	assert(f.force.distance_to(upright_force)<100.0 and (f.basis*f.force).y<0,"Inversion changed fixed local geometry")
	# First run the real native fall in vacuum with the six engines closed.
	f.power = 0
	f.reset_lab()
	f.freeze = false
	await physics_frame
	var initial_velocity := f.linear_velocity
	for i in 30: await physics_frame
	assert(absf((f.linear_velocity.y-initial_velocity.y)/Fixture.UNITS+Fixture.Flight.GRAVITY/2)<0.4)
	assert(absf(f.linear_velocity.x)<0.001 and absf(f.linear_velocity.z)<0.001 and f.angular_velocity.is_zero_approx())
	# Then apply an intentionally unbalanced fixed-axis wrench to the actual body.
	f.freeze = true
	f.power = 1.0
	f.side_power = Vector2(0.16,1)
	f.steer.y = 0.55
	f.reset_lab()
	for i in 60: f.tick(1.0/60)
	var moment := f.moment
	f.freeze = false
	await physics_frame
	for i in 6: await physics_frame
	assert(f.angular_velocity.dot(moment)>0.01,"Native rotation does not follow the measured foot moment")
	return true
