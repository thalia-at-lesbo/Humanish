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

# Trade routes (§8): driven by the trade_route_per_city civic (Free Market) and
# restricted by no_foreign_trade_routes (Mercantilism). Base routes default to 0.

func test_no_routes_without_civic():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 1, 9, 9, 6)
	assert_eq(TurnEngine._trade_route_commerce(gs, home, p), 0,
		"no trade routes without a granting civic")

func test_free_market_grants_a_route():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.policies = {"economy": "free_market"}  # trade_route_per_city: 1
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 1, 9, 9, 8)
	# yield = base 1 + (4+8)*25/100 = 1 + 3 = 4
	assert_eq(TurnEngine._trade_route_commerce(gs, home, p), 4,
		"Free Market runs one route to the best partner")

func test_route_picks_highest_yield_partner():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.policies = {"economy": "free_market"}
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 1, 9, 9, 8)   # bigger → higher yield
	make_settlement(gs, 1, 3, 3, 1)   # smaller
	assert_eq(TurnEngine._trade_route_commerce(gs, home, p), 4,
		"the single route goes to the largest partner")

func test_mercantilism_excludes_foreign_partners():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	p.policies = {"economy": "free_market", "labor": "mercantilism"}
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 2, 9, 9, 8)   # only a foreign partner exists
	assert_eq(TurnEngine._trade_route_commerce(gs, home, p), 0,
		"Mercantilism forbids foreign trade routes")

func test_no_route_to_a_partner_at_war():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	p.policies = {"economy": "free_market"}
	gs.get_alliance(1).at_war_with.append(2)
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 2, 9, 9, 8)   # foreign, but at war
	assert_eq(TurnEngine._trade_route_commerce(gs, home, p), 0,
		"no trade with an enemy you are at war with")

func test_foreign_partner_earns_bonus():
	var gs = make_gs(2)
	var p = gs.get_player(1)
	p.policies = {"economy": "free_market"}
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 2, 9, 9, 8)   # foreign, at peace
	# yield = 1 + (4+8)*25/100 + foreign_bonus 2 = 6
	assert_eq(TurnEngine._trade_route_commerce(gs, home, p), 6,
		"a peaceful foreign route earns the foreign bonus")

func test_multiple_routes_sum_top_partners():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	# Two domestic routes per city (stacking the civic value would need data; here
	# we drive the base constant to 2 to exercise multi-route selection).
	gs.db.constants["trade_routes_base"] = 2
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 1, 9, 9, 8)   # yield 4
	make_settlement(gs, 1, 3, 3, 4)   # yield 1 + (4+4)*25/100 = 3
	make_settlement(gs, 1, 2, 2, 1)   # yield 1 + (4+1)*25/100 = 2 (excluded)
	assert_eq(TurnEngine._trade_route_commerce(gs, home, p), 4 + 3,
		"the two best partners are summed")

func test_routes_feed_settlement_commerce():
	var gs = make_gs(1)
	var p = gs.get_player(1)
	p.policies = {"economy": "free_market"}
	var home = make_settlement(gs, 1, 5, 5, 4)
	make_settlement(gs, 1, 9, 9, 8)
	TurnEngine._settlement_growth(gs, home, p)
	assert_eq(home.output_commerce, 4,
		"trade-route commerce flows into the city's output")
