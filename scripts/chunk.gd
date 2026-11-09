class_name Chunk
extends Node3D
## A square piece of the world. It only holds the generated nodes (ground tile
## and scattered objects); all generation logic lives in WorldGenerator.
##
## The chunk's origin is its minimum (-X, -Z) corner, so a child at local
## position (x, y, z) sits at world position coord * chunk_size + (x, y, z).

var coord: Vector2i = Vector2i.ZERO
