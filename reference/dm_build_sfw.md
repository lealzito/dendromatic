# Assemble the standard SFW table from daily L2 and phase statistics

Builds the HOL-style SFW (stem features and water deficit) tibble from
daily L2 output and
[`treenetproc::phase_stats()`](https://rdrr.io/pkg/treenetproc/man/phase_stats.html)
output: species lookup, MDS and predawn/midday TWD normalisation, one
row per series and day. `build_sfw()` is the original DendroMatic name,
kept as an exported alias.

## Usage

``` r
build_sfw(
  L2_daily,
  phase_daily,
  site_tag,
  treatment = "Control",
  species_lut = default_species_lut(),
  site_col = c("tag", "series"),
  include_phase_cols = FALSE
)

dm_build_sfw(
  L2_daily,
  phase_daily,
  site_tag,
  treatment = "Control",
  species_lut = default_species_lut(),
  site_col = c("tag", "series"),
  include_phase_cols = FALSE
)
```

## Arguments

- L2_daily:

  Daily L2 data.frame; must contain `series`, `day`, `value`, `max`,
  `twd`, `gro_yr`, `pdtwd`, `mdtwd`.

- phase_daily:

  [`treenetproc::phase_stats()`](https://rdrr.io/pkg/treenetproc/man/phase_stats.html)
  output, deduplicated per series and day.

- site_tag:

  Site code written into the `tag` column.

- treatment:

  Treatment label written into the `treatment` column.

- species_lut:

  Lookup tibble with columns `species_abv` and `species`; defaults to
  [`dm_species_lut()`](https://lealzito.github.io/dendromatic/reference/dm_species_lut.md).

- site_col:

  Where to read the site from: `"tag"` or `"series"`.

- include_phase_cols:

  If `TRUE`, phase columns are kept in the output.

## Value

The SFW tibble, one row per series and day.
