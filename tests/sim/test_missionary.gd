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

# Missionary-driven belief spread (§8): the SPREAD_BELIEF command and the
# missionary build-gate.

func test_missionary_spreads_state_religion():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	p.state_religion = "buddhism"
	gs.current_player_id = 1
	var target = make_settlement(gs, 2, 8, 8, 3)  # faithless foreign city
	var miss = make_unit(gs, "missionary", 1, 8, 8)
	var f = bare_facade(gs)
	assert_true(f.apply_command(Commands.spread_belief(1, miss.id, target.id)),
		"missionary spreads the player's religion")
	assert_eq(target.belief_id, "buddhism", "the city adopts the religion")
	assert_null(gs.get_unit(miss.id), "the missionary is consumed")

func test_spread_requires_spread_religion_tag():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.state_religion = "buddhism"
	gs.current_player_id = 1
	var target = make_settlement(gs, 1, 8, 8, 3)
	var warrior = make_warrior(gs, 1, 8, 8)
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.spread_belief(1, warrior.id, target.id)),
		"a non-missionary cannot spread religion")

func test_spread_requires_unit_on_city_tile():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.state_religion = "buddhism"
	gs.current_player_id = 1
	var target = make_settlement(gs, 1, 8, 8, 3)
	var miss = make_unit(gs, "missionary", 1, 2, 2)  # elsewhere
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.spread_belief(1, miss.id, target.id)),
		"the missionary must stand on the target city")

func test_spread_fails_into_a_faithful_city():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.state_religion = "buddhism"
	gs.current_player_id = 1
	var target = make_settlement(gs, 1, 8, 8, 3)
	target.belief_id = "christianity"
	var miss = make_unit(gs, "missionary", 1, 8, 8)
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.spread_belief(1, miss.id, target.id)),
		"a city that already follows a religion is not converted")
	assert_not_null(gs.get_unit(miss.id), "the missionary survives a failed spread")

func test_spread_fails_without_a_religion():
	var gs = make_gs(1)
	gs.current_player_id = 1
	var target = make_settlement(gs, 1, 8, 8, 3)
	var miss = make_unit(gs, "missionary", 1, 8, 8)
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.spread_belief(1, miss.id, target.id)),
		"a player with no religion has nothing to spread")

func test_theocracy_blocks_foreign_spread():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	p.state_religion = "buddhism"
	var owner = gs.get_player(2)
	owner.state_religion = "christianity"
	owner.policies = {"religion": "theocracy"}  # blocks_nonstate_spread
	gs.current_player_id = 1
	var target = make_settlement(gs, 2, 8, 8, 3)
	var miss = make_unit(gs, "missionary", 1, 8, 8)
	var f = bare_facade(gs)
	assert_false(f.apply_command(Commands.spread_belief(1, miss.id, target.id)),
		"Theocracy blocks a non-state religion from spreading in")

func test_ai_gate_needs_religion_and_monastery():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	assert_false(PlayerAI._can_train_missionary(gs, s, p),
		"no religion, no missionary")
	p.state_religion = "buddhism"
	assert_false(PlayerAI._can_train_missionary(gs, s, p),
		"religion but no monastery / civic")
	s.structures.append("monastery")
	assert_true(PlayerAI._can_train_missionary(gs, s, p),
		"a Monastery trains missionaries")

func test_ai_gate_organized_religion_waives_monastery():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 3)
	p.state_religion = "buddhism"
	p.policies = {"religion": "organized_religion"}  # missionary_without_monastery
	assert_true(PlayerAI._can_train_missionary(gs, s, p),
		"Organized Religion lets any city train missionaries")
