# Run the L0 to L1 to L2 site pipeline backbone

Shared backbone for site processing scripts: validates the L0 input,
processes L1 and L2 via 'treenetproc' (optionally with a temperature
L1), and writes RDS outputs to the supplied directories. Requires the
suggested package 'treenetproc'. `run_L1_L2()` is the original
DendroMatic name, kept as an exported alias.

## Usage

``` r
run_L1_L2(
  L0_long,
  reso_min,
  site_tag,
  out_dir_L0,
  out_dir_L1,
  out_dir_L2,
  temp_L1 = NULL,
  tz_use = "UTC",
  write_per_series = FALSE,
  raw_dir = file.path(out_dir_L0, paste0(site_tag, "_RAW")),
  l0_fname = paste0(site_tag, "_L0_long.rds"),
  l1_fname = paste0(site_tag, "_L1.rds"),
  l2_fname = paste0(site_tag, "_L2_auto.rds")
)

dm_run_pipeline(
  L0_long,
  reso_min,
  site_tag,
  out_dir_L0,
  out_dir_L1,
  out_dir_L2,
  temp_L1 = NULL,
  tz_use = "UTC",
  write_per_series = FALSE,
  raw_dir = file.path(out_dir_L0, paste0(site_tag, "_RAW")),
  l0_fname = paste0(site_tag, "_L0_long.rds"),
  l1_fname = paste0(site_tag, "_L1.rds"),
  l2_fname = paste0(site_tag, "_L2_auto.rds")
)
```

## Arguments

- L0_long:

  L0 long data.frame (`series`, `ts`, `value`).

- reso_min:

  Measurement resolution in minutes.

- site_tag:

  Site code used in output filenames (e.g. `"HOL"`).

- out_dir_L0, out_dir_L1, out_dir_L2:

  Output directories for the L0, L1 and L2 RDS files. All writes go only
  to these user-supplied paths.

- temp_L1:

  Optional temperature L1 object for `proc_dendro_L2`.

- tz_use:

  Timezone used throughout.

- write_per_series:

  If `TRUE`, additionally writes one RDS per series.

- raw_dir:

  Directory for per-series raw dumps.

- l0_fname, l1_fname, l2_fname:

  Output filenames.

## Value

Invisibly, a list with elements `L0`, `L1` and `L2`.
