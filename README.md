# polycraft
Minecraft-like procedurally generated open world survival game in a low-poly style made in Godot v4.7.2.

## Status
Early prototype: seed-based infinite world with trees and bushes, a flat ground, and first-person WASD movement.

## Running
Open the project in the Godot editor once (so it imports the assets and registers the `class_name` scripts), then press **F5**.

| Key | Action |
| --- | --- |
| W A S D | Move |
| Mouse | Look |
| Space | Jump |
| Shift | Sprint |
| Esc | Release the mouse (click the window to grab it again) |

## Project layout
```
assets/models/     low-poly models (.obj + .mtl)
assets/textures/   textures (grass.png)
scenes/            main.tscn, player.tscn, ground.tscn
scenes/objects/    tree_pine, tree_oak, bush_small, bush_berry
scripts/           player.gd, world_generator.gd, chunk.gd, ground.gd, spawn_entry.gd
tools/             generate_assets.py (rebuilds models + texture, stdlib only)
```

## World generation
`scripts/world_generator.gd` streams the world in square chunks (32 m) around the player.

* **Seed-based:** each chunk is generated from its own RNG seeded by `(world_seed, chunk coordinate)`, so a chunk is identical
  every time, in any generation order. A seed-driven noise field decides where vegetation is dense (forests vs. clearings).
* **Setting the seed:** `world_seed` on the `World` node in `main.tscn`, the `randomize_seed` checkbox, or at launch with
  `godot -- --seed=1234` (any non-numeric text is hashed, e.g. `--seed=hello`).
* **What spawns:** `spawn_table` (an array of `SpawnEntry` resources). Leave it empty to use the built-in defaults in
  `_default_spawn_table()`, or fill it in the inspector. Each entry has a scene, attempts per chunk, a noise range, a footprint
  radius and a scale range. Footprints never overlap, even across chunk borders.
* **Ground:** `scenes/ground.tscn` is a flat tile per chunk. `size` is editable; `terrain_height()` in the generator is the
  hook for real terrain later.
* **Tuning:** `view_distance`, `chunks_per_frame`, `vegetation_frequency` and `spawn_clearing_radius` are exported on the node.
  Fog density in `main.tscn` should roughly match the view distance to hide chunks popping in.

## Regenerating assets
`python3 tools/generate_assets.py` rewrites the four models and the grass texture deterministically.
