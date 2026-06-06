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

# Save/Load screen (§11 session/meta). Regression guard: the screen must render
# as a proper modal overlay — an opaque, full-rect backdrop that hides the live
# map — not a few stray widgets drawn straight over the map.

func _screen(facade):
	var sl = load("res://scenes/screens/save_load_screen.gd").new()
	add_child_autofree(sl)
	sl.init(facade)
	return sl

func _find_backdrop(node):
	for child in node.get_children():
		if child is ColorRect:
			return child
	return null

func test_show_screen_is_visible_with_content() -> void:
	var sl = _screen(setup_facade(91))
	sl.show_screen()
	assert_true(sl.visible, "Save/Load screen should be visible after show_screen()")
	assert_true(sl.get_child_count() > 0, "…and should build its content")

func test_screen_has_opaque_full_rect_backdrop() -> void:
	var sl = _screen(setup_facade(92))
	sl.show_screen()
	var bg = _find_backdrop(sl)
	assert_not_null(bg, "Screen must draw a backdrop so the map does not show through")
	assert_eq(bg.color.a, 1.0, "Backdrop must be fully opaque")
	assert_eq(bg.anchor_right, 1.0, "Backdrop spans the full width")
	assert_eq(bg.anchor_bottom, 1.0, "Backdrop spans the full height")

func test_screen_is_modal_full_rect() -> void:
	var sl = _screen(setup_facade(93))
	assert_eq(sl.mouse_filter, Control.MOUSE_FILTER_STOP,
		"Screen swallows input so clicks do not fall through to the map")
	assert_eq(sl.anchor_right, 1.0, "Screen fills the viewport width")
	assert_eq(sl.anchor_bottom, 1.0, "Screen fills the viewport height")

func test_close_hides_screen() -> void:
	var sl = _screen(setup_facade(94))
	sl.show_screen()
	assert_true(sl.visible, "shown")
	sl._on_close()
	assert_false(sl.visible, "Close hides the screen")

func test_rebuild_is_synchronous_and_replaces_content() -> void:
	# rebuild() must not leave stale children behind (it once deferred frees and
	# yielded a frame, which flashed the old widgets / a missing backdrop).
	var sl = _screen(setup_facade(95))
	sl.show_screen()
	var first_count = sl.get_child_count()
	sl.rebuild()
	assert_eq(sl.get_child_count(), first_count,
		"A rebuild replaces the content in place, leaving no duplicate widgets")
	assert_not_null(_find_backdrop(sl), "…and the backdrop is rebuilt")
