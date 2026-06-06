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

# Religion advisor (§3.1 OPEN_RELIGION): founded beliefs, their founders, and how
# many cities follow each. Read-only.

func init(facade) -> void:
	_title = "Religions"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	if gs.founded_beliefs.empty():
		_add_line(vbox, "No religions founded yet.")
		return
	for belief_id in gs.founded_beliefs:
		var founder_id = int(gs.founded_beliefs[belief_id])
		var founder = gs.get_player(founder_id)
		var founder_name = founder.name if founder != null else "?"
		var followers = 0
		for s in gs.settlements:
			if s.belief_id == belief_id:
				followers += 1
		_add_line(vbox, "%s — founded by %s — %d cities" % [belief_id, founder_name, followers])
