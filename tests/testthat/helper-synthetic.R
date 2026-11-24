## Synthetic 10-day hourly series with a ~30 um reinstallation step at row 121
## (ported from DendroMatic_toolkit tests/e2e/test_clean.R).
make_step_series <- function(ser_name = "T1_step") {
  start <- as.POSIXct("2022-05-01 00:00:00", tz = "UTC")
  n     <- 10L * 24L
  ts    <- start + 3600 * (seq_len(n) - 1L)
  hour  <- as.integer(format(ts, "%H", tz = "UTC"))
  diel  <- -10 * sin(2 * pi * (hour - 6) / 24)
  trend <- 2 * (as.numeric(ts - start) / 86400)
  val   <- 10000 + trend + diel
  val[121:n] <- val[121:n] + 30
  data.frame(series = ser_name, ts = ts, value = round(val, 2),
             stringsAsFactors = FALSE)
}

step_brk_pair <- function() {
  c("2022-05-05 23:00:00", "2022-05-06 01:00:00")
}
