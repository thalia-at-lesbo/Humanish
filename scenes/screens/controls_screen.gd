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

# Controls reference screen: a brief overview of mouse and keyboard bindings.
# Reachable from the pause menu. Needs no game state.

func init(facade = null) -> void:
	_title = "Controls"
	.init(facade)

func _populate(vbox) -> void:
	_add_line(vbox, "--- Mouse ---")
	_add_line(vbox, "Left-click      Select unit / city; inspect empty tile")
	_add_line(vbox, "Right-click     Move selected unit(s) / attack / stack")
	_add_line(vbox, "")
	_add_line(vbox, "--- Keyboard ---")
	_add_line(vbox, "E               End Turn")
	_add_line(vbox, "N               Next idle unit")
	_add_line(vbox, "B               Next idle worker")
	_add_line(vbox, "C               Center on selection")
	_add_line(vbox, "")
	_add_line(vbox, "--- Function Keys ---")
	_add_line(vbox, "F1              Encyclopedia")
	_add_line(vbox, "F2              Technology tree")
	_add_line(vbox, "F3              Policies")
	_add_line(vbox, "F4              Diplomacy")
	_add_line(vbox, "F5              Quick Save")
	_add_line(vbox, "F9              Quick Load")
	_add_line(vbox, "")
	_add_line(vbox, "--- Menus ---")
	_add_line(vbox, "Escape          Pause menu (toggle)")
	_add_line(vbox, "~               Debug overlay (debug builds only)")
