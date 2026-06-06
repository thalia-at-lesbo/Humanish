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

# Turn log (§3.1 OPEN_TURN_LOG, §8): a scrollable history of the notification
# messages the rules layer has posted. Read-only.

func init(facade) -> void:
	_title = "Turn Log"
	.init(facade)

func _populate(vbox) -> void:
	var notifications = _facade.get_notification_queue()
	if notifications.empty():
		_add_line(vbox, "No events logged yet.")
		return
	var start = int(max(0, notifications.size() - 60))
	for i in range(start, notifications.size()):
		var n = notifications[i]
		_add_line(vbox, "[%d] %s" % [int(n.get("turn", 0)), str(n.get("text", ""))])
