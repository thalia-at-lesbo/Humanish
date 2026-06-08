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
# espionage points against each rival alliance. A "Select Mission…" button opens
# the EspionageMissionMenu popup showing options, costs, and interception risk.

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
	var min_cost: int = gs.db.get_constant("intel_mission_cost", 100)
	_add_line(vbox, "Espionage points by alliance:")
	for alliance_id in p.intel_points:
		var pts: int = int(p.intel_points[alliance_id])
		# Determine a human-readable target name.
		var target_name: String = "Alliance " + str(alliance_id)
		var target: Alliance = gs.get_alliance(int(alliance_id))
		if target != null and not target.member_player_ids.empty():
			var first = gs.get_player(int(target.member_player_ids[0]))
			if first != null:
				target_name = first.name
		_add_line(vbox, "  %s: %d EP" % [target_name, pts])
		# Show a "Select Mission…" button for any alliance with enough EP banked.
		if pts >= min_cost:
			var btn = Button.new()
			btn.text = "Select Mission vs. " + target_name + "…"
			btn.connect("pressed", self, "_on_select_mission", [int(alliance_id)])
			vbox.add_child(btn)

func _on_select_mission(alliance_id: int) -> void:
	var menu = load("res://scenes/screens/espionage_menu.gd").new()
	add_child(menu)
	menu.init(_facade, alliance_id, funcref(self, "rebuild"))
