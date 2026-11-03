## compute_pdmd_extrema --------------------------------------------------------
##
## Arguments:
##   L2_hourly    data.frame/tibble with columns: series, ts (POSIXct), twd
##   pd_start_hr  integer; first UTC hour of predawn window (inclusive)
##   pd_end_hr    integer; last  UTC hour of predawn window (inclusive)
##   md_start_hr  integer; first UTC hour of midday  window (inclusive)
##   md_end_hr    integer; last  UTC hour of midday  window (inclusive)
##
## Returns: tibble(series, date, pdtwd, mdtwd)
##   pdtwd = minimum TWD in the predawn window
##   mdtwd = maximum TWD in the midday window

compute_pdmd_extrema <- function(L2_hourly,
                                 pd_start_hr,
                                 pd_end_hr,
                                 md_start_hr,
                                 md_end_hr) {
  stopifnot(all(c("series", "ts", "twd") %in% names(L2_hourly)))
  
  L2_hourly %>%
    dplyr::mutate(
      date = as.Date(.data$ts),
      hr   = lubridate::hour(.data$ts)
    ) %>%
    dplyr::group_by(.data$series, .data$date) %>%
    dplyr::summarise(
      pdtwd = {
        w <- .data$twd[.data$hr >= pd_start_hr & .data$hr <= pd_end_hr]
        if (length(w) == 0L || all(is.na(w))) NA_real_ else min(w, na.rm = TRUE)
      },
      mdtwd = {
        w <- .data$twd[.data$hr >= md_start_hr & .data$hr <= md_end_hr]
        if (length(w) == 0L || all(is.na(w))) NA_real_ else max(w, na.rm = TRUE)
      },
      .groups = "drop"
    )
}

## compute_pdmd_extrema_tz -----------------------------------------------------
##
## Local-time-aware version of compute_pdmd_extrema.
##
## Arguments:
##   same as compute_pdmd_extrema, plus:
##   tz   IANA timezone string for local-time hour extraction
##        e.g. "Etc/GMT+1" (TIL), "Europe/Zurich" (LOT)
##
## The returned date column is the LOCAL date (as.Date using tz).

#' @rdname dm_pdmd_extrema
#' @export
compute_pdmd_extrema_tz <- function(L2_hourly,
                                    pd_start_hr,
                                    pd_end_hr,
                                    md_start_hr,
                                    md_end_hr,
                                    tz) {
  stopifnot(all(c("series", "ts", "twd") %in% names(L2_hourly)))
  stopifnot(is.character(tz) && length(tz) == 1L && nzchar(tz))
  
  L2_hourly %>%
    dplyr::mutate(
      ts_local   = lubridate::with_tz(.data$ts, tz),
      date_local = as.Date(.data$ts_local),
      hr_local   = lubridate::hour(.data$ts_local)
    ) %>%
    dplyr::group_by(.data$series, date = .data$date_local) %>%
    dplyr::summarise(
      pdtwd = {
        w <- .data$twd[.data$hr_local >= pd_start_hr & .data$hr_local <= pd_end_hr]
        if (length(w) == 0L || all(is.na(w))) NA_real_ else min(w, na.rm = TRUE)
      },
      mdtwd = {
        w <- .data$twd[.data$hr_local >= md_start_hr & .data$hr_local <= md_end_hr]
        if (length(w) == 0L || all(is.na(w))) NA_real_ else max(w, na.rm = TRUE)
      },
      .groups = "drop"
    )
}


#' Daily predawn and midday tree water deficit extrema (local time)
#'
#' Extracts, per series and local-time day, the predawn minimum and midday
#' maximum of the tree water deficit from hourly L2 data, using fixed
#' local-time hour windows. `compute_pdmd_extrema_tz()` is the original
#' DendroMatic name, kept as an exported alias.
#'
#' @param L2_hourly Hourly L2 data.frame with columns `series`, `ts`, `twd`.
#' @param pd_start_hr,pd_end_hr Predawn window (local hours, inclusive).
#' @param md_start_hr,md_end_hr Midday window (local hours, inclusive).
#' @param tz Local timezone used to derive day and hour.
#' @return A data.frame with one row per `series` and local `date`, holding
#'   `pdtwd` (window minimum) and `mdtwd` (window maximum).
#' @export
dm_pdmd_extrema <- compute_pdmd_extrema_tz
