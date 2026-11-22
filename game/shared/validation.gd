class_name Validation
## Input rules shared by client (for friendly errors) and server (for enforcement).

static var _name_re: RegEx


## Returns "" if the name is valid, otherwise a player-facing reason.
static func check_name(n: String) -> String:
	if _name_re == null:
		_name_re = RegEx.create_from_string("^[A-Za-z][A-Za-z0-9_]*$")
	if n.length() < GameConfig.NAME_MIN or n.length() > GameConfig.NAME_MAX:
		return "Names must be %d to %d characters." % [GameConfig.NAME_MIN, GameConfig.NAME_MAX]
	if _name_re.search(n) == null:
		return "Names start with a letter and use only letters, numbers, and _."
	return ""


static func check_password(p: String) -> String:
	if p.length() < GameConfig.PASSWORD_MIN or p.length() > GameConfig.PASSWORD_MAX:
		return "Passwords must be %d to %d characters." % [GameConfig.PASSWORD_MIN, GameConfig.PASSWORD_MAX]
	return ""


## Trims, strips control characters and BBCode brackets, and caps length. Returns "" if
## nothing is left to send.
static func clean_chat(t: String) -> String:
	var out := ""
	for i in t.length():
		var c := t.unicode_at(i)
		if c < 32 or c == 127:
			continue
		if c == 91 or c == 93: # [ ] would let players inject BBCode into chat labels
			continue
		out += char(c)
	out = out.strip_edges()
	if out.length() > GameConfig.CHAT_MAX:
		out = out.substr(0, GameConfig.CHAT_MAX)
	return out


## Canonical form used for uniqueness, so "Bob" and "bob" are the same account.
static func canonical(n: String) -> String:
	return n.to_lower()
