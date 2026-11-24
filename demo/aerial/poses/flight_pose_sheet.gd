extends RefCounted

# Overgrowth: a small set of authored poses with directional variations.
# Armored Core VI: distinct gather, drive and catch for directional boost.
# Hip, knee and ankle pitch offsets are in radians. Preview attitude is in degrees.
const HOVER_ANKLE_PITCH := -0.174 # Vertical heel axes on the reset bind pose.
const BOOST_ANKLE_TRIM := -0.43 # Loaded leg bias shared by drive and catch.
const KEYS := {
	"Hover_Neutral":{"hover":1.0,"lead":0.0,"ankle_aim":Vector3(HOVER_ANKLE_PITCH,0,0)},
	"Launch_Soft_Push":{"hover":0.65,"launch":0.6,"stance":Vector3(-0.10,0.25,-0.06),"lead":0.0,"preview":Vector3(-4,0,0)},
	"Launch_Hard_Push":{"hover":0.7,"launch":1.0,"drive":0.4,"stance":Vector3(0.05,-0.08,0.12),"lead":0.0,"preview":Vector3(-8,0,0)},
	"Hover_Climb":{"hover":1.0,"launch":0.5,"stance":Vector3(0.10,-0.22,0.15),"lead":0.0,"preview":Vector3(-5,0,0)},
	"Hover_Sink":{"hover":0.65,"coast":0.35,"compression":0.55,"stance":Vector3(-0.07,0.12,-0.04),"lead":0.0,"preview":Vector3(5,0,0)},
	"Flight_Drive":{"fighter":1.0,"track":0.65,"drive":1.0,"asymmetry":0.75,"g_load":2.0,"preview":Vector3(-83,0,0)},
	"Flight_Climb":{"fighter":1.0,"track":0.85,"steer":Vector3(0.65,0,0),"stance":Vector3(-0.13,0.28,-0.13),"preview":Vector3(-59,0,0)},
	"Flight_Dive":{"fighter":1.0,"track":1.0,"steer":Vector3(-0.6,0,0),"stance":Vector3(0.05,-0.08,-0.05),"preview":Vector3(-119,0,0)},
	"Flight_High_Thrust":{"fighter":1.0,"track":1.0,"thrust":4.0,"lead":0.0,"preview":Vector3(-90,0,0)},
	"Pitch_Pull_Arrest":{"fighter":1.0,"track":0.9,"steer":Vector3(-0.45,0,0),"stance":Vector3(0.07,-0.07,0.06),"preview":Vector3(-63,0,0)},
	"Pitch_Push_Arrest":{"fighter":1.0,"track":0.9,"steer":Vector3(0.45,0,0),"stance":Vector3(-0.08,0.18,-0.1),"preview":Vector3(-115,0,0)},
	"Brake_Open":{"coast":1.0,"flare":0.42,"prepare":0.55,"lead":0.0,"preview":Vector3(-57,0,0)},
	"Brake_Symmetric":{"coast":1.0,"brake":1.0,"lead":0.0,"preview":Vector3(-28,0,0)},
	"Brake_Close":{"coast":1.0,"flare":0.25,"lead":0.0,"preview":Vector3(-37,0,0)},
	"Retro_Release":{"coast":1.0,"retro":0.22,"stance":Vector3(0.08,-0.10,0.12),"preview":Vector3(9,0,0)},
	"Retro_Outbound":{"coast":1.0,"drive":0.9,"asymmetry":0.5,"preview":Vector3(9,0,0)},
	"Cutoff_Release":{"coast":1.0,"track":0.75,"stance":Vector3(-0.08,0.14,0.08),"preview":Vector3(-90,0,0)},
	"Coast_Detached":{"coast":1.0,"pressure":0.85,"flow":Vector3(0.7,0,0.7),"steer":Vector3(-0.25,-0.2,0.2),"preview":Vector3(-55,0,28)},
	"Coast_Compact":{"coast":1.0,"stance":Vector3(-0.11,0.22,0.06),"lead":0.0,"preview":Vector3(-42,0,0)},
	"Relight_Prepare":{"coast":1.0,"prepare":1.0,"track":0.45,"stance":Vector3(-0.10,0.14,-0.08),"preview":Vector3(-68,0,0)},
	"Fall_Recover":{"coast":0.6,"fall":0.4,"track":0.32,"pressure":0.6,"flare":0.28,"steer":Vector3(0.5,0,0),"preview":Vector3(-66,0,0)},
	"Front_Abort":{"coast":1.0,"acro":Vector2(0.8,0),"acro_sign":Vector2(-1,0),"acro_recovery":Vector2(1,0),"flip_degrees":105},
	"Back_Abort":{"coast":1.0,"acro":Vector2(0.8,0),"acro_sign":Vector2(1,0),"acro_recovery":Vector2(1,0),"flip_degrees":105},
	"Front_Arrest":{"hover":0.4,"coast":0.6,"acro":Vector2(0.45,0),"acro_sign":Vector2(-1,0),"acro_recovery":Vector2(1,0),"steer":Vector3(0.5,0,0),"flip_degrees":348},
	"Back_Arrest":{"hover":0.4,"coast":0.6,"acro":Vector2(0.45,0),"acro_sign":Vector2(1,0),"acro_recovery":Vector2(1,0),"steer":Vector3(-0.5,0,0),"flip_degrees":348},
	"Landing_Reach_Both":{"land":0.78,"coast":0.22,"feet":Vector2(2.5,2.5),"body_shift":Vector3(0,0,0.15),"lead":0.0,"preview":Vector3(-4,0,0)},
	"Landing_Cushion":{"land":0.60,"hover":0.40,"compression":0.55,"feet":Vector2(1.0,1.0),"body_shift":Vector3(0,0,0.16),"lead":0.0,"preview":Vector3(-3,0,0)},
	"Landing_Hard_Absorb":{"land":1.0,"compression":1.3,"g_load":4.0,"feet":Vector2.ZERO,"body_shift":Vector3(0,0,0.18),
		"pelvis_drop":0.27,"shoulder_brace":-0.24,"chest_offset":Vector3(0.18,0,0),"lead":0.0,"preview":Vector3(-6,0,0)},
	"Landing_Settle":{"land":1.0,"feet":Vector2.ZERO,"body_shift":Vector3(0,0,0.16),"pelvis_drop":0.12,"lead":0.0},
	"Landing_Miss":{"coast":0.75,"fall":0.25,"stance":Vector3(-0.12,0.27,-0.12),"steer":Vector3(0.5,0,0),"preview":Vector3(-16,0,0)},
}

const STUDIES := {
	"Launch_Soft":[[0.0,"Ready_Coil"],[0.28,"Launch_Soft_Push"],[0.58,"Hover_Catch"],[1.05,"Hover_Neutral"]],
	"Launch_Hard":[[0.0,"Ready_Coil"],[0.20,"Launch_Hard_Push"],[0.47,"Hover_Climb"],[0.78,"Hover_Catch"],[1.28,"Hover_Neutral"]],
	"Hover_Climb_And_Sink":[[0.0,"Hover_Neutral"],[0.48,"Hover_Climb"],[0.93,"Hover_Neutral"],[1.40,"Hover_Sink"],[1.86,"Hover_Catch"],[2.36,"Hover_Neutral"]],
	"Powered_Climb_And_Dive":[[0.0,"Hover_Neutral"],[0.42,"Flight_Pierce"],[0.78,"Flight_Drive"],[1.25,"Flight_Sustain"],[1.67,"Flight_Climb"],[2.1,"Pitch_Pull_Arrest"],[2.52,"Flight_Sustain"],[3.0,"Flight_Dive"],[3.45,"Pitch_Push_Arrest"],[3.97,"Flight_High_Thrust"],[4.6,"Flight_Sustain"]],
	"Airbrake":[[0.0,"Flight_Sustain"],[0.30,"Brake_Open"],[0.62,"Brake_Symmetric"],[0.97,"Brake_Symmetric"],[1.29,"Brake_Close"],[1.75,"Coast_Settle"]],
	"Retro_Reversal":[[0.0,"Coast_Settle"],[0.36,"Retro_Brace_Left"],[0.68,"Retro_Brace_Left"],[1.06,"Retro_Release"],[1.41,"Retro_Outbound"],[1.96,"Hover_Neutral"]],
	"Cutoff_And_Relight":[[0.0,"Flight_High_Thrust"],[0.35,"Cutoff_Release"],[0.90,"Coast_Detached"],[1.42,"Coast_Compact"],[1.96,"Relight_Prepare"],[2.27,"Flight_Drive"],[2.87,"Flight_Sustain"]],
	"Fall_And_Relight":[[0.0,"Cutoff_Release"],[0.65,"Coast_Detached"],[1.40,"Fall_Box"],[1.95,"Fall_Turn_Left"],[2.63,"Back_Fall"],[3.33,"Fall_Turn_Right"],[3.94,"Track"],[4.53,"Fall_Recover"],[5.06,"Relight_Prepare"],[5.42,"Flight_Drive"],[6.05,"Flight_Sustain"]],
	"Front_Flip_Abort":[[0.0,"Hover_Neutral"],[0.30,"Front_Swing"],[0.77,"Front_Abort"],[1.34,"Fall_Recover"],[1.96,"Coast_Settle"]],
	"Back_Flip_Abort":[[0.0,"Hover_Neutral"],[0.30,"Back_Swing"],[0.77,"Back_Abort"],[1.34,"Landing_Miss"],[1.96,"Coast_Settle"]],
	"Landing_Two_Foot":[[0.0,"Landing_Guard"],[0.32,"Landing_Reach_Both"],[0.53,"Landing_Cushion"],[0.69,"Landing_Absorb"],[1.20,"Landing_Settle"]],
	"Landing_Hard":[[0.0,"Landing_Guard"],[0.38,"Landing_Reach_Both"],[0.55,"Landing_Hard_Absorb"],[0.80,"Landing_Hard_Absorb"],[1.45,"Landing_Settle"]],
	"Landing_Missed":[[0.0,"Landing_Guard"],[0.34,"Landing_Reach_Left"],[0.59,"Landing_Miss"],[1.13,"Coast_Compact"],[1.72,"Hover_Neutral"]],
}

static func add_directional_variants(keys: Dictionary, studies: Dictionary) -> void:
	# Direction uses the asset's +Z-forward convention, as in the hover keys.
	var directions := {
		"Left":Vector3.RIGHT,"Right":Vector3.LEFT,"Forward":Vector3.BACK,"Back":Vector3.FORWARD,
		"Forward_Left":Vector3(1,0,1).normalized(),"Forward_Right":Vector3(-1,0,1).normalized(),
		"Back_Left":Vector3(1,0,-1).normalized(),"Back_Right":Vector3(-1,0,-1).normalized(),
	}
	for direction: String in directions:
		var move: Vector3 = directions[direction]
		var lead := signf(move.x) if absf(move.x)>0.01 else 1.0
		var gather := "Hover_"+direction
		keys[gather] = {"hover":1.0,"move_intent":move*0.48,"lead":lead,
			"ankle_aim":Vector3(lerpf(HOVER_ANKLE_PITCH,BOOST_ANKLE_TRIM,0.35),0,0),
			"chest_offset":Vector3(move.z*0.10,0,-move.x*0.12)}
		var drive := "Boost_"+direction+"_Drive"
		var catch_key := "Boost_"+direction+"_Catch"
		keys[drive] = _boost_drive(move,lead,1.0)
		keys[catch_key] = {"hover":1.0,"move_intent":-move*0.30,"lead":lead,"compression":0.62,
			"stance":Vector3(-0.19,0.13-maxf(move.z,0.0)*0.14,0),
			"body_shift":Vector3(0,0,-maxf(move.z,0.0)*0.094),
			"ankle_aim":Vector3(BOOST_ANKLE_TRIM-move.z*(0.30 if move.z<0.0 else 0.24),0,move.x*0.16)}
		studies["Boost_"+direction] = _boost_study(gather,drive,catch_key)

	for load_variant in [["Soft",0.55],["Heavy",1.25]]:
		var name: String = "Boost_Forward_"+load_variant[0]
		keys[name] = _boost_drive(Vector3.BACK,1.0,load_variant[1])
		studies[name] = _boost_study("Hover_Forward",name,"Boost_Forward_Catch")

	for side: String in ["Left","Right"]:
		var sign := 1.0 if side=="Left" else -1.0
		var slip := "Flight_Slip_"+side
		var bank_hold := "Bank_Hold_"+side
		var bank_arrest := "Bank_Arrest_"+side
		var yaw_start := "Yaw_"+side+"_Lead"
		var yaw_hold := "Yaw_"+side+"_Hold"
		var yaw_arrest := "Yaw_"+side+"_Arrest"
		var brake := "Brake_"+side
		var retro := "Retro_Brace_"+side
		var reach := "Landing_Reach_"+side
		var catch_key := "Landing_Catch_"+side
		var skid := "Landing_Skid_"+side
		var roll_abort := "Roll_"+side+"_Abort"
		var roll_arrest := "Roll_"+side+"_Arrest"
		keys[slip] = {"fighter":0.75,"coast":0.25,"track":0.8,"pressure":0.7,"flow":Vector3(sign,0.6,0),
			"steer":Vector3(0,sign*0.38,sign*0.32),"lead":sign,"preview":Vector3(-81,sign*18,sign*12)}
		keys[bank_hold] = {"fighter":1.0,"track":1.0,"bank_gesture":sign*0.65,"lead":sign,"preview":Vector3(-90,0,sign*35)}
		keys[bank_arrest] = {"fighter":1.0,"track":1.0,"bank_gesture":sign*0.2,"steer":Vector3(0,0,-sign*0.65),
			"lead":-sign,"preview":Vector3(-90,0,sign*32)}
		keys[yaw_start] = {"hover":1.0,"steer":Vector3(0,sign,0),"lead":sign,"preview":Vector3(0,0,0)}
		keys[yaw_hold] = {"hover":1.0,"steer":Vector3(0,sign*0.48,0),"lead":sign,"preview":Vector3(0,0,sign*19)}
		keys[yaw_arrest] = {"hover":1.0,"steer":Vector3(0,-sign*0.65,0),"lead":-sign,"preview":Vector3(0,0,sign*28)}
		keys[brake] = {"coast":1.0,"brake":1.0,"steer":Vector3(0.15,sign*0.35,sign*0.45),
			"brake_turn":Vector3(0.15,-sign*0.6,sign*0.75),"lead":sign,"preview":Vector3(-32,sign*14,sign*24)}
		keys[retro] = {"coast":1.0,"retro":1.0,"g_load":1.9,"compression":0.42,"asymmetry":1.0,"lead":sign,
			"lead_leg":Vector3(-0.10,0.22,-0.1),"trail_leg":Vector3(0.14,-0.12,0.08),"preview":Vector3(9,0,sign*12)}
		keys[reach] = {"land":0.78,"coast":0.22,"lead":sign,"feet":Vector2(2.5,8) if sign>0 else Vector2(8,2.5),
			"foot_inset":Vector2(0,6) if sign>0 else Vector2(6,0),"body_shift":Vector3(-sign*0.10,0,0.15),
			"support_lean":sign*0.45,"preview":Vector3(-4,0,-sign*4)}
		keys[catch_key] = {"land":1.0,"lead":sign,"compression":0.83,"g_load":2.4,"pelvis_drop":0.20,
			"feet":Vector2(0,7) if sign>0 else Vector2(7,0),"body_shift":Vector3(-sign*0.23,0,0.18),
			"foot_inset":Vector2(0,8) if sign>0 else Vector2(8,0),
			"support_lean":sign,"chest_offset":Vector3(0.08,0,-sign*0.18),"preview":Vector3(-4,0,-sign*3)}
		keys[skid] = {"land":0.8,"coast":0.2,"compression":0.8,"ground_skid":0.85,"lead":sign,
			"feet":Vector2(0,3) if sign>0 else Vector2(3,0),"contact_shift":Vector2(-sign*9,0),
			"body_shift":Vector3(-sign*0.31,0,0.18),"support_lean":sign*0.8,"preview":Vector3(-5,sign*7,-sign*4)}
		keys[roll_abort] = {"coast":1.0,"acro":Vector2(0,0.85),"acro_sign":Vector2(0,sign),
			"acro_recovery":Vector2(0,1),"roll_degrees":105}
		keys[roll_arrest] = {"fighter":0.8,"coast":0.2,"track":0.8,"acro":Vector2(0,0.45),"acro_sign":Vector2(0,sign),
			"acro_recovery":Vector2(0,1),"steer":Vector3(0,0,-sign*0.52),"roll_degrees":348}
		studies["Bank_"+side] = [[0.0,"Flight_Sustain"],[0.35,"Bank_"+side],[0.75,bank_hold],[1.12,"Bank_Pull_"+side],[1.51,bank_arrest],[2.07,"Flight_Sustain"]]
		studies["Yaw_"+side] = [[0.0,"Hover_Neutral"],[0.27,yaw_start],[0.64,yaw_hold],[0.98,yaw_arrest],[1.54,"Hover_Neutral"]]
		studies["Slip_"+side] = [[0.0,"Flight_Sustain"],[0.55,slip],[1.13,"Cutoff_Release"],[1.64,"Coast_Detached"],[2.20,"Coast_Compact"]]
		studies["Airbrake_"+side] = [[0.0,"Flight_Sustain"],[0.30,"Brake_Open"],[0.68,brake],[1.03,retro],[1.36,"Retro_Release"],[1.74,"Retro_Outbound"],[2.16,"Hover_Neutral"]]
		studies["Landing_One_Foot_"+side] = [[0.0,"Landing_Guard"],[0.33,reach],[0.54,catch_key],[1.16,"Landing_Settle"]]
		studies[skid] = [[0.0,"Landing_Guard"],[0.33,reach],[0.54,catch_key],[0.80,skid],[1.13,skid],[1.61,"Landing_Settle"]]

	for entry in [["Initiate",55],["Corkscrew",180],["Open",310]]:
		keys["Roll_Right_"+entry[0]] = {"coast":1.0,"acro":Vector2(0,1),"acro_sign":Vector2(0,-1),"roll_degrees":entry[1],"lead":-1.0}
	studies["Roll_Right"] = [[0.0,"Flight_Sustain"],[0.53,"Roll_Right_Initiate"],[1.46,"Roll_Right_Corkscrew"],[2.42,"Roll_Right_Open"],[2.69,"Roll_Right_Arrest"],[3.05,"Flight_Sustain"]]
	studies["Roll_Left_Abort"] = [[0.0,"Flight_Sustain"],[0.53,"Roll_Initiate"],[0.97,"Roll_Left_Abort"],[1.62,"Bank_Arrest_Left"],[2.21,"Flight_Sustain"]]
	studies["Roll_Right_Abort"] = [[0.0,"Flight_Sustain"],[0.53,"Roll_Right_Initiate"],[0.97,"Roll_Right_Abort"],[1.62,"Bank_Arrest_Right"],[2.21,"Flight_Sustain"]]

static func _boost_drive(move: Vector3, lead: float, load: float) -> Dictionary:
	return {"hover":1.0,"move_intent":move*0.60,"translate":move*0.60,"lead":lead,
		"drive":minf(load*0.64,1.0),"asymmetry":0.85,"compression":0.32*load,
		"shoulder_brace":maxf(load-1.0,0.0)*0.65,"chest_offset":Vector3(0.12,0,0)*maxf(load-1.0,0.0),
		"body_shift":Vector3(move.x*0.004,0,move.z*0.02-absf(move.x)*0.06+minf(move.z,0.0)*0.116),
		"lead_leg":Vector3(0.08,-0.16,0.0)*load,"trail_leg":Vector3(-0.08,0.17,0.0)*load,
		"ankle_aim":Vector3(BOOST_ANKLE_TRIM+move.z*0.30*load,0,-move.x*0.20*load)}

static func _boost_study(gather: String, drive: String, catch_key: String) -> Array:
	return [[0.0,"Hover_Neutral"],[0.13,gather],[0.40,drive],[0.55,drive],[0.86,catch_key],[1.38,"Hover_Neutral"]]
