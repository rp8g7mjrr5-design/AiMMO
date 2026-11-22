extends TestCase


func test_parse_address() -> void:
	check_eq(Transport.parse_address("1.2.3.4:9000", "enet"), ["enet", "1.2.3.4", 9000])
	check_eq(Transport.parse_address("ws://game.example.com:443", "enet"), ["websocket", "game.example.com", 443])
	check_eq(Transport.parse_address("myhost", "enet"), ["enet", "myhost", GameConfig.DEFAULT_PORT])


func test_cli_args() -> void:
	var a := CliArgs.parse(PackedStringArray(["--server", "--port=9", "junk"]))
	check_eq(a.get("server"), true)
	check_eq(a.get("port"), "9")
	check(not a.has("junk"), "positional args ignored")


func test_changelog_top_entry() -> void:
	var text := PatchNotes.load_text()
	var re := RegEx.create_from_string("(?m)^## Week (\\d\\d) — (.+)$")
	var m := re.search(text)
	check(m != null, "CHANGELOG.md starts entries with '## Week NN — Headline'")
	check(PatchNotes.to_bbcode(text).find("[b]") != -1, "renders to bbcode")
