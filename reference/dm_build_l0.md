# Convert a raw dendrometer table to 'treenetproc' L0 format

Ingests a raw logger table of almost any shape – long or wide, text or
Excel origin – and returns the strict L0 long format used by
'treenetproc' and the rest of the dendromatic pipeline: `series`
(character), `ts` (POSIXct) and `value` (micrometres). Handles timestamp
parsing (including Excel serial dates), unit conversion (mm, cm,
voltage- or resistance-based sensors to micrometres), species lookup,
tree-number extraction and deduplication. `raw_to_L0()` is the original
DendroMatic name, kept as an exported alias.

## Usage

``` r
raw_to_L0(
  df_raw,
  ts_col,
  value_col,
  tree_num_col = NULL,
  site,
  long_or_wide = c("long", "wide"),
  tz_in,
  tz_out = "UTC",
  measurement_unit = c("um", "mm", "cm", "voltage", "resistance"),
  species_col = NULL,
  metadata = NULL,
  meta_id_col = NULL,
  meta_species_col = NULL,
  species_abv = NULL,
  tree_num_pad = 3,
  tree_num_regex = "\\d+$",
  excel_epoch = c("windows", "mac"),
  date_format = NULL,
  supply_col = NULL,
  supply_voltage = NULL,
  scale_um = 11000,
  value_in_mv = FALSE,
  ohm_span = NULL,
  um_span = NULL,
  ohm_zero = 0,
  resist_invert = FALSE,
  treatment_col = NULL
)

dm_build_l0(
  df_raw,
  ts_col,
  value_col,
  tree_num_col = NULL,
  site,
  long_or_wide = c("long", "wide"),
  tz_in,
  tz_out = "UTC",
  measurement_unit = c("um", "mm", "cm", "voltage", "resistance"),
  species_col = NULL,
  metadata = NULL,
  meta_id_col = NULL,
  meta_species_col = NULL,
  species_abv = NULL,
  tree_num_pad = 3,
  tree_num_regex = "\\d+$",
  excel_epoch = c("windows", "mac"),
  date_format = NULL,
  supply_col = NULL,
  supply_voltage = NULL,
  scale_um = 11000,
  value_in_mv = FALSE,
  ohm_span = NULL,
  um_span = NULL,
  ohm_zero = 0,
  resist_invert = FALSE,
  treatment_col = NULL
)
```

## Arguments

- df_raw:

  Raw data.frame as read from the logger export.

- ts_col:

  Name of the timestamp column in `df_raw`.

- value_col:

  Name of the measurement column (long layout).

- tree_num_col:

  Optional column holding the tree number; `NULL` to extract it from
  series names via `tree_num_regex`.

- site:

  Site tag prepended to series identifiers (e.g. `"HOL"`).

- long_or_wide:

  `"long"` or `"wide"` input layout.

- tz_in:

  Timezone of the input timestamps.

- tz_out:

  Timezone of the output `ts` column.

- measurement_unit:

  Input unit: `"um"`, `"mm"` or `"cm"`; sensors reporting voltage or
  resistance are handled via the `supply_*`/`ohm_*` arguments.

- species_col:

  Optional column with species codes or names.

- metadata:

  Optional metadata data.frame joined by `meta_id_col`.

- meta_id_col, meta_species_col:

  Column names in `metadata` holding the tree identifier and the
  species.

- species_abv:

  Fallback species abbreviation when none can be derived.

- tree_num_pad:

  Zero-padding width for tree numbers in series names.

- tree_num_regex:

  Regex used to extract the tree number from raw ids.

- excel_epoch:

  `"windows"` or `"mac"` Excel date origin.

- date_format:

  Explicit timestamp format; `NULL` = auto-detect.

- supply_col, supply_voltage, scale_um, value_in_mv:

  Conversion settings for voltage-based sensors.

- ohm_span, um_span, ohm_zero, resist_invert:

  Conversion settings for resistance-based sensors.

- treatment_col:

  Optional treatment column carried through to the output.

## Value

A data.frame in L0 long format with columns `series` (character), `ts`
(POSIXct in `tz_out`) and `value` (micrometres), deduplicated on
(`series`, `ts`), plus any carried metadata columns.
