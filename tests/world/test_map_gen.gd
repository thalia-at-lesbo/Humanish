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

# Map generation: every map script fills every tile with valid terrain, is
# seed-deterministic, varies its land/water balance by type, and lays out start
# positions on passable land (within any per-type start bounds).

# Build a standalone map of `map_type` directly through MapGen (no full facade),
# so each script can be exercised cheaply.
func _gen(map_type, seed_val = 99, w = 60, h = 40):
	var db = make_db()
	var map = load("res://src/world/world_map.gd").new()
	map.init(w, h, true, false)
	var rng = load("res://src/core/rng.gd").new()
	rng.init(seed_val)
	MapGen.generate(map, db, rng, map_type)
	return {"map": map, "db": db}

func _land_count(g) -> int:
	var land = 0
	for tile in g.map.all_tiles():
		if g.db.get_terrain(tile.terrain_id).get("domain", "land") == "land":
			land += 1
	return land

func _all_map_types() -> Array:
	return make_db().get_map_types().keys()

# ── Original guarantees, now across every script ────────────────────────────────

func test_every_type_fills_every_tile_with_valid_terrain() -> void:
	for mt in _all_map_types():
		var g = _gen(mt)
		for tile in g.map.all_tiles():
			assert_true(tile.terrain_id != "",
				"%s: every tile must have a terrain id" % mt)
			assert_false(g.db.get_terrain(tile.terrain_id).empty(),
				"%s: terrain id '%s' must exist in the terrain table" % [mt, tile.terrain_id])

func test_every_type_is_varied() -> void:
	for mt in _all_map_types():
		var g = _gen(mt)
		var kinds = {}
		for tile in g.map.all_tiles():
			kinds[tile.terrain_id] = true
		assert_true(kinds.size() >= 3,
			"%s: a map should contain several terrain types, got %s" % [mt, kinds.keys()])

func test_every_type_has_some_land_and_some_water() -> void:
	for mt in _all_map_types():
		var g = _gen(mt)
		var total = g.map.all_tiles().size()
		var land = _land_count(g)
		assert_true(land > 0, "%s: must have land for players to settle" % mt)
		assert_true(land < total, "%s: must have some water" % mt)

func test_every_type_is_deterministic() -> void:
	for mt in _all_map_types():
		var a = _gen(mt, 2024)
		var b = _gen(mt, 2024)
		var identical = true
		var at = a.map.all_tiles()
		var bt = b.map.all_tiles()
		for i in range(at.size()):
			if at[i].terrain_id != bt[i].terrain_id or at[i].feature_id != bt[i].feature_id:
				identical = false
				break
		assert_true(identical, "%s: same seed must reproduce identical terrain + features" % mt)

# ── Shape-specific expectations ─────────────────────────────────────────────────

func test_pangaea_has_more_land_than_archipelago() -> void:
	# Pangaea is a single big landmass; Archipelago is fragmented and sea-heavy.
	assert_true(_land_count(_gen("pangaea")) > _land_count(_gen("archipelago")),
		"Pangaea should be far more land than Archipelago")

func test_continents_default_keeps_a_third_land() -> void:
	# The default script must stay settle-friendly (mirrors the old guarantee).
	var g = _gen("continents")
	assert_true(_land_count(g) > g.map.all_tiles().size() / 3,
		"Continents should leave at least a third of the map as land")

func test_inland_sea_centre_is_water() -> void:
	var g = _gen("inland_sea")
	var ter = g.db.get_terrain(g.map.get_tile(g.map.width / 2, g.map.height / 2).terrain_id)
	assert_eq(ter.get("domain", "land"), "sea", "Inland Sea must have open water at its centre")

func test_highlands_is_mountainous() -> void:
	# Highlands cranks the mountain/hill chances far above a normal script.
	var g_high = _gen("highlands")
	var g_plain = _gen("great_plains")
	assert_true(_rough_count(g_high) > _rough_count(g_plain),
		"Highlands should have many more mountains/hills than Great Plains")

func _rough_count(g) -> int:
	var n = 0
	for tile in g.map.all_tiles():
		if tile.terrain_id == "mountain" or tile.terrain_id == "hills":
			n += 1
	return n

func test_tectonics_builds_mountain_ranges() -> void:
	var g = _gen("tectonics")
	var mountains = 0
	for tile in g.map.all_tiles():
		if tile.terrain_id == "mountain":
			mountains += 1
	assert_true(mountains > 0, "Tectonics should raise mountains along plate boundaries")

func test_ice_age_is_cold() -> void:
	var g = _gen("ice_age")
	var cold = 0
	var warm = 0
	for tile in g.map.all_tiles():
		if tile.terrain_id == "snow" or tile.terrain_id == "tundra":
			cold += 1
		elif tile.terrain_id == "desert" or tile.terrain_id == "grassland":
			warm += 1
	assert_true(cold > warm, "Ice Age should be dominated by snow/tundra")

func test_oasis_has_central_desert_and_oases() -> void:
	var g = _gen("oasis")
	var centre = g.db.get_terrain(g.map.get_tile(g.map.width / 2, g.map.height / 2).terrain_id)
	assert_eq(centre.get("id", ""), "desert", "Oasis map should have a desert heart")
	var oases = 0
	for tile in g.map.all_tiles():
		if tile.feature_id == "oasis":
			oases += 1
	assert_true(oases > 0, "Oasis map should dot the desert with oases")

func test_shuffle_is_deterministic_and_valid() -> void:
	# Shuffle secretly resolves to a core script; the result must still be a fully
	# valid, reproducible map.
	var a = _gen("shuffle", 7777)
	var b = _gen("shuffle", 7777)
	var identical = true
	var at = a.map.all_tiles()
	var bt = b.map.all_tiles()
	for i in range(at.size()):
		if at[i].terrain_id != bt[i].terrain_id:
			identical = false
			break
	assert_true(identical, "Shuffle must reproduce the same hidden script for a seed")
	assert_true(_land_count(a) > 0, "Shuffle must still produce land")

# ── Terra: Old World starts, New World discoveries ──────────────────────────────

func test_terra_seeds_new_world_discoveries() -> void:
	var g = _gen("terra")
	var discoveries = 0
	for tile in g.map.all_tiles():
		if tile.has_discovery and tile.x >= g.map.width * 55 / 100:
			discoveries += 1
	assert_true(discoveries > 0, "Terra should seed exploration sites across the ocean")

func test_terra_start_positions_stay_in_old_world() -> void:
	var g = _gen("terra")
	var starts = MapGen.find_start_positions(g.map, g.db, 4, "terra")
	assert_eq(starts.size(), 4, "Should find four Old-World starts")
	var x_max = g.map.width * 42 / 100
	for s in starts:
		assert_true(int(s[0]) <= x_max,
			"Terra starts must stay within the Old World (x=%d, max=%d)" % [int(s[0]), x_max])

# ── Start positions (generic) ───────────────────────────────────────────────────

func test_start_positions_are_land_and_spread() -> void:
	for mt in ["continents", "pangaea", "fractal", "tectonics", "lakes"]:
		var g = _gen(mt, 555)
		var starts = MapGen.find_start_positions(g.map, g.db, 4, mt)
		assert_eq(starts.size(), 4, "%s: should find four start positions" % mt)
		for s in starts:
			var ter = g.db.get_terrain(g.map.get_tile(int(s[0]), int(s[1])).terrain_id)
			assert_eq(ter.get("domain", "land"), "land", "%s: start tile must be land" % mt)
			assert_false(ter.get("impassable", false), "%s: start tile must be passable" % mt)
