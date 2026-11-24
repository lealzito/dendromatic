# Package index

## Cleaning pipeline

The DendroMatic cleaning core and its composable steps.

- [`dm_clean_series()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
  [`apply_breaks_and_shift()`](https://lealzito.github.io/dendromatic/reference/dm_clean_series.md)
  : Clean a dendrometer series: breaks, dormancy, alignment, zero base
- [`dm_level_breaks()`](https://lealzito.github.io/dendromatic/reference/dm_level_breaks.md)
  : Level sensor breaks with growth-aware shifting
- [`dm_erase_dormancy()`](https://lealzito.github.io/dendromatic/reference/dm_erase_dormancy.md)
  : Erase dormancy periods outside the growing season
- [`dm_align_seasons()`](https://lealzito.github.io/dendromatic/reference/dm_align_seasons.md)
  : Align each season's start to the prior year's maximum
- [`dm_rebase_zero()`](https://lealzito.github.io/dendromatic/reference/dm_rebase_zero.md)
  : Re-base each series so its minimum is zero

## Ingestion and processing

- [`raw_to_L0()`](https://lealzito.github.io/dendromatic/reference/dm_build_l0.md)
  [`dm_build_l0()`](https://lealzito.github.io/dendromatic/reference/dm_build_l0.md)
  : Convert a raw dendrometer table to 'treenetproc' L0 format
- [`multi_proc_L1()`](https://lealzito.github.io/dendromatic/reference/dm_proc_l1.md)
  [`dm_proc_l1()`](https://lealzito.github.io/dendromatic/reference/dm_proc_l1.md)
  : Run 'treenetproc' L1 processing per variable
- [`run_L1_L2()`](https://lealzito.github.io/dendromatic/reference/dm_run_pipeline.md)
  [`dm_run_pipeline()`](https://lealzito.github.io/dendromatic/reference/dm_run_pipeline.md)
  : Run the L0 to L1 to L2 site pipeline backbone
- [`merge_series()`](https://lealzito.github.io/dendromatic/reference/dm_merge_series.md)
  [`dm_merge_series()`](https://lealzito.github.io/dendromatic/reference/dm_merge_series.md)
  : Merge consecutive dendrometer series from the same tree
- [`build_temp_L1_generic()`](https://lealzito.github.io/dendromatic/reference/dm_build_temp_l1.md)
  [`dm_build_temp_l1()`](https://lealzito.github.io/dendromatic/reference/dm_build_temp_l1.md)
  : Assemble a temperature L1 object from a climate folder

## Water-relations outputs

- [`compute_pdmd_extrema_tz()`](https://lealzito.github.io/dendromatic/reference/dm_pdmd_extrema.md)
  [`dm_pdmd_extrema()`](https://lealzito.github.io/dendromatic/reference/dm_pdmd_extrema.md)
  : Daily predawn and midday tree water deficit extrema (local time)
- [`build_sfw()`](https://lealzito.github.io/dendromatic/reference/dm_build_sfw.md)
  [`dm_build_sfw()`](https://lealzito.github.io/dendromatic/reference/dm_build_sfw.md)
  : Assemble the standard SFW table from daily L2 and phase statistics
- [`match_lwp_to_sfw()`](https://lealzito.github.io/dendromatic/reference/dm_match_lwp.md)
  [`dm_match_lwp()`](https://lealzito.github.io/dendromatic/reference/dm_match_lwp.md)
  : Match leaf water potential campaigns to the SFW table

## Utilities and data

- [`read_any_table()`](https://lealzito.github.io/dendromatic/reference/dm_read_table.md)
  [`dm_read_table()`](https://lealzito.github.io/dendromatic/reference/dm_read_table.md)
  : Read a delimited text file or Excel workbook
- [`repair_series_HOLstyle()`](https://lealzito.github.io/dendromatic/reference/dm_repair_series.md)
  [`dm_repair_series()`](https://lealzito.github.io/dendromatic/reference/dm_repair_series.md)
  : Standardise series identifiers to SITE_SpAb### style
- [`default_species_lut()`](https://lealzito.github.io/dendromatic/reference/dm_species_lut.md)
  [`dm_species_lut()`](https://lealzito.github.io/dendromatic/reference/dm_species_lut.md)
  : Default species abbreviation lookup table
- [`dendro_sample`](https://lealzito.github.io/dendromatic/reference/dendro_sample.md)
  : Synthetic example dendrometer dataset
