extends RefCounted
## Enemy archetypes + global AI tuning. Distances in metres, times in seconds, angles in degrees.

const ARCHETYPES := {
	"rifleman": {
		"name": "RIFLEMAN", "hp": 100.0,
		"walk": 2.0, "run": 4.5, "sprint": 5.5,
		"weapon_model": "ar", "rpm": 600.0, "burst": [3, 6], "burst_pause": [0.35, 0.8], "mag": 30, "reload": 2.2,
		"damage": [10.0, 14.0], "accuracy": 0.95, "range_pref": [12.0, 30.0], "max_range": 60.0,
		"tracer_every": 2, "flash_scale": 0.85, "sound": "enemy_fire",
		"peeks_before_move": [2, 4], "grenades": 1, "flank": false, "stagger_resist": 0.0,
		"body_armor": 1.0, "reaction": [0.35, 0.7],
		"tints": [Color(1, 1, 1), Color(1.0, 0.92, 0.8), Color(0.82, 0.86, 0.8)],
		"gear": {"helmet": "helmet", "color": Color(0.36, 0.34, 0.25), "backpack": true, "pouches": true},
		"drop_chance": 0.3, "score": 0,
	},
	"rusher": {
		"name": "RUSHER", "hp": 75.0,
		"walk": 2.4, "run": 5.2, "sprint": 6.3,
		"weapon_model": "smg", "rpm": 820.0, "burst": [5, 9], "burst_pause": [0.25, 0.5], "mag": 32, "reload": 1.8,
		"damage": [7.0, 10.0], "accuracy": 0.8, "range_pref": [4.0, 11.0], "max_range": 35.0,
		"tracer_every": 3, "flash_scale": 0.5, "sound": "enemy_fire", "suppressed": false,
		"peeks_before_move": [1, 2], "grenades": 0, "flank": true, "stagger_resist": 0.0,
		"body_armor": 1.0, "reaction": [0.3, 0.55],
		"tints": [Color(0.62, 0.62, 0.64), Color(0.7, 0.66, 0.6)],
		"gear": {"helmet": "cap", "color": Color(0.16, 0.16, 0.16), "backpack": false, "pouches": true},
		"drop_chance": 0.35, "score": 50,
	},
	"heavy": {
		"name": "HEAVY", "hp": 250.0,
		"walk": 1.6, "run": 3.2, "sprint": 3.2,
		"weapon_model": "ar", "weapon_scale": 1.12, "drum": true, "rpm": 650.0, "burst": [9, 16], "burst_pause": [0.8, 1.3],
		"mag": 90, "reload": 3.2,
		"damage": [9.0, 12.0], "accuracy": 0.55, "range_pref": [10.0, 28.0], "max_range": 60.0,
		"tracer_every": 2, "flash_scale": 1.1, "sound": "enemy_fire", "kick": 1.3,
		"peeks_before_move": [3, 5], "grenades": 0, "flank": false, "stagger_resist": 0.7,
		"body_armor": 0.6, "reaction": [0.45, 0.8],
		"tints": [Color(0.55, 0.56, 0.58)],
		"gear": {"helmet": "heavy", "color": Color(0.2, 0.21, 0.22), "helmet_color": Color(0.16, 0.17, 0.18), "backpack": false, "pouches": true},
		"drop_chance": 0.9, "score": 150,
	},
}

# perception
const VIEW_DIST := 60.0
const VIEW_HALF_ANGLE := 55.0       # ~110 deg cone
const PERIPHERAL_HALF_ANGLE := 80.0 # very slow awareness build outside the cone
const THINK_INTERVAL := 0.15
const PERCEPTION_INTERVAL := 0.12

# combat
const FIRST_SHOT_ACC := 0.35        # accuracy multiplier right after acquiring the target ...
const ACQUIRE_RAMP := 1.3           # ... ramping to 1.0 over this many seconds of continuous sight
const CORPSE_TIME := 15.0
const MAX_CORPSES := 6
const GRENADE_COOLDOWN := 12.0      # squad-wide
const GRENADE_DAMAGE := 110.0
const GRENADE_RADIUS := 6.5
const GRENADE_FUSE := 2.6
