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
- **Predicted XI flag**: when `starting_eleven` returns nil and `predicted_eleven` is
  used as fallback, a `[PREDICTED XI]` tag appears in the printed output next to the
  match header. Treat those proposals with extra caution.

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
`Home; Away; 1; X; 2; 1X; X2; 12; O15; U15; O25; U25; O35; U35; GG; Missing XGS; Both Cards; Score; Bet1; BetX; Bet2; Edge1; EdgeX; Edge2; Kelly1; KellyX; Kelly2`

Edge = simulated probability minus implied probability from decimal odds.
Kelly = edge / (decimal_odds - 1), only output when edge > 0.

## Thresholds (THRESHOLDS constant)
Used by `print_proposals` to flag eligible bets. Column indices map to:
- index 2,4 → 1 or 2 win: 60%
- index 3 → draw: 35%
- index 5,6,7 → double chance: 80%
- index 8–13 → over/under: 80%
- index 14 → GG: 80%
- index 16 → both cards: 80%

Columns for Score, Bet1/BetX/Bet2, Edge*, Kelly* are skipped in threshold checks.

## Edge-based exceptional bucket
`build_proposals` / `print_proposals` must surface a second class of bet: cases where the
bookmaker odds are significantly **mispricing** the simulation output, even when the raw
simulated probability does not meet the standard THRESHOLD.

**Rule**: for the 1/X/2 markets (the only ones with Edge/Kelly columns), also include the
bet if:
- `edge > EDGE_EXCEPTION_THRESHOLD` (bookmaker underestimates — value bet), OR
- `edge < -EDGE_EXCEPTION_THRESHOLD` (bookmaker overestimates — the outcome is much less
  likely than the odds imply; flag as a "lay / fade" signal)

`EDGE_EXCEPTION_THRESHOLD = 0.10` (i.e. ±10 percentage points) is the suggested default.

These rows must be clearly labeled in the printed output (e.g. `[EDGE]` tag) so they are
visually distinct from threshold-passing bets. A bet that qualifies on *both* grounds
(threshold AND edge) should be printed once with both tags.

**Why this matters**: a 55% home-win probability misses the 60% SINGLE_THRESHOLD, but if
the bookmaker prices it at 2.50 (implied 40%), the +15 pp edge is actionable regardless.
Conversely, a draw at 25% that a bookmaker prices at 1.80 (implied 56%) is a strong fade
signal even though 25% is below the 35% DRAW_THRESHOLD.

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
