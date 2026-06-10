---
title: "Computer Player AI"
role: design
summary: >
  Documents the deterministic computer player (PlayerAI). The AI is a *client* of
  SimFacade — exactly like the human UI — that drives a flagged player's whole turn
  through apply_command, drawing every random choice from the shared gs.rng. Its
  design is three orthogonal layers: a single competent Brain (how it plays), a
  per-difficulty Handicap (how strong it is, via ai_bonus), and a per-leader Focus
  (where it points its effort, via ai_focus trait weights). Direction × competence ×
  magnitude — tune one brain plus two data columns, never a behaviour matrix. The
  sim/world wall holds: PlayerAI lives in src/api/ and never references Node/scenes.
audience:
  - Coding agents extending or tuning the computer player
  - Contributors adding traits, difficulties, or AI tuning constants
  - Anyone tracing why an AI made a particular move in a determinism failure
key_files:
  - src/api/player_ai.gd               # PlayerAI — the whole AI, pure static facade client
  - src/sim/turn_engine.gd             # ai_bonus handicap sites (production + research yield)
  - data/constants.json                # ai_* tuning constants (brain + focus scaling)
  - data/difficulties.json             # per-difficulty ai_bonus handicap column
  - data/leaders_traits.json           # per-trait ai_focus weight blocks
  - tests/api/test_player_ai.gd        # unit coverage of every decision site
  - tests/manual/ai_full_game_smoke.gd # all-AI full-game gate (win, exit 0, zero errors)
sections:
  "§1  Position & invariants": "Facade client, src/api/, apply_command-only, gs.rng-only, sim/world wall"
  "§2  The three-layer model": "Brain × Handicap × Focus — direction × competence × magnitude"
  "§3  Turn structure":        "take_turn order: economy, research, civics, religion, assembly, production, units"
  "§4  Handicap (difficulty)": "ai_bonus as an integer yield multiplier on AI production + research; is_ai gated"
  "§5  Brain — economy/research/civics/religion/assembly": "The simple, solvency-aware non-combat managers"
  "§6  Brain — production":    "Role-ranked build list (defender → economy → expansion → fallback)"
  "§7  Brain — units":         "Four-pass deterministic playbook: settlers, garrisons, free military, workers/recon"
  "§8  Focus (leader personality)": "_focus_profile sums ai_focus; the five decision sites it biases; soft-bias-not-gates"
  "§9  Tuning constants":      "Every ai_* constant, what it does, and where it is read"
  "§10 Determinism & testing": "Why the AI is reproducible; the unit + full-game gates that protect it"
  "§11 Extending it":          "Adding a trait, a difficulty step, a new behaviour, a tuning knob"
editorial_rule: >
  Modify only with explicit user consent. This document is the design record for the
  computer player; the live code in src/api/player_ai.gd is authoritative when the two
  disagree. When adding a new decision site or tuning constant, document it in §9 and
  cover it in tests/api/test_player_ai.gd. Keep the three-layer separation: new
  behaviour goes in the Brain, new strength scaling reuses ai_bonus, new per-leader
  direction reuses ai_focus — never introduce N skill levels or a behaviour matrix.
provisional_sections:
  - "§8 Focus axis weights (ai_focus values per trait) are a first tuning pass."
---

# Computer Player AI

`PlayerAI` (`src/api/player_ai.gd`) is the deterministic computer player. This
document records its design; the code is authoritative where the two disagree.

## §1  Position & invariants

`PlayerAI` is **not** part of `sim/`. Like the human UI and the networking layer,
it is a *client* of `SimFacade`:

- It lives in `src/api/`, is a pure **static** class, and never references `Node`,
  scenes, or input — the hard `sim`/`world` ↔ `api` ↔ `scenes` wall holds.
- It mutates state **only** through `facade.apply_command(...)`, so it can never
  bypass rule validation. A rejected command always falls through to a safe
  default (fortify/skip), so a bad plan can never stall the turn loop.
- Every stochastic choice draws from the **shared `gs.rng`** in pipeline order —
  never its own generator. In practice the brain's unit and production logic is
  *wholly deterministic* (no RNG at all), and the few remaining random draws live
  in the engine commands it issues. Either way an AI turn is fully reproducible and
  is captured by save/load exactly like any other pipeline randomness.

`Player.is_ai` (serialized; default `false`) marks a player as computer-controlled.
It is set from each player config's `is_ai` in `SimFacade.setup()` and toggled
per-player by the `SetupScreen` row checkboxes. In the scene layer,
`HotseatManager` watches `player_turn_started` and `call_deferred`s
`PlayerAI.take_turn` for `is_ai` players, chaining through consecutive AI players
until a human's turn opens the pass-device screen. In remote multiplayer the
authoritative server plays AI slots itself via the same entry point.

## §2  The three-layer model

The AI is **one competent strategy**, scaled and steered by two data columns. The
three layers are orthogonal and independently testable:

| Layer | Controls | Lever | Where |
|---|---|---|---|
| **Brain** | *How* the AI plays | One fixed competent strategy — never N skill levels | `player_ai.gd` (§5–§7) |
| **Handicap** | *How strong* it is | `ai_bonus`, an integer yield multiplier per difficulty | `difficulties.json` → `turn_engine.gd` (§4) |
| **Focus** | *Where* it points effort | `ai_focus` trait weights, summed per leader | `leaders_traits.json` → `player_ai.gd` (§8) |

**Direction (focus) × competence (brain) × magnitude (handicap).** You tune one
brain plus two data columns, never a behaviour matrix — that is the maintainability
win. A new difficulty is a number; a new leader personality is a JSON block; only a
genuinely new *behaviour* touches code, and it touches the one brain that every
difficulty and leader shares.

The development history (Phases A–D) lives in
`docs/planning/advanced-ai-planning.md`; this section's `§B*`/`§C*` cross-references
point back to those phase steps.

## §3  Turn structure

`take_turn(facade, player_id)` runs one whole turn, then ends it. It no-ops if it is
not that player's turn or the player is gone/eliminated. The managers run in a fixed
order, each a self-contained pass:

```
manage_economy     → set the finance/research sliders (solvency- and focus-aware)
manage_research    → steer toward the cheapest researchable tech
manage_civics      → adopt the latest unlocked policy in each category
manage_religion    → adopt a state religion once one is present (never switch)
manage_assembly    → cast a self-interested vote on any open proposal
manage_production  → fill each idle city's queue with a role-ranked build list
manage_units       → drive every unit through the four-pass playbook
facade.apply_command(Commands.end_turn(player_id))
```

## §4  Handicap (difficulty)

Difficulty scales AI **strength**, not AI behaviour, through a single data column:
`ai_bonus` in `data/difficulties.json` (0 at Noble, ramping to 70 at Deity).

`turn_engine.gd` reads it at two yield sites, each gated `if player.is_ai` and each
the exact mirror of the §2.2 *human-only* handicap block (higher difficulty makes
the human weaker via `growth_bonus`/etc.; `ai_bonus` makes the AI stronger):

- **Production** (`turn_engine.gd:547`): `prod = Fixed.scale(prod, 100 + ai_bonus)`
  — AI cities produce `ai_bonus`% extra hammers.
- **Research** (`turn_engine.gd:1288`):
  `research_income = Fixed.scale(research_income, 100 + ai_bonus)` — AI beaker
  output scales the same way, so the bonus compounds like a real handicap.

Both sites read the **same** `ai_bonus`, so there is one number to tune per
difficulty. The handicap symmetry is a hard invariant: the AI block stays
`if player.is_ai`, the exact complement of the human-only aid, and the two paths
must never cross-apply.

The Noble→Deity ramp is `0 / 10 / 20 / 35 / 50 / 70` (an accelerating
+10/+10/+15/+15/+20 step). Sub-Noble difficulties (Settler/Chieftain/Warlord) keep
`ai_bonus: 0` and instead lean on human-side advantages (`free_early_wins`,
`combat_bonus_vs_wild`) — consistent with the "0 at Noble" baseline.

## §5  Brain — economy, research, civics, religion, assembly

These managers are deliberately simple and solvency-aware. They are correct and
reproducible but not where the strategic depth lives (that is production and units).

- **Economy** (`manage_economy`): sets the allocation sliders. Research-heavy by
  default; finance-heavy when the treasury runs thin (`SOLVENCY_TREASURY = 40`
  triggers a 50% finance reserve). The split always respects the policy-imposed
  `slider_increment` step and `slider_min_research` floor so `SimFacade` accepts
  it. A personality **tilt** (§8) layers a standing finance share for an
  economy-leaning leader; a traitless leader nets zero, preserving the
  research-everything default.
- **Research** (`manage_research`): always steers toward the **cheapest**
  researchable tech (`_cheapest_research`). Ties resolve to the data table's
  deterministic iteration order.
- **Civics** (`manage_civics`): adopts the **latest** (most advanced) unlocked
  policy in each category. The data lists policies oldest→newest, so the last
  qualifying one seen per category is the most advanced the player qualifies for.
- **Religion** (`manage_religion`): adopts a state religion once one is present in
  its cities and it has none, choosing the lowest-id belief present. It **never
  switches** afterward, so it never pays the anarchy cost — conservative, but it
  exercises the state-religion path.
- **Assembly** (`manage_assembly`): when a diplomatic-assembly session is open and
  this player is an eligible member that has not yet voted, it casts the
  deterministic self-interest vote chosen by `Assembly.ai_vote` (no RNG).

## §6  Brain — production

`manage_production` fills each city's queue with a **role-ordered build list**
(`_sorted_options`), replanned only when the city's queue runs dry (so a city works
steadily through the whole priority list rather than restarting on the top item
each turn). Roles, lowest builds first:

| Role | Rank | What |
|---|---|---|
| `ROLE_DEFENDER` | 0 | A military land unit while the city is **under its defender floor** (§7) |
| `ROLE_ECONOMY` | 1 | Any structure (growth / commerce / infrastructure) |
| `ROLE_EXPANSION` | 2 | A settler/worker **while the empire still wants them** (§7) |
| `ROLE_FALLBACK` | 3 | Extra military and everything else, cheapest-first |

Within a role, the comparator (`_option_better`) keys on **focus** (§8, the
leader's stronger axis builds earlier — a soft bias *below* the role floor), then
**cost** (cheaper first), then type, then id — so the whole plan is fully
determined without touching the RNG. Roles are derived from **data**, not a
hardcoded id list:

- `_unit_role`: a unit with strength on land is a defender (when needed) else
  fallback; a `can_found` settler or a `can_build` worker is expansion.
- Structures are all `ROLE_ECONOMY`.
- Excluded entirely: Great People (born, never built), already-built structures,
  missionaries when the city cannot train them, and expansion units the empire does
  not currently want (so the AI never spams settlers with nowhere to go or workers
  it cannot use).

A buildable's **focus axis** (`_unit_axis` / `_structure_axis`) is also
data-driven: military units → `military`, settlers → `expand`, workers → `economy`;
a `science_bonus` structure → `science`, a defensive or military-training structure
(via `defence_bonus`, an `*_xp` effect, or a key in `MILITARY_EFFECT_KEYS`) →
`military`, every other structure → `economy`.

## §7  Brain — units

`manage_units` is a **wholly deterministic, no-RNG** four-pass playbook. Unit ids
are snapshotted up front (a command may remove a unit by founding a city), every
unit is re-fetched and null-checked before acting, and a `handled` set guarantees
each unit acts in exactly one pass:

1. **Settlers** (`_manage_settler`, §B1): walk toward the best legal city site and
   found on arrival. The site is the highest-scoring legal unclaimed tile within
   `ai_settle_search_radius` (`_best_city_site`); score is the sum of surrounding
   tiles' weighted base yields over the work radius (`_site_score`) minus a distance
   penalty, rejected below `ai_site_min_score`. `_legal_site` mirrors
   `SimFacade._cmd_found` (passable land, no settlement closer than
   `min_settlement_distance`). With no positive site in range, found in place if
   legal, else step toward open land (`_seek_open_land`). Ties resolve by higher
   score then lower tile id — fully deterministic.
2. **Garrisons** (`_assign_garrisons`, §B4/§B5): the whole assignment is decided
   before any order is issued, so it is order-independent. Each city's defender
   slots are filled **nearest-first** from idle military units (`_nearest_unassigned`,
   ties by lower unit id); an assigned unit standing on its city fortifies,
   otherwise it marches there. A city's `_defender_target` is the `ai_min_defenders`
   floor, raised by the leader's `military` focus (§8) and by +1 more while a
   hostile stack is within `ai_threat_radius` (`_threats_near`, §B5).
3. **Free military** (`_manage_free_military`, §B6): a unit attacks an **adjacent**
   target it clearly out-powers (`_adjacent_attack_target`: a defender it beats by
   `_attack_margin`, or an undefended hostile city); else it advances on the nearest
   non-adjacent threat within `2 × ai_threat_radius` (`_nearest_threat`,
   consolidating toward the front); else it fortifies. Power is an
   apples-to-apples proxy: `effective_strength × health`, neutral terrain for the
   attacker, the defender's own tile (terrain + settlement bonus) for the defender.
   Deliberately conservative — no long-range invasions in v1; a unit that declines
   a too-strong neighbour holds rather than blundering in.
4. **Workers / recon / other** (`_manage_worker`): workers automate in priority
   order — finish any build already underway (never re-issued, which would reset
   progress), then improve a visible resource (here, else walk to the nearest owned
   resource tile needing it), then road a bare owned tile (here, else walk to the
   nearest), then sleep. Recon units explore (`mission_explore`); anything else
   digs in (`unit_fortify`).

Expansion appetite is governed by two predicates: `_wants_settler` (city count
below `_city_target` **and** a positive-scoring open site exists, so a settler is
never queued with nowhere to go) and `_wants_worker` (fewer workers than cities).
All scans are at most O(cities × radius²) — see §10.

## §8  Focus (leader personality)

A leader's personality is a **soft bias** layered on the one brain — it only tilts
emphasis above a baseline floor, it **never gates** a behaviour. A peaceful leader
still defends and expands a little; an aggressive one simply does more of its thing.

Each trait in `leaders_traits.json` carries an `ai_focus` block over four axes —
`expand`, `military`, `economy`, `science` (small integers).
`_focus_profile(player, db)` sums them across the player's traits into a
`{expand, military, economy, science}` profile (pure integer, no RNG, recomputed
per turn — trivial). A **traitless** leader sums all-zero, which makes every
`base + k·axis` expression below collapse to its Brain baseline.

Five decision sites read the profile, always as `base + k·axis` *above* the Brain
floor:

| Site | Function | Effect of focus |
|---|---|---|
| Production order | `_sorted_options` / `_option_better` | Items on the leader's stronger axis sort earlier within a role (below the role floor) |
| Sliders | `manage_economy` | `economy − science` tilts a standing finance share, capped at `ai_focus_finance_cap` |
| City target | `_city_target` | `+ expand · ai_focus_city_per_expand` cities |
| Defender floor | `_defender_target` | `+ military / ai_focus_defenders_divisor` defenders |
| Attack margin | `_attack_margin` | `− military · ai_focus_margin_per_military` (an aggressive leader strikes on a slimmer edge, floored at 0) |

The "soft bias, not gates" rule is an invariant: any `ai_focus` axis that *gated* a
behaviour (e.g. "never garrison") would break the difficulty curve for that leader.
Focus only ever **adds** above the floor.

## §9  Tuning constants

All live in `data/constants.json` (no magic numbers in rule code). Brain constants:

| Constant | Default | Role |
|---|---|---|
| `ai_city_target` | 6 | Base city-count target before `expand` focus |
| `ai_min_defenders` | 1 | Base garrison floor per city |
| `ai_threat_radius` | 3 | Hostile-stack proximity that raises a city's defender target; `2×` is free-military advance reach |
| `ai_attack_margin` | 20 | Base power edge (%) a unit needs to attack |
| `ai_settle_search_radius` | 6 | Settler site-search and open-site-scan radius |
| `ai_site_min_score` | 1 | Minimum site score to settle / count as open land |
| `ai_site_distance_penalty` | 2 | Per-tile distance penalty in `_best_city_site` |
| `ai_site_yield_food_weight` | 2 | Food weight in `_site_score` |
| `ai_site_yield_production_weight` | 2 | Production weight in `_site_score` |
| `ai_site_yield_commerce_weight` | 1 | Commerce weight in `_site_score` |

Focus scaling constants:

| Constant | Default | Role |
|---|---|---|
| `ai_focus_city_per_expand` | 1 | Extra cities per `expand` point |
| `ai_focus_defenders_divisor` | 3 | `military / this` extra defenders |
| `ai_focus_margin_per_military` | 5 | Attack-margin reduction per `military` point |
| `ai_focus_finance_per_economy` | 10 | Finance-share tilt per `(economy − science)` point |
| `ai_focus_finance_cap` | 50 | Cap on the focus-driven finance share (%) |

Plus the handicap column in `data/difficulties.json`: `ai_bonus` per difficulty
(§4), and the `SOLVENCY_TREASURY = 40` constant in `player_ai.gd` (the only
in-code threshold; the treasury level that flips the economy to a finance reserve).

## §10  Determinism & testing

**Determinism is the sharp edge.** Every choice is either drawn from `gs.rng` in
pipeline order or fully deterministic, and must survive a mid-game save/load. Unit
management draws **no** RNG at all — every tie is broken by an explicit ordering
(score, then tile id `y·width + x`, or lower unit id), so the AI is reproducible
from `gs.rng` alone. The `test_playthrough_save_load_determinism_midgame`
integration gate is what catches a slip; when it trips, diff `f.save()` against a
resumed `f2.save()` field-by-field.

**Per-turn cost** is bounded: all AI scans are at most O(cities × radius²). The
deepest path is `_open_site_exists`
(O(cities × search_radius² × work_radius²) ≈ 2 500 tile ops/settler/turn at the
default radius 6) with an early exit. No O(tiles²) or O(units²) pattern exists.

The gates, in order:

- **`tests/api/test_player_ai.gd`** — unit coverage of every decision site
  (site selection, city target, production order, garrison assignment, threat
  response, offense, worker priority, focus profile sums). Includes
  `test_contrasting_leaders_play_rounded_game` (~1.4 s): a peaceful science leader
  vs. a militaristic expansionist, asserting neither self-destructs and even the
  peaceful leader founds a city and keeps a garrison — the "soft bias, not gates"
  guarantee.
- **`tests/integration`** playthrough — the determinism gate above.
- **`tests/manual/ai_full_game_smoke.gd`** — all-AI full game runs to a win, exit 0,
  zero errors, within a 10-minute timeout (verified across seeds 42/99/7/123/2024).

> **GUT green ≠ passing.** A parse error in a new helper still reports green and
> aborts the rest of the test method (see `CLAUDE.md` "Recurring debugging
> gotchas"). Run each new `PlayerAI` test in isolation and confirm the asserted
> count is what you expect.

## §11  Extending it

Keep the three-layer separation — new strength scaling reuses `ai_bonus`, new
per-leader direction reuses `ai_focus`, only a genuinely new *behaviour* touches the
brain.

- **New trait** — add an entry to the `traits` block in `leaders_traits.json`
  **including an `ai_focus` block** over the four axes (`test_data_db.gd` enforces
  its presence). `_focus_profile` picks it up automatically; no code change. Wire
  any mechanical effects in the relevant sim module separately.
- **New difficulty / re-tune the ramp** — set its `ai_bonus` in
  `difficulties.json`. Both handicap sites read it; regenerate any AI-inclusive
  determinism fixtures (the hash legitimately changes) and keep
  `./run_tests.sh` green.
- **New tuning knob** — add the constant to `data/constants.json`, read it via
  `db.get_constant(name, default)`, document it in §9, and cover the behaviour in
  `test_player_ai.gd`.
- **New behaviour** — add it to the brain (`player_ai.gd`) as a pure static helper.
  Keep it deterministic (or draw from `gs.rng`), keep every scan O(cities ×
  radius²), make a rejected command fall through to a safe default, and add a unit
  test run in isolation. If it should vary by leader, read `_focus_profile` as a
  soft bias *above* a floor — never gate.
