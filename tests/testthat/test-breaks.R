## dm_clean_series / apply_breaks_and_shift -- break leveling on a synthetic
## step series. rerun_proc_L2 = FALSE throughout so 'treenetproc' is not needed.

run_clean <- function(df, brks) {
  suppressMessages(dm_clean_series(
    df            = df,
    brks          = brks,
    grow_start_dm = "01-05",
    grow_end_dm   = "31-10",
    growth_method = "daily_lm",
    rerun_proc_L2 = FALSE
  ))
}

test_that("a break window removes the post-break level step", {
  L0 <- make_step_series()
  out_no  <- run_clean(L0, brks = list())
  out_yes <- run_clean(L0, brks = list(T1_step = list(step_brk_pair())))

  post <- out_no$ts > as.POSIXct("2022-05-06 01:00:00", tz = "UTC")
  pre  <- out_no$ts < as.POSIXct("2022-05-05 23:00:00", tz = "UTC")

  ## pre-break region identical between the two runs
  expect_equal(out_yes$value[pre], out_no$value[pre], tolerance = 1e-8)

  ## post-break region shifted down by roughly the injected 30 um step
  d <- mean(out_no$value[post], na.rm = TRUE) -
       mean(out_yes$value[post], na.rm = TRUE)
  expect_gt(d, 5)
  expect_lt(d, 60)
})

test_that("flat unnamed brks pair list works for a single-series df", {
  L0 <- make_step_series()
  out_named <- run_clean(L0, brks = list(T1_step = list(step_brk_pair())))
  out_flat  <- run_clean(L0, brks = list(step_brk_pair()))
  expect_equal(out_flat$value, out_named$value)
})

test_that("flat brks pair list on a multi-series df errors", {
  L0 <- rbind(make_step_series("A1"), make_step_series("B2"))
  expect_error(run_clean(L0, brks = list(step_brk_pair())), "single-series")
})

test_that("missing required columns error", {
  expect_error(
    suppressMessages(dm_clean_series(data.frame(x = 1), brks = list())),
    "series, ts, value"
  )
})

test_that("per-series minimum is re-based to zero", {
  L0  <- make_step_series()
  out <- run_clean(L0, brks = list())
  expect_equal(min(out$value, na.rm = TRUE), 0)
})
