#!/usr/bin/env bash
# Humanish — a turn-based 4X strategy game.
# Copyright (C) 2026 thalia-at-lesbos
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Launch the headless multiplayer server. It runs the same engine as the desktop
# client, windowless, holding the one authoritative game; clients connect over
# WebSocket (see scenes/net/server_runner.gd and docs/design/network-design.md).
#
# Usage:
#   ./run_server.sh                       # 2-player game, port 9080, no AI
#   ./run_server.sh --players=3 --ai=1    # 3 slots, server plays 1 of them
#   ./run_server.sh --port=9000 --world=small --map=continents --pace=normal
#   ./run_server.sh --load=/path/to/game.sav
#
# Override the engine binary with GODOT=… (defaults to `godot3`). Every flag is
# forwarded verbatim to NetConfig (src/net/net_config.gd); --server is implied.
set -euo pipefail

GODOT="${GODOT:-godot3}"
RUNNER="res://scenes/net/server_runner.gd"

exec "$GODOT" --no-window -s "$RUNNER" -- --server "$@"
