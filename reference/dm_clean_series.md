# Clean a dendrometer series: breaks, dormancy, alignment, zero base

The DendroMatic cleaning core. Composes, in order:
[`dm_level_breaks()`](https://lealzito.github.io/dendromatic/reference/dm_level_breaks.md)
(growth-aware break leveling),
[`dm_erase_dormancy()`](https://lealzito.github.io/dendromatic/reference/dm_erase_dormancy.md)
and
[`dm_align_seasons()`](https://lealzito.github.io/dendromatic/reference/dm_align_seasons.md)
(one combined season pass, controlled by `do_dormancy_gap` and
`align_to_prev_peak`),
[`dm_rebase_zero()`](https://lealzito.github.io/dendromatic/reference/dm_rebase_zero.md),
and an optional re-run of
[`treenetproc::proc_dendro_L2()`](https://rdrr.io/pkg/treenetproc/man/proc_dendro_L2.html)
on the result ('treenetproc' required only for that step).
`apply_breaks_and_shift()` is the original DendroMatic name, kept as an
exported alias; output is byte-identical to the original single-function
implementation (enforced by the package's toolkit-parity test).

## Usage

``` r
dm_clean_series(
  df,
  brks,
  grow_start_dm = "01-05",
  grow_end_dm = "31-10",
  growth_window_days = 14,
  growth_method = c("daily_lm", "10min_lm", "daily_robust", "10min_lm_flip"),
  allow_negative_growth = FALSE,
  max_slope_day = Inf,
  max_growth_total = Inf,
  tz = "UTC",
  rerun_proc_L2 = TRUE,
  year_range = NULL,
  do_dormancy_gap = TRUE,
  align_to_prev_peak = TRUE,
  initial_clip_ts = NULL,
  final_clip_ts = NULL,
  first_year_override = NULL,
  last_year_override = NULL
)

apply_breaks_and_shift(
  df,
  brks,
  grow_start_dm = "01-05",
  grow_end_dm = "31-10",
  growth_window_days = 14,
  growth_method = c("daily_lm", "10min_lm", "daily_robust", "10min_lm_flip"),
  allow_negative_growth = FALSE,
  max_slope_day = Inf,
  max_growth_total = Inf,
  tz = "UTC",
  rerun_proc_L2 = TRUE,
  year_range = NULL,
  do_dormancy_gap = TRUE,
  align_to_prev_peak = TRUE,
  initial_clip_ts = NULL,
  final_clip_ts = NULL,
  first_year_override = NULL,
  last_year_override = NULL
)
```

## Arguments

- df:

  Data.frame with columns `series`, `ts`, `value`.

- brks:

  Named list: series name to a list of `c(start, end)` timestamp pairs.
  A flat unnamed list of pairs is accepted for a single-series `df`.

- grow_start_dm, grow_end_dm:

  Growing-season start and end as `"DD-MM"` strings.

- growth_window_days:

  Window (days) used for the slope estimate and the level-shift
  reference search around each break.

- growth_method:

  Slope estimation method: one of `"daily_lm"`, `"10min_lm"`,
  `"daily_robust"`, `"10min_lm_flip"`.

- allow_negative_growth:

  If `FALSE`, negative slope estimates are clamped to zero.

- max_slope_day:

  Cap on the slope estimate (micrometres per day).

- max_growth_total:

  Cap on the growth extrapolation per gap (micrometres).

- tz:

  Timezone for timestamp coercion.

- rerun_proc_L2:

  If `TRUE`, re-runs `proc_dendro_L2` on the cleaned data (requires
  'treenetproc').

- year_range:

  Optional year range for the attached display view.

- do_dormancy_gap:

  If `TRUE`, erases inter-seasonal dormancy periods and pre-first-season
  data.

- align_to_prev_peak:

  If `TRUE`, aligns each season's start to the prior year's maximum.

- initial_clip_ts, final_clip_ts:

  Optional timestamps; rows outside `[initial_clip_ts, final_clip_ts]`
  are dropped before any other step.

- first_year_override, last_year_override:

  Integers forcing the first or last growing-season year; `NULL` =
  auto-detect from data inside the growing-season window.

## Value

A data.frame of the same shape as `df` with breaks levelled, dormancy
erased, seasons aligned and each series re-based to zero (the L2 output
when `rerun_proc_L2 = TRUE`). Carries a `"dcr_view"` attribute with the
display view.

## Details

Progress is reported both as a terminal text bar and as 'progressr'
signals: wrap the call in
[`progressr::with_progress()`](https://progressr.futureverse.org/reference/with_progress.html)
(or a Shiny `withProgressShiny()` handler) to render them elsewhere.
