class_name WorldGenerator
extends Node3D
## Seed-based, chunked, infinite world generation.
##
## How it works
## ------------
## * The world is split into square chunks of `chunk_size` metres.
## * Chunks within `view_distance` of the `target` (the player) are generated;
##   chunks that fall too far behind are freed.
## * Every chunk is generated from its own RandomNumberGenerator, seeded from
##   (world_seed, chunk coordinate). A chunk therefore always comes out the same
##   no matter when it is generated or in which order - that's what makes the
##   world reproducible from the seed alone.
## * A low-frequency noise field (also driven by the seed) decides where
##   vegetation is dense, so trees form forests and clearings.
##
## Seed
## ----
## Set `world_seed` in the inspector, tick `randomize_seed`, or launch with
## `-- --seed=1234` / `-- --seed=any text` (text is hashed into a number).

signal chunk_generated(chunk: Chunk)
signal chunk_unloaded(coord: Vector2i)

const GROUND_SCENE: PackedScene = preload("res://scenes/ground.tscn")
const TREE_PINE_SCENE: PackedScene = preload("res://scenes/objects/tree_pine.tscn")
const TREE_OAK_SCENE: PackedScene = preload("res://scenes/objects/tree_oak.tscn")
const BUSH_SMALL_SCENE: PackedScene = preload("res://scenes/objects/bush_small.tscn")
const BUSH_BERRY_SCENE: PackedScene = preload("res://scenes/objects/bush_berry.tscn")

## Chunk coordinate used before the first update (never a real chunk).
const NO_CHUNK := Vector2i(1 << 30, 1 << 30)

@export_group("Seed")
@export var world_seed: int = 12345
## Pick a new random seed every launch (ignored if a --seed= argument is given).
@export var randomize_seed: bool = false

@export_group("Chunks")
## The node chunks are generated around (normally the player).
@export var target: Node3D
## Edge length of a chunk in metres.
@export var chunk_size: float = 32.0
## Radius, in chunks, that is kept generated around the target.
@export_range(1, 16) var view_distance: int = 3
## Max chunks generated per frame while streaming (keeps frame times smooth).
@export_range(1, 16) var chunks_per_frame: int = 2
## Chunks within this radius are generated immediately on startup, so the
## player never spawns above empty space.
@export_range(0, 4) var initial_sync_radius: int = 1

@export_group("Vegetation")
## Size of vegetation patches: lower = bigger forests / clearings.
@export var vegetation_frequency: float = 0.01
## Radius around world origin (the spawn point) that is kept free of objects.
@export var spawn_clearing_radius: float = 6.0
## What gets scattered. Leave empty to use the built-in defaults.
@export var spawn_table: Array[SpawnEntry] = []

var _chunks: Dictionary[Vector2i, Chunk] = {}
var _pending: Array[Vector2i] = []
var _center_chunk: Vector2i = NO_CHUNK
var _vegetation_noise: FastNoiseLite


func _ready() -> void:
	_apply_command_line_seed()
	if randomize_seed:
		world_seed = randi()
	_setup_noise()
	if spawn_table.is_empty():
		spawn_table = _default_spawn_table()
	print("[WorldGenerator] seed = %d" % world_seed)

	if target == null:
		push_warning("WorldGenerator: no target assigned, no chunks will be generated.")
		return
	_center_chunk = world_to_chunk(target.global_position)
	_refresh_chunks()
	# Build the ground right under the player before the first physics frame.
	while not _pending.is_empty() and _chunk_distance(_pending[0]) <= initial_sync_radius + 0.5:
		_generate_chunk(_pending.pop_front())


func _process(_delta: float) -> void:
	if target == null:
		return
	var current := world_to_chunk(target.global_position)
	if current != _center_chunk:
		_center_chunk = current
		_refresh_chunks()
	_process_queue(chunks_per_frame)


# --------------------------------------------------------------------------- #
# Public API
# --------------------------------------------------------------------------- #

## Chunk coordinate that contains the given world position.
func world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(floori(world_pos.x / chunk_size), floori(world_pos.z / chunk_size))


## Terrain height at a world X/Z position. The ground is flat for now; this is
## the single place to hook real terrain into later (objects already use it).
func terrain_height(_x: float, _z: float) -> float:
	return 0.0


## Throws away the current world and rebuilds it from a new seed.
func regenerate(new_seed: int) -> void:
	world_seed = new_seed
	_setup_noise()
	for coord: Vector2i in _chunks.keys():
		_unload_chunk(coord)
	_pending.clear()
	_center_chunk = NO_CHUNK  # forces a refresh on the next frame
	print("[WorldGenerator] seed = %d" % world_seed)


# --------------------------------------------------------------------------- #
# Chunk streaming
# --------------------------------------------------------------------------- #

func _chunk_distance(coord: Vector2i) -> float:
	return Vector2(coord - _center_chunk).length()


## Unloads chunks that are too far away and queues the missing nearby ones,
## nearest first.
func _refresh_chunks() -> void:
	var unload_distance := view_distance + 1.5  # hysteresis: avoids load/unload flicker
	for coord: Vector2i in _chunks.keys():
		if _chunk_distance(coord) > unload_distance:
			_unload_chunk(coord)

	_pending.clear()
	for dz in range(-view_distance, view_distance + 1):
		for dx in range(-view_distance, view_distance + 1):
			var coord := _center_chunk + Vector2i(dx, dz)
			if _chunk_distance(coord) <= view_distance + 0.5 and not _chunks.has(coord):
				_pending.append(coord)
	_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_distance(a) < _chunk_distance(b))


func _process_queue(budget: int) -> void:
	while budget > 0 and not _pending.is_empty():
		var coord: Vector2i = _pending.pop_front()
		if not _chunks.has(coord):
			_generate_chunk(coord)
			budget -= 1


func _unload_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = _chunks[coord]
	_chunks.erase(coord)
	chunk.queue_free()
	chunk_unloaded.emit(coord)


# --------------------------------------------------------------------------- #
# Chunk generation
# --------------------------------------------------------------------------- #

func _generate_chunk(coord: Vector2i) -> Chunk:
	var chunk := Chunk.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.coord = coord
	chunk.position = Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)

	# Fill the chunk while it's still outside the tree (cheaper), then add it.
	_build_ground(chunk)
	_populate_chunk(chunk)

	add_child(chunk)
	_chunks[coord] = chunk
	chunk_generated.emit(chunk)
	return chunk


func _build_ground(chunk: Chunk) -> void:
	var ground := GROUND_SCENE.instantiate() as Ground
	ground.size = chunk_size
	ground.position = Vector3(chunk_size * 0.5, 0.0, chunk_size * 0.5)
	chunk.add_child(ground)


func _populate_chunk(chunk: Chunk) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(chunk.coord)
	var chunk_origin := Vector2(chunk.coord) * chunk_size

	# Footprints already used in this chunk (local X/Z + radius).
	var placed_positions := PackedVector2Array()
	var placed_radii := PackedFloat32Array()

	for entry in spawn_table:
		if entry == null or entry.scene == null:
			continue
		# Keeping every footprint inside the chunk by its own radius guarantees
		# objects in neighbouring chunks can never overlap, with no cross-chunk
		# bookkeeping.
		var margin := entry.radius * entry.max_scale
		if chunk_size - margin * 2.0 <= 0.0:
			continue

		for _attempt in entry.attempts_per_chunk:
			# Always draw the same random values per attempt, so one attempt's
			# outcome never shifts the random stream of the next.
			var local := Vector2(
				rng.randf_range(margin, chunk_size - margin),
				rng.randf_range(margin, chunk_size - margin))
			var roll := rng.randf()
			var scale_roll := rng.randf()
			var yaw := rng.randf() * TAU

			var world_xz := chunk_origin + local
			if world_xz.length() < spawn_clearing_radius + entry.radius:
				continue
			if roll > entry.density_at(_vegetation_value(world_xz)):
				continue

			var object_scale := lerpf(entry.min_scale, entry.max_scale, scale_roll)
			var footprint := entry.radius * object_scale
			if _overlaps(local, footprint, placed_positions, placed_radii):
				continue

			var instance := entry.scene.instantiate() as Node3D
			instance.position = Vector3(local.x, terrain_height(world_xz.x, world_xz.y), local.y)
			if entry.random_rotation:
				instance.rotation.y = yaw
			instance.scale = Vector3.ONE * object_scale
			chunk.add_child(instance)

			placed_positions.append(local)
			placed_radii.append(footprint)


func _overlaps(local: Vector2, footprint: float, positions: PackedVector2Array, radii: PackedFloat32Array) -> bool:
	for i in positions.size():
		var min_distance := footprint + radii[i]
		if local.distance_squared_to(positions[i]) < min_distance * min_distance:
			return true
	return false


# --------------------------------------------------------------------------- #
# Seed + noise
# --------------------------------------------------------------------------- #

## Deterministic per-chunk seed (classic spatial hash of seed and coordinate).
func _chunk_seed(coord: Vector2i) -> int:
	return (world_seed * 73856093) ^ (coord.x * 19349663) ^ (coord.y * 83492791)


func _setup_noise() -> void:
	_vegetation_noise = FastNoiseLite.new()
	_vegetation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_vegetation_noise.seed = world_seed
	_vegetation_noise.frequency = vegetation_frequency
	_vegetation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_vegetation_noise.fractal_octaves = 2


## Vegetation density field at a world X/Z position, roughly in -1..1.
func _vegetation_value(world_xz: Vector2) -> float:
	return _vegetation_noise.get_noise_2d(world_xz.x, world_xz.y)


func _apply_command_line_seed() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			var value := arg.substr("--seed=".length())
			world_seed = value.to_int() if value.is_valid_int() else value.hash()
			randomize_seed = false


# --------------------------------------------------------------------------- #
# Default spawn table
# --------------------------------------------------------------------------- #

func _default_spawn_table() -> Array[SpawnEntry]:
	var table: Array[SpawnEntry] = []

	# Pines: dense forests where the vegetation noise is high.
	table.append(_make_entry(TREE_PINE_SCENE, {
		"attempts_per_chunk": 28,
		"chance": 0.9,
		"noise_min": 0.05,
		"radius": 1.4,
		"min_scale": 0.8,
		"max_scale": 1.3,
	}))
	# Oaks: mid-range noise, so they dominate forest edges and mixed woods.
	table.append(_make_entry(TREE_OAK_SCENE, {
		"attempts_per_chunk": 14,
		"chance": 0.8,
		"noise_min": -0.4,
		"noise_max": 0.3,
		"radius": 1.8,
		"min_scale": 0.8,
		"max_scale": 1.25,
	}))
	# Bushes: everywhere except the barest areas.
	table.append(_make_entry(BUSH_SMALL_SCENE, {
		"attempts_per_chunk": 22,
		"chance": 0.5,
		"noise_min": -0.5,
		"radius": 0.8,
		"min_scale": 0.7,
		"max_scale": 1.4,
	}))
	table.append(_make_entry(BUSH_BERRY_SCENE, {
		"attempts_per_chunk": 8,
		"chance": 0.5,
		"noise_min": -0.2,
		"radius": 0.8,
		"min_scale": 0.8,
		"max_scale": 1.2,
	}))
	return table


func _make_entry(scene: PackedScene, properties: Dictionary) -> SpawnEntry:
	var entry := SpawnEntry.new()
	entry.scene = scene
	for key: String in properties:
		entry.set(key, properties[key])
	return entry
