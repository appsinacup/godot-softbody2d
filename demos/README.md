# SoftBody2D demos

Open `demo_hub.tscn` and press play, or `godot --path . res://demos/demo_hub.tscn`.
Everything is built in script, so there is nothing to re-bake when the plugin changes.

Left mouse drag pulls the blob, right mouse drag slices (demo 3), `R` resets, `Esc` goes back.

| # | Demo | What it shows |
|---|---|---|
| 1 | Joints | Squash, stretch and shear a blob. Softness, joint reach, angular limits, yield strain. |
| 2 | Breaking | Weights, wall impacts and yanks. Both break modes and interior strength. |
| 3 | Cutting | Slice with `cut()`; each piece keeps its own shape. |
| 4 | Scaling | Three blobs at `bake_scale` 0.6 / 1.0 / 1.6, landing together. |
| 5 | Joint stress | Every joint coloured by its load: how to pick a `break_force`. |
| 6 | Crush test | A slab presses the blob flat; readouts say how well it came back. |
| 7 | Edge fit | Particle size, shape, `edge_clearance`, `min_area`, `skin_smoothing`: shapes inside the texture, smooth edges. |
| 8 | Benchmark | Spawns softbodies until the frame rate gives, with fps, physics time and counts. |
| 9 | Plasticity | Elastic and clay side by side; deform both, one keeps the dent. |

Demo 2's break force slider is calibrated on this scene: resting 0, dropped weight ~220,
wall impact ~370, full yank ~800.

Demo 8 also runs unattended:
`godot res://demos/08_benchmark.tscn -- --benchmark-auto [--interval=N] [--reach=N] [--ticks=N]`

Without [Godot Rapier Physics](https://godot.rapier.rs) demo 2 falls back to distance
breaking and demo 5 colours joints by stretch; everything else is unaffected.
