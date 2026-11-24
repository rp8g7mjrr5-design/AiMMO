class_name Appearance
## A traveller's look, as the player chose it in the character-creation window: a small
## Dictionary of whole numbers, one per option, e.g.
## {"body": 1, "height": 2, "skin": 3, "face": 0, "hair": 2, "hair_colour": 1, "beard": 3,
##  "headwear": 0, "tunic": 2, "trousers": 0}.
## Pure functions, used by the server (which checks and stores every look), the client (the
## creation window and every avatar it draws) and the bots.
##
## Rules:
## - An EMPTY look means "not chosen yet": the avatar is drawn from its appearance seed
##   exactly as before customization existed, and the creation window opens at login. Every
##   character saved before this feature loads that way (save compatibility rule).
## - Only the server stores a look, and only one that `check()` accepts. Clients send a whole
##   look; the server never trusts a number it hasn't range-checked.
## - Option keys and the meaning of each index are PERMANENT once shipped (they are stored in
##   characters.appearance). Add new choices at the END of a list, never in the middle, and
##   never remove one: `normalize()` clamps a stored index that is out of range instead of
##   dropping the look.
## - Colours live in Palette (art bible section 2), never here. The counts here must match the
##   palette lists they index (tests/unit/test_gameplay_appearance.gd checks it).

## Every option, in the order the creation window lists them: key -> {label, choices}.
## `choices` are the player-facing names, index = the stored number.
const OPTIONS := {
	"body": {"label": "Build", "choices": ["Lean", "Average", "Sturdy", "Broad"]},
	"height": {"label": "Height", "choices": ["Short", "Below average", "Average", "Above average", "Tall"]},
	"skin": {"label": "Skin", "choices": ["Fair", "Light", "Rosy", "Olive", "Tan", "Brown", "Dark brown", "Deep"]},
	"face": {"label": "Face", "choices": ["Narrow", "Square", "Round", "Strong brow"]},
	"hair": {"label": "Hair", "choices": ["Cropped", "Shaved", "Tied back", "Shoulder length", "Braid", "Bald"]},
	"hair_colour": {"label": "Hair colour", "choices": ["Black", "Dark brown", "Brown", "Auburn", "Ash blond", "Grey"]},
	"beard": {"label": "Beard", "choices": ["None", "Stubble", "Short beard", "Full beard", "Moustache"]},
	"headwear": {"label": "Head", "choices": ["Bare", "Hood", "Felt cap"]},
	"tunic": {"label": "Tunic", "choices": ["Undyed wool", "Madder red", "Woad blue", "Weld yellow", "Walnut brown", "Lichen green", "Sloe", "Charcoal"]},
	"trousers": {"label": "Trousers", "choices": ["Charcoal", "Walnut", "Moss", "Undyed", "Slate"]},
}
const ORDER := ["body", "height", "skin", "face", "hair", "hair_colour", "beard", "headwear", "tunic", "trousers"]
## What a new character's window starts on before their seed fills it in (an average build).
const DEFAULT := {"body": 1, "height": 2, "skin": 3, "face": 0, "hair": 0, "hair_colour": 1,
	"beard": 0, "headwear": 0, "tunic": 0, "trousers": 0}
## A stored look as JSON is far smaller than this; anything bigger is refused before parsing.
const MAX_JSON := 512

## What the server says when it refuses a look (never shown for a valid window's request).
const REFUSED := "That look couldn't be saved."


static func count(key: String) -> int:
	return (OPTIONS[key].choices as Array).size() if OPTIONS.has(key) else 0


static func choice_name(key: String, index: int) -> String:
	var n := count(key)
	return str(OPTIONS[key].choices[posmod(index, n)]) if n > 0 else ""


## True when the player has picked a look (any key present). An empty look is "not chosen".
static func is_chosen(look: Variant) -> bool:
	return typeof(look) == TYPE_DICTIONARY and not (look as Dictionary).is_empty()


## "" when `look` is a complete, in-range look from a client, else why not (for the log).
## Strict on purpose: the creation window always sends every key as a whole number, so
## anything else is a broken or hostile client.
static func check(look: Variant) -> String:
	if typeof(look) != TYPE_DICTIONARY:
		return "not a dictionary"
	var d: Dictionary = look
	if d.size() != ORDER.size():
		return "has %d keys, wants %d" % [d.size(), ORDER.size()]
	for key in ORDER:
		if not d.has(key):
			return "missing %s" % key
		var v: Variant = d[key]
		if typeof(v) != TYPE_INT:
			if typeof(v) == TYPE_FLOAT and float(v) == floorf(float(v)) and absf(float(v)) < 1000.0:
				v = int(v) # JSON numbers arrive as floats
			else:
				return "%s is not a whole number" % key
		if int(v) < 0 or int(v) >= count(key):
			return "%s %d is out of range" % [key, int(v)]
	return ""


## Any stored or received value -> a full look of in-range ints, or {} for "not chosen".
## Never throws a look away for one bad field: unknown keys are dropped, missing keys take
## DEFAULT, and out-of-range numbers are clamped (a choice retired later still loads).
static func normalize(look: Variant) -> Dictionary:
	if not is_chosen(look):
		return {}
	var d: Dictionary = look
	var out := {}
	for key in ORDER:
		var v: Variant = d.get(key, DEFAULT[key])
		var i := int(DEFAULT[key])
		match typeof(v):
			TYPE_INT, TYPE_FLOAT:
				i = int(v)
			TYPE_STRING:
				i = (v as String).to_int()
		out[key] = clampi(i, 0, count(key) - 1)
	return out


## A look as the text stored in characters.appearance: "" for "not chosen".
static func to_json(look: Variant) -> String:
	var n := normalize(look)
	return "" if n.is_empty() else JSON.stringify(n)


## characters.appearance -> a look ({} for "", unreadable or not an object, never an error).
static func from_json(text: Variant) -> Dictionary:
	if typeof(text) == TYPE_DICTIONARY:
		return normalize(text)
	var s := str(text) if text != null else ""
	if s == "" or s.length() > MAX_JSON:
		return {}
	var j := JSON.new()
	if j.parse(s) != OK:
		return {}
	return normalize(j.data)


## The look a seed has always drawn, as near as the choices allow: what the creation window
## starts on for a character who has never chosen, so opening it changes nothing at first.
## Deterministic. Mirrors AvatarBuilder's seeded draws (skin x3, then the head style), but
## lives here so the server and bots need nothing from procgen.
static func from_seed(appearance_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = appearance_seed
	var _a := rng.randf()
	var _b := rng.randf()
	var c := rng.randf() # the skin's lightness: 0 dark .. 1 fair
	var style := rng.randi() % 3 # 0 hood, 1 cap, 2 bare-headed
	var tunic_rng := RandomNumberGenerator.new()
	tunic_rng.seed = appearance_seed
	var look := DEFAULT.duplicate()
	look.skin = clampi(int((1.0 - c) * count("skin")), 0, count("skin") - 1)
	look.headwear = [1, 2, 0][style]
	look.hair_colour = posmod(hash(appearance_seed), count("hair_colour"))
	look.tunic = tunic_rng.randi() % count("tunic") # Palette.cloth_from_seed's first draw
	look.body = 1
	look.height = 2
	return look


## A random complete look (bots, and the window's "Roll" button).
static func random(rng: RandomNumberGenerator) -> Dictionary:
	var look := {}
	for key in ORDER:
		look[key] = rng.randi() % count(key)
	return look


## `look` with option `key` stepped by `delta` (wrapping), for the window's arrows.
static func stepped(look: Dictionary, key: String, delta: int) -> Dictionary:
	var out := normalize(look) if is_chosen(look) else DEFAULT.duplicate()
	out[key] = posmod(int(out[key]) + delta, count(key))
	return out
