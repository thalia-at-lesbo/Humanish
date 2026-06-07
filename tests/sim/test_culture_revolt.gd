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

# §4.9 cultural revolt / city flipping (provisional). Exercises CultureRevolt's
# eligibility, the revolt-power vs garrison comparison, the multi-success
# requirement, pressure relief, and the facade drain/signal.

# Build a two-player state with a P1 city at (5,5) and a P2 city one tile away,
# wired so P2 is the dominant culture on the P1 city's tile unless overridden.
# Forces the stochastic revolt check on (chance 100) and a single success to flip
# unless a test overrides those constants.
func _scenario(owner_inf = 10, rival_inf = 100, peak = 1, successes = 1):
	var gs = make_gs(2)
	gs.db.constants["revolt_check_chance"] = 100
	gs.db.constants["revolt_required_successes"] = successes
	var city = make_settlement(gs, 1, 5, 5, 3)
	city.peak_population = peak
	make_settlement(gs, 2, 5, 6, 3)   # rival city, distance 1, within culture_ring
	var tile = gs.map.get_tile(5, 5)
	tile.influence[1] = owner_inf
	tile.influence[2] = rival_inf
	return {"gs": gs, "city": city}

func test_no_flip_when_owner_out_cultures_rival():
	var sc = _scenario(100, 10)   # owner dominant
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 0, "no flip when owner leads culture")
	assert_eq(sc.city.owner_player_id, 1, "city retained")
	assert_eq(sc.city.revolt_progress, 0, "no progress accumulated")

func test_flip_when_rival_dominates_and_undefended():
	var sc = _scenario(10, 100)
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 1, "one flip recorded")
	assert_eq(int(flips[0]["from_player_id"]), 1, "from owner")
	assert_eq(int(flips[0]["to_player_id"]), 2, "to rival")
	assert_eq(sc.city.owner_player_id, 2, "ownership transferred")
	assert_true(sc.city.revolt_turns > 0, "enters occupation/revolt")
	assert_true(sc.city.in_disorder, "in disorder after flip")
	assert_eq(sc.city.revolt_progress, 0, "progress reset after flip")

func test_garrison_blocks_flip():
	var sc = _scenario(10, 100)   # peak 1, no adjacent rival tiles -> low power
	# Two warriors (data base_strength 2 each) -> garrison 1 + 2 + 2 = 5,
	# enough to meet the revolt power and stop the flip.
	make_warrior(sc.gs, 1, 5, 5)
	make_warrior(sc.gs, 1, 5, 5)
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 0, "garrison repels the cultural revolt")
	assert_eq(sc.city.owner_player_id, 1, "city retained")

func test_war_doubles_garrison_and_blocks_flip():
	var sc = _scenario(10, 100)
	make_warrior(sc.gs, 1, 5, 5)   # garrison 1 + 2 = 3 (would flip at peace)
	sc.gs.get_player_alliance(1).at_war_with.append(2)   # at war -> garrison ×2 = 6
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 0, "war-hardened garrison repels the flip")
	assert_eq(sc.city.owner_player_id, 1, "city retained")

func test_requires_multiple_successes():
	var sc = _scenario(10, 100, 1, 2)   # need two successful revolts
	var f1 = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(f1.size(), 0, "first success does not flip yet")
	assert_eq(sc.city.revolt_progress, 1, "one success banked")
	assert_eq(sc.city.owner_player_id, 1, "still owned after first success")
	var f2 = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(f2.size(), 1, "second success flips the city")
	assert_eq(sc.city.owner_player_id, 2, "ownership transferred")

func test_pressure_relief_resets_progress():
	var sc = _scenario(10, 100, 1, 3)   # need three; bank one then relieve
	CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(sc.city.revolt_progress, 1, "one success banked")
	# Owner re-takes the cultural lead on the tile.
	sc.gs.map.get_tile(5, 5).influence[1] = 1000
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 0, "no flip once pressure relieved")
	assert_eq(sc.city.revolt_progress, 0, "progress reset when no rival leads")

func test_no_flip_without_a_nearby_rival_city():
	var sc = _scenario(10, 100)
	# Move the rival city far away (beyond its culture_ring reach of the candidate).
	sc.gs.settlements[1].x = 18
	sc.gs.settlements[1].y = 18
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 0, "cultural pressure needs a nearby rival settlement")

func test_revolt_check_chance_gates_flips():
	var sc = _scenario(10, 100)
	sc.gs.db.constants["revolt_check_chance"] = 0   # never roll a revolt
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 0, "no revolt is ever checked at 0% chance")

func test_occupied_city_is_shielded():
	var sc = _scenario(10, 100)
	sc.city.revolt_turns = 4   # freshly conquered, still in occupation
	var flips = CultureRevolt.process_player(sc.gs, 1, sc.gs.rng, sc.gs.db)
	assert_eq(flips.size(), 0, "a city in occupation does not flip")
	assert_eq(sc.city.owner_player_id, 1, "city retained while shielded")

func test_revolt_progress_serializes():
	var gs = make_gs(2)
	var s = make_settlement(gs, 1, 3, 3, 2)
	s.revolt_progress = 2
	var restored = Settlement.deserialize(s.serialize())
	assert_eq(restored.revolt_progress, 2, "revolt_progress round-trips")

func test_facade_drains_flips_with_signal_and_notification():
	var gs = make_gs(2)
	var city = make_settlement(gs, 1, 5, 5, 3)
	var f = bare_facade(gs)
	f._notifications = []
	gs.pending_flips = [{
		"settlement_id": city.id, "from_player_id": 1, "to_player_id": 2
	}]
	watch_signals(f)
	f._drain_flips()
	assert_signal_emitted(f, "city_flipped")
	assert_true(gs.pending_flips.empty(), "flip queue drained")
	assert_eq(f._notifications.size(), 1, "a notification was raised")
