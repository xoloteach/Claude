# IRONLINE — Asset Credits & Notes

All third-party assets are **CC0 1.0** (public domain) or **SIL OFL 1.1** (fonts). No CC-BY assets are used,
so attribution is optional; it is given below anyway. Procedurally generated assets were made for this repo
and are also released as CC0.

## PBR textures — `assets/textures/<name>/`

1K (1024²). `albedo.jpg` (sRGB), `normal.jpg` (**OpenGL / +Y**, as Godot expects), `roughness.jpg`,
plus `ao.jpg` / `metallic.jpg` where the source had a useful one.

| Folder | Source asset | Author | License | Look |
|---|---|---|---|---|
| concrete_floor | [ambientCG Concrete042A](https://ambientcg.com/view?id=Concrete042A) | ambientCG (Lennart Demes) | CC0 | Mid-grey worn, stained poured concrete |
| concrete_wall | [ambientCG Concrete030](https://ambientcg.com/view?id=Concrete030) | ambientCG | CC0 | Cool grey smooth cast concrete, subtle pores |
| asphalt | [ambientCG Asphalt026C](https://ambientcg.com/view?id=Asphalt026C) | ambientCG | CC0 | Dark cracked, patched asphalt |
| corrugated_metal | [Poly Haven container_side](https://polyhaven.com/a/container_side) | Dimitrios Savva | CC0 | Shipping-container corrugation. **Albedo desaturated to neutral light grey (mean ≈0.62)** so it can be tinted with `albedo_color` (red/blue/green/orange containers); dirt/streak detail kept |
| rusty_metal | [Poly Haven rusty_metal_02](https://polyhaven.com/a/rusty_metal_02) | Rob Tuytel | CC0 | Pale grey steel with heavy orange rust blooms |
| painted_metal | [ambientCG PaintedMetal010](https://ambientcg.com/view?id=PaintedMetal010) | ambientCG | CC0 | Off-white paint with rust-brown chips (tintable) |
| brick | [ambientCG Bricks097](https://ambientcg.com/view?id=Bricks097) | ambientCG | CC0 | Weathered dark-red industrial brick |
| plaster | [ambientCG Plaster007](https://ambientcg.com/view?id=Plaster007) | ambientCG | CC0 | Dirty off-white plaster, greenish grime |
| wood_planks | [ambientCG Planks023A](https://ambientcg.com/view?id=Planks023A) | ambientCG | CC0 | Weathered grey-brown horizontal planks (pallets/crates) |
| ground_dirt | [ambientCG Ground110](https://ambientcg.com/view?id=Ground110) | ambientCG | CC0 | Dark dirt with gravel & stones |
| metal_plate | [Poly Haven metal_plate](https://polyhaven.com/a/metal_plate) | Rob Tuytel | CC0 | Dark, grimy diamond tread plate (floors, ramps) |
| metal_grate | [ambientCG MetalWalkway006](https://ambientcg.com/view?id=MetalWalkway006) | ambientCG | CC0 | Square-mesh steel grating. `albedo_alpha.png` = albedo + opacity in alpha (use alpha scissor) |
| fabric_tarp | [ambientCG Fabric066](https://ambientcg.com/view?id=Fabric066) | ambientCG | CC0 | Olive-grey canvas weave |
| gun_metal | [ambientCG Metal046B](https://ambientcg.com/view?id=Metal046B) | ambientCG | CC0 | Dark worn blued/anodized steel, fine grain (metallic) |
| polymer | [ambientCG Plastic012A](https://ambientcg.com/view?id=Plastic012A) | ambientCG | CC0 | Near-black textured grip polymer |
| fabric_uniform | [ambientCG Fabric030](https://ambientcg.com/view?id=Fabric030) | ambientCG | CC0 | Neutral grey woven fabric (tintable) |
| camo_fabric | albedo procedurally generated (this repo); normal/roughness/ao from Fabric030 | IRONLINE / ambientCG | CC0 | Tileable 4-colour woodland camo |

## HDRI — `assets/hdri/sky.hdr`

[Poly Haven — Qwantani Sunset (Pure Sky)](https://polyhaven.com/a/qwantani_sunset_puresky), 2K, by Greg Zaal & Jarod Guest, CC0.
Clear golden-hour sky, small hot orange sun just above a hazy horizon (peak radiance ≈ 58 000 — great sun highlight).
"Pure sky" = no baked ground, so our geometry sits on the horizon cleanly.

**Sun position** (measured from the brightest pixels): equirect `u ≈ 0.600, v ≈ 0.466` → **elevation ≈ 6°**.
With Godot's panorama mapping (`u = atan2(dir.x, -dir.z)/2π`), **direction toward the sun ≈ (-0.584, 0.108, 0.804)**
(i.e. low in the +Z / −X quadrant, azimuth 216° measured from −Z toward +X).
Matching `DirectionalLight3D`: `rotation_degrees ≈ Vector3(-6.2, -35.8, 0)`
(light forward −Z must point *away* from the sun: (0.584, −0.108, −0.804)). If you rotate the sky via
`Environment.sky_rotation`, rotate the light by the same yaw.

## Props — `assets/models/props/` (Poly Haven, CC0, 1K glTF packed to .glb, embedded textures recompressed to 512px JPG)

| File | Source | Author | Size in Godot (m, x×y×z) |
|---|---|---|---|
| barrel_01.glb | [Barrel 01](https://polyhaven.com/a/Barrel_01) (red explosive drum) | Jorge Camacho | 0.56×0.88×0.56 |
| barrel_02.glb | [Barrel 03](https://polyhaven.com/a/barrel_03) (steel drum) | Serhii Khromov | 0.63×0.93×0.64 |
| concrete_barrier_01.glb | [Concrete Road Barrier](https://polyhaven.com/a/concrete_road_barrier) (jersey barrier) | Amal Kumar | 1.55×0.83×0.64 |
| concrete_barrier_02.glb | [Concrete Road Barrier 02](https://polyhaven.com/a/concrete_road_barrier_02) | Amal Kumar | 1.57×1.11×0.44 |
| tire_01.glb | [Old Tyre](https://polyhaven.com/a/old_tyre) | MP | 0.6×0.6×0.17 (standing on edge, centred at origin) |
| cardboard_box_01.glb | [Cardboard Box 01](https://polyhaven.com/a/cardboard_box_01) | Rahul Chaudhary | 0.39×0.34×0.52 |
| fire_extinguisher_01.glb | [Korean Fire Extinguisher 01](https://polyhaven.com/a/korean_fire_extinguisher_01) | UM JOORIN | 0.28×0.66×0.37 |
| gas_cylinder_01.glb | [Propane Tank](https://polyhaven.com/a/propane_tank) | Slinc | 0.34×0.55×0.34 |
| wooden_crate_01.glb | [Wooden Crate 01](https://polyhaven.com/a/wooden_crate_01) | James Ray Cock | 0.83×0.35×0.41 |
| military_crate_01.glb | [Wooden Military Crate](https://polyhaven.com/a/wooden_military_crate) | Prabhjinder Singh | 1.24×0.46×0.52 |
| jerrycan_01.glb | [Metal Jerrycan](https://polyhaven.com/a/metal_jerrycan) | Sean Buckley | 0.35×0.46×0.17 |
| plastic_crate_01.glb | [Plastic Crate 03](https://polyhaven.com/a/plastic_crate_03) | Pacific Penguin | 0.48×0.27×0.26 |
| street_lamp_01.glb | [Street Lamp 01](https://polyhaven.com/a/street_lamp_01) | Josh Dean | 0.70×3.87×0.39 |
| utility_box_01.glb | [Utility Box 01](https://polyhaven.com/a/utility_box_01) | James Ray Cock | 0.52×1.12×0.43 |

Pivot = bottom centre (Y-up) except the tyre. No pallet / traffic cone was available as CC0 at this quality — build those procedurally.
The `*_diff.jpg / *_nor_gl.jpg / ...` files next to each .glb are Godot's auto-extracted embedded textures (keep them).

## Weapons — `assets/models/weapons/` (Poly Haven, CC0)

| File | Source | Author | Notes |
|---|---|---|---|
| pistol.glb | [Service Pistol](https://polyhaven.com/a/service_pistol) | Mateusz Sadek | Realistic WWII-style (P38-like) pistol, wood grips. 0.22 m long, barrel points **+X**, Y up. Separate nodes: `service_pistol_pistol_a` (frame), `service_pistol_slide_a` (animate for recoil), `service_pistol_magazine_loaded`, `service_pistol_hammer_a`, `service_pistol_trigger_a`. |
| sniper.glb | [Bolt Action Rifle 7.62](https://polyhaven.com/a/bolt_action_rifle_7_62) | Mateusz Sadek | Realistic Mosin-style bolt-action with scope + cloth-wrapped stock. 1.23 m long, muzzle **+X**. Nodes: `..._7_62` (rifle), `..._scope`, `..._wrap`, `..._bolt_a`, `..._trigger`. |

Both are photoreal PBR (1K). No CC0/CC-BY assault rifle, SMG or shotgun of comparable realism was found
(Quaternius/Kenney guns are low-poly/toy-like), so AR/SMG/shotgun should be modelled procedurally.
No CC0 first-person arms model was found — `arms.glb` is not provided (the soldier's own arm/hand bones can be reused).

## Character — `assets/models/characters/`

**soldier.glb** — built for this repo from
[Quaternius Universal Base Characters (Standard)](https://quaternius.com/packs/universalbasecharacters.html) "Superhero_Male" body +
[Quaternius Universal Animation Library (Standard)](https://quaternius.com/packs/universalanimationlibrary.html), both **CC0** by Quaternius
(files obtained via the GitHub mirror [NafisRayan/Animate-Rigged-Humanoid-No-Blender](https://github.com/NafisRayan/Animate-Rigged-Humanoid-No-Blender); original licence text: CC0 1.0).
Modifications: body texture repainted into a military outfit (procedural woodland-camo shirt & trousers, dark olive
chest/vest area, black tactical gloves, black boots, dark knit cap, face kept), clothing normals flattened + fabric weave,
textures 1024 JPG; UAL animations merged in (rotation tracks for all bones, translation only on `pelvis`, scaled ×1.035 to this body).

- **Height:** 1.82 m (feet at y≈0). Units = metres, Y up. **Faces +Z** (Godot `Vector3.MODEL_FRONT`); the character's right hand is at −X.
  Rotate the model 180° around Y if your enemy logic uses −Z as forward.
- **Node path:** `Armature/Skeleton3D` (+ `AnimationPlayer` at the scene root). Meshes: `SuperHero_Male`, `Eyes`, `Eyebrows`.
- **Animations (23)** — names as they appear in Godot (Godot strips the `_Loop` suffix and sets looping):
  `Idle`, `Walk`, `Jog_Fwd`, `Sprint`, `Crouch_Idle`, `Crouch_Fwd`, `Pistol_Idle`, `Pistol_Aim_Neutral`, `Pistol_Aim_Up`,
  `Pistol_Aim_Down`, `Pistol_Shoot`, `Pistol_Reload`, `Hit_Chest`, `Hit_Head`, `Death01`, `Roll`, `Jump_Start`, `Jump`,
  `Jump_Land`, `Punch_Cross`, `Interact`, `Idle_Talking`, `A_TPose`.
  There is no dedicated rifle set in the free UAL; the two-handed `Pistol_*` aim/shoot poses work for a rifle held at the right hand.
- **Bones (65):** `root, pelvis, spine_01, spine_02, spine_03, neck_01, Head, clavicle_l/r, upperarm_l/r, lowerarm_l/r, hand_l/r,`
  fingers `index/middle/ring/pinky/thumb_01..03_l/r` (+ `_04_leaf`), `thigh_l/r, calf_l/r, foot_l/r, ball_l/r, ball_leaf_l/r`.
  Key bones: **`Head`** (capital H, rest y≈1.60), **`hand_r`** (rest ≈(-0.71, 1.46, -0.07), T-pose), **`hand_l`**, **`spine_03`** (upper chest), `spine_02`, `pelvis`.

**anims.glb** — extra clips on the Quaternius UAL mannequin (same 65-bone skeleton/names), from
Universal Animation Library 2 (Standard), CC0 by Quaternius:
`Hit_Knockback`, `OverhandThrow` (grenade), `ClimbUp_1m`, `Slide_Start`, `Slide`, `Slide_Exit`, `LayToIdle`, `Idle_FoldArms`,
`Idle_TalkingPhone`, `Idle_Rail`, `Walk_Carry`, `Melee_Hook`, `Idle_No`, `Yes`. Can be copied into the soldier's AnimationPlayer
(tracks target `Armature/Skeleton3D:<bone>`; only pelvis has position tracks, so they play on the soldier without distortion).

## Fonts — `assets/fonts/` (SIL Open Font License 1.1, from [google/fonts](https://github.com/google/fonts))

- `Rajdhani-SemiBold.ttf`, `Rajdhani-Bold.ttf` — Indian Type Foundry — techy squared display font for HUD numbers. Licence: `OFL-Rajdhani.txt`
- `BarlowCondensed-SemiBold.ttf`, `BarlowCondensed-Bold.ttf` — The Barlow Project Authors (Jeremy Tribby) — condensed military-ish headings. Licence: `OFL-BarlowCondensed.txt`
- `Barlow-Regular.ttf`, `Barlow-Medium.ttf`, `Barlow-SemiBold.ttf` — clean UI body text. Licence: `OFL-Barlow.txt`

## FX & decals

Procedurally generated for this repo (numpy), CC0, 256² RGBA:
- `textures/fx/muzzle_flash_front.png` — 5-petal jagged star burst with white-hot core (view down the barrel)
- `textures/fx/muzzle_flash_side.png` — elongated flame, **muzzle at the left edge, flame extends toward +U**
- `textures/fx/spark.png` — thin tapered streak, bright head at the **right** edge (align U with velocity)
- `textures/fx/blood.png` — dark-red irregular mist with droplets
- `textures/decals/bullet_hole_concrete.png` (+ `_normal.png`) — dark hole, chipped crater, short cracks, dust
- `textures/decals/bullet_hole_metal.png` (+ `_normal.png`) — small hole, bright bent lip, scorch ring
  (normals are OpenGL convention; alpha is in the base PNG)

From [Kenney Particle Pack](https://kenney.nl/assets/particle-pack) (CC0, Kenney.nl), white sprites for tinting, resized to 256²
(`textures/fx/LICENSE-Kenney-ParticlePack.txt`): `smoke.png` (smoke_07), `smoke_02.png` (smoke_04), `debris.png` (dirt_01),
`tracer.png` (trace_01, vertical), `impact_flash.png` (scorch_01), `flame_kenney.png` (muzzle_04, vertical flame).

## Touch / mobile controls — `assets/textures/ui/touch/`

From [Kenney Mobile Controls](https://kenney.nl/assets/mobile-controls) (CC0, Kenney.nl), "Style C" white outline (tint via `modulate`)
+ icons: `joystick_circle_pad_a.png` (256², stick base), `joystick_circle_nub_a/b.png` (128², stick knob), `button_circle.png`,
`button_square.png`, `dpad.png`, `icon_fire`, `icon_crosshair` (aim), `icon_target`, `icon_jump`, `icon_arrow_rotate` (reload),
`icon_burst` (grenade), `icon_hand` (interact), `icon_arrow`, `icon_pause`, `icon_cog` (96²). Licence: `LICENSE-Kenney-MobileControls.txt`.
