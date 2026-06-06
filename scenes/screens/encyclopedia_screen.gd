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

# Encyclopedia (§3.1 OPEN_ENCYCLOPEDIA, §11): a minimal browsable reference —
# each game-object category and the ids it contains. Read-only.

func init(facade) -> void:
	_title = "Encyclopedia"
	.init(facade)

func _populate(vbox) -> void:
	var db = _facade._db
	_add_category(vbox, "Technologies", db.technologies)
	_add_category(vbox, "Units", db.units)
	_add_category(vbox, "Buildings & Wonders", db.structures)
	_add_category(vbox, "Resources", db.resources)
	_add_category(vbox, "Promotions", db.promotions)
	_add_category(vbox, "Beliefs", db.beliefs)
	_add_category(vbox, "Corporations", db.econ_orgs)

func _add_category(vbox, label, table) -> void:
	var ids = PoolStringArray()
	for key in table:
		ids.append(str(key))
	_add_line(vbox, "%s (%d): %s" % [label, ids.size(), ids.join(", ")])
