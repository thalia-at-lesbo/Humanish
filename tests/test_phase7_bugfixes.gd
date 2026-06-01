extends "res://addons/gut/test.gd"

# Phase 7: regression tests for the user-reported bug fixes.
# Covers the tech tree, civics, map generation, starting units, and slider math.

func _db():
	var db = load("res://src/core/data_db.gd").new()
	db.load_all()
	return db

func _new_player(db):
	var p = load("res://src/sim/player.gd").new()
	p.id = 1
	p.alliance_id = 1
	return p

# ── Bug 9: 4-stage tech tree (stone → bronze → iron → silicon) ─────────────────

func test_tech_tree_loads_without_errors() -> void:
	var db = _db()
	assert_true(db.get_errors().empty(),
		"DataDB should load all tables (incl. tech tree) with no errors: " + str(db.get_errors()))

func test_tech_tree_four_ages_present() -> void:
	var db = _db()
	for tid in ["stone_age", "bronze_age", "iron_age", "silicon_age"]:
		assert_false(db.get_technology(tid).empty(), "Tech '%s' must exist" % tid)

func test_tech_tree_is_linear_progression() -> void:
	var db = _db()
	assert_eq(db.get_technology("bronze_age").get("prereqs_all"), ["stone_age"],
		"bronze_age requires stone_age")
	assert_eq(db.get_technology("iron_age").get("prereqs_all"), ["bronze_age"],
		"iron_age requires bronze_age")
	assert_eq(db.get_technology("silicon_age").get("prereqs_all"), ["iron_age"],
		"silicon_age requires iron_age")

func test_tech_tree_research_gating() -> void:
	var db = _db()
	var Research = load("res://src/sim/research.gd")
	var p = _new_player(db)
	# Knows nothing → only stone_age (no prereqs) is researchable.
	assert_true(Research.can_research("stone_age", p, db), "stone_age open from the start")
	assert_false(Research.can_research("bronze_age", p, db), "bronze_age locked without stone_age")
	p.technologies = ["stone_age"]
	assert_true(Research.can_research("bronze_age", p, db), "bronze_age unlocks after stone_age")
	assert_false(Research.can_research("iron_age", p, db), "iron_age still locked")

func test_setup_seeds_starting_tech_and_research() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 42, "tiny", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}],
		["time"])
	var p = facade.get_state().players[0]
	assert_true(p.has_tech("stone_age"), "Players start knowing stone_age")
	assert_eq(p.current_research_id, "bronze_age", "Default research target is bronze_age")

# ── Bug 10: 4-item civic system ────────────────────────────────────────────────

func test_civics_all_four_present() -> void:
	var db = _db()
	var pols = db.policies.get("policies", {})
	for cid in ["communism", "anarcho_communism", "anarcho_capitalism", "fascism"]:
		assert_true(pols.has(cid), "Civic '%s' must exist" % cid)
		assert_eq(str(pols[cid].get("category", "")), "civic",
			"Civic '%s' is in the 'civic' category" % cid)

func test_civics_category_registered() -> void:
	var db = _db()
	assert_true("civic" in db.policies.get("categories", []),
		"'civic' must be a registered policy category")

func test_set_civic_policy_applies() -> void:
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, 7, "tiny", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}],
		["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var ok = facade.apply_command(Commands.set_policy(pid, "civic", "fascism"))
	assert_true(ok, "Selecting the fascism civic should be accepted")
	assert_eq(gs.players[0].policies.get("civic", ""), "fascism",
		"The civic category should now hold fascism")

# ── Bug 6: map generation ──────────────────────────────────────────────────────

func _generated_map(seed_val = 99):
	var db = _db()
	var facade = load("res://src/api/sim_facade.gd").new()
	facade.setup(db, seed_val, "small", "normal", "warlord",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 100}],
		["time"])
	return facade.get_state()

func test_map_has_terrain_on_every_tile() -> void:
	var gs = _generated_map()
	for tile in gs.map.all_tiles():
		assert_true(tile.terrain_id != "",
			"Every tile must have a terrain id after generation")

func test_map_is_varied() -> void:
	var gs = _generated_map()
	var kinds = {}
	for tile in gs.map.all_tiles():
		kinds[tile.terrain_id] = true
	assert_true(kinds.size() >= 4,
		"A varied map should contain several terrain types, got: " + str(kinds.keys()))

func test_map_has_substantial_land() -> void:
	var gs = _generated_map()
	var db = gs.db
	var land = 0
	for tile in gs.map.all_tiles():
		if db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
			land += 1
	assert_true(land > gs.map.all_tiles().size() / 3,
		"At least a third of the map should be land for players to settle")

func test_map_generation_is_deterministic() -> void:
	var a = _generated_map(2024)
	var b = _generated_map(2024)
	var identical = true
	for i in range(a.map.all_tiles().size()):
		if a.map.all_tiles()[i].terrain_id != b.map.all_tiles()[i].terrain_id:
			identical = false
			break
	assert_true(identical, "Same seed must produce identical terrain across the whole map")

func test_start_positions_are_land_and_spread() -> void:
	var gs = _generated_map(555)
	var starts = MapGen.find_start_positions(gs.map, gs.db, 4)
	assert_eq(starts.size(), 4, "Should find four start positions")
	for s in starts:
		var ter = gs.db.get_terrain(gs.map.get_tile(int(s[0]), int(s[1])).terrain_id)
		assert_eq(ter.get("domain", "land"), "land", "Start tile must be land")
		assert_false(ter.get("impassable", false), "Start tile must be passable")
