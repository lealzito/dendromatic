## Golden parity: the package's dm_clean_series() must reproduce the toolkit's
## apply_breaks_and_shift() byte-for-byte on the synthetic step series.
## Only runs on a machine that has the DendroMatic_toolkit checkout.

toolkit_helpers <- file.path(
  "G:/My Drive/3. PhD/08_software/IDMDB/DendroMatic_toolkit/R/pipeline_helpers.R"
)

test_that("package output matches toolkit apply_breaks_and_shift verbatim", {
  skip_if_not(file.exists(toolkit_helpers), "toolkit checkout not present")

  env <- new.env(parent = globalenv())
  suppressMessages(sys.source(toolkit_helpers, envir = env))

  L0   <- make_step_series()
  brks <- list(T1_step = list(step_brk_pair()))
  args <- list(df = L0, brks = brks, grow_start_dm = "01-05",
               grow_end_dm = "31-10", growth_method = "daily_lm",
               rerun_proc_L2 = FALSE)

  out_pkg     <- suppressMessages(do.call(dm_clean_series, args))
  out_toolkit <- suppressMessages(do.call(env$apply_breaks_and_shift, args))

  expect_equal(out_pkg, out_toolkit)
})
