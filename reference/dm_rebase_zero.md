# Re-base each series so its minimum is zero

Subtracts the per-series minimum from all values, flooring every series
at zero. Run after break leveling, dormancy erasure and season alignment
– tree water deficit depends only on relative differences, so the
constant per-series offset does not distort it. One of the composable
steps behind
[`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md).

## Usage

``` r
dm_rebase_zero(df)
```

## Arguments

- df:

  Data.frame with columns `series` and `value`.

## Value

`df` with each series' minimum re-based to zero.
