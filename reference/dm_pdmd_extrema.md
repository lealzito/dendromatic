# Daily predawn and midday tree water deficit extrema (local time)

Extracts, per series and local-time day, the predawn minimum and midday
maximum of the tree water deficit from hourly L2 data, using fixed
local-time hour windows. `compute_pdmd_extrema_tz()` is the original
DendroMatic name, kept as an exported alias.

## Usage

``` r
compute_pdmd_extrema_tz(
  L2_hourly,
  pd_start_hr,
  pd_end_hr,
  md_start_hr,
  md_end_hr,
  tz
)

dm_pdmd_extrema(L2_hourly, pd_start_hr, pd_end_hr, md_start_hr, md_end_hr, tz)
```

## Arguments

- L2_hourly:

  Hourly L2 data.frame with columns `series`, `ts`, `twd`.

- pd_start_hr, pd_end_hr:

  Predawn window (local hours, inclusive).

- md_start_hr, md_end_hr:

  Midday window (local hours, inclusive).

- tz:

  Local timezone used to derive day and hour.

## Value

A data.frame with one row per `series` and local `date`, holding `pdtwd`
(window minimum) and `mdtwd` (window maximum).
