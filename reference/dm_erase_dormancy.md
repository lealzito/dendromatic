# Erase dormancy periods outside the growing season

Sets to `NA` all data outside the `[grow_start_dm, grow_end_dm]` window
of each year: pre-first-season data, inter-annual dormancy gaps, and
data after the last year with valid growing-season observations. A
series with no growing-season data at all is fully erased. One of the
composable steps behind
[`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md).

## Usage

``` r
dm_erase_dormancy(
  df,
  grow_start_dm = "01-05",
  grow_end_dm = "31-10",
  tz = "UTC",
  first_year_override = NULL,
  last_year_override = NULL
)
```

## Arguments

- df:

  Data.frame with columns `series`, `ts`, `value`.

- grow_start_dm, grow_end_dm:

  Growing-season start and end as `"DD-MM"` strings.

- tz:

  Timezone for timestamp coercion.

- first_year_override, last_year_override:

  Integers forcing the first or last growing-season year; `NULL` =
  auto-detect from data inside the growing-season window.

## Value

`df` with dormancy periods erased (plus an internal `.row_id` ordering
column added by the input validation).
