# Run 'treenetproc' L1 processing per variable

Runs
[`treenetproc::proc_L1()`](https://rdrr.io/pkg/treenetproc/man/proc_L1.html)
independently on each variable in `vars` and full-joins the results back
on (`series`, `ts`). Static columns are optionally re-joined. Requires
the suggested package 'treenetproc' (GitHub: `treenet/treenetproc`).
`multi_proc_L1()` is the original DendroMatic name, kept as an exported
alias.

## Usage

``` r
multi_proc_L1(
  df,
  vars,
  timevar = "ts",
  reso = 60,
  tz = "UTC",
  date_format = "%Y-%m-%d %H:%M:%S",
  drop_static = FALSE,
  parallel = FALSE
)

dm_proc_l1(
  df,
  vars,
  timevar = "ts",
  reso = 60,
  tz = "UTC",
  date_format = "%Y-%m-%d %H:%M:%S",
  drop_static = FALSE,
  parallel = FALSE
)
```

## Arguments

- df:

  Long data.frame with columns `series`, `timevar` and `vars`.

- vars:

  Character vector of value columns to process.

- timevar:

  Name of the timestamp column.

- reso:

  Output resolution in minutes (passed to `proc_L1`).

- tz:

  Timezone (passed to `proc_L1`).

- date_format:

  Timestamp format (passed to `proc_L1`).

- drop_static:

  If `TRUE`, static (non-processed) columns are dropped instead of
  re-joined.

- parallel:

  If `TRUE` and 'future.apply' is installed, variables are processed in
  parallel.

## Value

A time-aligned L1 data.frame with columns `series`, `ts`, the processed
`vars`, and (unless `drop_static`) the static columns.
