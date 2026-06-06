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

# Options (§3.1 OPEN_OPTIONS, §11): a minimal options panel. Currently exposes
# the score-display toggle as an action button routed through the command
# pipeline (DO_CONTROL → TOGGLE_SCORE).

func init(facade) -> void:
	_title = "Options"
	.init(facade)

func _populate(vbox) -> void:
	_add_line(vbox, "Display:")
	var score_btn = Button.new()
	score_btn.text = "Toggle Score Display"
	score_btn.connect("pressed", self, "_on_toggle_score")
	vbox.add_child(score_btn)

func _on_toggle_score() -> void:
	var gs = _facade.get_state()
	_facade.apply_command(Commands.do_control(
		gs.current_player_id, IDs.ControlType.TOGGLE_SCORE))
