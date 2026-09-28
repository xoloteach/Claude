class_name WeaponDefs
extends RefCounted
## Data for every weapon. Angles in degrees, distances in meters, times in seconds.

const ORDER := ["ar", "smg", "shotgun", "sniper", "pistol"]

const DEFS := {
	"ar": {
		"name": "M13 ARBITER", "class": "ASSAULT RIFLE", "model": "ar",
		"damage": 32.0, "damage_min": 22.0, "range_start": 28.0, "range_end": 60.0,
		"head_mult": 1.5, "limb_mult": 0.85, "pellets": 1,
		"rpm": 760.0, "mode": "auto",
		"mag": 30, "reserve": 240, "reload": 2.0, "reload_empty": 2.5,
		"ads_time": 0.22, "ads_fov": 0.78, "ads_move": 0.62, "sprint_to_fire": 0.14,
		"hip_spread": 3.4, "ads_spread": 0.05, "move_spread": 2.2, "air_spread": 5.0,
		"recoil_v": 0.55, "recoil_h": 0.2, "recoil_h_bias": 0.06, "recoil_recover": 10.0, "ads_recoil": 0.62,
		"kick_back": 0.028, "kick_up": 2.4, "kick_roll": 2.2, "kick_side": 0.9, "shake": 0.10,
		"sound": "ar_fire", "tracer_every": 2, "equip": 0.42,
		"hip_pos": Vector3(0.105, -0.118, -0.29), "ads_dist": 0.19,
		"shell": "rifle", "flash_scale": 1.0,
	},
	"smg": {
		"name": "VX-9 VANDAL", "class": "SMG", "model": "smg",
		"damage": 26.0, "damage_min": 16.0, "range_start": 12.0, "range_end": 32.0,
		"head_mult": 1.35, "limb_mult": 0.9, "pellets": 1,
		"rpm": 920.0, "mode": "auto",
		"mag": 32, "reserve": 256, "reload": 1.75, "reload_empty": 2.15,
		"ads_time": 0.16, "ads_fov": 0.84, "ads_move": 0.8, "sprint_to_fire": 0.1,
		"hip_spread": 2.4, "ads_spread": 0.12, "move_spread": 1.0, "air_spread": 3.0,
		"recoil_v": 0.36, "recoil_h": 0.3, "recoil_h_bias": -0.04, "recoil_recover": 12.0, "ads_recoil": 0.7,
		"kick_back": 0.022, "kick_up": 1.8, "kick_roll": 2.6, "kick_side": 1.1, "shake": 0.07,
		"sound": "smg_fire", "tracer_every": 3, "equip": 0.35,
		"hip_pos": Vector3(0.1, -0.112, -0.27), "ads_dist": 0.22,
		"shell": "pistol", "flash_scale": 0.35, "suppressed": true,
	},
	"shotgun": {
		"name": "HS-12 BREACHER", "class": "SHOTGUN", "model": "shotgun",
		"damage": 19.0, "damage_min": 5.0, "range_start": 8.0, "range_end": 22.0,
		"head_mult": 1.2, "limb_mult": 1.0, "pellets": 9, "pellet_spread": 3.6,
		"rpm": 75.0, "mode": "pump",
		"mag": 6, "reserve": 42, "reload_shell": 0.48, "reload_start": 0.35, "reload": 0.5, "reload_empty": 0.5,
		"ads_time": 0.24, "ads_fov": 0.85, "ads_move": 0.7, "sprint_to_fire": 0.16,
		"hip_spread": 2.0, "ads_spread": 1.2, "move_spread": 0.6, "air_spread": 1.0,
		"recoil_v": 4.2, "recoil_h": 1.0, "recoil_h_bias": 0.2, "recoil_recover": 7.0, "ads_recoil": 0.8,
		"kick_back": 0.09, "kick_up": 11.0, "kick_roll": 5.0, "kick_side": 2.0, "shake": 0.45,
		"sound": "shotgun_fire", "tracer_every": 1, "equip": 0.5,
		"hip_pos": Vector3(0.11, -0.125, -0.27), "ads_dist": 0.16,
		"shell": "shotgun", "flash_scale": 1.6,
	},
	"sniper": {
		"name": "MR-91 LONGSHOT", "class": "SNIPER RIFLE", "model": "sniper",
		"damage": 120.0, "damage_min": 95.0, "range_start": 60.0, "range_end": 120.0,
		"head_mult": 2.0, "limb_mult": 0.8, "pellets": 1,
		"rpm": 48.0, "mode": "bolt",
		"mag": 5, "reserve": 30, "reload": 2.9, "reload_empty": 3.3,
		"ads_time": 0.34, "ads_fov": 0.26, "ads_move": 0.45, "sprint_to_fire": 0.22, "scope": true,
		"hip_spread": 7.0, "ads_spread": 0.0, "move_spread": 3.0, "air_spread": 8.0,
		"recoil_v": 5.0, "recoil_h": 0.8, "recoil_h_bias": 0.1, "recoil_recover": 5.0, "ads_recoil": 0.6,
		"kick_back": 0.08, "kick_up": 9.0, "kick_roll": 3.0, "kick_side": 1.0, "shake": 0.35,
		"sound": "sniper_fire", "tracer_every": 1, "equip": 0.55,
		"hip_pos": Vector3(0.11, -0.13, -0.26), "ads_dist": 0.09,
		"shell": "rifle", "flash_scale": 1.8,
	},
	"pistol": {
		"name": "P-38 WARDEN", "class": "PISTOL", "model": "pistol",
		"damage": 36.0, "damage_min": 24.0, "range_start": 14.0, "range_end": 30.0,
		"head_mult": 1.6, "limb_mult": 0.9, "pellets": 1,
		"rpm": 420.0, "mode": "semi",
		"mag": 8, "reserve": 96, "reload": 1.45, "reload_empty": 1.8,
		"ads_time": 0.13, "ads_fov": 0.86, "ads_move": 0.9, "sprint_to_fire": 0.08,
		"hip_spread": 1.8, "ads_spread": 0.15, "move_spread": 0.8, "air_spread": 2.5,
		"recoil_v": 1.5, "recoil_h": 0.35, "recoil_h_bias": 0.0, "recoil_recover": 10.0, "ads_recoil": 0.75,
		"kick_back": 0.03, "kick_up": 7.0, "kick_roll": 2.0, "kick_side": 1.0, "shake": 0.08,
		"sound": "pistol_fire", "tracer_every": 1, "equip": 0.3,
		"hip_pos": Vector3(0.085, -0.1, -0.3), "ads_dist": 0.3,
		"shell": "pistol", "flash_scale": 0.8,
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS["ar"])
