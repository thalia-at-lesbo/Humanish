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

# Issue 6: Worker improvement commands and
# Issue 13: Scout Explore mission.

# ── Issue 6: Worker improvements ─────────────────────────────────────────────

func test_worker_can_build_improvement() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	# Give the player all relevant techs so any improvement is unlocked.
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"  # flat landform
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	assert_true(ok, "Worker should be able to start building a farm on grassland")
	assert_eq(w.building_improvement, "farm", "Worker building_improvement set to farm")
	assert_true(w.build_turns_left > 0, "Build turns left should be positive")

func test_worker_cannot_build_improvement_on_wrong_landform() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	# Hills landform — farm requires flat.
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "farm"))
	assert_false(ok, "Worker should not build a farm on hills (wrong landform)")

func test_worker_cannot_build_improvement_without_tech() -> void:
	var gs = make_gs(1)
	# Player has no techs; mine requires mining.
	gs.get_player(1).technologies = []
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_false(ok, "Worker should not build a mine without the mining tech")

func test_non_worker_cannot_build_improvement() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var warrior = make_warrior(gs, 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "grassland"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, warrior.id, "farm"))
	assert_false(ok, "Warriors cannot build improvements")

func test_worker_can_build_mine_on_hills() -> void:
	var gs = make_gs(1)
	gs.get_player(1).technologies = gs.db.technologies.keys().duplicate()
	var w = make_unit(gs, "worker", 1, 5, 5)
	gs.map.get_tile(5, 5).terrain_id = "hills"
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.build_improvement(1, w.id, "mine"))
	assert_true(ok, "Worker can build a mine on hills")

# ── Issue 13: Scout Explore mission ──────────────────────────────────────────

func test_explore_command_accepted_for_scout() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_explore(1, scout.id))
	assert_true(ok, "MISSION_EXPLORE should be accepted for a scout")
	assert_true(scout.is_exploring, "Scout should have is_exploring set after explore command")

func test_explore_command_rejected_for_warrior() -> void:
	var gs = make_gs(1)
	var warrior = make_warrior(gs, 1, 5, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var ok: bool = facade.apply_command(Commands.mission_explore(1, warrior.id))
	assert_false(ok, "MISSION_EXPLORE must be rejected for non-recon units")
	assert_false(warrior.is_exploring, "Warrior should not have is_exploring set")

func test_exploring_scout_skipped_by_idle_cycle() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	facade._selection = load("res://src/api/selection_state.gd").new()
	gs.current_player_id = 1
	facade.cycle_idle_units(false)
	assert_true(facade.get_selection().head_unit() < 0,
		"An exploring scout must not be surfaced by idle-unit cycling")

func test_exploring_scout_does_not_block_end_turn() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	var state: int = facade.get_end_turn_state()
	assert_true(state != 2,
		"An exploring scout should not trigger the idle-units warning for end turn")

func test_unit_wake_cancels_explore() -> void:
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.unit_wake(1, scout.id))
	assert_false(scout.is_exploring, "UNIT_WAKE should cancel the explore mission")

func test_explore_mission_moves_scout() -> void:
	# Place a scout on an open grassland map and set it exploring; end the turn;
	# the scout should have moved from its starting position.
	var gs = make_gs(1)
	gs.get_player(1).treasury = 10000
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var start_x: int = scout.x
	var start_y: int = scout.y
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.end_turn(1))
	# The scout should have moved at least one step.
	var moved: bool = (scout.x != start_x or scout.y != start_y)
	assert_true(moved, "An exploring scout should move when the turn ends")

func test_explore_wakes_on_enemy_nearby() -> void:
	# Place a scout exploring; put an enemy warrior adjacent to it.
	# When the turn ends the scout should wake (is_exploring cleared) and a
	# notification should have been added.
	var gs = make_gs(2)
	gs.get_player(1).treasury = 10000
	gs.get_player(2).treasury = 10000
	for tile in gs.map.all_tiles():
		tile.terrain_id = "grassland"
	# Declare war so the enemy is treated as hostile.
	gs.alliances[0].at_war_with.append(2)
	gs.alliances[1].at_war_with.append(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	# Enemy unit within sight range (unit_sight default = 2).
	make_warrior(gs, 2, 6, 5)
	var facade = bare_facade(gs)
	gs.current_player_id = 1
	facade.apply_command(Commands.end_turn(1))
	assert_false(scout.is_exploring,
		"Scout should stop exploring when an enemy is spotted within sight range")

func test_explore_serializes_and_deserializes() -> void:
	var gs = make_gs(1)
	var scout = make_unit(gs, "scout", 1, 5, 5)
	scout.is_exploring = true
	var d: Dictionary = scout.serialize()
	assert_true(bool(d.get("is_exploring", false)),
		"serialize() must include is_exploring = true")
	var u2 = load("res://src/sim/unit.gd").deserialize(d)
	assert_true(u2.is_exploring,
		"deserialize() must restore is_exploring from the save dict")
