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
