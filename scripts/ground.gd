@tool
class_name Ground
extends StaticBody3D
## Flat, editable ground tile. The top surface is at local y = 0.
##
## Change `size` (in the inspector or from code) and both the visible plane and
## the collision box follow. WorldGenerator places one of these per chunk, so a
## future heightmap/terrain editor can replace this scene without touching the
## generator.

## Edge length of the square tile in metres.
@export var size: float = 32.0:
	set(value):
		size = maxf(value, 0.1)
		_apply_size()

## Thickness of the collision slab below the surface.
@export var thickness: float = 1.0:
	set(value):
		thickness = maxf(value, 0.1)
		_apply_size()

@onready var _mesh_instance: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $Collision


func _ready() -> void:
	_apply_size()


func _apply_size() -> void:
	# Setters also run while the scene is loading, before the child nodes exist.
	if not is_node_ready():
		return
	var plane := _mesh_instance.mesh as PlaneMesh
	if plane:
		plane.size = Vector2(size, size)
	var box := _collision.shape as BoxShape3D
	if box:
		box.size = Vector3(size, thickness, size)
	_collision.position.y = -thickness * 0.5
