# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name Assembly

# §7.2 Diplomatic assemblies, elections & resolutions (PROVISIONAL).
#
# A world voting body, founded by a world wonder, that elects a presiding resident
# and passes binding empire-wide resolutions. Two bodies exist: the religious
# assembly (Apostolic Palace, organised around one belief) and the secular United
# Nations (organised around all players); the secular body supersedes the religious.
#
# Pure static, like the rest of sim/. The lifecycle is driven once per whole-world
# step (§3.7) from TurnEngine via world_tick():
#   • a session OPENS on a fixed cadence, recording one proposal (a leadership
#     election while there is no resident, otherwise a random eligible resolution);
#   • every member then has one player-turn to cast a weighted Yea/Nay/Abstain
#     (humans through SimFacade.cast_assembly_vote / the CHOOSE_ELECTION popup,
#     computer players through PlayerAI.manage_assembly → ai_vote);
#   • the proposal RESOLVES on the next world step: non-voters abstain, votes are
#     tallied by weight, and a passing proposal's effect is applied.
# Every random draw goes through the shared gs.rng so sessions are reproducible and
# captured by save/load. All magnitudes live in data/constants.json and
# data/resolutions.json.

const VOTE_YEA := "yea"
const VOTE_NAY := "nay"
const VOTE_ABSTAIN := "abstain"

# ── Active body / gating ───────────────────────────────────────────────────────

# Which assembly currently exists, gated on its founding wonder. The secular United
# Nations supersedes the religious Apostolic Palace. "" when neither wonder is built.
static func active_body(gs) -> String:
	var has_religious: bool = false
	for s in gs.settlements:
		if s.has_structure("united_nations"):
			return "secular"
		if s.has_structure("apostolic_palace"):
			has_religious = true
	return "religious" if has_religious else ""

# The belief the religious assembly organises around: the faith of the city holding
# the Apostolic Palace. "" for the secular body (or an unfaithful Palace).
static func _religious_belief(gs) -> String:
	for s in gs.settlements:
		if s.has_structure("apostolic_palace"):
			return str(s.belief_id)
	return ""

# ── Membership & vote weight ───────────────────────────────────────────────────

# Religious members weight by population of their cities holding the assembly belief;
# secular members (the United Nations guarantees eligibility for all) weight by total
# governed population.
static func vote_weight(gs, player, body: String) -> int:
	if player == null or player.is_eliminated:
		return 0
	var belief: String = _religious_belief(gs)
	var w: int = 0
	for s in gs.settlements:
		if s.owner_player_id != player.id:
			continue
		if body == "religious":
			if belief != "" and s.belief_id == belief:
				w += s.population
		else:
			w += s.population
	return w

static func is_member(gs, player, body: String) -> bool:
	if player == null or player.is_eliminated:
		return false
	if body == "secular":
		return true
	if body == "religious":
		return vote_weight(gs, player, body) > 0
	return false

# Every eligible member, in player order (deterministic).
static func _members(gs, body: String) -> Array:
	var out: Array = []
	for p in gs.players:
		if is_member(gs, p, body):
			out.append(p)
	return out

# ── Lifecycle (called from the world step) ─────────────────────────────────────

static func world_tick(gs, rng) -> void:
	var body: String = active_body(gs)
	if body == "":
		# No founding wonder (or it was razed): no assembly.
		if not gs.assembly.empty():
			gs.assembly = {}
		return

	# Establish or re-establish the record when the body first appears or changes.
	if gs.assembly.empty() or str(gs.assembly.get("kind", "")) != body:
		_establish(gs, body)
	else:
		gs.assembly["belief_id"] = _religious_belief(gs) if body == "religious" else ""

	# One action per world tick. A proposal opened last session has now had a full
	# round of player turns to gather votes, so resolve it before opening another.
	if not gs.assembly.get("pending", {}).empty():
		_resolve_pending(gs)
		return

	var interval: int = gs.db.get_constant("assembly_session_interval", 12)
	if interval > 0 and gs.turn_number > 0 and gs.turn_number % interval == 0:
		_open_session(gs, rng)

static func _establish(gs, body: String) -> void:
	gs.assembly = {
		"kind": body,
		"belief_id": _religious_belief(gs) if body == "religious" else "",
		"resident_player_id": -1,
		"last_session_turn": -1,
		"standing": {},
		"pending": {}
	}

static func _open_session(gs, rng) -> void:
	var body: String = str(gs.assembly.get("kind", ""))
	var members: Array = _members(gs, body)
	if members.empty():
		return
	var resident: int = int(gs.assembly.get("resident_player_id", -1))
	var pending: Dictionary = {}

	if resident < 0 or gs.get_player(resident) == null:
		# No sitting resident → the chamber must first elect one.
		pending = _make_proposal(gs, "elect_resident", _front_runner(gs, members), -1)
	else:
		var pool: Array = _eligible_resolutions(gs, body)
		if pool.empty():
			return
		var res_id: String = pool[rng.randi_range(0, pool.size() - 1)]
		var candidate: int = resident
		var target_aid: int = -1
		if str(gs.db.get_resolution(res_id).get("kind", "resolution")) == "election":
			candidate = _front_runner(gs, members)
		if str(gs.db.get_resolution(res_id).get("effect", "")) == "trade_embargo":
			target_aid = _embargo_target(gs, resident)
			if target_aid < 0:
				return
		pending = _make_proposal(gs, res_id, candidate, target_aid)

	if pending.empty():
		return
	gs.assembly["pending"] = pending
	gs.assembly["last_session_turn"] = gs.turn_number
	gs.pending_assembly_events.append({
		"kind": "session_opened",
		"resolution_id": pending["resolution_id"],
		"name": pending["name"],
		"text": pending["text"]
	})

# Build the pending-proposal record (with an empty vote map) and its read-out text.
static func _make_proposal(gs, res_id: String, candidate_pid: int, target_aid: int) -> Dictionary:
	var res: Dictionary = gs.db.get_resolution(res_id)
	if res.empty():
		return {}
	var belief: String = str(gs.assembly.get("belief_id", ""))
	var pending: Dictionary = {
		"resolution_id": res_id,
		"name": str(res.get("name", res_id)),
		"candidate_player_id": candidate_pid,
		"target_alliance_id": target_aid,
		"belief_id": belief,
		"pass_share": int(res.get("pass_share", gs.db.get_constant("resolution_pass_share", 50))),
		"text": _fill_text(gs, str(res.get("text", "")), candidate_pid, target_aid, belief),
		"votes": {}
	}
	return pending

# ── Resolution ─────────────────────────────────────────────────────────────────

static func _resolve_pending(gs) -> void:
	var pending: Dictionary = gs.assembly.get("pending", {})
	var body: String = str(gs.assembly.get("kind", ""))
	var votes: Dictionary = pending.get("votes", {})
	var yea: int = 0
	var nay: int = 0
	var total: int = 0
	for member in _members(gs, body):
		var w: int = vote_weight(gs, member, body)
		if w <= 0:
			continue
		total += w
		var choice: String = str(votes.get(str(member.id), VOTE_ABSTAIN))
		if choice == VOTE_YEA:
			yea += w
		elif choice == VOTE_NAY:
			nay += w
	# Yea share of the whole chamber's weight (abstentions count present but not for,
	# so they make passage harder — as in a real quorum body).
	var pass_share: int = int(pending.get("pass_share", gs.db.get_constant("resolution_pass_share", 50)))
	var passed: bool = total > 0 and (yea * 100) / total >= pass_share
	var res_id: String = str(pending["resolution_id"])
	if passed:
		apply_effect(gs, res_id, pending)
	gs.pending_assembly_events.append({
		"kind": "resolution_resolved",
		"resolution_id": res_id,
		"name": str(pending.get("name", res_id)),
		"passed": passed,
		"yea": yea, "nay": nay, "total": total
	})
	gs.assembly["pending"] = {}

# Apply a passed proposal's binding effect. Provisional: elect_resident,
# diplomatic_victory, force_peace, civic_mandate, religion_mandate and resident_aid
# act immediately; trade_embargo/free_religion_spread/no_nuclear are recorded as
# standing effects (enforcement partial — see game-data.md §18).
static func apply_effect(gs, res_id: String, pending: Dictionary) -> void:
	var eff: String = str(gs.db.get_resolution(res_id).get("effect", res_id))
	match eff:
		"elect_resident":
			gs.assembly["resident_player_id"] = int(pending.get("candidate_player_id", -1))
		"diplomatic_victory":
			if "diplomatic" in gs.enabled_win_conditions:
				var cand = gs.get_player(int(pending.get("candidate_player_id", -1)))
				if cand != null:
					gs.winning_alliance_id = cand.alliance_id
		"force_peace":
			_force_peace(gs)
		"trade_embargo":
			gs.assembly["standing"]["trade_embargo"] = int(pending.get("target_alliance_id", -1))
		"civic_mandate":
			_civic_mandate(gs)
		"religion_mandate":
			_religion_mandate(gs, str(pending.get("belief_id", "")))
		"free_religion_spread":
			gs.assembly["standing"]["free_religion_spread"] = true
		"no_nuclear":
			gs.assembly["standing"]["no_nuclear"] = true
		"resident_aid":
			var r = gs.get_player(int(gs.assembly.get("resident_player_id", -1)))
			if r != null:
				r.treasury += gs.db.get_constant("resident_aid_gold", 100)

static func _force_peace(gs) -> void:
	for a in gs.alliances:
		a.at_war_with = []
		a.war_fatigue = {}

# Mandate the resident's government civic onto every member that has its enabling
# technology. Defiance anger (the §4.5 "assembly rulings" source) is left to a
# future contentment hook; the mandate itself is applied here.
static func _civic_mandate(gs) -> void:
	var resident = gs.get_player(int(gs.assembly.get("resident_player_id", -1)))
	if resident == null:
		return
	var civic: String = str(resident.policies.get("government", ""))
	if civic == "":
		return
	var pol: Dictionary = gs.db.policies.get("policies", {}).get(civic, {})
	var tech_req = pol.get("tech_required", null)
	for member in _members(gs, str(gs.assembly.get("kind", ""))):
		if tech_req == null or str(tech_req) == "" or member.has_tech(str(tech_req)):
			member.policies["government"] = civic

# Proclaim the assembly belief the state religion of every member that harbours it.
# The mandate is compelled, so it bypasses the §8.1 switching anarchy.
static func _religion_mandate(gs, belief: String) -> void:
	if belief == "":
		return
	for member in _members(gs, str(gs.assembly.get("kind", ""))):
		for s in gs.settlements:
			if s.owner_player_id == member.id and s.belief_id == belief:
				member.state_religion = belief
				break

# ── Voting (called from the facade / AI) ───────────────────────────────────────

static func has_open_session(gs) -> bool:
	if gs.assembly.empty():
		return false
	return not gs.assembly.get("pending", {}).empty()

static func pending_proposal(gs) -> Dictionary:
	if gs.assembly.empty():
		return {}
	return gs.assembly.get("pending", {})

static func has_voted(gs, player_id: int) -> bool:
	var pending: Dictionary = pending_proposal(gs)
	if pending.empty():
		return false
	return pending.get("votes", {}).has(str(player_id))

# Record one member's vote on the open proposal. Returns false if there is no open
# session, the player is not an eligible member, or the choice is not recognised.
static func cast_vote(gs, player_id: int, choice: String) -> bool:
	if not has_open_session(gs):
		return false
	if not (choice == VOTE_YEA or choice == VOTE_NAY or choice == VOTE_ABSTAIN):
		return false
	var body: String = str(gs.assembly.get("kind", ""))
	var p = gs.get_player(player_id)
	if not is_member(gs, p, body):
		return false
	gs.assembly["pending"]["votes"][str(player_id)] = choice
	return true

# Deterministic computer vote: self-interest, no RNG. Defaults to abstain.
static func ai_vote(gs, player_id: int) -> String:
	var pending: Dictionary = pending_proposal(gs)
	if pending.empty():
		return VOTE_ABSTAIN
	var me = gs.get_player(player_id)
	if me == null:
		return VOTE_ABSTAIN
	var eff: String = str(gs.db.get_resolution(str(pending["resolution_id"])).get("effect", ""))
	var cand = gs.get_player(int(pending.get("candidate_player_id", -1)))
	var cand_friendly: bool = cand != null and cand.alliance_id == me.alliance_id
	match eff:
		"elect_resident":
			return VOTE_YEA if cand_friendly else VOTE_NAY
		"diplomatic_victory":
			# Never hand the game to a rival; back only your own bloc.
			return VOTE_YEA if cand_friendly else VOTE_NAY
		"force_peace":
			var at_war: bool = false
			var a = gs.get_player_alliance(player_id)
			if a != null and not a.at_war_with.empty():
				at_war = true
			return VOTE_YEA if at_war else VOTE_ABSTAIN
		"trade_embargo":
			var tgt: int = int(pending.get("target_alliance_id", -1))
			return VOTE_NAY if tgt == me.alliance_id else VOTE_YEA
		"religion_mandate":
			return VOTE_YEA if me.state_religion == str(pending.get("belief_id", "")) else VOTE_NAY
		"civic_mandate":
			return VOTE_YEA
		"resident_aid":
			var r = gs.get_player(int(gs.assembly.get("resident_player_id", -1)))
			return VOTE_YEA if (r != null and r.alliance_id == me.alliance_id) else VOTE_NAY
		_:
			return VOTE_ABSTAIN

# ── Helpers ────────────────────────────────────────────────────────────────────

# The member with the greatest vote weight (ties → lowest player id) — the natural
# candidate for a leadership election.
static func _front_runner(gs, members: Array) -> int:
	var body: String = str(gs.assembly.get("kind", ""))
	var best_id: int = -1
	var best_w: int = -1
	for p in members:
		var w: int = vote_weight(gs, p, body)
		if w > best_w or (w == best_w and (best_id < 0 or p.id < best_id)):
			best_w = w
			best_id = p.id
	return best_id

# The strongest alliance other than the resident's — the natural embargo target.
static func _embargo_target(gs, resident_pid: int) -> int:
	var resident = gs.get_player(resident_pid)
	var own_aid: int = resident.alliance_id if resident != null else -1
	var weight: Dictionary = {}
	for p in gs.players:
		if p.is_eliminated or p.alliance_id == own_aid:
			continue
		weight[p.alliance_id] = int(weight.get(p.alliance_id, 0)) + _player_population(gs, p.id)
	var best_aid: int = -1
	var best_w: int = -1
	for aid in weight:
		var w: int = int(weight[aid])
		if w > best_w or (w == best_w and (best_aid < 0 or int(aid) < best_aid)):
			best_w = w
			best_aid = int(aid)
	return best_aid

static func _player_population(gs, player_id: int) -> int:
	var pop: int = 0
	for s in gs.settlements:
		if s.owner_player_id == player_id:
			pop += s.population
	return pop

# Resolution ids the active body may put forward this session (excludes the
# resident election, which is auto-proposed only when the chair is vacant).
static func _eligible_resolutions(gs, body: String) -> Array:
	var out: Array = []
	for res_id in gs.db.resolutions:
		if res_id == "_comment" or res_id == "elect_resident":
			continue
		var res: Dictionary = gs.db.resolutions[res_id]
		var rb: String = str(res.get("body", "any"))
		if rb != "any" and rb != body:
			continue
		var eff: String = str(res.get("effect", ""))
		if eff == "diplomatic_victory" and not ("diplomatic" in gs.enabled_win_conditions):
			continue
		if eff == "religion_mandate" and str(gs.assembly.get("belief_id", "")) == "":
			continue
		out.append(res_id)
	return out

# Substitute the {candidate} {proposer} {target} {belief} tokens in a proposal's
# read-out text with the names involved.
static func _fill_text(gs, raw: String, candidate_pid: int, target_aid: int, belief: String) -> String:
	var cand_name: String = _player_name(gs, candidate_pid)
	var t: String = raw
	t = t.replace("{candidate}", cand_name)
	t = t.replace("{proposer}", cand_name)
	t = t.replace("{target}", _alliance_name(gs, target_aid))
	t = t.replace("{belief}", _belief_name(gs, belief))
	return t

static func _player_name(gs, player_id: int) -> String:
	var p = gs.get_player(player_id)
	return p.name if (p != null and p.name != "") else "an unnamed power"

static func _alliance_name(gs, alliance_id: int) -> String:
	var a = gs.get_alliance(alliance_id)
	if a == null or a.member_player_ids.empty():
		return "a foreign power"
	return _player_name(gs, int(a.member_player_ids[0]))

static func _belief_name(gs, belief: String) -> String:
	if belief == "":
		return "the faith"
	var b: Dictionary = gs.db.beliefs.get(belief, {})
	return str(b.get("name", belief))
