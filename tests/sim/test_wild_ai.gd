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

# §9 wild-forces AI (provisional): scouts detect players and rouse camps, camps
# muster waves over several turns then cool down, mustered raiders march toward and
# attack players, wave strength scales with the leading player's tech, and all of
# it survives save/load and stays deterministic.

# A raider camp (owner -2) helper.
func _camp(gs, x, y):
	var s = make_settlement(gs, -2, x, y, 1)
	s.name = "Raider Camp"
	return s

# ── Detection / alerting ───────────────────────────────────────────────────────

func test_scout_sighting_a_player_rouses_nearest_camp() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	make_warrior(gs, -2, 10, 10, true)      # scout sitting on the camp
	make_warrior(gs, 1, 12, 10)             # a player unit, distance 2 (within sight)

	WildAI._detect_and_alert(gs, gs.rng)

	assert_true(camp.alert_turns > 0, "Camp should be roused by the sighting")
	assert_eq(camp.alert_target_x, 12, "Alert aims at the sighted player tile (x)")
	assert_eq(camp.alert_target_y, 10, "Alert aims at the sighted player tile (y)")

func test_no_player_in_sight_leaves_camp_idle() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	make_warrior(gs, -2, 10, 10, true)
	make_warrior(gs, 1, 0, 0)               # far outside the detection radius

	WildAI._detect_and_alert(gs, gs.rng)
	assert_eq(camp.alert_turns, 0, "An unseen player must not raise an alert")

func test_player_settlement_also_triggers_detection() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	make_warrior(gs, -2, 11, 10, true)
	make_settlement(gs, 1, 13, 10, 3)       # a player city within sight

	WildAI._detect_and_alert(gs, gs.rng)
	assert_true(camp.alert_turns > 0, "A player city should be detectable too")

# ── Mustering / cooldown ───────────────────────────────────────────────────────

func test_muster_spawns_one_per_turn_then_cools_down() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	camp.alert_turns = 3
	camp.alert_target_x = 5
	camp.alert_target_y = 5

	var cooldown = gs.db.get_constant("wild_alert_cooldown", 8)

	for _i in range(3):
		WildAI._muster(gs, gs.rng)
	var spawned = 0
	for u in gs.units:
		if u.is_wild:
			spawned += 1
	assert_eq(spawned, 3, "A length-3 wave musters exactly three raiders")
	assert_eq(camp.alert_turns, 0, "Wave exhausted")
	assert_eq(camp.alert_cooldown, cooldown, "Cooldown begins once the wave ends")

	# During cooldown no new units appear and the timer winds down.
	WildAI._muster(gs, gs.rng)
	var after = 0
	for u in gs.units:
		if u.is_wild:
			after += 1
	assert_eq(after, 3, "No new spawns while cooling down")
	assert_eq(camp.alert_cooldown, cooldown - 1, "Cooldown ticks each world step")

func test_mustered_raiders_carry_the_wave_target() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 10, 10)
	camp.alert_turns = 1
	camp.alert_target_x = 4
	camp.alert_target_y = 7
	WildAI._muster(gs, gs.rng)
	var raider = null
	for u in gs.units:
		if u.is_wild:
			raider = u
	assert_not_null(raider, "A raider was mustered")
	assert_eq(raider.goto_x, 4, "Raider marches toward the wave target (x)")
	assert_eq(raider.goto_y, 7, "Raider marches toward the wave target (y)")
	assert_eq(raider.owner_player_id, -2, "Mustered unit belongs to the wild faction")

# ── Wave unit selection (gap 2 + 3) ────────────────────────────────────────────

func test_wave_unit_scales_with_leading_tech_ignoring_resources() -> void:
	var gs = make_gs(2)
	# No techs yet: only the tech-free warrior qualifies.
	assert_eq(WildAI._strongest_wild_unit_type(gs), "warrior",
		"Stone-age raiders are warriors")

	# Give the leader bronze working (axeman) but NO copper: resource is ignored,
	# so the stronger axeman is still chosen.
	gs.players[0].technologies = ["bronze_working"]
	assert_eq(WildAI._strongest_wild_unit_type(gs), "axeman",
		"Raiders upgrade with tech and ignore the copper requirement")

# ── Marching / combat ──────────────────────────────────────────────────────────

func test_raider_marches_toward_its_goal() -> void:
	var gs = make_gs(2)
	var u = make_warrior(gs, -2, 2, 2, true)
	u.goto_x = 8
	u.goto_y = 2
	WildAI.run(gs, gs.rng)
	assert_true(u.x > 2, "Raider advanced toward its goal (now x=%d)" % u.x)
	assert_eq(u.goto_y, 2, "Goal retained until arrival")

func test_raider_attacks_a_player_unit_in_its_path() -> void:
	var gs = make_gs(2)
	make_warrior(gs, 1, 5, 5)               # player defender
	var raider = make_warrior(gs, -2, 5, 6, true)
	raider.goto_x = 5
	raider.goto_y = 5
	WildAI.run(gs, gs.rng)

	var saw_combat = false
	for e in gs.pending_wild_events:
		if e["kind"] == "combat":
			saw_combat = true
	assert_true(saw_combat, "A raider reaching a player resolves combat")

func test_raider_razes_an_undefended_player_city() -> void:
	var gs = make_gs(2)
	var city = make_settlement(gs, 1, 5, 5, 1)
	city.peak_population = 1
	city.health = 1                          # one hit from falling
	var raider = make_warrior(gs, -2, 5, 6, true)
	raider.goto_x = 5
	raider.goto_y = 5
	WildAI.run(gs, gs.rng)

	assert_null(gs.get_settlement_at(5, 5), "Undefended city was razed")
	var razed = false
	for e in gs.pending_wild_events:
		if e["kind"] == "razed":
			razed = true
	assert_true(razed, "A raze event was recorded for the facade to surface")

# ── Facade surfacing ───────────────────────────────────────────────────────────

func test_facade_drains_wild_events_into_signals() -> void:
	var gs = make_gs(2)
	var f = bare_facade(gs)
	gs.pending_wild_events = [
		{"kind": "razed", "settlement_id": 7, "name": "Pompeii"}]
	watch_signals(f)
	f._drain_wild_events()
	assert_signal_emitted(f, "city_razed")
	assert_true(gs.pending_wild_events.empty(), "Queue cleared after draining")

# ── Persistence + determinism ──────────────────────────────────────────────────

func test_camp_alert_state_survives_save_load() -> void:
	var gs = make_gs(2)
	var camp = _camp(gs, 9, 9)
	camp.alert_turns = 2
	camp.alert_target_x = 3
	camp.alert_target_y = 4
	camp.alert_cooldown = 5

	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	var rc = restored.get_settlement_at(9, 9)
	assert_eq(rc.alert_turns, 2, "alert_turns persisted")
	assert_eq(rc.alert_target_x, 3, "alert_target_x persisted")
	assert_eq(rc.alert_target_y, 4, "alert_target_y persisted")
	assert_eq(rc.alert_cooldown, 5, "alert_cooldown persisted")

func test_aggressive_flag_persists_and_widens_reach() -> void:
	var gs = make_gs(2)
	var base = WildAI._scout_sight(gs, gs.db)
	gs.wild_aggressive = true
	assert_true(WildAI._scout_sight(gs, gs.db) > base,
		"Aggressive raiders see further")
	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	assert_true(restored.wild_aggressive, "Aggression flag survives save/load")

func test_wild_ai_is_deterministic_under_same_seed() -> void:
	var a = setup_facade(909, "tiny")
	var b = setup_facade(909, "tiny")
	run_turns(a, 12)
	run_turns(b, 12)
	assert_eq(a.state_hash(), b.state_hash(),
		"Identical seeds must yield identical wild-forces play")
