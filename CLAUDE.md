# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all tests (headless)
godot3 --no-window -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# Run a single test file
godot3 --no-window -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_phase0_core.gd -gexit

# Run a single test by name within a file
godot3 --no-window -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_phase3_combat.gd -gunit_test_name=test_combat_same_seed_identical_outcome -gexit
```

The test framework is **GUT 7.4.3** (Godot 3.x). Tests extend `"res://addons/gut/test.gd"`. Each `test_*` method is one test case.

## Architecture

The design enforces a hard boundary: **`sim` (pure rules) ↔ `api` facade ↔ (future) presentation**. Nothing in `src/sim/` or `src/world/` may reference `Node`, scenes, or input. This keeps the engine headless and testable.

### Data flow

1. Caller creates a `DataDB`, calls `db.load_all()` to parse all JSON tables from `data/`.
2. Caller creates a `SimFacade`, calls `facade.setup(db, seed, ...)` to initialize `GameState`.
3. Each player action is a plain Dictionary built by `Commands.*()` helpers and submitted via `facade.apply_command(cmd)`. No other path mutates state.
4. Observers read `facade.get_state()` or subscribe to facade signals (`turn_advanced`, `combat_resolved`, etc.).
5. Save/load: `facade.save()` → JSON string → `facade.load_save(json)`. State hash via `facade.state_hash()` is the determinism gate.

### Non-negotiable engine invariants

1. **Integer math only** — no floats in `sim/` or `world/`. `Fixed` (100-unit scale) handles movement precision. Percentages are integer 0–100. Use ternaries instead of `max()`/`min()` in `-> int` typed functions (Godot 3's `max()`/`min()` returns float).
2. **One shared RNG** — every stochastic call goes through `gs.rng` in pipeline order. Never create a separate `RandomNumberGenerator`. The RNG seed/state is serialized as **strings** (not ints) to avoid JSON double-precision truncation of 64-bit values.
3. **Data-driven** — all numeric constants live in `data/*.json`, loaded by `DataDB`. No magic numbers in rule code.
4. **Pipeline order is a rule** — `TurnEngine.world_step()` and `player_step()` execute phases in strict §3 order. Each phase first calls `hooks.run(IDs.Phase.X, gs)` and skips the built-in if it returns `true`.

### Key class responsibilities

| Class | Role |
|---|---|
| `GameState` | Root aggregate; the single source of truth. All sim state lives here. |
| `TurnEngine` | Implements §3 pipeline as static methods; calls into every other sim module. |
| `SimFacade` | Public API; validates commands, routes to `TurnEngine`, emits signals. |
| `DataDB` | Loads/validates all JSON tables; provides typed getters. |
| `Fixed` | All integer math helpers (scale, proportion, movement conversion). |
| `RNG` | Seeded PCG32 wrapper; `get_state()`/`restore_state()` for save-resume. |
| `Hooks` | FuncRef registry keyed on `IDs.Phase`; lets rules be overridden per-phase. |
| `SaveLoad` | `JSON.print(gs.serialize())` / `GameState.deserialize()`; computes `state_hash()`. |
| `Commands` | Static factories for all command Dictionaries; no logic, pure construction. |

### Godot 3 GDScript constraints to remember

- `class_name Foo` creates a global name, but **do not use `Foo.new()` inside `foo.gd`** — it triggers a cyclic-reference parse error. Use `load("res://path/foo.gd").new()` in static factory methods instead.
- Test helper functions must **omit return type annotations** (`-> MyClass`) to avoid parse-order failures with class_name globals.
- GUT 7 has no `assert_gte`/`assert_lte` — use `assert_true(a >= b, "msg")`.
- `seed` is a GDScript built-in function name; do not use it as a parameter name.

### Adding new content

- **New unit/structure/tech/etc.**: add a JSON entry to the relevant file in `data/`. No code change required unless the entry introduces a mechanic not yet modelled.
- **New rule / phase override**: register via `facade.get_hooks().register(IDs.Phase.X, obj, "method")`. The method receives `(game_state, args: Dictionary)` and returns `bool`.
- **New command**: add a factory to `Commands`, add a case to `SimFacade.apply_command()`, implement a `_cmd_*` handler.
