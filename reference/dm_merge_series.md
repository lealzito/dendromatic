# Merge consecutive dendrometer series from the same tree

Concatenates two or more series (e.g. after a sensor swap) into one
output series, resolving overlap periods by the chosen method. No value
discontinuity correction is applied – run
[`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
with a break window afterwards. `merge_series()` is the original
DendroMatic name, kept as an exported alias.

## Usage

``` r
merge_series(
  input,
  series_names,
  output_series,
  overlap_method = c("first", "second", "mean"),
  tz = "UTC"
)

dm_merge_series(
  input,
  series_names,
  output_series,
  overlap_method = c("first", "second", "mean"),
  tz = "UTC"
)
```

## Arguments

- input:

  A long data.frame (`series`, `ts`, `value`) or a named list of
  per-series data.frames.

- series_names:

  Character vector (length \>= 2) of series to merge, in chronological
  order.

- output_series:

  Name of the merged output series.

- overlap_method:

  How to resolve overlapping timestamps: `"first"`, `"second"` or
  `"mean"`.

- tz:

  Timezone for timestamp coercion.

## Value

A data.frame (`series`, `ts`, `value`) holding the merged series under
`output_series`.
