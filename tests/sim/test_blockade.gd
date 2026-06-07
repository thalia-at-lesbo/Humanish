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

# Naval blockade (§5.6): a hostile fleet off a coastal city chokes its trade.

# Coastal city for player 1 at (5,5); ocean to the south at (5,6).
func _coastal(gs):
	gs.map.get_tile(5, 6).terrain_id = "ocean"
	return make_settlement(gs, 1, 5, 5, 4)

func test_inland_city_never_blockaded():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = make_settlement(gs, 1, 5, 5, 4)  # all grassland around → inland
	gs.get_alliance(1).at_war_with.append(2)
	make_unit(gs, "galley", 2, 5, 6)
	assert_eq(TurnEngine._blockade_penalty(gs, s, p), 0, "an inland city cannot be blockaded")

func test_coastal_no_enemy_no_penalty():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	assert_eq(TurnEngine._blockade_penalty(gs, s, p), 0, "no fleet, no blockade")

func test_enemy_fleet_blockades():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	gs.get_alliance(1).at_war_with.append(2)
	make_unit(gs, "galley", 2, 5, 6)  # enemy ship adjacent
	assert_eq(TurnEngine._blockade_penalty(gs, s, p),
		gs.db.get_constant("blockade_commerce_penalty", 50),
		"a hostile fleet in range blockades the coastal city")

func test_fleet_at_peace_does_not_blockade():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	make_unit(gs, "galley", 2, 5, 6)  # not at war
	assert_eq(TurnEngine._blockade_penalty(gs, s, p), 0,
		"a fleet you are at peace with does not blockade")

func test_own_fleet_does_not_blockade():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	make_unit(gs, "galley", 1, 5, 6)  # your own ship
	assert_eq(TurnEngine._blockade_penalty(gs, s, p), 0, "your own fleet does not blockade you")

func test_land_unit_does_not_blockade():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	gs.get_alliance(1).at_war_with.append(2)
	make_warrior(gs, 2, 5, 6)  # land unit, even if adjacent
	assert_eq(TurnEngine._blockade_penalty(gs, s, p), 0, "only naval units blockade")

func test_wild_fleet_blockades():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	make_unit(gs, "galley", -2, 5, 6)  # wild raider fleet
	assert_eq(TurnEngine._blockade_penalty(gs, s, p),
		gs.db.get_constant("blockade_commerce_penalty", 50),
		"a wild fleet blockades too")

func test_out_of_range_fleet_does_not_blockade():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	gs.get_alliance(1).at_war_with.append(2)
	gs.map.get_tile(5, 12).terrain_id = "ocean"
	make_unit(gs, "galley", 2, 5, 12)  # far away (> blockade_range)
	assert_eq(TurnEngine._blockade_penalty(gs, s, p), 0, "a distant fleet does not blockade")

func test_blockade_cuts_commerce_in_growth():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	var s = _coastal(gs)
	# Two worked road tiles → 2 commerce before any blockade.
	gs.map.get_tile(6, 5).improvement_id = "road"
	gs.map.get_tile(7, 5).improvement_id = "road"
	s.worked_tiles = [[6, 5], [7, 5]]
	TurnEngine._settlement_growth(gs, s, p)
	var clear: int = s.output_commerce
	assert_eq(clear, 2, "two roads yield 2 commerce unblockaded")
	gs.get_alliance(1).at_war_with.append(2)
	make_unit(gs, "galley", 2, 5, 6)
	TurnEngine._settlement_growth(gs, s, p)
	assert_true(s.output_commerce < clear, "the blockade cuts the city's commerce")
