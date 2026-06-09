# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

class_name WildForces

# Spawning of wild (raider) forces per §9 — a provisional port of Civilization IV
# Beyond the Sword's barbarian generation (CvGame::createBarbarianUnits /
# createBarbarianCities; constants from CIV4HandicapInfo.xml). Adapted to this
# engine's structures and difficulty/pace tables.
#
# The model has three gates and a per-area density target:
#
#   * Turn gate    — nothing spawns until `wild_creation_turns_elapsed` turns have
#                    passed (scaled by game pace), the BtS iBarbarianCreationTurnsElapsed.
#   * Era gate     — organised wild units only appear once the game's current era
#                    clears the `no_wild_units` flag (BtS bNoBarbUnits / the "quiet
#                    animal phase"; this engine has no fauna yet, so the early era is
#                    simply silent — see designgaps).
#   * City-density — wild units hold off until the world has settled in:
#                    civ cities >= ratio_num/ratio_den * living civs (BtS 3/2 = 1.5x).
#
# Once the gates clear, each contiguous land area is topped up toward a target
# density of one wild unit per `unowned_tiles_per_wild_unit` *unowned* tiles in
# that area, refilling roughly a quarter of the deficit per world step:
#
#     needed = ((area_unowned / divisor) - area_existing) / 4 + 1   (only if > 0)
#
# (Naval raiders — `unowned_water_tiles_per_wild_unit` — are tabled in the data but
# not yet wired: WildAI is land-only. See designgaps / the doc's provisional note.)
#
# Everything draws from the shared `gs.rng` in pipeline order, so spawning is
# deterministic and captured by save/load.

# ── Ambient wild-unit spawning ──────────────────────────────────────────────────

static func spawn_turn(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	var diff: Dictionary = db.get_difficulty(game_state.difficulty_id)

	# Gate 1 — turn threshold, scaled by game pace (slower paces push it later).
	var gate: int = _scaled_turns(game_state,
		int(diff.get("wild_creation_turns_elapsed",
			db.get_constant("wild_creation_turns_elapsed", 30))))
	if game_state.turn_number < gate:
		return

	# Gate 2 — the current era still suppresses organised wild units.
	if _era_suppresses_wild(game_state, db):
		return

	# Gate 3 — the world is still too empty (civ cities < ratio * living civs).
	var num: int = db.get_constant("wild_city_ratio_num", 3)
	var den: int = db.get_constant("wild_city_ratio_den", 2)
	if den < 1:
		den = 1
	if _count_civ_cities(game_state) * den < _count_living_civs(game_state) * num:
		return

	var divisor: int = int(diff.get("unowned_tiles_per_wild_unit",
		db.get_constant("wild_land_per_unit", 80)))
	if divisor < 1:
		divisor = 1

	# Label contiguous land areas, each carrying its unowned count, its current wild
	# unit count, and the open tiles a new wild unit may spawn on.
	var areas: Array = _label_land_areas(game_state)

	# Global ceiling guards against many small areas each adding their "+1": total
	# wild land units never exceed one per `divisor` unowned land tiles (+1 slack).
	var total_unowned: int = 0
	for a in areas:
		total_unowned += a.unowned
	var global_cap: int = total_unowned / divisor + 1
	var total_wild: int = _count_wild_land_units(game_state)

	var unit_type: String = _strongest_wild_unit_type(game_state)

	for a in areas:
		if total_wild >= global_cap:
			break
		var target: int = a.unowned / divisor
		var deficit: int = target - a.wild_units
		if deficit <= 0:
			continue
		var needed: int = deficit / 4 + 1
		var placed: int = 0
		while placed < needed and total_wild < global_cap and not a.open.empty():
			var idx: int = rng.randi_range(0, a.open.size() - 1)
			var t = a.open[idx]
			a.open.remove(idx)
			_spawn_wild_unit(t.x, t.y, game_state, unit_type)
			placed += 1
			total_wild += 1

# ── Wild-city (raider camp) spawning ────────────────────────────────────────────

static func spawn_raider_settlement(game_state, rng: RNG) -> void:
	var db: DataDB = game_state.db
	var diff: Dictionary = db.get_difficulty(game_state.difficulty_id)

	# Turn gate (later than the unit gate, as in BtS).
	var gate: int = _scaled_turns(game_state,
		int(diff.get("wild_city_creation_turns_elapsed",
			db.get_constant("wild_city_creation_turns_elapsed", 35))))
	if game_state.turn_number < gate:
		return

	var divisor: int = int(diff.get("unowned_tiles_per_wild_city",
		db.get_constant("raider_land_per_camp", 130)))
	if divisor < 1:
		divisor = 1
	var prob: int = int(diff.get("wild_city_creation_prob",
		db.get_constant("wild_city_creation_prob", 6)))
	var min_dist: int = db.get_constant("wild_city_min_distance", 6)

	# Per area: respect the density cap, roll the creation chance, then place a camp
	# at least `min_dist` from any civ culture/settlement.
	for a in _label_land_areas(game_state):
		var cap: int = a.unowned / divisor
		if a.wild_cities >= cap:
			continue
		if not rng.rand_bool_percent(prob):
			continue
		var spot = _pick_city_tile(game_state, a, min_dist, rng)
		if spot != null:
			_spawn_raider_settlement(spot.x, spot.y, game_state)

# ── Area labelling ──────────────────────────────────────────────────────────────

# Flood-fill the map into contiguous passable-land areas (8-connectivity, matching
# BtS's area grouping). Each returned area is a Dictionary:
#   { tiles, unowned, open, wild_units, wild_cities }
# where `open` is the unowned, unoccupied tiles a wild unit may spawn on (kept a
# little clear of civ units/cities by `wild_spawn_min_distance`).
static func _label_land_areas(game_state) -> Array:
	var db: DataDB = game_state.db
	var map = game_state.map
	var min_clear: int = db.get_constant("wild_spawn_min_distance", 2)

	# area_of["x,y"] -> area index, computed once.
	var area_of: Dictionary = {}
	var areas: Array = []
	for tile in map.all_tiles():
		if not _is_passable_land(tile, db):
			continue
		var key: String = "%d,%d" % [tile.x, tile.y]
		if area_of.has(key):
			continue
		# New area: BFS over passable-land neighbours.
		var idx: int = areas.size()
		var area: Dictionary = {
			"tiles": [], "unowned": 0, "open": [], "wild_units": 0, "wild_cities": 0}
		areas.append(area)
		var queue: Array = [tile]
		area_of[key] = idx
		while not queue.empty():
			var t = queue.pop_back()
			area.tiles.append(t)
			if t.owner_player_id < 0:
				area.unowned += 1
				if _is_open_spawn_tile(game_state, t, min_clear):
					area.open.append(t)
			for nb in map.neighbours8(t.x, t.y):
				if not _is_passable_land(nb, db):
					continue
				var nkey: String = "%d,%d" % [nb.x, nb.y]
				if area_of.has(nkey):
					continue
				area_of[nkey] = idx
				queue.append(nb)

	# Tally existing wild units / cities into their area.
	for u in game_state.units:
		if u.is_wild:
			var k: String = "%d,%d" % [u.x, u.y]
			if area_of.has(k):
				areas[area_of[k]].wild_units += 1
	for s in game_state.settlements:
		if s.owner_player_id == -2:
			var k2: String = "%d,%d" % [s.x, s.y]
			if area_of.has(k2):
				areas[area_of[k2]].wild_cities += 1

	return areas

# ── Tile predicates ─────────────────────────────────────────────────────────────

static func _is_passable_land(tile, db: DataDB) -> bool:
	var ter: Dictionary = db.get_terrain(tile.terrain_id)
	return ter.get("domain", "land") == "land" and not ter.get("impassable", false)

# A tile a wild unit may spawn on: unowned, no unit, no settlement, and at least
# `min_clear` tiles from any civ unit or settlement (BtS MIN_BARBARIAN_STARTING_DISTANCE).
static func _is_open_spawn_tile(game_state, tile, min_clear: int) -> bool:
	if tile.owner_player_id >= 0:
		return false
	if not Stack.at(game_state.units, tile.x, tile.y).empty():
		return false
	if game_state.get_settlement_at(tile.x, tile.y) != null:
		return false
	var map = game_state.map
	for u in game_state.units:
		if u.owner_player_id >= 0 and map.distance(tile.x, tile.y, u.x, u.y) < min_clear:
			return false
	for s in game_state.settlements:
		if s.owner_player_id >= 0 and map.distance(tile.x, tile.y, s.x, s.y) < min_clear:
			return false
	return true

# Pick a tile in `area` for a wild city: open (no unit/settlement) and at least
# `min_dist` from any civ-owned (cultural) tile and any settlement. null if none.
static func _pick_city_tile(game_state, area: Dictionary, min_dist: int, rng: RNG):
	var map = game_state.map
	var choices: Array = []
	for t in area.tiles:
		if t.owner_player_id >= 0:
			continue
		if not Stack.at(game_state.units, t.x, t.y).empty():
			continue
		if game_state.get_settlement_at(t.x, t.y) != null:
			continue
		var ok: bool = true
		for s in game_state.settlements:
			if map.distance(t.x, t.y, s.x, s.y) < min_dist:
				ok = false
				break
		if ok:
			# Also keep clear of any civ cultural tile.
			for other in map.tiles_in_range(t.x, t.y, min_dist - 1):
				if other.owner_player_id >= 0:
					ok = false
					break
		if ok:
			choices.append(t)
	if choices.empty():
		return null
	return choices[rng.randi_range(0, choices.size() - 1)]

# ── Gate helpers ────────────────────────────────────────────────────────────────

# Turn count scaled by game pace: a 40-turn gate becomes ~60 on Epic, ~120 on
# Marathon, ~27 on Quick (mirrors BtS's GameSpeed barb-percent scaling).
static func _scaled_turns(game_state, base: int) -> int:
	var pace: Dictionary = game_state.db.get_pace(game_state.pace_id)
	var scale: int = int(pace.get("growth_scale", 100))
	if scale < 1:
		scale = 100
	return base * scale / 100

# True while the game's current era (the most advanced any player has reached)
# still carries the no_wild_units flag.
static func _era_suppresses_wild(game_state, db: DataDB) -> bool:
	var era: int = 0
	for p in game_state.players:
		var e: int = Eras.player_era(p, db)
		if e > era:
			era = e
	var age = Eras.age_at(era, db)
	return bool(age.get("no_wild_units", false))

static func _count_civ_cities(game_state) -> int:
	var n: int = 0
	for s in game_state.settlements:
		if s.owner_player_id >= 0:
			n += 1
	return n

static func _count_living_civs(game_state) -> int:
	var n: int = 0
	for p in game_state.players:
		if not p.is_eliminated:
			n += 1
	return n if n > 0 else 1

static func _count_wild_land_units(game_state) -> int:
	var n: int = 0
	for u in game_state.units:
		if u.is_wild:
			n += 1
	return n

# The strongest generic land unit the most-advanced player has unlocked, so ambient
# raiders scale with the game's tech (resources deliberately ignored, like the wave
# path). Mirrors WildAI._strongest_wild_unit_type; kept local to avoid coupling the
# spawner to the AI module.
static func _strongest_wild_unit_type(game_state) -> String:
	var db: DataDB = game_state.db
	var leader = null
	for p in game_state.players:
		if leader == null or p.technologies.size() > leader.technologies.size():
			leader = p

	var best_id: String = "warrior"
	var best_str: int = -1
	for uid in db.units:
		var ud: Dictionary = db.units[uid]
		if ud.get("domain", "land") != "land":
			continue
		if str(ud.get("unique_to", "")) != "":
			continue
		var bs: int = int(ud.get("base_strength", 0))
		if bs <= 0:
			continue
		var tech_req = ud.get("tech_required", null)
		if tech_req != null and str(tech_req) != "":
			if leader == null or not leader.has_tech(str(tech_req)):
				continue
		if bs > best_str:
			best_str = bs
			best_id = str(uid)
	return best_id

# ── Spawning primitives ─────────────────────────────────────────────────────────

static func _spawn_wild_unit(x: int, y: int, game_state, unit_type_id: String = "warrior") -> void:
	var db: DataDB = game_state.db
	var unit_data: Dictionary = db.get_unit(unit_type_id)
	var u := Unit.new()
	u.id = game_state.next_unit_id()
	u.unit_type_id = unit_type_id
	u.owner_player_id = -2  # -2 = wild
	u.x = x; u.y = y
	u.base_strength = int(unit_data.get("base_strength", 5))
	u.movement_total = int(unit_data.get("movement", 200))
	u.movement_left = u.movement_total
	u.is_wild = true
	game_state.units.append(u)

static func _spawn_raider_settlement(x: int, y: int, game_state) -> void:
	var s := Settlement.new()
	s.id = game_state.next_settlement_id()
	s.name = "Raider Camp"
	s.owner_player_id = -2
	s.x = x; s.y = y
	s.population = 1
	game_state.settlements.append(s)
