extends TestCase


func test_names() -> void:
	check_eq(Validation.check_name("Ash_01"), "", "valid name")
	check(Validation.check_name("ab") != "", "too short")
	check(Validation.check_name("a".repeat(17)) != "", "too long")
	check(Validation.check_name("1abc") != "", "must start with a letter")
	check(Validation.check_name("bad name") != "", "no spaces")
	check(Validation.check_name("[b]x") != "", "no bbcode")


func test_passwords() -> void:
	check_eq(Validation.check_password("abcd"), "", "4 chars ok")
	check(Validation.check_password("abc") != "", "too short")


func test_chat_cleaning() -> void:
	check_eq(Validation.clean_chat("  hi there  "), "hi there")
	check_eq(Validation.clean_chat("[color=red]x[/color]"), "color=redx/color", "brackets stripped")
	check_eq(Validation.clean_chat("a\nb\tc"), "abc", "control chars stripped")
	check_eq(Validation.clean_chat("x".repeat(500)).length(), GameConfig.CHAT_MAX, "capped")
	check_eq(Validation.clean_chat("   "), "", "blank")


func test_canonical() -> void:
	check_eq(Validation.canonical("BoB"), "bob")
