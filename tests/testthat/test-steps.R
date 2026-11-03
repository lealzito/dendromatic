## The composable step functions introduced in 0.2.0.

test_that("dm_level_breaks removes the step without touching pre-break data", {
  L0  <- make_step_series()
  out <- suppressMessages(suppressWarnings(
    dm_level_breaks(L0, brks = list(T1_step = list(step_brk_pair())))
  ))
  pre  <- out$ts < as.POSIXct("2022-05-05 23:00:00", tz = "UTC")
  post <- out$ts > as.POSIXct("2022-05-06 01:00:00", tz = "UTC")

  ## pre-break untouched (no zero rebase in this step)
  expect_equal(out$value[pre], L0$value[order(L0$ts)][pre])

  ## step mostly removed: post-break values pulled down toward pre-break level
  d <- mean(L0$value[order(L0$ts)][post], na.rm = TRUE) -
       mean(out$value[post], na.rm = TRUE)
  expect_gt(d, 5)
  expect_lt(d, 60)

  ## in-break span deleted
  gap <- out$ts >= as.POSIXct("2022-05-05 23:00:00", tz = "UTC") &
         out$ts <= as.POSIXct("2022-05-06 01:00:00", tz = "UTC")
  expect_true(all(is.na(out$value[gap])))
})

test_that("dm_rebase_zero floors every series at zero", {
  df <- data.frame(series = rep(c("A", "B"), each = 3),
                   value  = c(5, 7, 9, -2, 0, 4))
  out <- dm_rebase_zero(df)
  expect_equal(min(out$value[out$series == "A"]), 0)
  expect_equal(min(out$value[out$series == "B"]), 0)
  expect_equal(out$value[out$series == "A"], c(0, 2, 4))
})

## Two-year series: season 1 (May-Oct 2021) grows to ~100, dormancy dip,
## season 2 (May-Oct 2022) restarts at ~40.
make_two_season_series <- function() {
  ts1 <- seq(as.POSIXct("2021-05-01", tz = "UTC"),
             as.POSIXct("2021-10-31", tz = "UTC"), by = "6 hours")
  ts2 <- seq(as.POSIXct("2021-11-01", tz = "UTC"),
             as.POSIXct("2022-04-30", tz = "UTC"), by = "6 hours")
  ts3 <- seq(as.POSIXct("2022-05-01", tz = "UTC"),
             as.POSIXct("2022-10-31", tz = "UTC"), by = "6 hours")
  data.frame(
    series = "S1",
    ts     = c(ts1, ts2, ts3),
    value  = c(seq(0, 100, length.out = length(ts1)),       # season 1 growth
               seq(100, 40, length.out = length(ts2)),      # winter shrinkage
               seq(40, 150, length.out = length(ts3)))      # season 2 growth
  )
}

test_that("dm_erase_dormancy erases the inter-seasonal gap only", {
  df  <- make_two_season_series()
  out <- suppressMessages(dm_erase_dormancy(df))
  dormant <- out$ts > as.POSIXct("2021-10-31 23:59:59", tz = "UTC") &
             out$ts < as.POSIXct("2022-05-01 00:00:00", tz = "UTC")
  expect_true(all(is.na(out$value[dormant])))
  expect_true(all(!is.na(out$value[!dormant])))
})

test_that("dm_align_seasons lifts season 2 to the season 1 maximum", {
  df  <- make_two_season_series()
  ## erase dormancy first so the winter values do not act as season-2 anchor
  out <- suppressMessages(dm_align_seasons(suppressMessages(dm_erase_dormancy(df))))
  s1_max   <- max(out$value[out$ts <= as.POSIXct("2021-10-31 23:59:59", tz = "UTC")],
                  na.rm = TRUE)
  s2_first <- out$value[!is.na(out$value) &
                        out$ts >= as.POSIXct("2022-05-01", tz = "UTC")][1]
  expect_equal(s2_first, s1_max)
})

test_that("a series with no growing-season data is fully erased", {
  ts <- seq(as.POSIXct("2021-11-15", tz = "UTC"),
            as.POSIXct("2022-02-15", tz = "UTC"), by = "day")
  df  <- data.frame(series = "W1", ts = ts, value = seq_along(ts))
  out <- suppressMessages(dm_erase_dormancy(df))
  expect_true(all(is.na(out$value)))
})

test_that("progressr signals are emitted by the engines", {
  L0 <- make_step_series()
  expect_no_error(
    progressr::with_progress(
      suppressMessages(dm_clean_series(L0, brks = list(T1_step = list(step_brk_pair())),
                                       rerun_proc_L2 = FALSE)),
      handlers = progressr::handler_void()
    )
  )
})
