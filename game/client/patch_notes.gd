class_name PatchNotes
## Shows CHANGELOG.md in-game. The file is exported with the client (see export filters).


static func load_text() -> String:
	for p in ["res://CHANGELOG.md"]:
		if FileAccess.file_exists(p):
			return FileAccess.get_file_as_string(p)
	return "No patch notes found."


## Turns the small subset of Markdown we use into BBCode.
static func to_bbcode(md: String) -> String:
	var out := PackedStringArray()
	for raw in md.split("\n"):
		var line := raw.replace("[", "(").replace("]", ")")
		if line.begins_with("# "):
			continue
		elif line.begins_with("## "):
			out.append("[font_size=20][b]%s[/b][/font_size]" % line.substr(3))
		elif line.begins_with("### "):
			out.append("[b]%s[/b]" % line.substr(4))
		elif line.begins_with("- "):
			out.append("  •  " + _bold(line.substr(2)))
		else:
			out.append(_bold(line))
	return "\n".join(out).strip_edges()


static func _bold(s: String) -> String:
	var parts := s.split("**")
	var r := ""
	for i in parts.size():
		r += ("[b]%s[/b]" % parts[i]) if i % 2 == 1 else parts[i]
	return r
