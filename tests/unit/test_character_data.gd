extends TestCase
## Save compatibility: rows written by any older version must still load.


func test_missing_fields_get_defaults() -> void:
	var ch := CharacterData.normalize({"id": 5, "account_id": 2, "name": "Old"})
	check_eq(ch.id, 5)
	check_eq(ch.appearance_seed, 0)
	check_eq(typeof(ch.yaw), TYPE_FLOAT)
	check_near(ch.y, Terrain.height(0, 0), 0.0001, "snapped to ground")


func test_text_rows_from_postgres() -> void:
	var ch := CharacterData.from_pg_row({"id": "7", "account_id": "3", "name": "Pg", "pos_x": "10.5", "pos_y": "0", "pos_z": "-4.25", "yaw": "1.5", "appearance_seed": "99"})
	check_eq(ch.id, 7)
	check_near(ch.x, 10.5, 0.0001)
	check_near(ch.z, -4.25, 0.0001)
	check_eq(ch.appearance_seed, 99)


func test_bad_values_are_repaired() -> void:
	var ch := CharacterData.normalize({"id": 1, "x": NAN, "z": 99999.0, "yaw": INF})
	check_near(ch.x, 0.0, 0.0001, "NaN x")
	check_near(ch.z, GameConfig.WORLD_HALF_SIZE, 0.0001, "pulled back inside the world")
	check_near(ch.yaw, 0.0, 0.0001, "inf yaw")


func test_new_character_spawns_on_ground() -> void:
	var ch := CharacterData.new_for({"id": 1, "username": "Fern", "username_lc": "fern"})
	check_eq(ch.name, "Fern")
	check_near(ch.y, Terrain.height(ch.x, ch.z), 0.0001)
	check_eq(ch.appearance_seed, CharacterData.new_for({"id": 2, "username": "Fern", "username_lc": "fern"}).appearance_seed, "seed stable")
