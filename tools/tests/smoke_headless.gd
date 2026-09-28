extends SceneTree
## Headless logic smoke test: boots main scene, starts a run, simulates input, reports errors/state.
var frames := 0
var main
var G
func _init():
	G = root.get_node_or_null("Game"); print("Game autoload: ", G)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d):
	frames += 1
	if frames == 5: main.start_game()
	if frames == 10: G.run_command("move fwd on")
	if frames == 30: G.run_command("fire on")
	if frames == 60: G.run_command("fire off"); G.run_command("key reload")
	if frames == 90: G.run_command("hold sprint on")
	if frames == 100: G.run_command("key crouch")
	if frames == 140: G.run_command("key jump")
	for i in [160, 200, 240, 280]:
		if frames == i: G.run_command("weapon %d" % ((i-160)/40 + 1)); G.run_command("fire on")
	if frames % 50 == 0: print(JSON.stringify(G.get_state()))
	if frames > 320: quit()
	return false
