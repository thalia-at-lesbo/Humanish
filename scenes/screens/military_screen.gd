# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version. See the LICENSE file for the full text and warranty
# disclaimer.

extends "res://scenes/screens/info_screen.gd"

# Military advisor (§3.1 OPEN_MILITARY, §11): the current player's standing army,
# counted by unit type. Read-only.

func init(facade) -> void:
	_title = "Military"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var pid = gs.current_player_id
	var counts = {}
	var total = 0
	for u in gs.units:
		if u.owner_player_id != pid:
			continue
		counts[u.unit_type_id] = int(counts.get(u.unit_type_id, 0)) + 1
		total += 1
	if total == 0:
		_add_line(vbox, "You have no units.")
		return
	_add_line(vbox, "Total units: %d" % total)
	for type_id in counts:
		_add_line(vbox, "  %s x%d" % [type_id, int(counts[type_id])])
