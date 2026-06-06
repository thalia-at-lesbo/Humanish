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

# Espionage advisor (§3.1 OPEN_ESPIONAGE, §11): the intel slider and accumulated
# espionage points against each rival alliance. Read-only.

func init(facade) -> void:
	_title = "Espionage"
	.init(facade)

func _populate(vbox) -> void:
	var gs = _facade.get_state()
	var p = gs.get_player(gs.current_player_id)
	if p == null:
		_add_line(vbox, "No active player.")
		return
	_add_line(vbox, "Intel slider: %d%%" % p.slider_intel)
	if p.intel_points.empty():
		_add_line(vbox, "No espionage points accumulated.")
		return
	_add_line(vbox, "Espionage points by alliance:")
	for alliance_id in p.intel_points:
		_add_line(vbox, "  alliance %s: %d" % [str(alliance_id), int(p.intel_points[alliance_id])])
