extends TestCase
## Client: the client builds whatever world the server says it runs (s2c_world), so an island
## server shows its island. Ashgrove's server sends Ashgrove's config: nothing is rebuilt.

const ClientScript := preload("res://client/client.gd")


func _client() -> Node:
	var c = ClientScript.new()
	c.settings = ClientSettings.new()
	c.camera = Camera3D.new()
	c.add_child(c.camera)
	c.world = WorldBuilder.build()
	c.world.set_meta("world_config", WorldGen.config())
	c.add_child(c.world)
	c.grazers = GrazerFigures.new()
	c.world.add_child(c.grazers)
	c.zombai_figures = ZombaiFigures.new()
	c.world.add_child(c.zombai_figures)
	return c


func test_the_same_world_is_kept() -> void:
	expect_error("Parameter \"m\" is null") # freeing meshes on the headless dummy renderer
	WorldGen.reset()
	var c := _client()
	var before: Node3D = c.world
	c._on_world_config(WorldGen.config())
	check(c.world == before, "Ashgrove's server: the world built at start is kept")
	c.free()


func test_an_island_server_gets_its_island() -> void:
	expect_error("Parameter \"m\" is null")
	WorldGen.reset()
	var c := _client()
	var before: Node3D = c.world
	var avatar := Node3D.new()
	before.add_child(avatar)
	c.avatars[7] = {"node": avatar}
	var t := Time.get_ticks_msec()
	c._on_world_config({"seed": 5, "size_m": 3000.0, "gen_version": WorldGen.ISLAND})
	var ms := Time.get_ticks_msec() - t
	check(WorldGen.is_island(), "the client now runs the server's island")
	check(c.world != before, "a new world was built")
	check(c.world.get_parent() == c, "and put in place")
	var terrain := c.world.get_node("Terrain") as TerrainStream
	check(terrain != null and terrain.streaming, "its ground streams in around you")
	check(c.grazers.get_parent() == c.world and c.zombai_figures.get_parent() == c.world, "herds and the Zombai moved over")
	check(avatar.get_parent() == c.world, "avatars moved over")
	check(ms < 15000, "built in %d ms" % ms)
	print("[test] island world built in %d ms" % ms)
	terrain.finish()
	c.free()
	WorldGen.reset()
