# Getting started with dendromatic

dendromatic is the computational core behind the DendroMatic
applications: cleaning and normalization of point-dendrometer time
series. This vignette walks the standard path from a raw-ish series to a
cleaned one on the shipped synthetic dataset.

``` r

library(dendromatic)
```

## The example data

`dendro_sample` holds two synthetic hourly series over two growing
seasons. `SYN_Pa002` carries the two artefacts this package exists to
fix: a +35 µm sensor-reinstallation step (2022-06-15) and a multi-day
data gap.

``` r

d <- subset(dendro_sample, series == "SYN_Pa002")
plot(d$ts, d$value, type = "l", xlab = "", ylab = "stem radius (µm)",
     main = "SYN_Pa002, raw")
abline(v = as.POSIXct("2022-06-15 12:00:00", tz = "UTC"), col = "red", lty = 2)
```

![](dendromatic_files/figure-html/raw-plot-1.png)

## Cleaning in one call

[`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
applies, in order: break leveling, dormancy erasure, season alignment,
and per-series zero re-basing. Break windows are passed as a named list,
one `c(start, end)` pair per break. `rerun_proc_L2 = FALSE` keeps this
vignette independent of the GitHub-only ‘treenetproc’ package; in a real
pipeline leave it `TRUE` so TWD and zero-growth columns are recomputed.

``` r

brks <- list(SYN_Pa002 = list(
  c("2022-06-15 10:00:00", "2022-06-15 14:00:00")
))

cleaned <- dm_clean_series(
  df            = dendro_sample,
  brks          = brks,
  grow_start_dm = "01-05",   # growing season: 1 May ...
  grow_end_dm   = "31-10",   # ... to 31 October
  rerun_proc_L2 = FALSE
)
#> apply_breaks_and_shift [breaks]: 1 break(s) across 2 series...
#>   |                                                          |                                                  |   0%  |                                                          |=========================                         |  50%  |                                                          |==================================================| 100%
#> 
#> apply_breaks_and_shift [dormancy/alignment]: 2 series...
#>   |                                                          |                                                  |   0%  |                                                          |=========================                         |  50%  |                                                          |==================================================| 100%
#> 
```

``` r

cd <- subset(cleaned, series == "SYN_Pa002")
plot(cd$ts, cd$value, type = "l", xlab = "", ylab = "stem radius (µm)",
     main = "SYN_Pa002, cleaned")
```

![](dendromatic_files/figure-html/clean-plot-1.png)

The step is gone, the dormancy period between the seasons is erased,
season two starts at season one’s maximum, and the series minimum sits
at zero.

## Daily predawn / midday extrema

Downstream water-relations work usually needs the daily predawn minimum
and midday maximum of tree water deficit (TWD). With a `twd` column
(normally from the treenetproc L2 step),
[`dm_pdmd_extrema()`](https://lealzito.github.io/dendromatic/reference/dm_pdmd_extrema.md)
extracts both in local time:

``` r

## toy TWD: running max minus value, per series
cleaned$twd <- ave(cleaned$value, cleaned$series, FUN = function(v) {
  m <- cummax(ifelse(is.na(v), -Inf, v)); ifelse(is.na(v), NA, m - v)
})
pdmd <- dm_pdmd_extrema(cleaned, pd_start_hr = 3, pd_end_hr = 6,
                        md_start_hr = 12, md_end_hr = 15, tz = "Etc/GMT-1")
head(pdmd)
#> # A tibble: 6 × 4
#>   series    date       pdtwd mdtwd
#>   <chr>     <date>     <dbl> <dbl>
#> 1 SYN_Fs001 2021-04-01    NA    NA
#> 2 SYN_Fs001 2021-04-02    NA    NA
#> 3 SYN_Fs001 2021-04-03    NA    NA
#> 4 SYN_Fs001 2021-04-04    NA    NA
#> 5 SYN_Fs001 2021-04-05    NA    NA
#> 6 SYN_Fs001 2021-04-06    NA    NA
```

## Progress reporting

All engines signal progress via ‘progressr’ (alongside a terminal text
bar). In scripts:

``` r

progressr::with_progress(
  cleaned <- dm_clean_series(dendro_sample, brks = brks)
)
```

In a Shiny app, wrap the same call with
[`progressr::withProgressShiny()`](https://progressr.futureverse.org/reference/withProgressShiny.html)
– the core stays UI-free.

## Original names

Every function also answers to its original DendroMatic name
([`apply_breaks_and_shift()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md),
[`raw_to_L0()`](https://lealzito.github.io/dendromatic/reference/dm_build_l0.md),
…), so existing scripts keep running unchanged. See the README API map.
