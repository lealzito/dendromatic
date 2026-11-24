# Changelog

## dendromatic 0.2.0

- [`apply_breaks_and_shift()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
  split into composable steps:
  [`dm_level_breaks()`](https://lealzito.github.io/dendromatic/reference/dm_level_breaks.md),
  [`dm_erase_dormancy()`](https://lealzito.github.io/dendromatic/reference/dm_erase_dormancy.md),
  [`dm_align_seasons()`](https://lealzito.github.io/dendromatic/reference/dm_align_seasons.md),
  [`dm_rebase_zero()`](https://lealzito.github.io/dendromatic/reference/dm_rebase_zero.md).
  [`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
  composes them in the original sequence; output remains byte-identical
  to the toolkit implementation (enforced by the parity test).
  [`apply_breaks_and_shift()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
  stays as an exported alias.
- Progress is now also signalled via ‘progressr’ (new Import): wrap
  calls in
  [`progressr::with_progress()`](https://progressr.futureverse.org/reference/with_progress.html)
  or Shiny’s `withProgressShiny()` handler. The terminal text bar is
  unchanged.
- New synthetic example dataset `dendro_sample` (two series, two
  seasons, one reinstallation step, one gap;
  `data-raw/dendro_sample.R`).
- Two vignettes: “Getting started with dendromatic” and “How break
  leveling works”.
- pkgdown site configuration and GitHub Actions (R CMD check matrix +
  pkgdown deploy).

## dendromatic 0.1.0

Initial package release (GitHub/r-universe stage; not on CRAN).

- Code extracted verbatim from the DendroMatic `pipeline_helpers.R`
  (toolkit canonical copy, 2026-11-03). No behavior changes.
- New `dm_*` API names; every original name is kept as an exported alias
  ([`raw_to_L0()`](https://lealzito.github.io/dendromatic/reference/dm_build_l0.md),
  [`apply_breaks_and_shift()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md),
  …) so existing scripts and the DendroMatic Shiny apps keep working
  unchanged.
- `treenetproc` (GitHub-only) moved to `Suggests`: all call sites
  guarded, core break/level/normalize logic works without it.
- Interactive `datacleanr` session glue (`run_interactive_cleaning()`,
  `prep_for_dcr()`, …) intentionally NOT included — it stays app-side.
- Planned for 0.2.0: split
  [`apply_breaks_and_shift()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
  into composable steps
  ([`dm_level_breaks()`](https://lealzito.github.io/dendromatic/reference/dm_level_breaks.md),
  [`dm_erase_dormancy()`](https://lealzito.github.io/dendromatic/reference/dm_erase_dormancy.md),
  [`dm_align_seasons()`](https://lealzito.github.io/dendromatic/reference/dm_align_seasons.md),
  [`dm_rebase_zero()`](https://lealzito.github.io/dendromatic/reference/dm_rebase_zero.md))
  behind a golden-file equivalence gate; `progressr` progress
  signalling; sample dataset + quick-start vignette.
