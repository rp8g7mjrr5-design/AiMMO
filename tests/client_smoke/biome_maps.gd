extends SceneTree
## Top-down maps of an island on two generator versions, with biome shares and relief numbers
## (not a test: it never fails, it only draws and prints).
##
##   godot --headless --path game -s tests/client_smoke/biome_maps.gd -- --out=/abs/dir [--seed=1126] [--gens=2,3] [--px=512]

func _initialize() -> void:
	var out := "/tmp"
	var seed_v := 1126
	var gens := [2, 3]
	var px := 512
	var size := 3000.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--seed="):
			seed_v = a.substr(7).to_int()
		elif a.begins_with("--px="):
			px = a.substr(5).to_int()
		elif a.begins_with("--size="):
			size = a.substr(7).to_float()
		elif a.begins_with("--gens="):
			gens = []
			for g in a.substr(7).split(","):
				gens.append(g.to_int())
	for g in gens:
		var t := Time.get_ticks_msec()
		WorldGen.configure(seed_v, size, g)
		WorldGen.ruin_sites()
		var built := Time.get_ticks_msec() - t
		var img := WorldMap.paint(px)
		img.save_png("%s/map-s%d-v%d.png" % [out, seed_v, g])
		var counts := {}
		var land := 0
		var hs: Array = []
		var steep := 0
		var n := 200
		var half := WorldGen.half_size()
		for j in n:
			for i in n:
				var x := -half + (i + 0.5) * size / n
				var z := -half + (j + 0.5) * size / n
				var h := Terrain.height(x, z)
				if h < 0.0:
					continue
				land += 1
				hs.append(h)
				var b := WorldGen.biome_for(x, z, h)
				counts[b] = int(counts.get(b, 0)) + 1
				if absf(Terrain.height(x + 1.0, z) - h) + absf(Terrain.height(x, z + 1.0) - h) > 0.8:
					steep += 1
		hs.sort()
		var shares := {}
		for b in counts:
			shares[b] = snappedf(100.0 * counts[b] / land, 0.1)
		var kinds := {}
		for s in WorldGen.ruin_sites():
			kinds[s.kind] = int(kinds.get(s.kind, 0)) + 1
		print("v%d seed %d: layout %d ms; land h p10 %.1f p50 %.1f p90 %.1f max %.1f; steep %.1f%%" % [g, seed_v, built,
			hs[int(hs.size() * 0.1)], hs[int(hs.size() * 0.5)], hs[int(hs.size() * 0.9)], hs[-1], 100.0 * steep / land])
		print("  biomes %: ", shares)
		print("  sites: ", kinds, " landings ", WorldGen.landings().size(), " nodes ", WorldGen.node_spots().size())
	quit()
