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

# §7.2 Diplomatic assemblies, elections & resolutions (provisional). Exercises the
# founding-wonder gate, membership/vote weight, the session→vote→resolve lifecycle,
# resolution effects, and serialization. The facade voting path lives in
# tests/api/test_sim_facade.gd-adjacent suites; here we drive the Assembly module
# and GameState directly.

const APOSTOLIC := "apostolic_palace"
const UN := "united_nations"

# Build a 3-player state where player 1 founds the religious assembly via the
# Apostolic Palace in a christian capital. Players 2/3 also hold christian cities so
# they are eligible religious members.
func _religious_gs(seed_val = 7):
	var gs = make_gs(3, seed_val)
	var c1 = make_settlement(gs, 1, 3, 3, 5)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	var c2 = make_settlement(gs, 2, 8, 8, 3)
	c2.belief_id = "christianity"
	var c3 = make_settlement(gs, 3, 14, 14, 2)
	c3.belief_id = "christianity"
	return gs

# ── Founding-wonder gate ───────────────────────────────────────────────────────

func test_no_assembly_without_a_founding_wonder() -> void:
	var gs = make_gs(2)
	make_settlement(gs, 1, 3, 3, 4)
	assert_eq(Assembly.active_body(gs), "", "No wonder, no assembly")
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_true(gs.assembly.empty(), "world_tick founds nothing without a wonder")

func test_apostolic_palace_founds_religious_body() -> void:
	var gs = _religious_gs()
	assert_eq(Assembly.active_body(gs), "religious", "Apostolic Palace founds the religious body")

func test_united_nations_supersedes_religious_body() -> void:
	var gs = _religious_gs()
	gs.get_settlement(1).structures.append(UN)
	assert_eq(Assembly.active_body(gs), "secular", "The UN supersedes the Apostolic Palace")

func test_assembly_torn_down_when_wonder_lost() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_false(gs.assembly.empty(), "Assembly established")
	gs.get_settlement(1).structures.erase(APOSTOLIC)
	Assembly.world_tick(gs, gs.rng)
	assert_true(gs.assembly.empty(), "Losing the founding wonder dissolves the assembly")

# ── Membership & vote weight ───────────────────────────────────────────────────

func test_religious_weight_counts_only_believing_cities() -> void:
	var gs = _religious_gs()
	# Player 1 also has a non-believing city: it must not add weight.
	var extra = make_settlement(gs, 1, 5, 5, 9)
	extra.belief_id = ""
	assert_eq(Assembly.vote_weight(gs, gs.get_player(1), "religious"), 5,
		"Only the christian capital (pop 5) counts toward religious weight")

func test_secular_weight_counts_all_population() -> void:
	var gs = _religious_gs()
	var extra = make_settlement(gs, 1, 5, 5, 9)
	extra.belief_id = ""
	assert_eq(Assembly.vote_weight(gs, gs.get_player(1), "secular"), 14,
		"Secular weight is total population (5 + 9)")

func test_nonbelievers_are_not_religious_members() -> void:
	var gs = make_gs(2)
	var c1 = make_settlement(gs, 1, 3, 3, 4)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	make_settlement(gs, 2, 8, 8, 4)  # no belief
	assert_true(Assembly.is_member(gs, gs.get_player(1), "religious"), "Believer is a member")
	assert_false(Assembly.is_member(gs, gs.get_player(2), "religious"),
		"A player with no believing city is not a religious member")

# ── Session lifecycle: first session elects a resident ─────────────────────────

func test_first_session_opens_a_resident_election() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_true(Assembly.has_open_session(gs), "A session opens on the cadence")
	var pending = Assembly.pending_proposal(gs)
	assert_eq(str(pending["resolution_id"]), "elect_resident",
		"With no resident, the chamber first elects one")
	# Front-runner is the highest-weight member (player 1, pop 5).
	assert_eq(int(pending["candidate_player_id"]), 1, "Highest-weight member is the candidate")
	assert_true(str(pending["text"]).find("P1") >= 0, "Proposal text names the candidate")

func test_resident_elected_when_members_vote_yea() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)   # open
	for pid in [1, 2, 3]:
		assert_true(Assembly.cast_vote(gs, pid, Assembly.VOTE_YEA), "Member %d votes" % pid)
	Assembly.world_tick(gs, gs.rng)   # resolve
	assert_false(Assembly.has_open_session(gs), "Proposal resolved, session closed")
	assert_eq(int(gs.assembly["resident_player_id"]), 1, "The candidate becomes resident")

func test_proposal_fails_below_pass_share() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	# Yea weight 3 of 10 total (30%) is below the 50% pass share, so the motion fails.
	Assembly.cast_vote(gs, 1, Assembly.VOTE_NAY)   # weight 5
	Assembly.cast_vote(gs, 2, Assembly.VOTE_YEA)   # weight 3
	Assembly.cast_vote(gs, 3, Assembly.VOTE_NAY)   # weight 2
	Assembly.world_tick(gs, gs.rng)
	assert_eq(int(gs.assembly["resident_player_id"]), -1, "A defeated election seats no resident")

func test_non_member_cannot_vote() -> void:
	var gs = make_gs(2)
	var c1 = make_settlement(gs, 1, 3, 3, 4)
	c1.belief_id = "christianity"
	c1.structures.append(APOSTOLIC)
	make_settlement(gs, 2, 8, 8, 4)
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)
	assert_false(Assembly.cast_vote(gs, 2, Assembly.VOTE_YEA),
		"A non-member's vote is rejected")

# ── Resolution effects ─────────────────────────────────────────────────────────

func test_force_peace_ends_all_wars() -> void:
	var gs = _religious_gs()
	gs.get_alliance(1).at_war_with = [2]
	gs.get_alliance(2).at_war_with = [1]
	Assembly._establish(gs, "religious")
	gs.assembly["resident_player_id"] = 1
	Assembly.apply_effect(gs, "force_peace", {})
	assert_true(gs.get_alliance(1).at_war_with.empty(), "Aggressor's wars cleared")
	assert_true(gs.get_alliance(2).at_war_with.empty(), "Defender's wars cleared")

func test_diplomatic_victory_elects_a_winner_when_enabled() -> void:
	var gs = _religious_gs()
	gs.enabled_win_conditions = ["diplomatic"]
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "diplomatic_victory", {"candidate_player_id": 2})
	assert_eq(gs.winning_alliance_id, 2, "Passing the supreme-leadership motion wins the game")

func test_diplomatic_victory_inert_when_condition_disabled() -> void:
	var gs = _religious_gs()
	gs.enabled_win_conditions = ["time"]
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "diplomatic_victory", {"candidate_player_id": 2})
	assert_eq(gs.winning_alliance_id, -1, "No diplomatic win when the condition is off")

func test_religion_mandate_sets_state_religion() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "religion_mandate", {"belief_id": "christianity"})
	assert_eq(gs.get_player(2).state_religion, "christianity",
		"Members harbouring the faith adopt it as state religion")

func test_resident_aid_grants_gold() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	gs.assembly["resident_player_id"] = 1
	var before = gs.get_player(1).treasury
	Assembly.apply_effect(gs, "resident_aid", {})
	assert_eq(gs.get_player(1).treasury, before + gs.db.get_constant("resident_aid_gold", 100),
		"The resident receives the aid grant")

func test_civic_mandate_aligns_members() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	gs.assembly["resident_player_id"] = 1
	gs.get_player(1).policies["government"] = "despotism"
	Assembly.apply_effect(gs, "civic_mandate", {})
	assert_eq(str(gs.get_player(2).policies.get("government", "")), "despotism",
		"Members align to the resident's government civic")

func test_trade_embargo_recorded_as_standing_effect() -> void:
	var gs = _religious_gs()
	Assembly._establish(gs, "religious")
	Assembly.apply_effect(gs, "trade_embargo", {"target_alliance_id": 2})
	assert_eq(int(gs.assembly["standing"]["trade_embargo"]), 2,
		"The embargo target is recorded as a standing effect")

# ── Determinism / persistence ──────────────────────────────────────────────────

func test_assembly_state_round_trips_through_save_load() -> void:
	var gs = _religious_gs()
	gs.turn_number = 12
	Assembly.world_tick(gs, gs.rng)         # open a session
	Assembly.cast_vote(gs, 1, Assembly.VOTE_YEA)
	var restored = load("res://src/sim/game_state.gd").deserialize(gs.serialize(), gs.db)
	assert_eq(str(restored.assembly["kind"]), "religious", "Body survives save/load")
	assert_eq(str(restored.assembly["pending"]["resolution_id"]), "elect_resident",
		"An in-progress proposal survives save/load")
	assert_eq(str(restored.assembly["pending"]["votes"]["1"]), Assembly.VOTE_YEA,
		"Cast votes survive save/load")
