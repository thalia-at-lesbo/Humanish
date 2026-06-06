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

# Victory progress (§3.1 OPEN_VICTORY_PROGRESS, §11): the enabled win conditions
# and a per-player standings line (score, cities). Read-only.

func init(facade) -> void:
	_title = "Victory Progress"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()

	_add_line(vbox, "Turn %d of %d" % [gs.turn_number, gs.max_turns])

	_add_line(vbox, "Enabled win conditions:")
	if gs.enabled_win_conditions.empty():
		_add_line(vbox, "  (none)")
	else:
		for wc in gs.enabled_win_conditions:
			_add_line(vbox, "  - " + str(wc))

	_add_line(vbox, "Standings:")
	for p in gs.players:
		if p.is_eliminated:
			_add_line(vbox, "  %s — eliminated" % p.name)
			continue
		var cities = 0
		for s in gs.settlements:
			if s.owner_player_id == p.id:
				cities += 1
		_add_line(vbox, "  %s — score %d — %d cities" % [p.name, p.score, cities])
