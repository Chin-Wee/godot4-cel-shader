extends RefCounted

# The lower-body sheet from FLIGHT_ARTICULATION_DESIGN.md, calibrated on MechAsset.
# Hip and ankle are XYZ degrees in chassis reference axes. Knee is flexion in degrees.
# Armored Core VI is the reference for the directional lean and staggered boost.
const NEUTRAL := [[Vector3(-8.8,0,5),5,Vector3(3.6,0,-5)]]
const AUTHORED := {
	"Neutral_Flight": NEUTRAL,
	"Hover_Hold": [[Vector3(-16,0,10),18,Vector3(12,0,-8)]],
	"Unpowered_Coast": [[Vector3(-3,0,7),8,Vector3(-5,0,-4)]],
	"Pitch_Up_Soft": [[Vector3(-12,0,7),5,Vector3(12,0,-7)]],
	"Pitch_Up_Hard": [[Vector3(-40,0,22),85,Vector3(10,0,-10)]],
	"Pitch_Down_Soft": [[Vector3(16,0,12),5,Vector3(-25,0,-8)]],
	"Pitch_Down_Hard": [[Vector3(32,0,22),8,Vector3(-35,0,-10)]],
	"Roll_Left_Soft": [[Vector3(-10,0,4),5,Vector3(2,0,-4)],[Vector3(10,0,-4),5,Vector3(-14,0,4)]],
	"Roll_Left_Hard": [[Vector3(-25,0,6),7,Vector3(9,0,-5)],[Vector3(25,0,-6),7,Vector3(-36,0,5)]],
	"Yaw_Left_Soft": [[Vector3(-12,-4,9),12,Vector3(-21,4,-2)],[Vector3(5,0,-11),5,Vector3(-17,0,9)]],
	"Yaw_Left_Hard": [[Vector3(-31,-13,20),38,Vector3(-27,8,-8)],[Vector3(10,0,-19),7,Vector3(-22,0,8)]],
	"Vertical_Ascent": [[Vector3(-8.8,0,3),5,Vector3(3.6,0,-3)]],
	"Forward_Boost": [[Vector3(5,0,10),9,Vector3(-35,0,-8)],[Vector3(13,0,-10),12,Vector3(-35,0,8)]],
	"Backward_Boost": [[Vector3(-30,0,19),24,Vector3(28,0,-10)],[Vector3(-22,0,-16),17,Vector3(28,0,9)]],
	"Lateral_Boost_Left": [[Vector3(-30,2,24),31,Vector3(-11,1,-10)],[Vector3(9,0,-17),6,Vector3(-19,0,-11)]],
	"Retrograde_Brake": [[Vector3(-32,0,32),72,Vector3(9,0,-10)]],
}
const MIRRORED := {
	"Roll_Right_Soft":"Roll_Left_Soft", "Roll_Right_Hard":"Roll_Left_Hard",
	"Yaw_Right_Soft":"Yaw_Left_Soft", "Yaw_Right_Hard":"Yaw_Left_Hard",
	"Lateral_Boost_Right":"Lateral_Boost_Left",
}
const REFLECT := Vector3(1,-1,-1)

static func angles(key: String) -> PackedVector3Array:
	var sides: Array = AUTHORED.get(MIRRORED.get(key,key),NEUTRAL)
	var result := PackedVector3Array()
	for side in 2:
		var source_side := 1-side if MIRRORED.has(key) else side
		var values: Array = sides[mini(source_side,sides.size()-1)]
		var sign_axes := REFLECT if MIRRORED.has(key) or (source_side==1 and sides.size()==1) else Vector3.ONE
		result.append(values[0]*sign_axes*(PI/180.0))
		result.append(Vector3(deg_to_rad(values[1]),0,0))
		result.append(values[2]*sign_axes*(PI/180.0))
	return result

static func blend(from: PackedVector3Array, to: PackedVector3Array, weight: float, knee_weight: float) -> PackedVector3Array:
	var result := PackedVector3Array()
	for joint in from.size():
		result.append(from[joint].lerp(to[joint],knee_weight if joint%3==1 else weight))
	return result

# Reverse burn is a continuous load, not a competing manoeuvre key.
static func retrograde_weight(velocity: Vector3, delivered: Vector3, requested: Vector3, weight: float, powered: bool) -> float:
	var speed := velocity.length()
	if speed<0.001: return 0.0
	var travel := velocity/speed
	var actual := maxf(0.0,-delivered.dot(travel))/maxf(weight,1.0)
	var intent := maxf(0.0,-requested.dot(travel))/maxf(weight,1.0) if powered else 0.0
	return smoothstep(2.0,10.0,speed)*smoothstep(0.08,0.65,maxf(actual,intent*0.8))

static func select(steer: Vector3, move: Vector3, power: float, reversing: float) -> PackedVector3Array:
	var base := _maneuver(steer,move,power)
	if power<0.001: return base
	var brace := clampf(reversing,0.0,1.0)
	var loaded := angles("Retrograde_Brake")
	var result := base.duplicate()
	var extended_pitch_down := steer.x < -0.55 and absf(steer.x) >= maxf(absf(steer.y),absf(steer.z))*0.8
	# Compression and stance are common-mode loads. Keep directional
	# differences rather than replacing both legs with the same brake key.
	for joint in 3:
		var left := base[joint]
		var right := base[joint+3]*REFLECT
		var mean := (left+right)*0.5
		var correction := (loaded[joint]-mean)*brace
		for side in 2:
			var index := side*3+joint
			var mirror := REFLECT if side==1 else Vector3.ONE
			var angle := base[index]+correction*mirror
			if joint==0:
				angle.z = maxf(angle.z*mirror.z,lerpf(base[index].z*mirror.z,loaded[joint].z,brace))*mirror.z
			elif joint==1 and not extended_pitch_down:
				angle.x = maxf(angle.x,maxf(base[index].x,lerpf(base[index].x,loaded[joint].x,brace)))
			result[index] = angle
	# A dominant forward pitch-down is an extended high-speed posture.
	# Translation blending and braking corrections may not fold its knees.
	if extended_pitch_down:
		var pitch_down := _turn_pose(Vector3(-1,0,0),0)
		for side in 2:
			var knee := side*3+1
			result[knee].x = minf(result[knee].x,pitch_down[knee].x)
	return result

static func _maneuver(steer: Vector3, move: Vector3, power: float) -> PackedVector3Array:
	var rest := angles("Neutral_Flight")
	var strength := steer.abs()
	var turn := strength[strength.max_axis_index()]
	var translation := move.abs()
	var demand := translation[translation.max_axis_index()]
	if power<0.001: return angles("Unpowered_Coast")
	if demand<=0.0001 and turn>0.0:
		return _turn_pose(steer,strength.max_axis_index())
	var boost_keys := ["Lateral_Boost_Right" if move.x>=0 else "Lateral_Boost_Left",
		"Vertical_Ascent" if move.y>=0 else "Retrograde_Brake", "Forward_Boost" if move.z>=0 else "Backward_Boost"]
	var total := translation.x+translation.y+translation.z
	if total<=0.0001: return rest
	var mixed := rest.duplicate()
	var keys := [angles(boost_keys[0]),angles(boost_keys[1]),angles(boost_keys[2])]
	for index in mixed.size():
		mixed[index] = (keys[0][index]*translation.x+keys[1][index]*translation.y+keys[2][index]*translation.z)/total
	var intensity := minf(move.length(),1.0)
	var result := blend(rest,mixed,intensity,intensity*intensity)
	# A hover boost and the simultaneous W/S/A/D attitude input share a
	# translation base. Independent yaw retains a stronger correction.
	for axis in 3:
		if strength[axis]<0.001: continue
		var rotation := _turn_pose(steer,axis)
		var influence := 0.75 if axis==0 else (0.65 if axis==1 else 0.25)
		for index in result.size():
			var delta := (rotation[index]-rest[index])*influence
			var angle := result[index]+delta
			if index%3==1 and axis!=0: angle.x = maxf(result[index].x,angle.x)
			result[index] = angle
	return result

static func _turn_pose(steer: Vector3, axis: int) -> PackedVector3Array:
	var rest := angles("Neutral_Flight")
	var turn := absf(steer[axis])
	var keys := ["Pitch_Up" if steer.x>=0 else "Pitch_Down",
		"Yaw_Left" if steer.y>=0 else "Yaw_Right",
		"Roll_Left" if steer.z>=0 else "Roll_Right"]
	var soft := angles(keys[axis]+"_Soft")
	if turn<=0.5: return blend(rest,soft,2.0*turn,pow(2.0*turn,2))
	return blend(soft,angles(keys[axis]+"_Hard"),2.0*turn-1.0,pow(2.0*turn-1.0,2))

# Local torso offsets (radians), distributed by the existing four-bone spine.
# Hathaway's Messer and Titanfall's Titans provide the loaded body accents.
const TORSO := {
	"Neutral":Vector3.ZERO,
	"Arch":Vector3(-0.10,0,0),
	"Deep_Arch":Vector3(-0.34,0,0),
	"Forward_Lean":Vector3(0.12,0,0),
	"Deep_Forward_Lean":Vector3(0.35,0,0),
	"Lateral_Lean":Vector3(0,0.10,0.35),
	"Axial_Twist":Vector3(0,-0.24,0.08),
	"Compressed_Brace":Vector3(0.22,0,0),
	"Extended_Release":Vector3(-0.08,0,0),
}
const TORSO_MIRRORED := {"Lateral_Lean_Right":"Lateral_Lean","Axial_Twist_Right":"Axial_Twist"}

# Swing, humerus twist, elevation from the side, and elbow flexion.
const ARMS := {
	"Neutral_Straight":Vector4(0.02,0,0.22,0.28),
	"Streamlined":Vector4(0.68,-0.10,0.25,0.30),
	"Trailing_Extension":Vector4(0.61,-0.11,0.25,0.30),
	"Forward_Brace":Vector4(-0.42,-0.42,0.72,0.91),
	"Asymmetric_Balance":[Vector4(-0.14,-0.36,0.60,0.82),Vector4(0.26,-0.16,0.27,0.36)],
	"Counterrotation":[Vector4(0.52,-0.18,0.49,0.70),Vector4(-0.32,-0.36,0.32,0.86)],
	"Wide_Brace":Vector4(-0.22,-0.68,1.32,1.04),
	"Relaxed_Suspension":Vector4(-0.05,-0.18,0.31,0.53),
	"Landing_Guard":Vector4(-0.30,-0.43,0.55,1.02),
}
const ARMS_MIRRORED := {"Asymmetric_Balance_Right":"Asymmetric_Balance","Counterrotation_Right":"Counterrotation"}
# Curl amount and knuckle fan relative to the imported hand's bind/grip targets.
const HANDS := {
	"Natural_Open":Vector2(0.12,0.05),
	"Spread_Fingers":Vector2(0.07,0.16),
	"Extended_Fingers":Vector2(0.025,0.025),
	"Loose_Curl":Vector2(0.22,0.065),
	"Natural_Curl":Vector2(0.34,0.045),
	"Tighter_Curl":Vector2(0.47,0.03),
	"Loose_Fist":Vector2(0.58,0.02),
	"Normal_Fist":Vector2(0.72,0.01),
	"Hard_Clench":Vector2(0.86,0.0),
}

# Belly/back support is a separate freefall family, adapted from AXIS.
const BELLY_LEGS := [Vector3(0.22,0,0.52),Vector3(0.82,0,0),Vector3(0.16,0,0)]
const BACK_LEGS := [Vector3(-1.09,0,0.45),Vector3(1.39,0,0),Vector3(0.20,0,0)]
const BELLY_ARMS := Vector4(0.43,-1.55,1.96,1.61)
const BACK_ARMS := Vector4(0.71,-1.30,1.82,1.18)

static func torso_key(key: String) -> Vector3:
	var angles: Vector3 = TORSO[TORSO_MIRRORED.get(key,key)]
	return angles*REFLECT if TORSO_MIRRORED.has(key) else angles

static func arm_key(key: String, side: int) -> Vector4:
	var pose: Variant = ARMS[ARMS_MIRRORED.get(key,key)]
	if pose is Array: return pose[1-side if ARMS_MIRRORED.has(key) else side]
	return pose

static func torso_target(frame: Dictionary) -> Vector3:
	var steer: Vector3 = frame.steer
	var pitch := absf(steer.x)
	var soft := torso_key("Arch" if steer.x>0.0 else "Forward_Lean")
	var hard := torso_key("Deep_Arch" if steer.x>0.0 else "Deep_Forward_Lean")
	var target := torso_key("Neutral").lerp(soft,2.0*pitch) if pitch<0.5 else soft.lerp(hard,2.0*pitch-1.0)
	var lateral: float = clampf(steer.y+frame.reach.x*0.55,-1,1)
	var side := torso_key("Lateral_Lean" if lateral>=0 else "Lateral_Lean_Right")
	target = target.lerp(side,absf(lateral)*(1.0-pitch*0.65))
	var roll: float = steer.z
	var twist := torso_key("Axial_Twist" if roll>=0 else "Axial_Twist_Right")
	target += twist*absf(roll)*(1.0-absf(lateral)*0.65)
	target = target.lerp(torso_key("Forward_Lean"),frame.drive*0.65)
	target = target.lerp(torso_key("Extended_Release"),frame.coast*0.75)
	target = target.lerp(torso_key("Compressed_Brace"),maxf(frame.retro,maxf(frame.flare*0.7,frame.land)))
	target.x += frame.back*0.12-frame.belly*0.18
	return target

static func arm_target(frame: Dictionary, side: int) -> Vector4:
	var steer: Vector3 = frame.steer
	var lateral: float = clampf(steer.y+frame.reach.x,-1,1)
	var target := arm_key("Neutral_Straight",side).lerp(arm_key("Streamlined",side),frame.track)
	target = target.lerp(arm_key("Relaxed_Suspension",side),frame.coast+frame.fall)
	target = target.lerp(arm_key("Trailing_Extension",side),frame.drive)
	target = target.lerp(arm_key("Asymmetric_Balance" if lateral>=0 else "Asymmetric_Balance_Right",side),absf(lateral)*0.75)
	target = target.lerp(arm_key("Counterrotation" if steer.z>=0 else "Counterrotation_Right",side),absf(steer.z)*0.65)
	target = target.lerp(arm_key("Forward_Brace",side),frame.retro)
	target = target.lerp(BELLY_ARMS,frame.belly)
	target = target.lerp(BACK_ARMS,frame.back)
	target = target.lerp(arm_key("Wide_Brace",side),frame.flare)
	return target.lerp(arm_key("Landing_Guard",side),frame.land)

static func hand_target(frame: Dictionary, side: int, texture: float) -> Vector2:
	var sx := 1.0 if side==0 else -1.0
	var firm: float = maxf(frame.drive,maxf(frame.retro,smoothstep(0.3,1.0,absf(frame.steer.x))*frame.get("stress",0.0)))
	firm = maxf(firm,frame.get("impact",0.0))
	var open: float = maxf(frame.flare,frame.fall*frame.steer.length()*0.6)
	firm = clampf(firm+sx*(frame.steer.y*0.18+frame.get("differential",0.0)*0.16),0,1)
	var relaxed: Vector2 = HANDS.Loose_Curl.lerp(HANDS.Natural_Curl,0.5+texture*0.5)
	relaxed = relaxed.lerp(HANDS.Tighter_Curl,frame.track*0.65)
	var closed: Vector2 = HANDS.Loose_Fist.lerp(HANDS.Normal_Fist,firm)
	closed = closed.lerp(HANDS.Hard_Clench,smoothstep(0.75,1.0,firm))
	var flat: Vector2 = HANDS.Natural_Open.lerp(HANDS.Extended_Fingers,maxf(-texture,0.0))
	flat = flat.lerp(HANDS.Spread_Fingers,maxf(texture,frame.flare*0.6))
	return relaxed.lerp(closed,firm).lerp(flat,clampf(open,0,1))
