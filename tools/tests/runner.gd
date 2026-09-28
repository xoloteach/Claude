extends Node
## Test scenario runner, activated with: godot --headless -- --test=<name>
## Runs scripted commands against the live game and prints state + any errors.
var frames := 0
var steps := []
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	steps = [
		[5, "start"], [10, "god"], [12, "move fwd on"], [30, "fire on"], [60, "fire off"], [62, "key reload"],
		[90, "hold sprint on"], [95, "key sprint"], [120, "key crouch"], [160, "key jump"], [170, "move fwd off"],
		[180, "weapon 1"], [200, "fire on"], [230, "fire off"], [240, "weapon 2"], [270, "fire on"], [300, "fire off"],
		[310, "weapon 3"], [340, "fire on"], [370, "fire off"], [380, "weapon 4"], [410, "ads on"], [440, "fire on"], [450, "fire off"], [470, "ads off"],
		[480, "key reload"], [560, "spawn 3"], [700, "look 300 0"], [900, "quit"],
	]
func _process(_d):
	frames += 1
	for s in steps:
		if s[0] == frames:
			if s[1] == "quit":
				print("STATE ", JSON.stringify(Game.get_state()))
				get_tree().quit()
			else:
				Game.run_command(s[1])
	if frames % 60 == 0:
		print("STATE ", JSON.stringify(Game.get_state()))
