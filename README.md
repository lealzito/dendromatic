# dendromatic

Processing, cleaning and normalization of point-dendrometer time series.
The computational core behind the DendroMatic Shiny applications, usable
standalone in scripted workflows.

**Status: pre-release (0.1.x).** GitHub/r-universe stage; CRAN submission is
planned only after the API freezes at 1.0.0. Function names may still change —
pin a commit/tag if you depend on this.

## Installation

```r
# install.packages("remotes")
remotes::install_github("treenet/treenetproc")   # suggested dependency
remotes::install_github("joaoglmartins/dendromatic")
```

## Core pipeline

```r
library(dendromatic)

L0 <- dm_build_l0(raw_df, ts_col = "timestamp", value_col = "um",
                  site = "MYSITE", tz_in = "Etc/GMT-1")
L1 <- dm_proc_l1(L0, vars = "value", reso = 10)
cleaned <- dm_clean_series(L1, brks = list(MYSITE_FaSy001 = list(
  c("2021-06-01 00:00:00", "2021-06-04 12:00:00"))))
```

The cleaning core is also available as composable steps:

```r
L1 |>
  dm_level_breaks(brks)  |>   # growth-aware sensor-break leveling
  dm_erase_dormancy()    |>   # NA outside the growing season
  dm_align_seasons()     |>   # carry growth across winters
  dm_rebase_zero()            # floor each series at zero
```

Try it on the shipped synthetic dataset `dendro_sample`; see
`vignette("dendromatic")` (quick start) and `vignette("break-leveling")`
(method). Progress reporting works in terminals and Shiny alike via
`progressr::with_progress()`.

Every function also answers to its original DendroMatic name
(`raw_to_L0()`, `multi_proc_L1()`, `apply_breaks_and_shift()`, ...).

## API map

| `dm_*` name | original name | purpose |
|---|---|---|
| `dm_build_l0()` | `raw_to_L0()` | any raw logger table -> treenetproc L0 |
| `dm_proc_l1()` | `multi_proc_L1()` | per-variable proc_L1 + join |
| `dm_run_pipeline()` | `run_L1_L2()` | L0 -> L1 -> L2 backbone with RDS outputs |
| `dm_clean_series()` | `apply_breaks_and_shift()` | breaks + dormancy + alignment + zero-norm |
| `dm_level_breaks()` | — (new, 0.2.0) | break leveling step alone |
| `dm_erase_dormancy()` | — (new, 0.2.0) | dormancy erasure step alone |
| `dm_align_seasons()` | — (new, 0.2.0) | season alignment step alone |
| `dm_rebase_zero()` | — (new, 0.2.0) | per-series zero re-base step alone |
| `dm_merge_series()` | `merge_series()` | merge consecutive series, same tree |
| `dm_pdmd_extrema()` | `compute_pdmd_extrema_tz()` | daily predawn/midday TWD extrema |
| `dm_build_sfw()` | `build_sfw()` | assemble SFW table from L2 + phase stats |
| `dm_match_lwp()` | `match_lwp_to_sfw()` | two-tier LWP campaign matching |
| `dm_build_temp_l1()` | `build_temp_L1_generic()` | assemble temperature L1 from a folder |
| `dm_read_table()` | `read_any_table()` | delimiter/encoding-robust table reader |
| `dm_repair_series()` | `repair_series_HOLstyle()` | standardize series IDs (SITE_SpAb###) |
| `dm_species_lut()` | `default_species_lut()` | species abbreviation lookup table |

## Provenance

Extracted from `DendroMatic_toolkit/R/pipeline_helpers.R` (2026-11-03,
verbatim; see `NEWS.md`). Plan and design decisions:
`DendroMatic_toolkit/docs/plans/2026-11-03-cran-package-plan.md`.
