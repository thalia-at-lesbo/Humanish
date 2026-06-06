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

# TurnPrompts walks the start-of-turn to-do list: it opens the tech chooser when
# no research is set, then the city screen for each idle city, chaining off each
# chooser's `closed` signal and offering each item at most once per turn.

func _harness(facade):
	var tech = load("res://scenes/screens/tech_chooser.gd").new()
	add_child_autofree(tech)
	tech.init(facade)
	var city = load("res://scenes/screens/city_screen.gd").new()
	add_child_autofree(city)
	city.init(facade)
	var tp = load("res://scenes/hud/turn_prompts.gd").new()
	add_child_autofree(tp)
	tp.init(facade, tech, city)
	return {"tech": tech, "city": city, "tp": tp}

func _facade_with_city(seed_val):
	var facade = setup_facade(seed_val, "small",
		[{"name": "A", "leader_id": "", "traits": [], "starting_gold": 50}], ["time"])
	var gs = facade.get_state()
	var pid = gs.players[0].id
	gs.current_player_id = pid
	var s = make_settlement(gs, pid, 5, 5, 2)
	s.production_queue = []   # idle: nothing queued
	return {"facade": facade, "gs": gs, "pid": pid, "city_id": s.id}

func test_prompts_research_then_idle_city() -> void:
	var f = _facade_with_city(81)
	var p = f.gs.get_player(f.pid)
	p.current_research_id = ""   # no research selected
	var h = _harness(f.facade)
	# Precondition: there is something to research, else the chooser is skipped.
	assert_true(h.tp._has_researchable(p), "the player should have a researchable tech")

	h.tp._begin(f.pid)
	assert_true(h.tech.visible, "no research → the tech chooser opens first")
	assert_false(h.city.visible, "the city screen waits until research is handled")

	# Player picks a tech; the chooser closes and the chain advances to the idle city.
	p.current_research_id = "pottery"
	h.tech._on_close()
	assert_false(h.tech.visible, "the tech chooser closes")
	assert_true(h.city.visible, "after research, the idle city is offered")
	assert_eq(h.city._city_id, f.city_id, "it opens the idle city")

func test_idle_city_only_when_research_already_set() -> void:
	var f = _facade_with_city(82)
	var p = f.gs.get_player(f.pid)
	p.current_research_id = "pottery"   # research already chosen
	var h = _harness(f.facade)

	h.tp._begin(f.pid)
	assert_false(h.tech.visible, "research is set → no tech prompt")
	assert_true(h.city.visible, "an idle city is still prompted")

func test_no_prompt_when_nothing_needs_attention() -> void:
	var f = _facade_with_city(83)
	var p = f.gs.get_player(f.pid)
	p.current_research_id = "pottery"
	f.gs.get_settlement(f.city_id).production_queue = [{"type": "unit", "id": "warrior"}]
	var h = _harness(f.facade)

	h.tp._begin(f.pid)
	assert_false(h.tech.visible, "research set → no tech prompt")
	assert_false(h.city.visible, "city is busy → no production prompt")
	assert_false(h.tp._chaining, "the chain ends when nothing needs attention")

func test_cancelling_research_does_not_reloop() -> void:
	var f = _facade_with_city(84)
	var p = f.gs.get_player(f.pid)
	p.current_research_id = ""
	var h = _harness(f.facade)

	h.tp._begin(f.pid)
	assert_true(h.tech.visible, "tech chooser opens")
	# Player cancels without choosing — research stays empty.
	h.tech._on_close()
	# It must not re-open the tech chooser (offered once per turn); it moves on to
	# the idle city instead.
	assert_false(h.tech.visible, "cancelled tech chooser is not reopened")
	assert_true(h.city.visible, "the chain still advances to the idle city")

func test_ai_player_is_not_prompted() -> void:
	var f = _facade_with_city(85)
	var p = f.gs.get_player(f.pid)
	p.is_ai = true
	p.current_research_id = ""
	var h = _harness(f.facade)
	h.tp._on_turn_started(f.pid)   # the public entry point checks is_ai
	# _on_turn_started defers _begin, but an AI player must be filtered out before
	# anything is deferred; drive _begin directly too to be sure nothing opens.
	h.tp._begin(f.pid)
	assert_false(h.tech.visible, "AI turns never raise a chooser")
	assert_false(h.city.visible, "AI turns never raise a chooser")
