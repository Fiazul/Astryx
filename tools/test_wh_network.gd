extends SceneTree
# Wormhole-network test. Builds SystemDB's graph and reports the properties that matter:
#   - full connectivity (every destination reachable from Earth/Sol)
#   - hop distances from Earth (max / how many need > 3 hops)
#   - worst-case any-to-any hop distance (network diameter)
#   - node degrees (which systems are "hubs", and whether any is bloated)
#   - platform coverage (nearest-platform hop distance)
# Run:  godot --headless --script res://tools/test_wh_network.gd

func _initialize() -> void:
	var systems: Array = SystemDB.all()
	var nodes: Array = systems.duplicate()
	nodes.append(SystemDB.INTERSTELLAR)
	print("=== WORMHOLE NETWORK TEST ===")
	print("destinations: %d   graph nodes (incl hub): %d" % [systems.size(), nodes.size()])

	# --- BFS hop distance from Earth (Sol) over the full graph ---
	var dist := _bfs(SystemDB.SOL)
	var unreached := []
	var maxhop := 0
	var over3 := []
	for id in systems:
		if not dist.has(id):
			unreached.append(id)
		else:
			maxhop = maxi(maxhop, dist[id])
			if dist[id] > 3:
				over3.append("%s(%d)" % [id, dist[id]])
	print("\n-- reachability from Earth --")
	print("unreached: %d  %s" % [unreached.size(), str(unreached)])
	print("max hops from Earth: %d" % maxhop)
	print("destinations needing > 3 hops: %d" % over3.size())
	if over3.size() > 0:
		print("   ", str(over3))

	# --- network diameter (worst-case any-to-any) ---
	var diameter := 0
	var worst := ""
	for a in nodes:
		var d := _bfs(a)
		for b in nodes:
			if d.has(b) and d[b] > diameter:
				diameter = d[b]; worst = "%s -> %s" % [a, b]
	print("\n-- worst-case any-to-any --")
	print("network diameter (max hops between any two): %d   (%s)" % [diameter, worst])

	# --- degrees: which nodes are hubs, any bloated? ---
	var degs := []
	for id in nodes:
		degs.append([id, SystemDB.neighbors(id).size()])
	degs.sort_custom(func(a, b): return a[1] > b[1])
	print("\n-- node degrees (top 10) --")
	for i in mini(10, degs.size()):
		print("   %-18s %d" % [degs[i][0], degs[i][1]])

	# --- verdict ---
	print("\n-- VERDICT --")
	print("connected:        %s" % ("PASS" if unreached.is_empty() else "FAIL"))
	print("Earth <= 3 hops:  %s" % ("PASS" if over3.is_empty() else "FAIL (%d over)" % over3.size()))
	print("any <= 3 hops:    %s" % ("PASS" if diameter <= 3 else "FAIL (diameter %d)" % diameter))
	quit()


func _bfs(src: String) -> Dictionary:
	var dist := { src: 0 }
	var q := [src]
	while not q.is_empty():
		var cur: String = q.pop_front()
		for nb in SystemDB.neighbors(cur):
			if not dist.has(nb):
				dist[nb] = dist[cur] + 1
				q.append(nb)
	return dist
