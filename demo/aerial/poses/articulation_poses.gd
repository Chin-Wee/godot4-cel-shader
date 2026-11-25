extends RefCounted

# The lower-body sheet from FLIGHT_ARTICULATION_DESIGN.md, calibrated on MechAsset.
# Hip and ankle are XYZ degrees in chassis reference axes. Knee is flexion in degrees.
# Armored Core VI is the reference for the directional lean and staggered boost.
const NEUTRAL := [[Vector3(-8.8,0,5),5,Vector3(3.6,0,-5)]]
const AUTHORED := {
	"Neutral_Flight": NEUTRAL,
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
	"Forward_Boost": [[Vector3(5,0,7),9,Vector3(-35,0,-6)],[Vector3(13,0,-7),12,Vector3(-35,0,6)]],
	"Backward_Boost": [[Vector3(-24,0,8),12,Vector3(28,0,-7)]],
	"Lateral_Boost_Left": [[Vector3(-30,2,21),31,Vector3(-11,1,-4)],[Vector3(9,0,-5),6,Vector3(-19,0,-10)]],
	"Retrograde_Brake": [[Vector3(-32,0,24),56,Vector3(9,0,-7)]],
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

static func select(steer: Vector3, move: Vector3, power: float, reversing: float) -> PackedVector3Array:
	var rest := angles("Neutral_Flight")
	var strength := steer.abs()
	var turn := strength[strength.max_axis_index()]
	var translation := move.abs()
	var demand := translation[translation.max_axis_index()]
	if power<0.001: return angles("Unpowered_Coast")
	if reversing>maxf(turn,demand):
		return blend(rest,angles("Retrograde_Brake"),reversing,reversing*reversing)
	if turn>demand and turn>0.0:
		var axis := strength.max_axis_index()
		var turn_keys := ["Pitch_Up" if steer.x>=0 else "Pitch_Down",
			"Yaw_Left" if steer.y>=0 else "Yaw_Right",
			"Roll_Left" if steer.z>=0 else "Roll_Right"]
		var soft := angles(turn_keys[axis]+"_Soft")
		if turn<=0.5: return blend(rest,soft,2.0*turn,pow(2.0*turn,2))
		var hard := angles(turn_keys[axis]+"_Hard")
		return blend(soft,hard,2.0*turn-1.0,pow(2.0*turn-1.0,2))
	var boost_keys := ["Lateral_Boost_Right" if move.x>=0 else "Lateral_Boost_Left",
		"Vertical_Ascent" if move.y>=0 else "Retrograde_Brake", "Forward_Boost" if move.z>=0 else "Backward_Boost"]
	return blend(rest,angles(boost_keys[translation.max_axis_index()]),demand,demand*demand)
