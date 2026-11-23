extends TestCase
## Art bible lints (docs/art_bible.md sections 7 and 8): the server, shared code and the
## bot-test harness never touch art, and only palette.gd hard-codes colours. Today's
## exceptions live in art_lint_allow.json, which only shrinks.

const L := preload("res://tests/unit/art_lint.gd")
const ALLOW_PATH := "res://tests/unit/art_lint_allow.json"
## Code that must never touch art, no exceptions.
const ART_FREE_DIRS := ["res://server", "res://shared", "res://tests/bot_test"]
const BEHAVIOUR_DIR := "res://tests/bot_test/behaviours"


func _allow(section: String) -> Dictionary:
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ALLOW_PATH))
	var d: Dictionary = all.get(section, {}).duplicate()
	d.erase("_about")
	return d


func _gd_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(f)
	return out


# --- the maths, on small strings -------------------------------------------------------

func test_split_line_drops_comments_and_blanks_strings() -> void:
	var p := L.split_line('var a := Flora.x("res://procgen/flora.gd") # NodeProps here')
	check_eq(p[0], 'var a := Flora.x("") ')
	check_eq(p[1], PackedStringArray(["res://procgen/flora.gd"]))
	var q := L.split_line("var s := 'a # not a comment' + \"b\\\"c\"")
	check_eq(q[1], PackedStringArray(["a # not a comment", "b\\\"c"]))
	check(not q[0].contains("not a comment"), "string content is blanked")


func test_art_refs_finds_procgen_classes_and_paths() -> void:
	var cls := PackedStringArray(["Flora", "NodeProps"])
	var src := "\n".join([
		"## Flora is mentioned in a docstring only",
		"var n := NodeProps.parts(x)",
		"const F := preload(\"res://procgen/flora.gd\")",
		"var florals := 3  # FloraX is not Flora",
		"print(\"Flora in a message\")",
	])
	var r := L.art_refs(src, cls)
	check_eq(r.size(), 2, "found %s" % [r])
	check(r[0].begins_with("line 2:") and r[0].contains("NodeProps"), r[0])
	check(r[1].begins_with("line 3:") and r[1].contains("res://procgen/flora.gd"), r[1])


func test_art_refs_finds_visual_engine_classes() -> void:
	var src := "\n".join([
		"var m := ArrayMesh.new()",
		"var t: Texture2D = null",
		"var mat := StandardMaterial3D.new()",
		"var sh := Shader.new()",
		"var p := GPUParticles3D.new()",
		"var st := SurfaceTool.new()",
		"var mesh_count := 0",
		"var MESH_LIMIT := 2",
		"var v := Vector3.ZERO",
	])
	var r := L.art_refs(src, PackedStringArray())
	check_eq(r.size(), 6, "found %s" % [r])
	for i in 6:
		check(r[i].begins_with("line %d:" % (i + 1)), r[i])


func test_colour_literals_counts_hard_coded_colours_only() -> void:
	var src := "\n".join([
		"const A := Color(0.1, 0.2, 0.3)",            # 1
		"const B := Color(1, 1, 1, 0.5)",            # 1
		"var c := Color(\"#f2a541\")",               # 1
		"var d := Color8(242, 165, 65)",             # 1
		"var e := Color.from_hsv(0.07, 0.5, 0.8)",   # 1
		"var f := Color.WHITE.lerp(Color.html(\"ffd27a\"), 0.5)",  # 2
		"var g := Color(base.r * k, base.g, base.b)",  # 0: built from another colour
		"var h := Color(Palette.EMBER, 0.4)",       # 0
		"var i: Color = Palette.EMBER",            # 0
		"# Color(0.9, 0.9, 0.9) in a comment",       # 0
		"func tint(c: Color, extra := {}) -> Color:",  # 0
	])
	check_eq(L.colour_literals(src), 7)


func test_compare_allowance_fails_growth_and_notes_shrinkage() -> void:
	var res := L.compare_allowance({"a.gd": 3, "b.gd": 1, "c.gd": 2, "d.gd": 0}, {"a.gd": 3, "b.gd": 2, "e.gd": 1})
	check_eq(res[0], PackedStringArray(["c.gd: 2, allowed 0"]))
	check_eq(res[1].size(), 2, "notes %s" % [res[1]])
	check(res[1][0].begins_with("b.gd: 1"), res[1][0])
	check(res[1][1].begins_with("e.gd is on the allow-list"), res[1][1])
	var over := L.compare_allowance({"a.gd": 4}, {"a.gd": 3})
	check_eq(over[0], PackedStringArray(["a.gd: 4, allowed 3"]))


func test_class_names_reads_procgen() -> void:
	var cls := L.class_names()
	check(cls.has("Palette") and cls.has("NodeProps") and cls.has("WorldBuilder"), "got %s" % [cls])


# --- the real tree -----------------------------------------------------------------------

func test_server_shared_and_bot_harness_never_touch_art() -> void:
	var cls := L.class_names()
	for dir in ART_FREE_DIRS:
		for f in _gd_files(dir):
			var refs := L.art_refs(FileAccess.get_file_as_string(dir.path_join(f)), cls)
			check(refs.is_empty(), "%s must not touch art (art bible section 7): %s" % [dir.path_join(f), ", ".join(refs)])


func test_bot_behaviours_stay_art_free_except_the_allow_list() -> void:
	var cls := L.class_names()
	var counts := {}
	for f in _gd_files(BEHAVIOUR_DIR):
		var refs := L.art_refs(FileAccess.get_file_as_string(BEHAVIOUR_DIR.path_join(f)), cls)
		counts[f] = 1 if refs.size() > 0 else 0
		if refs.size() > 0 and not _allow("art_free_behaviours").has(f):
			print("[art-lint] %s: %s" % [f, ", ".join(refs)])
	var res := L.compare_allowance(counts, _allow("art_free_behaviours"))
	for msg in res[0]:
		check(false, "bot behaviour builds or loads art (art checks go in unit tests or the client smoke test, art bible section 7): %s" % msg)
	for msg in res[1]:
		print("[art-lint] note: behaviour %s" % msg)


func test_only_palette_hard_codes_colours() -> void:
	var counts := {}
	for f in _gd_files("res://procgen"):
		if f == "palette.gd":
			continue
		counts[f] = L.colour_literals(FileAccess.get_file_as_string("res://procgen".path_join(f)))
	var res := L.compare_allowance(counts, _allow("palette"))
	for msg in res[0]:
		check(false, "new colour literals outside palette.gd (put them in palette.gd, art bible section 2): %s" % msg)
	for msg in res[1]:
		print("[art-lint] note: palette %s" % msg)
