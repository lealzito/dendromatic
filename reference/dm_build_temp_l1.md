# Assemble a temperature L1 object from a climate folder

Recursively searches `clim_root` for xlsx/csv files with a recognisable
timestamp and temperature column and assembles a 'treenetproc'
temperature L1 object. Requires the suggested package 'treenetproc'.
`build_temp_L1_generic()` is the original DendroMatic name, kept as an
exported alias.

## Usage

``` r
build_temp_L1_generic(
  clim_root,
  site_tag,
  tz = "UTC",
  reso = 10L,
  ts_col_priority = c("timestamp_UTC", "ts", "timestamp", "date_time", "datetime",
    "DateTime", "TIMESTAMP"),
  temp_col_priority = c("Temp_degC_forest", "Ta_degC", "temp", "temperature",
    "Temp_degC", "Tair", "TA"),
  out_rds = NULL
)

dm_build_temp_l1(
  clim_root,
  site_tag,
  tz = "UTC",
  reso = 10L,
  ts_col_priority = c("timestamp_UTC", "ts", "timestamp", "date_time", "datetime",
    "DateTime", "TIMESTAMP"),
  temp_col_priority = c("Temp_degC_forest", "Ta_degC", "temp", "temperature",
    "Temp_degC", "Tair", "TA"),
  out_rds = NULL
)
```

## Arguments

- clim_root:

  Root directory searched for climate files.

- site_tag:

  Site code used for the series name.

- tz:

  Timezone of the input timestamps.

- reso:

  Output resolution in minutes.

- ts_col_priority, temp_col_priority:

  Candidate column names tried in order for the timestamp and
  temperature columns.

- out_rds:

  Optional path; when given, the result is also saved there.

## Value

A temperature L1 data.frame, or `NULL` when no usable file is found.
