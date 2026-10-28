extends SceneTree

const Pose = preload("res://aerial/flight_pose.gd")
var completed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(20).timeout.connect(func():
		if not completed: push_error("Procedural flight checks did not complete"); quit(1))
	# An analytic spring must give the same result at different frame rates and
	# retain velocity across reversals instead of restarting a tween each frame.
	var previous := Vector3.ZERO
	for fps in [30,60,120]:
		var spring := Pose.Spring.new()
		for frame in fps: spring.step(Vector3.ONE,1.0/fps,0.35)
		if fps > 30: assert(spring.value.distance_to(previous) < 0.00001,"Spring depends on frame rate")
		previous = spring.value
		var velocity := spring.velocity
		spring.step(Vector3.ZERO,0.001,0.35)
		assert(spring.velocity.distance_to(velocity) < 0.1,"Target reversal discarded spring momentum")
	var scene = load("res://aerial/aerial_demo.tscn").instantiate()
	root.add_child(scene)
	scene.animate = false
	var mech = scene.hero
	await process_frame
	assert(mech.flames.size() == 6 and mech.gas_jets.size() == 4,"Wrong propulsion layout")
	assert(_check_mount_surfaces(mech),"A booster is not seated against its armor")
	for socket in mech.sockets+mech.gas_sockets:
		assert(not "Hands" in socket.bone_name and not "Arm" in socket.bone_name,"Hand/arm booster reintroduced")
	for frame in 120: mech.update_animation(1.0/60,0.35)
	await process_frame
	assert(_check_ik(mech),"Native arm IK missed its target or produced a non-finite pose")
	for flame in mech.flames:
		assert(flame.global_basis.z.normalized().dot(Vector3.DOWN) > 0.95,"Neutral jets are not downward")
	mech.flight_amount = 1.0
	mech.flight_pose = 1
	mech.update_animation(0.08,1.0)
	assert(mech.rig.chest.value.x > mech.rig.hips.value.x,"Chest does not lead the heavier hips")
	assert(mech.rig.hands[0].value.z > -1.0,"Arms snapped to a target")
	for frame in 120: mech.update_animation(1.0/60,1.0)
	await process_frame
	assert(_check_ik(mech),"Native arm IK missed its target or produced a non-finite pose")
	assert(mech.rig.shares[0] != mech.rig.shares[1],"Turning never shifts thruster load")
	var total := 0.0
	for share in mech.rig.shares:
		assert(share > 0.0)
		total += share
	assert(is_equal_approx(total,1.0),"Allocated thrust does not sum to one")
	# A wrap through +/-pi is a small turn, not an enormous yaw impulse.
	mech.rotation.y = PI-0.001
	mech.reset_motion()
	mech.update_animation(0,1.0)
	mech.rotation.y = -PI+0.001
	mech.update_animation(0.02,1.0)
	assert(absf(mech.yaw_rate) < 0.11,"Heading wrap produced a false turn")
	mech.position += Vector3(1000,1000,1000)
	mech.reset_motion()
	mech.update_animation(0.02,1.0)
	assert(mech.local_acceleration == Vector3.ZERO,"Preview teleport produced an acceleration spike")
	mech.flying = false
	for frame in 90: mech.update_animation(1.0/60,1.0)
	await process_frame
	assert(not mech.rig.active and not mech.rig.ik.active,"Flight modifiers contaminate the walk")
	assert(mech.actor.current_animation == &"Walk")
	var clock: float = mech.rig.clock
	var pose: Transform3D = mech.actor.transform
	await process_frame
	assert(mech.rig.clock == clock and mech.actor.transform == pose,"Rendering a paused rig advances its springs")
	scene.queue_free()
	await process_frame
	completed = true
	print("Procedural flight checks passed: springs, mass lag, native arm IK, thrust allocation, six seated boosters, four control jets, heading wrap, walk and pause.")
	quit()

func _check_ik(mech: Node3D) -> bool:
	for side in 2:
		var suffix := ".L" if side == 0 else ".R"
		var hand: Transform3D = mech.bone_poses[mech.skeleton.find_bone("Hands"+suffix)]
		var target: Vector3 = mech.rig.hand_targets[side].position
		if not hand.origin.is_finite() or not hand.basis.is_finite() or hand.origin.distance_to(target) >= 0.05: return false
	return true

func _check_mount_surfaces(mech: Node3D) -> bool:
	# Test against source triangles, excluding the collars we add ourselves. Bone
	# attachment alone cannot prove that a booster is seated against the armor.
	var sk: Skeleton3D = mech.skeleton
	for mount in mech.MOUNTS+mech.COLD_MOUNTS:
		var nearest := INF
		for child in sk.get_children():
			var candidates := []
			var transform := Transform3D.IDENTITY
			if child is BoneAttachment3D and child.bone_name == mount[1] and not str(child.name).begins_with("Thruster"):
				candidates = child.get_children()
			elif child is MeshInstance3D and child.name == &"Cube" and mount[1] == &"Torso":
				candidates = [child]
				transform = sk.get_bone_global_rest(sk.find_bone("Torso")).affine_inverse()
			for mesh in candidates:
				if not mesh is MeshInstance3D: continue
				var to_bone: Transform3D = transform*mesh.transform
				var faces: PackedVector3Array = mesh.mesh.get_faces()
				for index in range(0,faces.size(),3):
					nearest = minf(nearest,_triangle_distance(mount[2],to_bone*faces[index],to_bone*faces[index+1],to_bone*faces[index+2]))
		if nearest >= 0.02:
			push_error("Booster floats away from source armor: %s (%s source units)"%[mount[0],nearest])
			return false
	return true

func _triangle_distance(point: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var normal := (b-a).cross(c-a).normalized()
	var hit = Geometry3D.segment_intersects_triangle(point+normal*100,point-normal*100,a,b,c)
	if hit != null: return point.distance_to(hit)
	return minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point,a,b)),minf(point.distance_to(Geometry3D.get_closest_point_to_segment(point,b,c)),point.distance_to(Geometry3D.get_closest_point_to_segment(point,c,a))))
