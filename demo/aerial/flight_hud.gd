extends CanvasLayer

# Existing readout for the DCS/Elite Dangerous flight model; never drives physics.
const AerialMech = preload("res://aerial/aerial_mech.gd")
var flight_stats: Label

func _ready() -> void:
	layer = 2
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(panel)
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_top = 18
	var label := Label.new()
	label.text = "GUNDAM · PHYSICS FLIGHT\nW/S: pitch · A/D: bank / roll · Q/E: yaw\nHover direction tap: 4× burst / 0.5s · cooldown 1s · Ctrl: precision\nSpace / C: thrust 0 → 0.5 → 1 → 2 → 4× · R: thruster launch\nShift: brake / spread · Mouse: look\nMMB / Tab: focus · Esc: release · Wheel: zoom · Home: camera reset\nP: pause · G: walk preview · F9: force vectors · 1/2: palette · 3/4: weather · F8: explosion"
	label.add_theme_color_override("font_color",Color(1,0.93,0.82))
	label.add_theme_font_size_override("font_size",15)
	panel.add_child(label)
	flight_stats = Label.new()
	flight_stats.text = "ASSIST · THRUST 1.0×"
	panel.add_child(flight_stats)
	for text in [label,flight_stats]:
		text.add_theme_constant_override("outline_size",3)
		text.add_theme_color_override("font_outline_color",Color(0.03,0.04,0.06,0.85))

func update_status(mech: AerialMech) -> void:
	var fc = mech.controller
	var warning := ""
	if fc.time_to_impact < 2.4: warning = " · TERRAIN %.1fs%s"%[fc.time_to_impact," — PULL UP"]
	flight_stats.text = "THRUST %.1f× · ENGINE %.2f× · %.0f m/s · HOVER %.0f%% · AERO %.0f%% · %.1f G%s\nREQUEST %.0f kN · DELIVERED %.0f kN · RCS %.0f%%%s%s" % [
		fc.DETENTS[fc.detent], fc.thrust_level, fc.velocity.length(), fc.hover_assist * 100, fc.aero_authority * 100, fc.g_load, warning,
		fc.requested_thrust / 1000, fc.delivered_thrust / 1000, fc.rcs_load * 100,
		" · TORQUE LIMIT" if fc.torque_saturated else "", " · GIMBAL LIMIT" if fc.motor_saturated else ""]
	flight_stats.text += " · BOOST " + ("ACTIVE" if fc.burst_remaining > 0 else ("%.1fs" % fc.burst_cooldown if fc.burst_cooldown > 0 else "READY"))
	if mech.debug_forces:
		flight_stats.text += "\nMOMENT kNm · MAIN %.0f · AIR %.0f · COLD GAS %.0f"%[fc.main_torque.length()/1000,fc.aero_torque.length()/1000,fc.rcs_torque.length()/1000]
		var weights: PackedFloat32Array = mech.rig.posture_weights
		var feet = mech.rig.contacts
		flight_stats.text += "\nPOSE H %.0f / FLIGHT %.0f / SPREAD %.0f / COAST %.0f / LAND %.0f%%\nFEET %s/%s · PROBES %d · IMPACT %.2f" % [weights[0]*100,weights[1]*100,weights[2]*100,weights[3]*100,weights[4]*100,"PLANT" if feet.planted[0] else "FREE","PLANT" if feet.planted[1] else "FREE",feet.probe_count,feet.impact]
	flight_stats.modulate = Color(1,0.4,0.25) if fc.time_to_impact < 2.4 else Color.WHITE
