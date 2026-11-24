# Level sensor breaks with growth-aware shifting

Applies user-defined break windows (sensor relocations, reinstallations,
jumps) to a series: the in-break span is deleted and all post-break
values are shifted so the level reconnects to the pre-break reference,
plus a growth extrapolation estimated from the pre-break slope. The
reference on each side of the break is the nearest non-NA value within
`growth_window_days` (so a break endpoint sitting on a data gap does not
poison the shift). One of the composable steps behind
[`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md).

## Usage

``` r
dm_level_breaks(
  df,
  brks,
  grow_start_dm = "01-05",
  grow_end_dm = "31-10",
  growth_window_days = 14,
  growth_method = c("daily_lm", "10min_lm", "daily_robust", "10min_lm_flip"),
  allow_negative_growth = FALSE,
  max_slope_day = Inf,
  max_growth_total = Inf,
  tz = "UTC"
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

## Value

`df` with breaks levelled (plus an internal `.row_id` ordering column
added by the input validation).
