extends RefCounted
## Two source lints from the art bible (docs/art_bible.md, sections 7 and 8):
## - art-free server: the server, shared code and the bot-test harness never reference a
##   class from game/procgen/ and never create meshes, materials, textures, shaders or
##   particles;
## - palette: no file in game/procgen/ other than palette.gd hard-codes colours.
## Pure functions over source text, so the maths is unit-tested on small strings and
## test_qa_art_lint.gd runs it over the real tree.

const PROCGEN_DIR := "res://procgen"
## Engine classes that mean "this code builds or holds art".
const VISUAL_CLASS_RE := "\\b([A-Z][A-Za-z0-9]*)?(Mesh|Material|Texture|Shader|Particles|SurfaceTool)[A-Za-z0-9]*\\b"
## Colour literals: Color(<numbers>), Color("#hex"/"name"), Color8(), Color.html(),
## Color.from_hsv/from_rgbe9995/from_string() and named constants such as Color.WHITE.
const COLOUR_RES := [
	"\\bColor\\(\\s*[-+]?[0-9.]+(\\s*,\\s*[-+]?[0-9.]+)*\\s*\\)",
	"\\bColor\\(\\s*\"",
	"\\bColor8\\(",
	"\\bColor\\.(html|from_hsv|from_ok_hsl|from_rgbe9995|from_string)\\(",
	"\\bColor\\.[A-Z][A-Z_]+\\b",
]


## Returns [code, strings] for one line: `code` has comments removed and every string
## literal blanked to "", `strings` holds the string literals' contents.
static func split_line(line: String) -> Array:
	var code := ""
	var strings: PackedStringArray = []
	var quote := ""
	var cur := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\" and i + 1 < line.length():
				cur += line.substr(i, 2)
				i += 2
				continue
			if c == quote:
				strings.append(cur)
				cur = ""
				code += quote + quote
				quote = ""
			else:
				cur += c
		elif c == "#":
			break
		elif c == "\"" or c == "'":
			quote = c
		else:
			code += c
		i += 1
	if quote != "":
		strings.append(cur)
		code += quote + quote
	return [code, strings]


## Every class_name declared in a folder of scripts.
static func class_names(dir: String = PROCGEN_DIR) -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		for line in FileAccess.get_file_as_string(dir.path_join(f)).split("\n"):
			if line.begins_with("class_name "):
				out.append(line.substr(11).strip_edges().split(" ")[0])
	return out


## Art references in one script's source: ["line N: what", ...]. `art_classes` are the
## game/procgen/ class names.
static func art_refs(source: String, art_classes: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var visual := RegEx.create_from_string(VISUAL_CLASS_RE)
	var names := RegEx.create_from_string("\\b[A-Za-z_][A-Za-z0-9_]*\\b")
	var n := 0
	for line in source.split("\n"):
		n += 1
		var parts := split_line(line)
		for s in parts[1]:
			if s.contains("res://procgen/"):
				out.append("line %d: loads %s" % [n, s])
		for m in names.search_all(parts[0]):
			if art_classes.has(m.get_string()):
				out.append("line %d: uses procgen class %s" % [n, m.get_string()])
		for m in visual.search_all(parts[0]):
			out.append("line %d: uses visual class %s" % [n, m.get_string()])
	return out


## Number of colour literals in one script's source (comments ignored).
static func colour_literals(source: String) -> int:
	var res := []
	for r in COLOUR_RES:
		res.append(RegEx.create_from_string(r))
	var count := 0
	for line in source.split("\n"):
		# Keep strings in for Color("#hex"), drop only the comment.
		var parts := split_line(line)
		var code: String = parts[0]
		var with_strings := _restore_strings(code, parts[1])
		for r in res:
			count += r.search_all(with_strings).size()
	return count


## Puts the string contents back into a line whose strings were blanked by split_line.
static func _restore_strings(code: String, strings: PackedStringArray) -> String:
	var out := ""
	var k := 0
	var i := 0
	while i < code.length():
		var c := code[i]
		if (c == "\"" or c == "'") and i + 1 < code.length() and code[i + 1] == c and k < strings.size():
			out += c + strings[k] + c
			k += 1
			i += 2
			continue
		out += c
		i += 1
	return out


## Compares measured counts with the allow-list. Returns [failures, notes]: a file over
## its allowance (or not listed and above zero) fails; a file under its allowance is a
## note so qa can lower the list (it only ever shrinks).
static func compare_allowance(counts: Dictionary, allowed: Dictionary) -> Array:
	var failures: PackedStringArray = []
	var notes: PackedStringArray = []
	var files := counts.keys()
	files.sort()
	for f in files:
		var got := int(counts[f])
		var cap := int(allowed.get(f, 0))
		if got > cap:
			failures.append("%s: %d, allowed %d" % [f, got, cap])
		elif got < cap:
			notes.append("%s: %d, allow-list still says %d (lower it)" % [f, got, cap])
	for f in allowed:
		if not counts.has(f):
			notes.append("%s is on the allow-list but no longer exists (remove it)" % f)
	return [failures, notes]
