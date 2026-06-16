extends SceneTree
# Dumps the wormhole network (nodes + edges + hub flags + 2D top-down positions) to
# /tmp/wh_graph.json so tools/draw_wh_network.py can render WORMHOLE_NETWORK.png.
# Run:  godot --headless --script res://tools/export_wh_graph.gd

func _initialize() -> void:
	var nodes: Array = SystemDB.all()
	nodes.append(SystemDB.INTERSTELLAR)
	var hubs := {}
	for nb in SystemDB.neighbors(SystemDB.SOL):
		if nb != SystemDB.INTERSTELLAR:
			hubs[nb] = true
	var out := { "earth": SystemDB.SOL, "nodes": [], "edges": [] }
	for id in nodes:
		var p: Vector3 = Vector3.ZERO if id == SystemDB.INTERSTELLAR else SystemDB.coord(id)
		out["nodes"].append({
			"id": id, "name": SystemDB.display_name(id),
			"x": p.x, "z": p.z,
			"hub": hubs.has(id), "earth": id == SystemDB.SOL,
		})
	var seen := {}
	for e in SystemDB.wh_edges():
		var k1: String = "%s|%s" % [e[0], e[1]]
		var k2: String = "%s|%s" % [e[1], e[0]]
		if seen.has(k1) or seen.has(k2):
			continue
		seen[k1] = true
		out["edges"].append([e[0], e[1]])
	var f := FileAccess.open("/tmp/wh_graph.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("wrote /tmp/wh_graph.json  nodes=%d edges=%d hubs=%d" % [out["nodes"].size(), out["edges"].size(), hubs.size()])
	quit()
