# Enemy AI & wave director

All code is in `scripts/ai/`. `main.gd` loads `wave_director.gd` if it exists.

| File | Role |
|---|---|
| `wave_director.gd` | Wave flow, spawning, sharing contacts between squad-mates, attack tokens, grenade cooldown, corpse cap, debug commands |
| `enemy.gd` | `CharacterBody3D` brain: perception, state machine, NavigationAgent3D movement, shooting, reactions, death |
| `soldier_rig.gd` | Visuals: `soldier.glb`, gear, rifle in hand, left-hand IK, AnimationTree, hitboxes, ragdoll hand-off |
| `aim_modifier.gd` | `SkeletonModifier3D`: spine twist (torso stays on target while legs follow movement), crouch/sprint leveling, recoil and flinch springs |
| `ragdoll.gd` | Builds the `PhysicalBoneSimulator3D` (12 bodies, cone/hinge joints) at death |
| `cover_finder.gd` | Picks cover from `level.get_cover_points()` plus sampled points, checked with raycasts (low ray blocked, peek spot has LOS) |
| `grenade.gd` | Frag: arc, bounces, 2.6 s fuse, `FX.explosion`, damage falloff + LOS, on-screen warning arrow |
| `ammo_pickup.gd` | Ammo box drop: `refill_all(0.4)` |
| `ai_config.gd` | Archetype stats and global tuning |

## Enemy API (used by other systems)
`take_damage(amount, info) -> {"killed", "headshot", "armor"}`, `aim_point()`, `alive`, `hear_noise(pos, radius)`, group `"enemy"`.
Hitboxes: 13 `Area3D` on `BoneAttachment3D`s (layer `L_HITBOX`, metas `hitbox/enemy/zone/bone`).
Ragdoll bodies use layer 64 (bit 7) with mask `WORLD|PROPS`, so bullets, the player and other enemies ignore corpses.

## Behaviour
- **Perception** (every 0.12 s, staggered): a 110° / 60 m vision cone plus a slow-building peripheral band out to ±80°. LOS is raycast from the eye to the player's head and chest (`WORLD|PROPS`). Awareness builds faster when the player is close or sprinting and slower when crouched. Gunfire within 45% of the noise radius puts the enemy straight into combat. Contacts are shared with squad-mates within 45 m.
- **States**: `idle → hunt` (wave spawns know roughly where the player is) → `investigate` → `combat`. Combat sub-modes:
  `reposition → move → cover ⇄ peek` (2–4 peeks, then reposition; reposition immediately if flanked), `strafe` (in the open), `advance` (heavy),
  `flank → assault` (rusher), `suppress` (fires at the last known position), `push` (when the player has been hidden for more than 4 s), `throw`, `retreat` (rifleman below 30% HP).
- **Shooting**: hitscan. Each shot rolls a hit chance, and misses land visibly near the player (impacts, `bullet_whiz`). Hit chance is `accuracy × range × player speed × stance (crouch 0.8, slide 0.45, air 0.7) × acquisition ramp (0.35→1 over 1.3 s) × self-moving 0.8 × flinch 0.5 × token (0.4 without one) × mercy (0.7 below 35% HP) × difficulty × input device (touch 0.78, pad 0.9)`. Reaction time before the first shot is 0.35–0.7 s.
- **Attack tokens**: only the 2 (wave 1) or 3 closest enemies with LOS shoot at full accuracy.
- **Animation**: locomotion clips are time-scaled to ground speed (Walk 1.05, Jog 3.3, Sprint 4.9, Crouch 0.78 m/s). Legs yaw towards the movement direction (up to ±80°, and Walk plays reversed when backpedalling), while the spine twist keeps the rifle on target. Upper-body aim uses `Pistol_Aim_Down/Neutral/Up` in a Blend3 (pitch/90°), filtered to the `spine_02` subtree. Flinch, reload and throw are upper-body one-shots; stagger is full-body. Animation LOD advances the tree every 1/2/3 frames at <25 / <50 / ≥50 m.
- **Death**: ragdoll with an impulse from the bullet (30–95, shotgun 140). The corpse stays for 15 s, then sinks once it is off-screen. At most 6 corpses are kept.

## Archetypes
| | HP | Speeds (walk/run/sprint) | Weapon | Burst | Damage | Accuracy | Notes |
|---|---|---|---|---|---|---|---|
| Rifleman | 100 | 2.0 / 4.5 / 5.5 | AR 600 rpm | 3–6, pause 0.35–0.8 s | 10–14 | 0.95 | cover/peek, 1 grenade, retreats |
| Rusher | 75 | 2.4 / 5.2 / 6.3 | SMG 820 rpm | 5–9 | 7–10 | 0.8 (falls off fast past 15 m) | flanks, cap and balaclava |
| Heavy | 250 | 1.6 / 3.2 | AR + drum 650 rpm | 9–16, pause 0.8–1.3 s | 9–12 | 0.55 | body ×0.6 (`armor`), head ×2, resists stagger, suppresses |

Headshots kill riflemen and rushers instantly.

**Measured time-to-kill** (headless, one enemy, stationary player, from the enemy's first shot): rifleman 10 m 3.0 s, 20 m 2.1–2.6 s, 35 m 2.9 s; heavy at 20 m 7.2 s.

## Waves
- Wave 1: 5 riflemen. Wave 2: 7 enemies including 2 rushers. Wave 3+: `7 + 2(n-2)` enemies (capped at 26), about 30% rushers and `1 + (n-3)/2` heavies.
- Alive cap is `min(8, 4 + wave)`. Spawns trickle in from points at least 25 m away that the player can't see.
- Between waves there is a 9 s break: "WAVE COMPLETE|+500" banner, full heal, full ammo refill.

## Debug / testing
- `Game.run_command("ai …")` needs a 3-line hook in `game.gd` (see the change request in the report). Commands: `ai lineup <pose> [dist]`, `ai pose <aim|low|walk|jog|sprint|crouch|strafe|back|live>`, `ai kill [head]`, `ai clear`, `ai waves off|on`. You can call `director.debug_cmd([...])` directly without the hook.
- Headless: `tools/tests/ai_runner.gd` covers debug spawn, pathing, shooting a god-mode player, kill test and wave progression. `game.gd` only auto-loads `tools/tests/runner.gd`, so copy `ai_runner.gd` over it locally to run the test.
- Visual: `node tools/playtest.mjs tools/scenarios/ai_view.json --viewport 960x540 --timeout 3000000`. The dockyard map runs at about 0.1–1 fps in SwiftShader.
