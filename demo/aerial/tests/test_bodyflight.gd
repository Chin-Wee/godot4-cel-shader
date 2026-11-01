extends "res://aerial/tests/test_animation_contract.gd"

# Use completed native geometry to isolate air control from engine/RCS torque.
func _surface_pose(request: Vector3) -> Vector3:
	mech.reset_flight(Vector3(175,9000,340))
	_neutral()
	mech.quaternion = Quaternion(Vector3.RIGHT,-PI/2)
	mech.linear_velocity = Vector3.FORWARD*700
	fc.control_blend = 1
	fc.engine_level = 2
	fc.detent = 3
	fc.aero_authority = 1
	fc.local_airflow = Vector3(0,-70,0)
	fc.air_velocity = Vector3.FORWARD*70
	fc.main_force = Vector3.FORWARD*mech.mass*fc.GRAVITY*2
	fc.requested_main_force = fc.main_force
	fc.rotation_command = request
	await _ticks(180)
	fc._calculate_aerodynamics(mech.aerodynamic_surfaces())
	assert(fc.aero_power<0,"Passive panels add mechanical energy")
	assert(fc.aero_surface_forces.size()==5)
	return fc.pilot_frame().inverse()*fc.aero_torque

func _run() -> void:
	create_timer(60).timeout.connect(func():
		if not finished: push_error("Body-flight checks did not finish"); quit(1))
	scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.set_process_unhandled_input(false)
	mech = scene.hero
	mech.player_controlled = false
	mech.freeze = true
	fc = mech.controller
	var total := 0.0
	for fraction in mech.rig.profile.aero_fractions: total += fraction
	assert(absf(total-1)<0.0001,"Proxy panels duplicate the original total area")
	var neutral: Vector3 = await _surface_pose(Vector3.ZERO)
	for axis in 3:
		for sign in [-1.0,1.0]:
			var request := Vector3.ZERO
			request[axis] = sign
			var moment: Vector3 = await _surface_pose(request)
			assert((moment[axis]-neutral[axis])*sign>5000,"Limb pressure opposes the requested flight rotation")
	fc.air_density = 0
	fc._calculate_aerodynamics(mech.aerodynamic_surfaces())
	assert(fc.aero_force.is_zero_approx() and fc.aero_torque.is_zero_approx() and fc.aero_power==0,"Vacuum retains aerodynamic control")
	fc.air_density = 1.225
	fc.air_velocity = Vector3.ZERO
	mech.angular_velocity = Vector3.ZERO
	fc._calculate_aerodynamics(mech.aerodynamic_surfaces())
	assert(fc.aero_force.is_zero_approx() and fc.aero_torque.is_zero_approx(),"Stationary armor creates air force")
	# Rotation at the panel points creates real drag even at zero COM velocity.
	mech.angular_velocity = Vector3(0.2,-0.3,0.4)
	fc._calculate_aerodynamics(mech.aerodynamic_surfaces())
	assert(fc.aero_power<0 and fc.aero_torque.length()>1,"Panel model omits angular airflow/damping")
	finished = true
	print("Body-flight checks passed: five posed surfaces, shared total area, signed pitch/yaw/roll moments, passive angular airflow, zero-flow and vacuum invariants.")
	scene.queue_free()
	await process_frame
	quit()
