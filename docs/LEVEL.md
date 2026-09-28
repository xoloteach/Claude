# DOCKYARD — level notes

Golden-hour industrial port. The map is built entirely in code by `scripts/world/level.gd` and its helpers. There are no scene files.

Axes: **X = east, Z = south, Y = up**. In the web bridge, `face <yaw> <pitch>` uses yaw 0 = north (−Z) and +90 = west.
The sun sits low in the **west-south-west** (≈11.5° elevation), over the water.

## Files

| File | Role |
|---|---|
| `scripts/world/level.gd` | Public API, materials, environment, quality tiers, navmesh bake, spawns, cover points, menu path, self-check |
| `scripts/world/wkit.gd` | Build kit. Merges geometry per material and 40 m cell into ArrayMeshes, groups collision by surface, instances glb props via MultiMesh, generates the noise textures |
| `scripts/world/containers.gd` | ISO 20ft/40ft containers (2.44 × 2.59 × 6.06 / 12.19 m): geometric corrugation, posts, rails, castings, door bars/cams/handles/hinges, open-door variant, LOD variant |
| `scripts/world/dock_layout.gd` | Ground zones, quay, water, ship, gantry cranes, container yard, stairs/catwalks, boundaries, spawn list |
| `scripts/world/dock_buildings.gd` | Wall-with-openings helper, warehouse (racking, trusses, sun shafts, portacabin), office, gate booth, pump house/tanks |
| `scripts/world/dock_dressing.gd` | Markings, decals, prop clusters, vehicles, lamps/floodlights, signage, particles |
| `scripts/world/dock_backdrop.gd` | Distant cranes/ship, stacks, sheds, tank farm, chimneys, pylons, city skyline, hills, breakwater + lighthouse |
| `assets/shaders/world_surface.gdshader` | World-space triplanar PBR. Also: macro variation, vertex-colour tint, fake contact AO/grime (repeats per container level through `stack_h`), rust streaks, `flatten` |
| `assets/shaders/world_water.gdshader` | Scrolling normals, fresnel, sun glitter, analytic foam at the quay wall/ship hull. No depth or screen textures |
| `world_paint` / `world_blob` / `world_wet` | Worn paint markings (opaque + discard) / multiplicative AO, oil and joint decals / puddles and dirt patches. All three pull slightly toward the camera to avoid z-fighting |
| `world_shaft` / `world_backdrop` | Additive fake light shafts / distant silhouettes with procedural lit windows |

## Layout (playable x −56..63, z −62..63)

- **West lane: quay** (x −56..−42). This is the long N–S sniper lane, about 120 m, with sparse cover: barriers, cable drums, a barrel cluster and 20ft containers.
  - Bollards, fenders and mooring lines run along the edge.
  - The moored ship hull (side at x −61) runs north of z −18.
  - Two gantry cranes: crane 1 at z −30 (boom down over the ship) and crane 2 at z 36 (boom raised).
  - The quay edge has an invisible wall.
- **Middle lane: container yard** (x −42..8). Four rows: A z −42, B z −22, C z 6, D z 28.
  - Column groups (x centres): G1 −38.4/−35.9, G2 −28.6/−26.1/−23.6, G3 −15/−12.5, G4 −5.2/−2.7/−0.2.
  - Stacks are 1–4 high.
  - The central lane is x −22..−16. An E–W cross road runs at z −12..−4.
  - **Verticality:**
    - A steel stair at (1.9, 0, −12.3) rises north to the B-04 platform at 5.18 m.
    - Catwalks at 5.18 m run B-04 → B-03 → B-02, crossing over the central lane.
    - Pallet-and-crate steps (1.06 m) stand next to eight 1-high containers. Players can mantle up in two steps.
- **Road** x 8..18 (N–S). It has lamps, a parked container truck at (15.6, 16) and a forklift.
- **East lane: warehouse** x 18..60, z −48..6 (CQB).
  - Doors: west z −39..−33 (open) and z −11..−5 (shutter half down), south x 25..31 and 44..50, north x 36..42. Personnel doors are on the west and east walls.
  - Racking rows run at x 25, 33 and 41 (double) and x 58.3 (single). The bottom shelves carry waist-high goods, with see-through gaps above.
  - The south part is an open staging area with a portacabin.
  - Sun shafts come in through the west clerestory windows.
- **East alley** x 60..63 is a flank route behind the warehouse.
- **Office** x 22..38, z 34..46, two storeys (upper floor at 3.5 m). There is an external stair on the west side and an internal stair on the east side. The upper-floor control room overlooks the yard.
- **South truck yard / gate** z 48..63. This is the player spawn area. It has a gate booth, a parked trailer and barrier funnels.
- **North service road** z −62..−48. This is the enemy side. It has barricades, a fuel-tank enclosure and a pump house. The north boundary is a wall of containers stacked 3–4 high.

**Player spawn:** (−4, 0, 55), yaw 8°, looking north up the yard.

**Enemy spawns:** 16 points along the north road, the east alley, inside the warehouse, on the quay and on the cross road. They are validated against the navmesh.

**Cover points:** about 890, generated around every cover box and snapped to the navmesh.

## Quality tiers (`apply_quality`)

- **0 (low):** only the fire-barrel flames stay on. Dust is off. Detail visibility range is 45 m.
- **1 (medium):** about 14 lights (street lamps, 2 floodlights, warehouse, office, fire, fluorescent), smoke plumes and 60 dust motes. Range 70 m.
- **2 (high):** every light and spot, sparks light, crane beacon and 140 dust motes. Range 110 m.

No omni light casts shadows.

## Testing

- `godot --headless -- --test --level-check` prints `[level-check]` lines: spawn validity, capsule clearance, navmesh paths from the spawn to every key area and enemy spawn, and the cover-point count.
- `--level-stats` also prints the vertex count per material.
- On web, evaluating `window.level_stats = 1` prints draw calls, objects and primitives every 5 s.
- `node tools/playtest.mjs level_a|level_b --viewport 960x540` produces review screenshots in `tools/shots/level_a|b/`.

## Performance

These numbers come from the web build under SwiftShader at quality 1.

- **Build:** about 3.3 s. Around 2 s of that is loading textures and making the noise textures.
- **Navmesh bake:** about 0.18 s.
- **Geometry:** about 630k merged vertices in 448 batches.
- **Draw calls:** 190–590 in the busiest views, with 90k–440k primitives including shadow passes.

## Known issues

- Crane steel still shows faint paint-chip speckle.
- The water uses no depth, so it has no depth-based shoreline colour.
- ReflectionProbe ambient-override interiors depend on Compatibility probe support.
- The ornate glb street lamp is stylistically a little off for a port.
