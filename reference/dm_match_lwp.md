# Match leaf water potential campaigns to the SFW table

Two-tier matching of leaf water potential (LWP) observations to SFW
rows: Tier A matches on timestamp against hourly L2 data within
`TIER_A_TOL_MIN` minutes; Tier B falls back to a date join on (`series`,
`day`). `match_lwp_to_sfw()` is the original DendroMatic name, kept as
an exported alias.

## Usage

``` r
match_lwp_to_sfw(
  SFW,
  LWP_daily,
  L2_hourly = NULL,
  TIER_A_TOL_MIN = 30L,
  old_series_col = NULL,
  site_tag = "?"
)

dm_match_lwp(
  SFW,
  LWP_daily,
  L2_hourly = NULL,
  TIER_A_TOL_MIN = 30L,
  old_series_col = NULL,
  site_tag = "?"
)
```

## Arguments

- SFW:

  SFW data.frame; must contain `series`, `day`, `MDS_max`, `pdtwd`,
  `mdtwd`.

- LWP_daily:

  LWP data.frame; must contain `series`, `day`, `pdlwp`, `mdlwp`.

- L2_hourly:

  Optional hourly L2 data.frame enabling Tier A timestamp matching.

- TIER_A_TOL_MIN:

  Tier A matching tolerance in minutes.

- old_series_col:

  Optional column in `LWP_daily` holding legacy series names to
  translate.

- site_tag:

  Site label used in diagnostic messages.

## Value

The SFW data.frame with matched LWP columns and per-row tier flags
(`lwp_tier_pd`, `lwp_tier_md`).
