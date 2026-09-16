# Soccer Predictor — Claude Context

## What this project does
Monte Carlo simulation engine for predicting soccer match outcomes.
Scrapes WhoScored for player xG stats and lineup data, runs 100k simulations
per match using Poisson-distributed shot counts, and exports probabilities to
CSV for betting analysis.

## Main scripts
- `xg_script.rb` — main script; fetches today's fixtures, scrapes per-player xG,
  runs simulation, exports to `bet_proposals.csv`
- `xg_script_greece.rb` — lighter variant using team-level xG (not per-player),
  used for Greek Super League

## Simulation accuracy notes
- **Home/away xG split**: `xgs_new` fetches `field=Home` stats for the home team and
  `field=Away` for the away team, so shot volumes and xG quality already reflect
  venue-specific performance. No separate multiplier is applied.
- **Early-season / low-sample fallback (added 2026-08)**: early in a season a team may
  have played only 1-2 games at a given venue, so the `field=Home`/`field=Away` feed
  returns no row at all for most of the predicted XI (not just a low value) — the sim
  was silently treating them as players who never shoot, producing degenerate results
  (e.g. U2.5 99%+, GG <2%). `xgs_new` now also fetches `field=Overall` (both venues) for
  each team and falls back to a player's Overall row whenever their Home/Away-specific
  `apps` is 0. Verified against WhoScored's live JSON for Celta Vigo (2026/27 season,
  matchday 3): `field=Home` returned only 4 of the 11 predicted starters; `field=Overall`
  returned 8, each with roughly double the sample. Confirmed real players can still be
  legitimately absent from both (e.g. keepers, or anyone with zero shots all season) —
  that's not a bug, `xgs_warning` still catches when too many remain empty.
- **Predicted XI flag**: when `starting_eleven` returns nil and `predicted_eleven` is
  used as fallback, a `[PREDICTED XI]` tag appears in the printed output next to the
  match header. Treat those proposals with extra caution — this is also correlated
  with early-season/preview matches, i.e. exactly when the fallback above matters most.

## Key architecture decisions
- **Always headless**: All Watir browsers must use `:chrome, options: { args: ['--headless=new', ...] }`.
  All Puppeteer launches must use `headless: true`. Never leave either as the default
  (which opens visible windows).
- **Browser reuse in xgs_new**: A single `@br` instance is reused across all four
  fetch steps (home xGs → home cards → away xGs → away cards) then quit in `ensure`.
- **`starting_eleven` vs `predicted_eleven`**: `starting_eleven` hits the WhoScored
  lineups JSON endpoint directly; `predicted_eleven` uses Puppeteer to scrape a
  preview page. The main flow tries `starting_eleven` first, falls back to
  `predicted_eleven`.

## Data flow
```
games()           — fetch today's fixtures from WhoScored livescores JSON
starting_eleven() — fetch confirmed lineups (or predicted_eleven() as fallback)
xgs_new()         — fetch per-player xG and card stats for both teams
simulate_match()  — run 100k Poisson simulations → probabilities
export_to_csv()   — append results to bet_proposals.csv
print_proposals() — filter CSV rows against THRESHOLDS and print eligible bets
```

## CSV output (`bet_proposals.csv`)
Columns (semicolon-delimited):
```
Home; Away; 1; X; 2; 1X; X2; 12; O15; U15; O25; U25; O35; U35; GG; Missing XGS; Both Cards; Score
Bet1; BetX; Bet2; BetO15; BetU15; BetO25; BetU25; BetO35; BetU35; BetGG; BetNG
Edge1; EdgeX; Edge2; EdgeO15; EdgeU15; EdgeO25; EdgeU25; EdgeO35; EdgeU35; EdgeGG; EdgeNG
Kelly1; KellyX; Kelly2; KellyO15; KellyU15; KellyO25; KellyU25; KellyO35; KellyU35; KellyGG; KellyNG
```

Edge = simulated probability minus implied probability from decimal odds (sim% / 100 − 1/odds).
Kelly = edge / (decimal_odds − 1), only stored when edge > 0.
NG probability is derived as (100 − GG%) — there is no separate NG simulation column.

**WhoScored JSON bet keys** (in `games()`): `home`, `draw`, `away`, `over15`, `under15`,
`over25`, `under25`, `over35`, `under35`, `gg`, `ng`. These keys are best-guess matches
to WhoScored's livescores JSON structure — if a market returns 0 odds, the key name may
differ and needs adjustment.

## Thresholds (THRESHOLDS constant)
Used by `print_proposals` to flag eligible bets. Column indices map to:
- index 2,4 → 1 or 2 win: 60%
- index 3 → draw: 35%
- index 5,6,7 → double chance: 80%
- index 8–13 → over/under: 80%
- index 14 → GG: 80%
- index 16 → both cards: 80%

All Bet*, Edge*, Kelly* columns are in `skip_cols` and excluded from threshold checks.

## Edge-based exceptional bucket
`build_proposals` / `print_proposals` surfaces a second class of bet: cases where the
bookmaker odds are significantly **mispricing** the simulation output for **any market
with stored odds**, even when the raw simulated probability does not meet the THRESHOLD.

**Rule**: for all markets with Edge columns (1/X/2, O15/U15, O25/U25, O35/U35, GG, NG),
also include the bet if:
- `edge > EDGE_EXCEPTION_THRESHOLD` (bookmaker underestimates — value bet), OR
- `edge < -EDGE_EXCEPTION_THRESHOLD` (bookmaker overestimates — flag as "lay / fade")

`EDGE_EXCEPTION_THRESHOLD = 0.10` (i.e. ±10 percentage points) is the suggested default.

These rows are labeled `[EDGE]` or `[FADE]` in the printed output. A bet that qualifies on
*both* grounds (threshold AND edge) is printed once with both tags.

**Why this matters**: GG at 72% misses the 80% GG_THRESHOLD, but if the bookmaker prices
it at 2.20 (implied 45%), the +27 pp edge is clearly actionable. Conversely, O25 at 55%
that a bookmaker prices at 1.50 (implied 67%) is a strong fade even below threshold.

## Output ordering
`build_proposals` sorts matches in **descending order by the highest bet probability** among that match's qualifying bets, so the most confident picks always appear first.

## Available leagues (AVAILABLE_LEAGUES)
Keyed by WhoScored tournament ID. Championship (id 7) is currently commented out.

## Gotchas
- `away_cards` must reference `away_cards`, not `home_cards` (easy copy-paste bug).
- `print_proposals` must guard `next unless threshold` before calling `[:value]`
  or it crashes on CSV columns with no matching threshold index.
- `NUMBER_OF_SIMULATIONS` is 100_000 in the main script, 1_000_000 in the Greece
  variant (simpler simulation so it can afford more).
- `scores` array is populated in the simulation loop but must be excluded from the
  final `transform_values` normalization pass (it's a string, not a count).
- `xgs_warning` (drives the `Missing XGS` CSV column) counts players whose xG hash
  value equals `[0, 0]` — the value is a 2-element array (`[xg_per_shot, avg_shots]`),
  not a bare `0`. `v == 0` silently never matches (fixed 2026-08); if this is ever
  touched again, keep comparing against `[0, 0]`.
- `ask_claude_for_tips*` shell out to the `claude` CLI via `Open3.capture3` (previously
  `IO.popen(..., err: :close, ...)`, which discarded stderr and always printed the
  generic "no output" message even when `claude` reported a real reason, e.g. not
  being logged in). Keep using `Open3.capture3` so `err_output` stays available.
- **Diagnosed 2026-09-08**: a scheduled run processed only 1 of 7 eligible fixtures
  (the rest being Champions League matches) and then stopped with no ruby/chrome
  process left running. Root cause: `games()` and `starting_eleven()` had **unbounded**
  `retry` loops on `Watir::Wait::TimeoutError` / `StaleElementReferenceError` /
  `Net::ReadTimeout` — a single slow or broken preview page (e.g. a
  European-competition preview rendering differently than a domestic one) could
  relaunch Chrome and retry forever, hanging the whole run on one fixture and never
  reaching the rest of the day's matches. Fixed by adding `MAX_SCRAPE_RETRIES = 3`:
  both methods now give up after 3 attempts and return a safe fallback (`[]` for
  `games()`, `nil` for `starting_eleven()`, which already falls through to
  `predicted_eleven`) instead of looping indefinitely.
- **`NUMBER_OF_SIMULATIONS` typo (fixed 2026-09-08)**: was `100_00` (= 10,000, just a
  missing zero) instead of the documented/intended `100_000`. Underscores are only
  digit separators in Ruby — `100_00` and `10000` are identical. Simulations were
  running at 1/10th the intended sample size.
- **Cross-competition xG fallback + `League XGs` flag (added 2026-09-10)**: a team's
  first match of a new competition each season (e.g. a Champions League/Europa league-
  phase opener) can have ZERO rows for every player in `tournamentOptions=<competition>`
  — not just a low value, no data at all, since nobody in that competition has taken a
  shot yet this season. Neither the venue-specific nor the Overall-within-competition
  fallback can help here (there's nothing in that competition to fall back to). `xgs_new`
  now adds a third tier: drop `tournamentOptions` entirely (confirmed via the live API
  that this returns a team's stats across whatever competition(s) they've actually
  played this season — normally just their domestic league) and use that as a rough
  stand-in per player, sorted by `apps` descending when a player has rows in more than
  one competition. This is a known, accepted imprecision (deliberately chosen over
  excluding these matches) — a domestic-league shot rate is not a like-for-like proxy
  for Champions League-level opposition. Any match that needed it is flagged:
  `league_xgs_fallback` in the sim result, persisted as the `League XGs` CSV column
  (last column, appended at the end specifically so it doesn't shift any of the
  positional THRESHOLDS indices — see the Gotchas note on column ordering), shown as a
  `[LEAGUE XG]` tag next to `[PREDICTED XI]` in `build_proposals`' printed output, and
  called out with an explicit caution line in both AI-tips prompt builders
  (`format_results_for_prompt` / `format_csvs_for_prompt`) so the model treats those
  numbers as lower-confidence rather than blending them in silently.
- **CSV column ordering is load-bearing**: `THRESHOLDS` (see above) references CSV
  columns by raw positional index, computed from the `headers` array in
  `write_proposals_csv`. Never insert a new column in the middle of that array — it
  silently shifts every later THRESHOLDS index and miscategorizes bets. Append new
  columns at the very end (after `KellyNG`) instead, as done for `League XGs`.
- **Confirmed-zero vs missing-data conflation in the Missing-XGS check (fixed
  2026-09-16)**: the `[0,0]` sentinel used to count "unmatched" players toward
  `xgs_warning` (`> 2` triggers `Missing XGS: true`) didn't distinguish two very
  different situations: (a) a player who genuinely couldn't be matched in any of the
  three xG fallback tiers (real data uncertainty), and (b) a player who WAS matched
  but structurally has zero shots/apps recorded because they're a goalkeeper, or
  because they're an ever-present outfield player (e.g. a centre-back who plays every
  minute but has taken 0 shots all season) — both `[0,0]`, but the second case is a
  confirmed, legitimate value, not missing data. Diagnosed via Atletico Madrid vs
  Osasuna (2026-09-16 slate): Osasuna's predicted lineup produced 4 `[0,0]` players
  (Sergio Herrera - GK, Alejandro Catena - ever-present zero-shot CB with apps=5/450
  mins, Enzo Boyomo - apps=1(1)/111 mins, Romain Del Castillo - apps=0(1)/19 mins)
  against the naive `> 2` threshold, wrongly flagging a perfectly normal, well-attested
  domestic league match as `Missing XGS: true` just because the lineup happened to
  include a goalkeeper and one nailed-on defensive player alongside two genuinely
  thin-data fringe players. Fixed by moving the `home_cards_url`/`away_cards_url`
  fetch (the summary/cards endpoint, which lists every rostered player's real `apps`
  regardless of shot volume) earlier in `xgs_new`, before the warning computation, and
  replacing the blunt `[0,0]` count with `home_unexplained_zeros`/
  `away_unexplained_zeros`: a `[0,0]` player now only counts toward the warning if they
  ALSO show zero `apps` in that summary feed for this competition — i.e. no confirmed
  playing-time signal exists for them at all. A rostered player who's clearly playing
  regularly (any real `apps` count) but has 0 shots is treated as a confirmed
  legitimate zero and excluded from the warning count. This dropped Osasuna's
  "unexplained" count from 4 to 2 (Boyomo + Del Castillo only, the actual thin-data
  cases), so this kind of match should no longer be wrongly excluded going forward.
