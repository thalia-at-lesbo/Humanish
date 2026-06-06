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

# HotseatManager turn-start flow. The opening player's turn is never announced
# via player_turn_started, so an AI opener must be driven by begin() — otherwise
# the game hangs on a player that never acts.

func _hsm(facade):
	var h = load("res://scenes/hotseat/hotseat_manager.gd").new()
	add_child_autofree(h)
	h.init(facade, null)   # no world_view needed for these tests
	return h

func test_ai_opening_player_is_driven_by_begin() -> void:
	var facade = setup_facade(4242, "small",
		[{"name": "CPU", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "Human", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.players[0].is_ai = true     # the game opens on an AI slot
	gs.players[1].is_ai = false
	gs.current_player_id = gs.players[0].id

	var h = _hsm(facade)
	h.begin()
	yield(get_tree(), "idle_frame")   # let the deferred AI turn run

	assert_eq(gs.current_player_id, gs.players[1].id,
		"begin() runs the AI opener's whole turn so play reaches the human (no hang)")

func test_human_opening_player_is_not_driven() -> void:
	var facade = setup_facade(4343, "small",
		[{"name": "Human", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "CPU", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.players[0].is_ai = false
	gs.players[1].is_ai = true
	gs.current_player_id = gs.players[0].id

	var h = _hsm(facade)
	h.begin()
	yield(get_tree(), "idle_frame")

	assert_eq(gs.current_player_id, gs.players[0].id,
		"A human opener keeps control; begin() does not advance their turn")

func test_begin_on_all_ai_does_not_error() -> void:
	# A spectator (all-AI) game should simply start running, not crash.
	var facade = setup_facade(4444, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50},
		 {"name": "B", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	gs.players[0].is_ai = true
	gs.players[1].is_ai = true
	gs.current_player_id = gs.players[0].id

	var h = _hsm(facade)
	h.begin()
	yield(get_tree(), "idle_frame")
	assert_true(true, "begin() on an all-AI game runs without error")
