class_name SpawnEntry
extends Resource
## Describes one kind of object the world generator scatters across chunks
## (a tree type, a bush type, ...).
##
## Each chunk tries `attempts_per_chunk` random positions for this entry. A
## position is accepted with probability `chance`, scaled by how well the
## vegetation noise at that spot fits the [noise_min, noise_max] range. That is
## what makes forests clump together instead of being spread uniformly.

## The scene to instantiate. Its root must be a Node3D (or subclass).
@export var scene: PackedScene

## How many random positions are tried per chunk (an upper bound on the count).
@export_range(0, 200) var attempts_per_chunk: int = 10

## Base probability that a tried position is accepted (before the noise check).
@export_range(0.0, 1.0) var chance: float = 1.0

## Range of the vegetation noise (roughly -1..1) in which this object can spawn.
## Use the defaults to allow spawning everywhere.
@export_range(-2.0, 2.0) var noise_min: float = -2.0
@export_range(-2.0, 2.0) var noise_max: float = 2.0

## Width of the soft edge at both ends of the noise range.
@export_range(0.01, 1.0) var noise_feather: float = 0.15

## Footprint radius in metres (before scaling). Objects never overlap each
## other's footprints, including across chunk borders.
@export var radius: float = 1.0

@export var min_scale: float = 0.85
@export var max_scale: float = 1.2
@export var random_rotation: bool = true


## Spawn probability (0..1) for a given vegetation-noise value.
func density_at(noise_value: float) -> float:
	var feather := maxf(noise_feather, 0.001)
	var rising := smoothstep(noise_min, noise_min + feather, noise_value)
	var falling := 1.0 - smoothstep(noise_max - feather, noise_max, noise_value)
	return chance * rising * falling
