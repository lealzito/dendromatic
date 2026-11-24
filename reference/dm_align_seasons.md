# Align each season's start to the prior year's maximum

For every year after the first growing season, shifts the season (and
all later data) up so its first value matches the previous season's
maximum – preserving cumulative growth across the winter. The first
growing season is never shifted (no prior peak exists). One of the
composable steps behind
[`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md).

## Usage

``` r
dm_align_seasons(
  df,
  grow_start_dm = "01-05",
  grow_end_dm = "31-10",
  tz = "UTC",
  first_year_override = NULL
)
```

## Arguments

- df:

  Data.frame with columns `series`, `ts`, `value`.

- grow_start_dm, grow_end_dm:

  Growing-season start and end as `"DD-MM"` strings.

- tz:

  Timezone for timestamp coercion.

- first_year_override:

  Integer forcing the first growing-season year; `NULL` = auto-detect
  from data inside the growing-season window.

## Value

`df` with seasons aligned (plus an internal `.row_id` ordering column
added by the input validation).
