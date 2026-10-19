@tool
extends Node3D

const FACTORY_MATERIAL: ShaderMaterial = preload("res://materials/materials/factory-cel.tres")

func _ready() -> void:
	_apply_material(get_node("ground-2/factory"))
	_apply_material(get_node("box-small2"))

func _apply_material(root: Node) -> void:
	if root is MeshInstance3D:
		root.material_override = FACTORY_MATERIAL
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.material_override = FACTORY_MATERIAL
