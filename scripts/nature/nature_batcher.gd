@tool
class_name NatureBatcher
extends Node3D
## Sammelt Deko-Modelle (Bäume, Büsche, Steine …) für die Quest:
## Im Editor sind alle Kinder normale, verschiebbare Instanzen.
## Beim Spielstart werden gleiche Meshes zu je einem MultiMesh zusammengefasst
## (wenige Draw Calls), die Originale entfernt.
## Außerdem: Blätter von "weich transparent" auf Alpha Scissor (harte Kante, viel günstiger),
## optional Normal-Maps aus, und Pflanzen bewegen sich im Wind (Vertex-Shader, sehr günstig).

## Blätter mit harter Kante statt weicher Transparenz (empfohlen für Quest).
@export var alpha_scissor := true
@export_range(0.0, 1.0, 0.01) var alpha_threshold := 0.5
## Normal-Maps abschalten (spart Leistung, im Comic-Stil kaum sichtbar).
@export var disable_normal_maps := true
## Kinder, deren Name einen dieser Begriffe enthält, bekommen einen Stamm-Kollider.
@export var trunk_keywords: PackedStringArray = PackedStringArray(["Tree", "Pine"])
@export_range(0.0, 2.0, 0.05) var trunk_radius := 0.35

@export_group("Wind")
@export var wind_enabled := true
## Windrichtung in der Welt (x, z).
@export var wind_direction := Vector2(1.0, 0.3)
@export_range(0.0, 5.0, 0.05) var wind_speed := 1.0
## Bäume: Kinder mit diesen Begriffen im Namen.
@export var tree_keywords: PackedStringArray = PackedStringArray(["Tree", "Pine"])
## Ausschlag der Baumkrone (m) auf Höhe tree_sway_height.
@export_range(0.0, 1.0, 0.01) var tree_sway := 0.18
@export_range(0.5, 20.0, 0.5) var tree_sway_height := 8.0
@export_range(0.0, 0.1, 0.002) var tree_flutter := 0.02
## Kleine Pflanzen: Kinder mit diesen Begriffen im Namen.
@export var plant_keywords: PackedStringArray = PackedStringArray(["Bush", "Fern", "Flower", "Plant", "Clover", "Grass"])
@export_range(0.0, 0.5, 0.005) var plant_sway := 0.05
@export_range(0.1, 3.0, 0.05) var plant_sway_height := 1.0
@export_range(0.0, 0.05, 0.001) var plant_flutter := 0.008
static var _mat_cache := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_batch()


func _batch() -> void:
	var groups := {} # Mesh -> Array[Transform3D]
	var kinds := {} # Mesh -> 0 = ohne Wind, 1 = Baum, 2 = Pflanze
	var inv := global_transform.affine_inverse()
	var trunks: Array[Vector3] = []
	for child in get_children():
		if not (child is Node3D):
			continue
		for mi: MeshInstance3D in _meshes_of(child):
			if mi.mesh == null or not mi.visible:
				continue
			var key := mi.mesh
			if not groups.has(key):
				groups[key] = []
				kinds[key] = _kind_of(child.name)
			groups[key].append(inv * mi.global_transform)
		for kw in trunk_keywords:
			if kw in child.name:
				trunks.append(inv * (child as Node3D).global_position)
				break
	for child in get_children():
		child.queue_free()
	for mesh: Mesh in groups:
		var xforms: Array = groups[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _fixed_mesh(mesh, kinds[mesh])
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "MM_" + str(mesh.resource_name if mesh.resource_name != "" else mesh.get_instance_id())
		add_child(mmi)
	if not trunks.is_empty() and trunk_radius > 0.0:
		var body := StaticBody3D.new()
		body.name = "Trunks"
		add_child(body)
		var shape := CylinderShape3D.new()
		shape.radius = trunk_radius
		shape.height = 4.0
		for p in trunks:
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = p + Vector3(0, 2.0, 0)
			body.add_child(cs)


func _meshes_of(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.find_children("*", "MeshInstance3D", true, false):
		out.append(c)
	return out


func _kind_of(n: String) -> int:
	if not wind_enabled:
		return 0
	for kw in tree_keywords:
		if kw in n:
			return 1
	for kw in plant_keywords:
		if kw in n:
			return 2
	return 0


# Kopie des Meshes mit Quest-tauglichen Materialien (pro Mesh nur einmal).
func _fixed_mesh(mesh: Mesh, kind: int) -> Mesh:
	var m: Mesh = mesh.duplicate()
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		if kind == 0:
			m.surface_set_material(s, _fixed_material(mat))
		else:
			var cutout := mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var tree := kind == 1
			m.surface_set_material(s, NatureWind.material(mat, cutout and alpha_scissor, alpha_threshold,
				tree_sway if tree else plant_sway, tree_sway_height if tree else plant_sway_height,
				tree_flutter if tree else plant_flutter, wind_direction, wind_speed))
	return m


func _fixed_material(mat: Material) -> Material:
	if not (mat is BaseMaterial3D):
		return mat
	var key := [mat, alpha_scissor, alpha_threshold, disable_normal_maps]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m: BaseMaterial3D = mat.duplicate()
	if alpha_scissor and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = alpha_threshold
	if disable_normal_maps:
		m.normal_enabled = false
	_mat_cache[key] = m
	return m
