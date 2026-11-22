class_name CliArgs
## Parses `--key=value` and `--flag` user args (the ones after `--`).


static func parse(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var body := a.substr(2)
		var eq := body.find("=")
		if eq == -1:
			out[body] = true
		else:
			out[body.substr(0, eq)] = body.substr(eq + 1)
	return out


## Reads a setting from args first, then an environment variable, then a default.
static func setting(args: Dictionary, key: String, env_name: String, default_value: String) -> String:
	if args.has(key) and typeof(args[key]) == TYPE_STRING:
		return args[key]
	var env := OS.get_environment(env_name)
	if env != "":
		return env
	return default_value
