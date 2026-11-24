# dendromatic 0.2.0

* `apply_breaks_and_shift()` split into composable steps: `dm_level_breaks()`,
  `dm_erase_dormancy()`, `dm_align_seasons()`, `dm_rebase_zero()`.
  `dm_clean_series()` composes them in the original sequence; output remains
  byte-identical to the toolkit implementation (enforced by the parity test).
  `apply_breaks_and_shift()` stays as an exported alias.
* Progress is now also signalled via 'progressr' (new Import): wrap calls in
  `progressr::with_progress()` or Shiny's `withProgressShiny()` handler. The
  terminal text bar is unchanged.
* New synthetic example dataset `dendro_sample` (two series, two seasons,
  one reinstallation step, one gap; `data-raw/dendro_sample.R`).
* Two vignettes: "Getting started with dendromatic" and "How break leveling
  works".
* pkgdown site configuration and GitHub Actions (R CMD check matrix + pkgdown
  deploy).

# dendromatic 0.1.0

Initial package release (GitHub/r-universe stage; not on CRAN).

* Code extracted verbatim from the DendroMatic `pipeline_helpers.R`
  (toolkit canonical copy, 2026-11-03). No behavior changes.
* New `dm_*` API names; every original name is kept as an exported alias
  (`raw_to_L0()`, `apply_breaks_and_shift()`, ...) so existing scripts and
  the DendroMatic Shiny apps keep working unchanged.
* `treenetproc` (GitHub-only) moved to `Suggests`: all call sites guarded,
  core break/level/normalize logic works without it.
* Interactive `datacleanr` session glue (`run_interactive_cleaning()`,
  `prep_for_dcr()`, ...) intentionally NOT included — it stays app-side.
* Planned for 0.2.0: split `apply_breaks_and_shift()` into composable steps
  (`dm_level_breaks()`, `dm_erase_dormancy()`, `dm_align_seasons()`,
  `dm_rebase_zero()`) behind a golden-file equivalence gate; `progressr`
  progress signalling; sample dataset + quick-start vignette.
