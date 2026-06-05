# Design ↔ Implementation Gaps

Places where the documents under `docs/design/` describe behaviour or content
that the current source does **not** implement (or implements differently). This
is a living checklist — when a gap is closed, delete its entry. It is *not* a bug
list; everything here is known, deliberate scope that simply hasn't been built.

Unless noted otherwise, the design docs are treated as the source of truth and the
engine is expected to grow toward them. Findings below were spot-checked against
the source on 2026-06-05; line references drift, so grep before relying on them.

---

## 1. Terminology: design spec vs. data tables

`game-data.md` is written in player-facing design language; the JSON tables and
sim use different identifiers for the same concepts. This is intentional, but
worth stating so the two aren't mistaken for a content gap:

| `game-data.md` term | Data / code term |
|---|---|
| Factions | `societies` (in `leaders_traits.json`) |
| Civics | `policies` (`policies.json`) |
| Religions | `beliefs` (`beliefs.json`) |
| Corporations | `econ_orgs` (`econ_orgs.json`) |

Counts spot-checked and consistent: traits 11, leaders 52, societies 34, the six
win-condition types. The remaining content tables (wonders, buildings, resources,
promotions, terrain) were **not** exhaustively audited entry-by-entry against the
prose — only structurally. A full content reconciliation is still outstanding.

## 2. Policy / civic effects — most now applied; a few remain blocked

`policies.json` matches `game-data.md` §8 (five categories, 26 civics). The
*mechanical* fields were always read (`slider_increment`, `slider_min_research`
→ `sim_facade._cmd_set_sliders`; `transition_turns` → anarchy tick in
`turn_engine._tick_states`; `anger_modifier` → `_update_contentment`;
`upkeep_modifier` → `_update_treasury`). As of 2026-06-05 the per-civic `effects`
dictionaries are read too, through the single helper `sim/policy_effects.gd`
(`PolicyEffects.sum_int` / `has_flag`), wired into the relevant sim modules:

- **Happiness / health** (`turn_engine._update_contentment` / `_update_wellbeing`):
  `happiness_per_garrison`, `barracks_happiness`, `happiness_per_forest`,
  `happiness_per_religion`, `happiness_largest_cities`, `war_anger_reduction`,
  `health_empire`.
- **Output** (`_settlement_growth`): `town_production`, `town_commerce`,
  `workshop_production`, `watermill_farm_production`, `windmill_commerce`,
  `capital_commerce`, `capital_production`, `free_specialist_per_city`; and
  `culture_all_cities` in `_settlement_culture`.
- **Production** (`_settlement_production` via `_policy_production_delta`):
  `military_production`, `religious_building_production`,
  `production_per_military_unit`.
- **Research / intel** (`_apply_research` / `_apply_intelligence`):
  `science_per_scientist`, `science_output`, `espionage`.
- **Treasury** (`_update_treasury`): `free_units_per_city`,
  `no_distance_maintenance`.
- **Commands** (`sim_facade`): `can_rush_with_gold` and the bare `rush_by_pop`
  gate the two rush methods in `_cmd_rush_production`; the bare
  `worker_speed_bonus` shortens build time in `_cmd_build_improvement`.
- **Unit/GP** (`_complete_item` / `_special_person_progress`): `new_unit_xp` and
  `state_religion_unit_xp` set a new military unit's starting experience;
  `great_person_rate` scales Great-Person point accrual.

Covered by `tests/sim/test_policy_effects.gd`.

**Still inert — blocked on an unbuilt subsystem, not on the wiring:**

- `unlimited_specialists` (Caste System) — the sim caps specialists only by
  population; there is no per-building specialist *slot* ceiling to lift, so the
  flag has nothing to relax until a slot system exists.
- `faster_cottage_growth` (Emancipation) and Emancipation's cross-faction
  unhappiness — cottage→hamlet→village→town upgrading is not modelled.
- `trade_route_per_city`, `no_foreign_trade_routes` (Free Market / Mercantilism)
  and `corporation_maintenance_reduction` — trade routes are unbuilt (§3), and
  econ orgs charge a per-spread cost rather than ongoing maintenance.
- `can_draft` (Nationhood), `missionary_without_monastery` (Organized Religion),
  `blocks_nonstate_spread` (Theocracy) — tied to the unbuilt draft / missionary /
  religion-spread-restriction mechanics noted in §3.

## 3. UI vocabulary: the spec is a deliberate superset

`user-interface-design.md` §3.1–§3.3 enumerate the full functional command set as a
superset; the *implemented* vocabulary is whatever the `IDs` enums define
(`ControlType`, `UnitCmd`, `UnitMission`, `InterfaceMode`, `WidgetType`,
`PopupType`, `DirtyRegion`). Items present in the spec with **no** enum value,
command, or handler in the current build include (verified absent in `src/`, not
exhaustive):

- **Controls (§3.1):** camera/view modes (orthographic/flying/top-down/isometric,
  globe 3D view), score-display toggle, and several advisor/info screens named in
  the spec (religion, corporation, turn log, domestic advisor, victory progress,
  hall of fame, game/admin details, options, world-builder). Session controls
  `retire`, `all-chat`, `team-chat`, `free-colony` are also unmodelled.
- **Unit commands (§3.2):** `gift to another player` has no command. (Load/unload
  *do* exist — `CommandType.LOAD_UNIT` / `UNLOAD_UNIT`; automation exists as
  `UnitCmd.AUTOMATE` / `STOP_AUTOMATE`.)
- **Unit missions (§3.3):** `air patrol`, `sea patrol`, `sentry`, `heal`,
  `move-to-unit`, `scout/recon`, and the distinct espionage verbs `sabotage` /
  `destroy` / `steal plans` have no `UnitMission` value. (Many other spec
  "missions" *are* implemented through other paths — `SPREAD_BELIEF`,
  `ESPIONAGE_MISSION`, and Great-Person verbs via `GP_ACTION` — so they are not
  gaps.) `draft` (Nationhood) and `establish trade route` are likewise unbuilt,
  matching their inert policy effects in §2.

## 4. Pipeline phase stubs

Two `TurnEngine` phases are intentional no-ops awaiting their subsystem:

- `IDs.Phase.PLAYER_BOOKKEEPING` — `pass` (placeholder for AI planning).
- `IDs.Phase.WORLD_ASSIGN_SITES` — `pass` (special-site assignment unimplemented).

(For the record, two phases previously labelled "stub" in `code-layout.md` are in
fact implemented and have been corrected there: `WORLD_TILE_UPKEEP` →
`_tile_upkeep` charges improvement maintenance, and `WORLD_ASSEMBLY` →
`_resolve_assembly` tallies population-weighted `gs.diplomatic_votes`.)

---

## Recently reconciled

- **2026-06-05** — Most civic `effects` are now applied (§2). Added
  `sim/policy_effects.gd` as the single reader and wired the headline gameplay
  bonuses into `TurnEngine` and `SimFacade`; `tests/sim/test_policy_effects.gd`
  covers each. Only effects blocked on an unbuilt subsystem (specialist slots,
  cottage growth, trade routes, draft/missionary/religion-spread) remain inert —
  see the list under §2.
- **2026-06-05** — `policies.json` brought in line with `game-data.md` §8: removed
  the undocumented 6th `civic` category (communism / anarcho-communism /
  anarcho-capitalism / fascism) and the stray `monarchy` government policy, and
  re-gated Republic on Code of Laws. The orphaned `slider_max_research` cap (only
  Communism used it) was removed from `sim_facade` and its test. See §2 for the
  effects still pending.
