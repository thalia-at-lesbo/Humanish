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

# Domestic advisor (§3.1 OPEN_DOMESTIC_ADVISOR, §11): a per-city summary for the
# current player — population, output, and unrest. Read-only.

func init(facade) -> void:
	_title = "Domestic Advisor"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var pid = gs.current_player_id
	var any = false
	for s in gs.settlements:
		if s.owner_player_id != pid:
			continue
		any = true
		_add_line(vbox, "%s — pop %d — F%d P%d C%d — unrest %d%s" % [
			s.name, s.population, s.output_food, s.output_production,
			s.output_commerce, s.discontented,
			(" [DISORDER]" if s.in_disorder else "")])
	if not any:
		_add_line(vbox, "You have no cities.")
