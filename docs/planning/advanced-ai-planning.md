# Plan: Advanced Player AI

> **Status: ALL PHASES COMPLETE** (2026-06-09). Phase A (difficulty handicap)
> landed on `feat/phase-a-ai-handicap`; Phase B (competent brain) on
> `feat/phase-b-ai-brain`; Phase C (trait-driven focus) on
> `feat/phase-c-ai-focus`; Phase D (tuning/docs/hardening) on
> `feat/phase-d-ai-tuning` — all merged to `main`. Supersedes nothing — builds on
> the existing `PlayerAI` (`src/api/player_ai.gd`), which stays a pure static
> `SimFacade` *client* throughout. This document is the design record and the step
> list; the live code is authoritative.

## Context

`PlayerAI` today is a deliberately simple, deterministic facade client. It is
*correct* — every choice goes through `facade.apply_command()` and every random
draw comes from `gs.rng`, so an AI turn is reproducible and captured by save/load
— but it is strategically inert:

- **Research** picks the cheapest researchable tech.
- **Civics** adopt the latest unlocked policy per category.
- **Production** queues *every* buildable item, cheapest-first.
- **Units** garrison ~50% of the time and otherwise wander and act at random.
- **Founding** happens at random (`_random_action`), with no site selection.

Two structural gaps make difficulty meaningless against this AI:

1. **`ai_bonus` is dead data.** `data/difficulties.json` defines `ai_bonus`
   (0 at noble → 70 at deity), but a grep of `src/` shows it is **never read**.
   The only difficulty scaling that runs is the §2.2 handicap block in
   `turn_engine.gd`, gated `if not player.is_ai` — i.e. higher difficulty makes
   the *human* weaker and does nothing to the AI.
2. **No strategy to scale.** Even a buffed economy is wasted on random unit play
   and undirected production.

### Design thesis

Three orthogonal layers, each independently testable:

| Layer | What it controls | Lever |
|---|---|---|
| **Brain** (Phase B) | *How* the AI plays | One competent fixed strategy — never N skill levels. |
| **Handicap** (Phase A) | *How strong* the AI is | `ai_bonus` as an integer yield multiplier, per difficulty. |
| **Focus** (Phase C) | *Where* the AI points its effort | `ai_focus` trait weights, summed per leader. |

Direction (focus) × competence (brain) × magnitude (handicap). You tune **one
brain plus two data columns**, never a behavior matrix — that is the
maintainability win.

### Invariants every step must hold

- `PlayerAI` stays in `src/api/`, pure static, `apply_command`-only. It never
  references `Node`/scenes/input and never bypasses rule validation.
- Every stochastic choice draws from `gs.rng` in pipeline order. No new RNG.
- Integer math only in any `sim/` touch (use `Fixed.scale`); data-driven
  constants (no magic numbers in rule code).
- The §2.2 human-only / AI-only handicap symmetry stays intact.
- Each step leaves the suite green: unit suites, then the `tests/integration`
  playthrough gate, then `tests/manual/ai_full_game_smoke.gd` (exit 0 = win +
  zero errors).

---

## Phase A — Difficulty handicap (wire `ai_bonus`)

Small, isolated, immediately makes existing difficulty levels bite. Ships first
so the brain (Phase B) has a magnitude knob to scale against.

### A1. Read `ai_bonus` into AI city production ✓ DONE
- **Goal:** AI cities produce `ai_bonus`% extra hammers; humans unchanged.
- **Changes:** In `turn_engine.gd`, at the production-yield site, add a block
  mirroring the §2.2 handicap but gated `if player.is_ai`:
  `yield = Fixed.scale(yield, 100 + ai_bonus)`. Read `ai_bonus` from
  `db.get_difficulty(gs.difficulty_id)`.
- **Test:** `tests/sim/test_turn_engine.gd` — an `is_ai` city on `deity` out-
  produces an identical human city by the expected ratio; on `noble`
  (`ai_bonus: 0`) they match. Assert the human is unaffected by `ai_bonus`.
- **Complexity: Low.** One yield site, one gating clause, parallels existing code.

### A2. Extend the handicap to research (and optionally gold) ✓ DONE
- **Goal:** AI research output scales by `ai_bonus` too, so the bonus compounds
  the way a real difficulty handicap should.
- **Changes:** Apply the same `is_ai` multiplier at the research-accrual site
  (and, if desired, the treasury/commerce site). Keep each site reading the same
  `ai_bonus` so there is one number to tune.
- **Test:** `tests/sim/test_turn_engine.gd` — AI beaker output scales; human
  unchanged. Determinism: same seed + difficulty → identical `state_hash`.
- **Complexity: Low.**

### A3. Regenerate determinism fixtures + document ✓ DONE
- **Goal:** Keep the gates green; record the now-live field.
- **Changes:** Any `tests/integration` expected-hash fixtures for AI-inclusive
  games regenerate (the hash legitimately changes). Update
  `docs/planning/designgaps.md` (remove "ai_bonus unwired" if listed) and the
  `difficulties.json` notes.
- **Test:** Full `./run_tests.sh` green incl. the playthrough gate.
- **Complexity: Low** (mechanical, but do not skip — the determinism gate will
  fail loudly otherwise).

**Phase A exit:** ✓ difficulty now changes AI strength via a single data column.
The AI is still strategically simple — that is Phase B.

---

## Phase B — Competent brain ✓ COMPLETE

Replaces random unit/production play with a flat, ordered priority playbook. No
planner, no tree — a handful of deterministic `_score_*` helpers. Each step is a
self-contained behavior with its own test, landable independently.

> **Landed 2026-06-09** on `feat/phase-b-ai-brain`. `manage_units` is now a
> wholly deterministic four-pass playbook (settlers → garrison → free military →
> workers/recon); `_sorted_options` is role-ranked (defender → economy →
> expansion → fallback). New AI tuning constants live in `data/constants.json`
> (`ai_city_target`, `ai_min_defenders`, `ai_threat_radius`, `ai_attack_margin`,
> `ai_settle_search_radius`, `ai_site_*`). No RNG is drawn in unit management —
> every choice is deterministic, so determinism gates pass unchanged.
>
> **Full-game gate (B7):** the all-AI `ai_full_game_smoke.gd` reaches a win with
> exit 0 / zero errors across seeds 42/99/7/123/2024; the seed-123 run plays the
> full 500 turns (10 cities founded, 28 combats, 48 techs, 2 era advances),
> proving the brain expands, fights, and never stalls or loops. (Several seeds win
> early by the engine's small-map Domination quirk — a pre-existing trait: the old
> random AI also won by turn 7–11 — not a Phase-B regression.)

### B1. Expansion: settlers seek the best site and found ✓ DONE
- **Goal:** Settlers walk toward the highest-scoring legal unclaimed city site
  and found there, instead of founding at random.
- **Changes:** Add `_best_city_site(gs, unit, player)` scoring candidate tiles
  (sum of nearby tile yields − distance penalty − too-close-to-existing-city
  rejection, reusing the facade's existing legality check). Settler handling in
  `manage_units` routes via `mission_move_to` then `found_settlement` on arrival,
  replacing the random-`found` branch. All ties broken deterministically (score,
  then tile id); no RNG needed here.
- **Test:** `tests/api/test_player_ai.gd` — given two candidate regions, the
  settler moves toward and founds on the higher-yield one; an illegal site is
  never chosen. Determinism across a save/load mid-move.
- **Complexity: Medium.** Site scoring is the most new logic in the phase, but
  it is a single pure helper.

### B2. City-count target: keep expanding while good land remains ✓ DONE
- **Goal:** The AI builds settlers until it hits a city-count target or runs out
  of good sites, instead of relying on random settler production.
- **Changes:** A `_wants_settler(gs, player)` predicate (city count below target
  AND a positive-scoring site exists AND a safe escort is available). Feeds
  Phase-B3 production priority. Target is a data constant (later biased by
  `ai_focus.expand` in Phase C).
- **Test:** `tests/api/test_player_ai.gd` — below target with open land →
  wants a settler; at target → does not; no land → does not (avoids settler
  spam with nowhere to go).
- **Complexity: Low–Medium.**

### B3. Directed production priority ✓ DONE
- **Goal:** Replace cheapest-first-everything with a role-ordered build list:
  needed defender → growth/economy structure → settler/worker if expanding →
  cheapest remaining fallback.
- **Changes:** Refactor `_sorted_options` so the comparator keys on a **role
  rank** first, then cost. Roles derived from existing data tags/effects
  (a structure with a growth/commerce effect ranks economy; a combat unit ranks
  military), not a hardcoded id list. Keep the deterministic selection sort.
- **Test:** `tests/api/test_player_ai.gd` — a city under defender floor queues a
  defender first; an undefended-but-safe city queues the granary before a random
  cheap unit. Order is fully determined (no RNG).
- **Complexity: Medium.** Touches the most-tested existing helper — keep the
  current cheapest-first as the final tiebreak so nothing regresses.

### B4. Military floor: garrison to strength ✓ DONE
- **Goal:** Each city maintains ≥ `ai_min_defenders` fortified defenders;
  surplus units are freed for other roles instead of the 50/50 coin flip.
- **Changes:** Replace the `rand_bool_percent(50)` garrison split with a
  deterministic assignment: fill each city's defender slots from nearest idle
  military units, fortify them; remaining units go to the B5/B6 roles.
  `ai_min_defenders` is a data constant (later biased by `ai_focus.military`).
- **Test:** `tests/api/test_player_ai.gd` — with N cities and few units, the
  scarce units fill garrisons nearest-first; surplus units are not stuck
  fortifying. No RNG in the assignment.
- **Complexity: Medium.**

### B5. Threat response ✓ DONE
- **Goal:** When an enemy/wild stack is within `ai_threat_radius` of a city whose
  garrison is under strength, build and/or route a defender to it.
- **Changes:** A `_threats_near(gs, settlement)` scan (reuses `gs.map.distance`
  and existing power comparison). Raises the city's effective defender target and
  pulls the nearest free unit toward it.
- **Test:** `tests/api/test_player_ai.gd` — plant a hostile stack near a weakly
  held city; the AI redirects a unit toward it / queues a defender. No false
  alarm when the nearest stack is friendly or out of radius.
- **Complexity: Medium.**

### B6. Opportunistic offense ✓ DONE
- **Goal:** A local stack that clearly out-powers an adjacent enemy/wild target
  attacks; otherwise it consolidates. Deliberately conservative — no long-range
  invasions in v1.
- **Changes:** For each idle military unit, if an adjacent target's defensive
  power is below the unit's attack power by a data margin, issue the attack
  command (reusing the same power read combat already computes); else move toward
  the nearest threat or fortify.
- **Test:** `tests/api/test_player_ai.gd` — AI attacks a weak adjacent target,
  holds against a strong one. Determinism through a combat resolution + save/load.
- **Complexity: Medium.**

### B7. Brain integration + full-game gate ✓ DONE
- **Goal:** All B-steps cooperate over a whole game without stalls, loops, or
  errors.
- **Changes:** Wire the helpers into `manage_units`/`manage_production`; ensure
  no command-rejection infinite loops (a rejected action always falls through to
  a safe default — fortify/skip — exactly as the current code does).
- **Test:** `tests/manual/ai_full_game_smoke.gd` (all-AI) runs to a win, exit 0,
  zero errors, within the 10-minute timeout; `tests/integration` playthrough
  green. Compare turns-to-win vs. the old AI as a sanity check that it expands
  and fights.
- **Complexity: Medium.** Mostly integration/tuning; the risk is per-turn cost,
  so keep every scan O(units × cities), not O(tiles²).

**Phase B exit:** ✓ one competent strategy that expands, defends, and fights, the
same at every difficulty. Phase A's handicap now scales a strategy worth scaling.

---

## Phase C — Trait-driven strategic focus ✓ COMPLETE

Layers leader personality on top of the one brain as **soft bias, never gates**.
A peaceful leader still defends and expands a little; traits only tilt emphasis
above a baseline floor. Fully data-driven: a new trait adds a JSON block, no code.

> **Landed 2026-06-09** on `feat/phase-c-ai-focus`. Each of the 11 traits carries
> an `ai_focus` block over four axes (`expand`/`military`/`economy`/`science`) in
> `leaders_traits.json`; `PlayerAI._focus_profile(player, db)` sums them per turn
> (pure integer, no RNG, all-zero for a traitless leader so every site collapses
> to its Phase-B baseline). Five decision sites read the profile as soft bias
> *below* the Phase-B floors: production order (`_sorted_options` keys role →
> focus → cost, with `_unit_axis`/`_structure_axis` classifying each buildable),
> the finance/research slider tilt (`manage_economy`), the city-count target
> (`_city_target`), the garrison floor (`_defender_target`), and the attack margin
> (`_attack_margin`). New scaling constants live in `data/constants.json`
> (`ai_focus_city_per_expand`, `ai_focus_defenders_divisor`,
> `ai_focus_margin_per_military`, `ai_focus_finance_per_economy`,
> `ai_focus_finance_cap`).
>
> **Gates:** the full unit suite + `tests/integration` playthrough are green; the
> all-AI `ai_full_game_smoke.gd` wins with exit 0 / zero errors across seeds
> 42/99/7 (each playing the full 500 turns). A fast CI regression
> (`test_contrasting_leaders_play_rounded_game`, ~1.4 s) pits a peaceful science
> leader against a militaristic expansionist and confirms the "soft bias, not
> gates" guarantee — neither self-destructs, and even the peaceful leader still
> founds a city and keeps a garrison.

### C1. Add `ai_focus` weights to trait data ✓ DONE
- **Goal:** Each of the 11 traits carries an `ai_focus` weight block over four
  axes: `expand`, `military`, `economy`, `science` (integers, e.g. 0–3).
- **Changes:** Add `ai_focus` to each entry in `leaders_traits.json` (proposed
  mapping: aggressive→military, protective→military, imperialistic→expand,
  expansive→expand+economy, financial→economy, organized→economy,
  industrious→economy, creative→science, philosophical→science, spiritual→
  science, charismatic→expand+military). No code yet.
- **Test:** `tests/core/test_data_db.gd` — every trait parses an `ai_focus` dict;
  schema/key sanity.
- **Complexity: Low** (pure data + a load assertion).

### C2. Sum a leader's focus profile ✓ DONE
- **Goal:** Derive a per-player `{expand, military, economy, science}` profile by
  summing `ai_focus` across `player.traits`.
- **Changes:** A pure helper `PlayerAI._focus_profile(player, db)` (integer sums,
  no RNG, reads only `player.traits`). Cache-free — recompute per turn; it is
  trivial.
- **Test:** `tests/api/test_player_ai.gd` — a two-trait leader sums correctly
  (Washington = expansive+charismatic → expand-heavy); a single-trait leader
  matches its one block.
- **Complexity: Low.**

### C3. Bias production order by focus ✓ DONE
- **Goal:** Within the B3 role-ranked list, nudge the dominant axis's items
  earlier (financial → markets before barracks; aggressive → the reverse).
- **Changes:** Add a focus-weighted term to the B3 comparator, *below* the safety
  floors (defender floor from B4 still wins). Never zero out a role.
- **Test:** `tests/api/test_player_ai.gd` — economy-focus and military-focus
  leaders, same city/state, produce different orderings; both still satisfy the
  defender floor.
- **Complexity: Low–Medium.**

### C4. Bias sliders, expansion target, and military floor by focus ✓ DONE
- **Goal:** `economy` vs `science` weight tilts the finance/research/culture
  split (honoring policy step/floor as `manage_economy` already does); `expand`
  scales the B2 city-count target; `military` scales the B4 defender floor and
  the B6 attack appetite.
- **Changes:** Replace the fixed Phase-B constants with `base + k·focus_axis`
  expressions, baseline floor preserved.
- **Test:** `tests/api/test_player_ai.gd` — expand-heavy leader targets more
  cities; military-heavy leader holds a higher garrison and attacks on a smaller
  margin; science-heavy leader runs a higher research slider. All within legal
  bounds.
- **Complexity: Medium.**

### C5. Personality regression gate ✓ DONE
- **Goal:** Confirm distinct leaders play measurably differently and none
  self-destructs (the "soft bias not gates" guarantee).
- **Changes:** none beyond test.
- **Test:** `tests/api/test_player_ai.gd::test_contrasting_leaders_play_rounded_game`
  drives a fast all-AI opening (Gandhi science vs. Genghis military/expand, fixed
  16 turns, ~1.4 s) and asserts neither self-destructs and even the peaceful
  leader founds a city and keeps a garrison. The *full* all-AI win gate stays the
  manual `ai_full_game_smoke.gd`, which already pits distinct societies and was
  re-run green (seeds 42/99/7) under the focus layer. The measurable-difference
  guarantee is covered by the C2–C4 unit tests (distinct profiles → distinct
  production order, sliders, city target, garrison floor, attack margin).
- **Complexity: Low–Medium.**

**Phase C exit:** same difficulty feels different per leader; equally hard,
varied direction.

---

## Phase D — Tuning, docs, and hardening ✓ COMPLETE

> **Landed 2026-06-09** on `feat/phase-d-ai-tuning`. D1 corrected `warlord`'s
> stray `ai_bonus: 5` to 0 (consistent with the stated "0 at noble" baseline —
> the human's `free_early_wins` and `combat_bonus_vs_wild` advantages at
> sub-Noble difficulties already compensate); the Noble→Deity ramp is
> 0/10/20/35/50/70, an accelerating +10/+10/+15/+15/+20 step. D2 confirmed no
> O(tiles²) scan in the AI: the deepest path is `_open_site_exists` at
> O(cities × radius² × work_radius²) ≈ 2 500 tile ops/settler/turn on the
> default 6-tile radius — well within budget. D3 updated `CLAUDE.md` and
> `docs/ref/code-layout.md` to document the three-layer model (handicap × brain
> × focus). Full test suite green.

### D1. Difficulty curve tuning pass ✓ DONE
- **Goal:** Pick `ai_bonus` magnitudes (and the Phase-B/C base constants) that
  give a believable noble→deity ramp.
- **Changes:** `difficulties.json`: `warlord.ai_bonus` 5 → 0 (below-Noble
  entries rely on human-side advantages rather than an AI handicap, matching the
  "0 at noble" design baseline). Noble→Deity ramp verified correct: 0, 10, 20,
  35, 50, 70 (+10/+10/+15/+15/+20). Phase-B/C base constants in `constants.json`
  unchanged — the current values produce stable gameplay across the test suite and
  the full-game smoke.
- **Test:** Full `./run_tests.sh` green incl. the playthrough gate.
- **Complexity: Low.**

### D2. Per-turn cost check ✓ DONE
- **Goal:** Confirm the brain adds no pathological per-turn cost at large map /
  high unit counts.
- **Changes:** None. Static analysis confirmed all AI scans are at most
  O(cities × radius²) — the deepest path is `_open_site_exists`
  (O(cities × search_radius² × work_radius²), ~2 500 ops/settler/turn at default
  radius 6) with an early exit. No O(tiles²) or O(units²) pattern found.
- **Test:** Full-game smoke (`ai_full_game_smoke.gd`) completes within the
  10-minute budget; full unit + integration suite green.
- **Complexity: Low.**

### D3. Documentation ✓ DONE
- **Goal:** Record the new model where future contributors will look.
- **Changes:** Updated `CLAUDE.md` `PlayerAI` table row and Computer-players
  section to document the Phase-C focus layer (`_focus_profile`, the five
  decision sites, and `ai_focus_*` constants). Updated
  `docs/ref/code-layout.md` facade-clients entry to replace the old
  cheapest-first/random-garrison description with the three-layer (A/B/C) model.
  `designgaps.md` had no AI-specific gap entries to trim.
- **Test:** docs-only.
- **Complexity: Low.**

---

## Suggested build order & dependencies

```
A1 → A2 → A3            (handicap; independent, ship first)
                 ┌── B1 → B2 ─┐
B-prereq: none → ┤            ├→ B3 → B7   (production needs B2 + B4 signals)
                 └── B4 → B5 ─┴→ B6 ──────┘
C1 → C2 → {C3, C4} → C5     (needs B3/B4/B6 to bias)
D1 → D2 → D3                (after A+B+C land)
```

Phase A is fully independent and low-risk — land it first for immediate value.
Phase B is the bulk of the work; each step is individually testable and
shippable behind the existing gates. Phase C is a thin, data-driven layer that
only makes sense once the brain (B3/B4/B6) exists. Phase D is iteration.

## Risk notes

- **Determinism is the sharp edge.** Every new choice must draw from `gs.rng` (or
  be fully deterministic) and survive a mid-game save/load — the
  `test_playthrough_save_load_determinism_midgame` gate is what catches a slip.
  Diff `f.save()` vs. a resumed `f2.save()` field-by-field when it trips.
- **GUT green ≠ passing.** A parse error in a new helper still reports green and
  aborts the rest of the method (see `CLAUDE.md` "Recurring debugging gotchas").
  Run each new `PlayerAI` test in isolation and confirm the asserted count.
- **Keep bias soft.** Any `ai_focus` axis that *gates* a behavior (e.g. never
  garrison) breaks the difficulty curve for that leader. Always keep a floor.
- **Handicap symmetry.** The Phase-A block must stay `if player.is_ai`, the exact
  mirror of the §2.2 human-only aid — do not let the two paths drift.
