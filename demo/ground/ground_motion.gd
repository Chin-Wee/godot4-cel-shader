extends RefCounted

# Armored Core VI short boost and landing commitment, with Hathaway sole rollover.
# ponytail: two traction patches over the existing capsule. Articulated physical
# feet are a separate change if rough-terrain support exceeds this model.
const Flight = preload("res://aerial/flight_controller.gd")
const U := Flight.WORLD_UNITS_PER_METER
const G := Flight.GRAVITY
const STEP := 0.70
const LOAD := 0.13
const HOP_TIME := 0.50
const GRIP := 0.70
const SKID := 0.45
const HEEL := -0.55*U
const TOE := 0.85*U
const WIDTH := 0.93*U
const FLOOR_UP := 0.9063

var body: RigidBody3D
var supported := false
var support_rids: Array[RID] = []
var support_normal := Vector3.UP
var feet := [Vector3.ZERO,Vector3.ZERO]
var foot_normals := [Vector3.UP,Vector3.UP]
var foot_headings := [Vector3.FORWARD,Vector3.FORWARD]
var rock := [0.0,0.0]
var loaded := [false,false]
var traction := [Vector3.ZERO,Vector3.ZERO]
var load_budget := 0.0
var traction_moment := Vector3.ZERO
var jet_force := Vector3.ZERO
var jet_moment := Vector3.ZERO
var hot_enabled := false
var landing_pose := 0.0
var landing_load := 0.0
var ik_weight := 0.0
var swing_ik_weight := 0.0
var slip := 0.0
var guard := false
var touchdowns := 0
var steps := 0
var pivots := 0
var launches := 0
var cushions := 0
var missed_cushions := 0
var last_sink := 0.0
var recovery := 0.0
var clock := 0.0

var origin := Vector3.ZERO
var heading := Vector3.FORWARD
var velocity := Vector3.ZERO
var previous_velocity := Vector3.ZERO
var pre_contact_velocity := Vector3.ZERO
var desired_velocity := Vector3.ZERO
var yaw_accel := 0.0
var step_time := -1.0
var step_duration := STEP
var swing := 0
var swing_start := Vector3.ZERO
var swing_goal := Vector3.ZERO
var swing_heading := Vector3.FORWARD
var swing_normal := Vector3.UP
var step_direction := Vector3.ZERO
var pivot_goal := Vector3.FORWARD
var pivot_steps := 0
var pivot_side := 0
var pivot_direction := 0
var pending_turn := 0
var hop_load := 0.0
var hop_elapsed := INF
var hop_direction := Vector3.FORWARD
var next_hop := 0.0
var cushion_used := false
var cushion_time := 0.0
var catch_time := 0.0
var skidding := false
var braking := false
var previous_hop := false
var previous_turn := 0

func _init(owner: RigidBody3D) -> void:
	body = owner

func _floor(state: PhysicsDirectBodyState3D, point: Vector3, reach := 2.6) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*U,point-Vector3.UP*reach*U,2)
	ray.exclude = [body.get_rid()]
	var hit := state.get_space_state().intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < FLOOR_UP: return {}
	return hit

func _stance(side: int, forward: Vector3) -> Vector3:
	var right := forward.cross(Vector3.UP)
	return origin-Vector3.UP*body.hull.shape.height*0.5+right*WIDTH*(-1 if side==0 else 1)

func _seed_feet(state: PhysicsDirectBodyState3D) -> void:
	for side in 2:
		var rest := _stance(side,heading)
		var hit := _floor(state,rest)
		loaded[side] = not hit.is_empty() and hit.rid in support_rids
		feet[side] = hit.get("position",rest)
		foot_normals[side] = hit.get("normal",Vector3.UP)
		foot_headings[side] = heading
		rock[side] = 0.0
	swing_ik_weight = 0.0

func prepare(state: PhysicsDirectBodyState3D, input: Dictionary) -> void:
	var dt := state.step
	clock += dt
	origin = state.transform.origin
	heading = -state.transform.basis.z.slide(Vector3.UP).normalized()
	if heading.is_zero_approx(): heading = Vector3.FORWARD
	velocity = state.linear_velocity/U
	for side in 2:
		if loaded[side] and rock[side]>0.0: rock[side] = move_toward(rock[side],0.0,2.1*dt)
	var was_supported := supported
	supported = false
	support_rids.clear()
	for index in state.get_contact_count():
		var normal := state.get_contact_local_normal(index)
		if normal.y < FLOOR_UP or velocity.dot(normal)>0.75: continue
		if not supported: support_normal = normal
		supported = true
		var collider := state.get_contact_collider(index)
		if collider not in support_rids: support_rids.append(collider)

	var movement: Vector2 = input.get("move",Vector2.ZERO)
	movement = movement.limit_length()
	var move_world := heading*movement.y+heading.cross(Vector3.UP)*movement.x
	var turn: int = input.get("turn",0)
	var hop: bool = input.get("hop",false)
	braking = input.get("brake",false)
	guard = input.get("guard",false)
	var hop_edge := hop and not previous_hop
	var turn_edge := turn != 0 and turn != previous_turn
	previous_hop = hop
	previous_turn = turn
	recovery = maxf(0.0,recovery-dt)
	catch_time = maxf(0.0,catch_time-dt)
	landing_load *= exp(-dt/0.23)
	slip = 0.0
	yaw_accel = 0.0
	desired_velocity = Vector3.ZERO
	jet_force = Vector3.ZERO
	hot_enabled = false
	landing_pose = 0.0

	if supported and not was_supported:
		# The native solver can slow the body a tick before reporting its contact.
		last_sink = maxf(0.0,-minf(previous_velocity.dot(support_normal),pre_contact_velocity.dot(support_normal)))
		if last_sink>0.9:
			touchdowns += 1
			catch_time = 0.12
			recovery = maxf(recovery,0.45 if last_sink>=5.0 else 0.20)
			landing_load = clampf(last_sink/7.0,0.22,1.0)
		step_time = -1.0
		cushion_time = 0.0
		cushion_used = false
		_seed_feet(state)
		skidding = velocity.slide(support_normal).length()>1.0 and catch_time>0
	if not supported:
		loaded = [false,false]
		step_time = -1.0
		pivot_steps = 0
		hop_load = 0.0
		skidding = false
		swing_ik_weight = 0.0

	if supported and hop_edge and hop_load<=0.0 and clock>=next_hop and recovery<=0.0 and pivot_steps==0 and not braking and (loaded[0] or loaded[1]):
		hop_direction = move_world.normalized() if move_world.length_squared()>0.01 else heading
		hop_load = LOAD
	if hop_load>0.0:
		hop_load = maxf(0.0,hop_load-dt)
		if hop_load==0.0:
			hop_elapsed = 0.0
			next_hop = clock+1.0
			launches += 1
			cushion_used = false

	var launching := hop_elapsed<HOP_TIME
	if launching:
		var target := hop_direction*4.2+Vector3.UP*4.8
		var left := maxf(0.16,HOP_TIME-hop_elapsed)
		var accel := (target-velocity)/left+Vector3.UP*G
		# Keep the requested lift positive while the boost closes and let the valves
		# deliver their actual tail. Never correct the trajectory directly.
		accel.y = maxf(0.0,accel.y)
		jet_force = accel.limit_length(4.0*G)*body.mass
		hot_enabled = true
		hop_elapsed += dt

	if supported and not launching:
		_ground_step(state,move_world,turn if turn_edge else 0)
	elif not supported and not launching:
		_descent(state)
	else:
		ik_weight = 0.0 if not supported else 1.0

	var basis := state.transform.basis.orthonormalized()
	var rates := basis.y.cross(support_normal if supported else Vector3.UP)*4.0
	# Ground yaw comes from the contact couple. In air damp unwanted spin.
	rates.y = state.angular_velocity.y if supported and loaded[0] and loaded[1] else 0.0
	var angular := ((rates-state.angular_velocity)*6.0).limit_length(5.0)
	var inertia := state.inverse_inertia_tensor.inverse()
	jet_moment = inertia*angular/(U*U)
	if supported and loaded[0]!=loaded[1]:
		# The support pad carries normal load. Trim only the yaw induced by one
		# off-centre tangential foot push until two feet can oppose it.
		jet_moment -= Vector3.UP*traction_moment.y
	pre_contact_velocity = previous_velocity if not was_supported else velocity
	previous_velocity = velocity

func _ground_step(state: PhysicsDirectBodyState3D, move: Vector3, turn: int) -> void:
	var dt := state.step
	ik_weight = 1.0
	landing_pose = landing_load*0.5
	var speed := velocity.slide(support_normal).length()
	var brake_demand := (-velocity.slide(support_normal)*4.0+Vector3.UP.slide(support_normal)*G).length()*body.mass
	if (braking and speed>0.25 and brake_demand>load_budget*GRIP) or skidding:
		skidding = speed>0.16
		if skidding:
			slip = speed
			step_time = -1.0
			_seed_feet(state)
			if catch_time>0: loaded[1] = false
			return
		_seed_feet(state)
	if catch_time>0:
		loaded[1] = false
		return
	if not loaded[0] or not loaded[1]:
		if step_time<0.0: _seed_feet(state)
	if recovery>0.0 or hop_load>0.0: return

	if turn!=0 and pivot_steps==0: pending_turn = turn
	if pending_turn!=0 and pivot_steps==0 and step_time<0.0 and speed<0.22:
		pivot_direction = pending_turn
		pending_turn = 0
		pivot_side = 1 if pivot_direction>0 else 0
		pivot_goal = heading.rotated(Vector3.UP,pivot_direction*PI/4.0)
		pivot_steps = 2
	if pivot_steps>0:
		if step_time>=0:
			_advance_step(state)
			return
		var angle := heading.signed_angle_to(pivot_goal,Vector3.UP)
		var rate := signf(angle)*minf(absf(angle)*4.5,minf(1.35,sqrt(4.0*absf(angle))))
		yaw_accel = clampf((rate-state.angular_velocity.y)*6.0,-3.5,3.5)
		if absf(angle)<deg_to_rad(2.0) and absf(state.angular_velocity.y)<0.18:
			_start_step(state,pivot_side,Vector3.ZERO,pivot_goal)
		return

	if pending_turn!=0 and step_time<0.0: return
	# Finish the swing under the hips when the hull has actually met a wall.
	for index in state.get_contact_count():
		var normal := state.get_contact_local_normal(index)
		var drive := step_direction if step_time>=0.0 else move
		if normal.y<0.45 and normal.dot(drive.normalized())<-0.4:
			if step_time>=0.0:
				var hit := _floor(state,_stance(swing,heading))
				swing_goal = hit.get("position",swing_start)
				_advance_step(state)
			return
	if step_time<0.0 and move.length()>0.1 and not braking:
		_start_step(state,swing,move,heading)
	if step_time>=0.0:
		if not braking:
			desired_velocity = step_direction if step_time>=LOAD else step_direction*smoothstep(0.0,LOAD,step_time)*0.38
		_advance_step(state)

func _start_step(state: PhysicsDirectBodyState3D, side: int, move: Vector3, forward: Vector3) -> void:
	var forward_amount := maxf(0.0,move.dot(heading))
	var speed := lerpf(1.25,2.5,forward_amount) if not guard else 1.25
	var target := _stance(side,forward)+move*speed*0.76*U
	var hit := _floor(state,target,1.1)
	# Floor rays alone are insufficient. Reject a swing through a solid wall.
	var ray := PhysicsRayQueryParameters3D.create(origin,target+Vector3.UP*0.7*U,4)
	ray.exclude = [body.get_rid()]
	if hit.is_empty() or absf(hit.position.y-target.y)>0.55*U or not state.get_space_state().intersect_ray(ray).is_empty():
		if pivot_steps>0: pivot_steps = 0
		return
	swing = side
	swing_start = feet[side]
	swing_goal = hit.position
	swing_heading = forward
	swing_normal = hit.normal
	step_direction = move.slide(support_normal)*speed
	step_time = 0.0
	swing_ik_weight = 1.0

func _advance_step(state: PhysicsDirectBodyState3D) -> void:
	step_time += state.step
	var phase := clampf((step_time-LOAD)/(step_duration-LOAD),0.0,1.0)
	if step_time<LOAD:
		swing_ik_weight = 1.0
		rock[swing] = -deg_to_rad(14.0)*smoothstep(0.0,LOAD,step_time)
		return
	loaded[swing] = false
	# The authored clip owns early swing; physical IK reclaims the boot before contact.
	swing_ik_weight = smoothstep(0.55,0.88,phase)
	var curve := smoothstep(0.0,1.0,phase)
	feet[swing] = swing_start.lerp(swing_goal,curve)+Vector3.UP*sin(PI*phase)*0.28*U
	foot_headings[swing] = foot_headings[swing].slerp(swing_heading,curve).normalized()
	foot_normals[swing] = swing_normal
	rock[swing] = lerpf(-deg_to_rad(14.0),deg_to_rad(11.0),curve)
	if phase<1.0: return
	var hit := _floor(state,swing_goal,0.55)
	if hit.is_empty() or absf(hit.position.y-_stance(swing,heading).y)>0.55*U or (_stance(swing,heading)-swing_goal).slide(Vector3.UP).length()>1.75*U:
		_seed_feet(state)
	else:
		loaded[swing] = true
		feet[swing] = hit.position
		foot_normals[swing] = hit.normal
		foot_headings[swing] = swing_heading
		steps += 1
	step_time = -1.0
	swing_ik_weight = 0.0
	swing = 1-swing
	if pivot_steps>0:
		pivot_steps -= 1
		if pivot_steps==0:
			pivots += 1
		else:
			pivot_side = swing
			pivot_goal = pivot_goal.rotated(Vector3.UP,pivot_direction*PI/4.0)

func _descent(state: PhysicsDirectBodyState3D) -> void:
	var hit := _floor(state,origin-Vector3.UP*body.hull.shape.height*0.5,4.0)
	ik_weight = 0.0
	if hit.is_empty() or velocity.y>=-0.2: return
	var height := maxf(0.0,(origin.y-hit.position.y-body.hull.shape.height*0.5)/U)
	var ttc := (velocity.y+sqrt(velocity.y*velocity.y+2.0*G*height))/G
	landing_pose = 1.0-smoothstep(0.06,0.45,ttc)
	if not cushion_used and ttc<=0.24 and velocity.y<-2.5:
		cushion_used = true
		if ttc>=0.12 and body.controller.hot_valves.any(func(valve): return valve.preview(1.0,ttc)>0.10):
			cushion_time = minf(0.20,ttc)
			cushions += 1
		else: missed_cushions += 1
	if cushion_time>0:
		hot_enabled = true
		jet_force = Vector3.UP*body.mass*clampf(G+(-2.0-velocity.y)/maxf(ttc,0.10),0.0,2.3*G)
		cushion_time -= state.step

func apply_traction(state: PhysicsDirectBodyState3D, delivered: Vector3) -> void:
	traction = [Vector3.ZERO,Vector3.ZERO]
	traction_moment = Vector3.ZERO
	load_budget = 0.0
	if not supported: return
	var count := 0
	var valid := [false,false]
	for side in 2:
		if not loaded[side]: continue
		var hit := _floor(state,feet[side],0.55)
		if hit.is_empty() or hit.rid not in support_rids: continue
		var reach: Vector3 = _stance(side,heading)-feet[side]
		if absf(reach.y)>0.65*U or reach.slide(Vector3.UP).length()>2.2*U: continue
		valid[side] = true
		count += 1
	if count==0: return
	load_budget = clampf(body.mass*G*support_normal.y-delivered.dot(support_normal),0.0,body.mass*G)
	var planar := velocity.slide(support_normal)
	var limit := 6.8 if braking else 1.85
	var accel := ((desired_velocity-planar)*4.0).limit_length(limit)
	if skidding: accel = (-planar/state.step).limit_length(3.0)
	var total := (accel+Vector3.UP.slide(support_normal)*G)*body.mass
	var couple := Vector3.ZERO
	if count==2:
		var span: Vector3 = (feet[1]-feet[0]).slide(support_normal)/U
		if span.length()>0.1:
			var inverse := state.inverse_inertia_tensor*support_normal
			var yaw := yaw_accel if pivot_steps>0 else -state.angular_velocity.dot(support_normal)*6.0
			var moment := yaw/(maxf(0.00000001,inverse.dot(support_normal))*U*U)
			couple = support_normal.cross(span.normalized())*moment/span.length()
	for side in 2:
		if not valid[side]: continue
		var force := (total/count+couple*(-1 if side==0 else 1)).limit_length(load_budget/count*(SKID if skidding else GRIP))
		traction[side] = force
		var lever: Vector3 = sole_anchor(side)-origin
		state.apply_force(force*U,lever)
		traction_moment += (lever/U).cross(force)

func _flat_basis(side: int) -> Basis:
	var normal: Vector3 = foot_normals[side]
	var forward: Vector3 = foot_headings[side].slide(normal).normalized()
	return Basis(forward.cross(normal).normalized(),forward,normal)

func foot_basis(side: int) -> Basis:
	var flat := _flat_basis(side)
	return flat*Basis(Vector3.RIGHT,rock[side])

func sole_anchor(side: int) -> Vector3:
	var offset := TOE if rock[side]<0 else HEEL if rock[side]>0 else 0.0
	return feet[side]+_flat_basis(side).y*offset

func sole_position(side: int) -> Vector3:
	var offset := TOE if rock[side]<0 else HEEL if rock[side]>0 else 0.0
	var lift := Vector3.UP*0.24*U*smoothstep(0.0,0.12,catch_time) if side==1 else Vector3.ZERO
	return sole_anchor(side)-foot_basis(side).y*offset+lift

func pelvis_offset() -> Vector3:
	var side := -1.0 if swing==1 else 1.0
	var shift := side*0.075*sin(PI*clampf(step_time/step_duration,0.0,1.0)) if step_time>=0 else 0.0
	var support_sink := 0.035*ik_weight
	var crouch_sink := 0.10 if guard else 0.0
	var step_sink := 0.045*(1.0-smoothstep(0.0,LOAD,step_time)) if step_time>=0.0 else 0.0
	var hop_sink := 0.10 if hop_load>0.0 else 0.0
	return Vector3(shift,-support_sink-crouch_sink-step_sink-landing_load*0.13-hop_sink-slip*0.013,0.0)
