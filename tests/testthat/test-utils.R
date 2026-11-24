test_that("hours_to_hhmm formats fractional hours", {
  expect_equal(dendromatic:::hours_to_hhmm(c(13.5, 0, NA)),
               c("13:30", "00:00", NA_character_))
})

test_that("interp_gaps_hourly bridges short gaps only", {
  v <- c(1, NA, 3, rep(NA, 15), 20)
  out <- dendromatic:::interp_gaps_hourly(v, max_gap = 12L)
  expect_equal(out[2], 2)
  expect_true(all(is.na(out[4:18])))
})

test_that("year_windows covers the range", {
  w <- dendromatic:::year_windows(2014, 2017, span_years = 2, step_years = 2)
  expect_equal(w, list(2014:2015, 2016:2017))
})

test_that("dm_repair_series standardises names and passes clean ones through", {
  ok <- dm_repair_series(c("TIL_Ps699", "TIL_Fs001"), site_tag = "TIL")
  expect_equal(ok$series_new, ok$series_old)
})

test_that("dm_species_lut has the expected shape", {
  lut <- dm_species_lut()
  expect_true(all(c("species_abv", "species") %in% names(lut)))
  expect_true(nrow(lut) >= 10)
})

test_that("dm_merge_series concatenates two series with overlap resolution", {
  t1 <- as.POSIXct("2022-05-01 00:00:00", tz = "UTC") + 3600 * 0:99
  t2 <- as.POSIXct("2022-05-04 00:00:00", tz = "UTC") + 3600 * 0:99
  df <- rbind(
    data.frame(series = "A1", ts = t1, value = 1),
    data.frame(series = "A2", ts = t2, value = 2)
  )
  out <- suppressMessages(
    capture.output(res <- dm_merge_series(df, c("A1", "A2"), "A_merged"))
  )
  expect_true(all(res$series == "A_merged"))
  ## overlap resolved by "first": overlapping hours keep value 1
  ovl <- res$ts >= min(t2) & res$ts <= max(t1)
  expect_true(all(res$value[ovl] == 1))
})

test_that("dm_pdmd_extrema extracts window extrema in local time", {
  ts <- as.POSIXct("2022-06-01 00:00:00", tz = "UTC") + 3600 * 0:47
  twd <- rep(c(5:16, 16:5), 2)   # diel-ish cycle
  df <- data.frame(series = "S1", ts = ts, twd = twd)
  out <- suppressMessages(
    dm_pdmd_extrema(df, pd_start_hr = 3, pd_end_hr = 6,
                    md_start_hr = 12, md_end_hr = 15, tz = "UTC"))
  expect_true(all(c("pdtwd", "mdtwd") %in% names(out)))
  expect_true(all(out$mdtwd >= out$pdtwd, na.rm = TRUE))
})
