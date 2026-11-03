## Generate the shipped synthetic example dataset `dendro_sample`.
## Fully synthetic (no site/collaborator data, no sharing constraints):
## two stem-dendrometer series, two growing seasons (2021-2022), hourly.
##   SYN_Fs001 -- clean series: growth + diel cycle + winter shrinkage.
##   SYN_Pa002 -- same shape plus a +35 um reinstallation step on 2022-06-15
##                and a 4-day data gap in August 2021.
## Values in micrometres, timestamps UTC. Regenerate with:
##   source("data-raw/dendro_sample.R")

set.seed(421)

mk_series <- function(name, amp_diel, grow1, grow2, shrink) {
  ts <- seq(as.POSIXct("2021-04-01 00:00:00", tz = "UTC"),
            as.POSIXct("2022-11-30 23:00:00", tz = "UTC"), by = "hour")
  doy   <- as.POSIXlt(ts, tz = "UTC")$yday + 1L
  yr    <- as.POSIXlt(ts, tz = "UTC")$year + 1900L
  hour  <- as.POSIXlt(ts, tz = "UTC")$hour

  ## seasonal growth: logistic ramp inside May-Oct, flat otherwise
  season <- function(doy) plogis((doy - 170) / 25)   # mid-season inflection
  grow <- ifelse(yr == 2021, grow1 * season(doy), grow1 + grow2 * season(doy))
  ## winter shrinkage between the seasons
  winter <- ifelse(yr == 2022 & doy < 100, -shrink * plogis((100 - doy) / 15), 0)
  winter[yr == 2021 & doy > 330] <- -shrink * 0.5
  ## diel cycle (shrink by day, recover by night) + noise
  diel  <- -amp_diel * sin(2 * pi * (hour - 6) / 24)
  value <- 12000 + grow + winter + diel + stats::rnorm(length(ts), sd = 1.5)

  data.frame(series = name, ts = ts, value = round(value, 2))
}

s1 <- mk_series("SYN_Fs001", amp_diel = 12, grow1 = 220, grow2 = 260, shrink = 35)
s2 <- mk_series("SYN_Pa002", amp_diel = 8,  grow1 = 150, grow2 = 180, shrink = 25)

## reinstallation step: +35 um from 2022-06-15 12:00 onward
step_from <- as.POSIXct("2022-06-15 12:00:00", tz = "UTC")
s2$value[s2$ts >= step_from] <- s2$value[s2$ts >= step_from] + 35

## data gap: 2021-08-10 .. 2021-08-14
gap <- s2$ts >= as.POSIXct("2021-08-10", tz = "UTC") &
       s2$ts <  as.POSIXct("2021-08-14", tz = "UTC")
s2$value[gap] <- NA_real_

dendro_sample <- rbind(s1, s2)
rownames(dendro_sample) <- NULL

usethis::use_data(dendro_sample, overwrite = TRUE, compress = "xz")
