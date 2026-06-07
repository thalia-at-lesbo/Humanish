# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://tests/support/sim_fixture.gd"

# SimFacade command routing: founding settlements (and the min-distance rule),
# setting research, class-bounded moves, friendly stacking, and the settler's
# Found City action surfaced through the flyout.

func _settler(facade, player_id, x, y):
	var gs = facade.get_state()
	var u = load("res://src/sim/unit.gd").new()
	u.id = gs.next_unit_id(); u.unit_type_id = "settler"
	u.owner_player_id = player_id; u.x = x; u.y = y
	u.base_strength = 0; u.health = 100
	u.movement_total = 200; u.movement_left = 200
	gs.units.append(u)
	return u.id

# ── Found settlement ─────────────────────────────────────────────────────────

func test_found_settlement_creates_settlement() -> void:
	var facade = setup_facade(100)
	var gs = facade.get_state()
	var uid: int = _settler(facade, gs.players[0].id, 5, 5)
	gs.current_player_id = gs.players[0].id
	assert_true(facade.apply_command(Commands.found_settlement(gs.players[0].id, uid, "Alpha")),
		"Found settlement command should succeed")
	assert_eq(gs.settlements.size(), 1, "One settlement should exist")
	assert_eq(gs.settlements[0].name, "Alpha", "Settlement name set correctly")

func test_found_settlement_too_close_fails() -> void:
	var facade = setup_facade(200)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid1: int = _settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid1, "A"))
	var uid2: int = _settler(facade, gs.players[0].id, 6, 5)
	assert_false(facade.apply_command(Commands.found_settlement(gs.players[0].id, uid2, "B")),
		"Cannot found within min distance")

func test_first_city_is_founded_with_a_palace() -> void:
	var facade = setup_facade(101)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid: int = _settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid, "Capital"))
	assert_true(gs.settlements[0].has_structure("palace"),
		"A player's first city (its capital) is founded with the Palace")

func test_only_the_first_city_gets_a_palace() -> void:
	var facade = setup_facade(102)
	var gs = facade.get_state()
	gs.current_player_id = gs.players[0].id
	var uid1: int = _settler(facade, gs.players[0].id, 5, 5)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid1, "Capital"))
	# A second city, far enough away to clear the minimum-distance check.
	var uid2: int = _settler(facade, gs.players[0].id, 20, 20)
	facade.apply_command(Commands.found_settlement(gs.players[0].id, uid2, "Second"))
	assert_eq(gs.settlements.size(), 2, "Both cities are founded")
	assert_true(gs.get_settlement(gs.settlements[0].id).has_structure("palace"),
		"The capital keeps its Palace")
	assert_false(gs.get_settlement(gs.settlements[1].id).has_structure("palace"),
		"A later city is not given a Palace")

func test_each_players_first_city_gets_its_own_palace() -> void:
	var facade = setup_facade(103, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var p0 = gs.players[0].id
	var p1 = gs.players[1].id

	gs.current_player_id = p0
	var u0: int = _settler(facade, p0, 5, 5)
	facade.apply_command(Commands.found_settlement(p0, u0, "ACity"))

	gs.current_player_id = p1
	var u1: int = _settler(facade, p1, 20, 20)
	facade.apply_command(Commands.found_settlement(p1, u1, "BCity"))

	for s in gs.settlements:
		assert_true(s.has_structure("palace"),
			"Every society's first city has its own Palace (" + s.name + ")")

func test_found_city_action_offered_and_works() -> void:
	var facade = setup_facade(31, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(6, 6).terrain_id = "grassland"
	var u = make_unit(gs, "settler", pid, 6, 6)

	var found_item = {}
	for it in facade.get_flyout_menu(6, 6):
		if int(it.get("action_id", -1)) == IDs.UnitMission.FOUND_SETTLEMENT:
			found_item = it
			break
	assert_false(found_item.empty(), "Flyout should offer Found City for a settler")

	var before = gs.settlements.size()
	assert_true(facade.apply_command(Commands.found_settlement(pid, int(found_item.get("unit_id", u.id)))),
		"Found settlement command should succeed")
	assert_eq(gs.settlements.size(), before + 1, "A new settlement should exist")
	assert_null(gs.get_unit(u.id), "The founding settler should be consumed")

func test_found_city_not_offered_for_warrior() -> void:
	var facade = setup_facade(32, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 7, 7)
	for it in facade.get_flyout_menu(7, 7):
		assert_true(int(it.get("action_id", -1)) != IDs.UnitMission.FOUND_SETTLEMENT,
			"A warrior must not be offered Found City")

# ── Research command ───────────────────────────────────────────────────────────

func test_set_research_command() -> void:
	var facade = setup_facade(300)
	var gs = facade.get_state()
	var p = gs.players[0]
	gs.current_player_id = p.id
	assert_true(facade.apply_command(Commands.set_research(p.id, "mining")),
		"Set research should succeed")
	assert_eq(p.current_research_id, "mining", "Research target set")

# ── Movement & stacking via commands ───────────────────────────────────────────

func test_move_stack_command_succeeds_on_open_map() -> void:
	var facade = setup_facade(123, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_unit(gs, "warrior", pid, 2, 2)
	assert_true(facade.apply_command(Commands.move_stack(pid, 2, 2, 3, 2)),
		"Moving a unit one tile on open land should succeed")

func test_friendly_units_may_stack_on_one_tile() -> void:
	var facade = setup_facade(1212, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	make_warrior(gs, pid, 5, 5)  # already on the target tile
	var b = make_unit(gs, "scout", pid, 6, 5)

	assert_true(facade.apply_command(Commands.move_stack(pid, 6, 5, 5, 5)),
		"A unit must be able to move onto a friendly-occupied tile")
	assert_eq([gs.get_unit(b.id).x, gs.get_unit(b.id).y], [5, 5],
		"The moving unit ends up on the shared tile")
	assert_eq(Stack.at(gs.units, 5, 5, pid).size(), 2, "Both friendly units now occupy the same tile")

# ── move_stack unit_ids subset: peel a single member off a stack ──────────────

func test_move_stack_moves_only_listed_units() -> void:
	var facade = setup_facade(135, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	var b = make_unit(gs, "scout", pid, 4, 4)
	assert_true(facade.apply_command(Commands.move_stack(pid, 4, 4, 5, 4, [a.id])),
		"Moving a single listed member should succeed")
	assert_eq([gs.get_unit(a.id).x, gs.get_unit(a.id).y], [5, 4], "The listed unit moves")
	assert_eq([gs.get_unit(b.id).x, gs.get_unit(b.id).y], [4, 4],
		"The unlisted stack member stays behind")

# ── Multi-turn go-to (§3.3) ─────────────────────────────────────────────────────

func test_move_to_far_tile_sets_goto_and_continues() -> void:
	var facade = setup_facade(321, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 5, 5)

	# Destination six tiles east — well beyond one turn of movement.
	assert_true(facade.apply_command(Commands.move_stack(pid, 5, 5, 11, 5)),
		"Issuing a far move should succeed")
	assert_true(gs.get_unit(u.id).x < 11, "It does not reach the far tile in one turn")
	assert_eq(gs.get_unit(u.id).goto_x, 11, "It remembers the destination (x)")
	assert_eq(gs.get_unit(u.id).goto_y, 5, "It remembers the destination (y)")

	# Simulate the start of later turns: refresh movement and resume the order.
	for _i in range(6):
		if gs.get_unit(u.id).x == 11:
			break
		gs.get_unit(u.id).movement_left = gs.get_unit(u.id).movement_total
		facade._resume_goto(pid)
	assert_eq([gs.get_unit(u.id).x, gs.get_unit(u.id).y], [11, 5],
		"The unit travels to the destination over several turns")
	assert_eq(gs.get_unit(u.id).goto_x, -1, "The go-to goal clears on arrival")

func test_adjacent_move_clears_goto() -> void:
	var facade = setup_facade(322, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 3, 3)
	facade.apply_command(Commands.move_stack(pid, 3, 3, 4, 3))
	assert_eq(gs.get_unit(u.id).goto_x, -1,
		"A move that reaches its target leaves no standing go-to order")

func test_goto_survives_save_load() -> void:
	var facade = setup_facade(323, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 5, 5)
	facade.apply_command(Commands.move_stack(pid, 5, 5, 11, 5))
	var saved: String = facade.save()
	assert_true(facade.load_save(saved), "reload the saved game")
	var ru = facade.get_state().get_unit(u.id)
	assert_eq(ru.goto_x, 11, "the standing go-to destination survives save/load")

func test_can_stack_move_true_for_open_tile_false_for_water() -> void:
	var facade = setup_facade(136, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	gs.map.get_tile(4, 4).terrain_id = "grassland"
	gs.map.get_tile(5, 4).terrain_id = "grassland"
	gs.map.get_tile(4, 5).terrain_id = "ocean"
	make_unit(gs, "warrior", pid, 4, 4)
	assert_true(facade.can_stack_move(4, 4, 5, 4),
		"An adjacent open land tile is a legal destination for a land unit")
	assert_false(facade.can_stack_move(4, 4, 4, 5),
		"Water is not a legal destination for a land unit")

func test_inspect_tile_clears_selection_and_records_tile() -> void:
	var facade = setup_facade(137, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var u = make_unit(gs, "warrior", pid, 4, 4)
	facade.select_unit(u.id)
	facade.inspect_tile(7, 7)
	assert_eq(facade.get_selection().head_unit(), -1, "Inspecting a tile clears the unit selection")
	assert_true(facade.get_selection().has_inspected_tile(), "…and records the inspected tile")

func test_tile_info_text_reports_terrain() -> void:
	var facade = setup_facade(138, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.map.get_tile(3, 3).terrain_id = "grassland"
	var text = facade.tile_info_text(3, 3)
	assert_true(text.find("Grassland") >= 0, "Tile info names the terrain")
	assert_true(text.find("Yields") >= 0, "Tile info lists yields")

func test_mission_move_to_is_per_unit() -> void:
	# MISSION_MOVE_TO is a per-unit move command: only the named unit leaves a
	# shared tile, so it can be peeled off a stack.
	var facade = setup_facade(139, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var a = make_unit(gs, "warrior", pid, 4, 4)
	var b = make_unit(gs, "scout", pid, 4, 4)
	assert_true(facade.apply_command(Commands.mission_move_to(pid, a.id, 5, 4)),
		"A per-unit move order should succeed")
	assert_eq([gs.get_unit(a.id).x, gs.get_unit(a.id).y], [5, 4], "The ordered unit moves")
	assert_eq([gs.get_unit(b.id).x, gs.get_unit(b.id).y], [4, 4],
		"…the rest of the stack stays behind")
