#### DendroMatic: pipeline_helpers.R ####
##
## CHANGELOG (most recent first):
##   v3 (2026-06-23): apply_breaks_and_shift() level-shift reference lookup replaced by a
##     bounded nearest-non-NA search (valid_pre / valid_post within growth_window_days of
##     each break endpoint). Levels breaks whose endpoints land on NA grid cells / gaps,
##     including dcr_app anchors mistakenly placed on NA points, instead of skipping them.
##     Fallback when no in-window reference exists: in-gap delete + skip + warning. The v2
##     is.finite(adj) guard is retained downstream as a final net.
##   v2: is.finite(adj) guard around the level shift; stopped post-break tail erasure but
##     left recovered data un-levelled at guarded breaks.
##
## Shared utility functions for the DendroMatic pipeline.
## Source this file at the top of any pipeline script:
##
##   source(file.path(project_root, "R", "pipeline_helpers.R"))
##
## Functions are organised into eight sections:
##   1. File I/O utilities
##   2. Series naming utilities
##   3. Timestamp and timezone utilities
##   4. Unit conversion utilities
##   5. treenetproc wrappers
##   6. datacleanr / visual cleaning utilities
##   7. LWP-to-SFW matching utilities (match_lwp_to_sfw)
##   8. Series merging utilities (merge_series)
##
## Internal helpers (not intended for direct use) are prefixed with a dot.
##
## Dependencies: dplyr, tidyr, lubridate, stringr, tibble, rlang, fs,
##               treenetproc, datacleanr (section 6 only)


## Null-coalescing operator: returns `a` if non-NULL, else `b`.
## Available to all scripts that source this file.
`%||%` <- function(a, b) if (!is.null(a)) a else b

#### 0. raw_to_L0: raw data to strict treenetproc L0 format ####################

## Converts any raw dendrometer data frame to the strict L0 format expected by
## treenetproc: columns series (character), ts (POSIXct), value (numeric, µm).
##
## Series identifier: {SITE}_{SpAb}{zero_padded_num}  e.g. HOL_Aa075
##
## Site code rule  : exactly 3 alphanumeric characters.
## Species code rule: [A-Z][a-z] — e.g. "Aa", "Fs", "Pa".
##   Rows with NA species survive and produce SITE_NA### series (all-uppercase
##   "NA" cannot be confused with a valid [A-Z][a-z] code); they must be
##   corrected before downstream use.
##   Rows with no extractable tree number are a fatal error.

## Internal: robust numeric coercion (handles comma decimals) ------------------
.to_num <- function(x) {
  if (is.numeric(x)) return(as.numeric(x))
  x <- stringr::str_replace_all(as.character(x), ",", ".")
  suppressWarnings(as.numeric(x))
}

## Internal: robust timestamp parsing -----------------------------------------
## Tries multiple lubridate formats in sequence; handles Excel numeric dates.
## excel_epoch: "windows" (origin 1899-12-30) or "mac" (origin 1904-01-01).
## Both epochs produce plausible years for real dendrometer data, so the choice
## must be made explicit rather than inferred from data.
## fmt: lubridate parse_date_time orders string (e.g. "dmy HM"). When not NULL
## and not "auto", this format is tried first before the auto-detect cascade.
## This is the correct fix for ambiguous 2-digit-year dates like "01/01/12"
## which ymd() reads as 2001-01-12 instead of the intended 2012-01-01 (dmy).
.parse_ts <- function(x, tz = "UTC", excel_epoch = c("windows", "mac"), fmt = NULL,
                      year_min = 1950L, year_max = 2100L) {
  excel_epoch <- match.arg(excel_epoch)
  if (inherits(x, "POSIXct")) return(lubridate::with_tz(x, tzone = tz))
  if (inherits(x, "Date"))    return(as.POSIXct(x, tz = tz))
  if (is.numeric(x)) {
    origin <- if (excel_epoch == "windows") "1899-12-30" else "1904-01-01"
    return(as.POSIXct(x * 86400, origin = origin, tz = tz))
  }
  x <- stringr::str_remove_all(as.character(x), "^\\(|\\)$")
  
  ## If user specified a format, try it first before the auto cascade
  if (!is.null(fmt) && nzchar(fmt) && fmt != "auto") {
    y <- suppressWarnings(
      lubridate::parse_date_time(x, orders = fmt, tz = tz, quiet = TRUE)
    )
    if (!all(is.na(y))) return(y)
    message(".parse_ts: user format \"", fmt, "\" produced all NA; falling back to auto-detect.")
  }
  
  ## Helper: accept a parse when >=90% of values are non-NA AND >=90% of parsed
  ## years fall within [year_min, year_max]. Using the bulk (not ALL) years avoids
  ## a handful of absurd rows (e.g. a "9999" or "1901" typo, or an impossible
  ## "31/02") rejecting an otherwise-correct parse and forcing the crash-prone base
  ## fallback; the stray rows are left NA / out-of-range for the QC panel to flag.
  .plausible <- function(y) {
    if (all(is.na(y))) return(FALSE)
    yrs <- lubridate::year(y[!is.na(y)])
    mean(!is.na(y)) >= 0.9 && mean(yrs >= year_min & yrs <= year_max) >= 0.9
  }
  
  ## Auto-detect via parse_date_time with a trained order list. The old hand-rolled
  ## ymd_hms/dmy_hms cascade greedily read the concatenated digits of
  ## "01/06/2021 00:00" (DMY, no seconds) as YYMMDDHHMMSS -> 2001-06-20 21:00, and
  ## the year-range guard rubber-stamped it. parse_date_time respects field
  ## boundaries and picks the single best-matching format across the vector.
  ## Sniff whether the FIRST numeric token is a 4-digit / >31 year (=> real YMD) or
  ## a day/month (=> DMY/MDY, 4-digit year last) to order the candidates; ISO still
  ## parses correctly under either order because dmy cannot match a 4-digit day.
  year_first <- {
    s   <- utils::head(x[!is.na(x) & nzchar(x)], 200L)
    tok <- stringr::str_match(s, "^\\s*(\\d+)\\D+(\\d+)\\D+(\\d+)")
    f   <- suppressWarnings(as.integer(tok[, 2L]))
    fnc <- nchar(tok[, 2L])
    ok  <- !is.na(f)
    if (!any(ok)) TRUE else mean((fnc[ok] >= 4L) | (f[ok] > 31L)) >= 0.5
  }
  orders <- if (year_first)
    c("Ymd HMS", "Ymd HM", "Ymd", "dmy HMS", "dmy HM", "dmy", "mdy HMS", "mdy HM", "mdy")
  else
    c("dmy HMS", "dmy HM", "dmy", "mdy HMS", "mdy HM", "mdy", "Ymd HMS", "Ymd HM", "Ymd")
  y <- suppressWarnings(lubridate::parse_date_time(x, orders = orders, tz = tz, quiet = TRUE))
  if (.plausible(y)) return(y)

  ## Last resort: base R. Wrapped so an unparseable string cannot abort the whole
  ## upload — on failure every row becomes NA and is dropped + reported downstream,
  ## rather than propagating a stop() that kills the ingest.
  suppressWarnings(tryCatch(
    as.POSIXct(x, tz = tz),
    error = function(e) as.POSIXct(rep(NA_real_, length(x)), tz = tz)))
}

#### 1. File I/O utilities #####################################################


.guess_delim_line <- function(l1) {
  # Infer the most likely column delimiter from one line of text.
  # Returns one of: "\t", ";", ","
  if (length(l1) == 0 || !nzchar(l1)) return(",")
  n_sc <- stringr::str_count(l1, ";")
  n_cm <- stringr::str_count(l1, ",")
  n_tb <- stringr::str_count(l1, "\t")
  if (n_tb >= n_sc && n_tb >= n_cm) return("\t")
  if (n_sc >= n_cm) return(";")
  ","
}

guess_delim_1line <- function(fp) {
  # Infer the most likely column delimiter from the first line of a text file.
  # Returns one of: "\t", ";", ","
  l1 <- readLines(fp, n = 1, warn = FALSE)
  if (length(l1) == 0) return(",")
  .guess_delim_line(l1)
}

.normalize_text_source <- function(fp) {
  # Pre-parse normalization for delimited text files (edit ledger
  # _EDIT_LEDGER_2026-09-24_reader-fixes.md, E2). Two defects readr cannot
  # handle from a file path:
  #   (a) UTF-16/32 BOM exports (Excel "Unicode text"): embedded NUL bytes
  #       hard-error vroom ("embedded nul in string").
  #   (b) lone-CR line endings: vroom treats a bare \r as field content, not a
  #       record separator, silently gluing consecutive rows (readLines-based
  #       inspection shows the rows, the parse loses them).
  # Sniffs cheaply (BOM = first 4 bytes; lone CR = first 1 MB — a file whose
  # FIRST lone CR sits beyond 1 MB is not caught, documented limit). Only when
  # a defect is present is the whole file read raw and converted; clean files
  # return the untouched path, so the fast path allocates nothing.
  # Returns list(src = path or I(utf8 text), first_line = chr).
  hdr <- tryCatch(readBin(fp, "raw", n = 1048576L), error = function(e) raw(0))
  if (length(hdr) == 0L)
    return(list(src = fp, first_line = ""))
  enc <- NA_character_
  if (length(hdr) >= 2L) {
    if (hdr[1] == as.raw(0xFF) && hdr[2] == as.raw(0xFE))
      enc <- if (length(hdr) >= 4L && hdr[3] == as.raw(0x00) &&
                 hdr[4] == as.raw(0x00)) "UTF-32LE" else "UTF-16LE"
    if (hdr[1] == as.raw(0xFE) && hdr[2] == as.raw(0xFF)) enc <- "UTF-16BE"
    if (length(hdr) >= 4L && hdr[1] == as.raw(0x00) && hdr[2] == as.raw(0x00) &&
        hdr[3] == as.raw(0xFE) && hdr[4] == as.raw(0xFF)) enc <- "UTF-32BE"
  }
  cr <- which(hdr == as.raw(0x0D))
  lone_cr <- length(cr) > 0L &&
    any(cr == length(hdr) | hdr[pmin(cr + 1L, length(hdr))] != as.raw(0x0A))
  if (is.na(enc) && !lone_cr)
    return(list(src = fp,
                first_line = tryCatch(readLines(fp, n = 1, warn = FALSE),
                                      error = function(e) "")))
  b <- tryCatch(readBin(fp, "raw", n = file.info(fp)$size),
                error = function(e) raw(0))
  txt <- if (!is.na(enc)) {
    out <- iconv(list(b), from = enc, to = "UTF-8")[[1]]
    if (is.na(out))
      stop("read_any_table: could not convert ", enc,
           " file to UTF-8 - re-export as UTF-8 or plain csv.")
    out
  } else {
    out <- tryCatch(rawToChar(b), error = function(e) NULL)
    # embedded NULs without a BOM: fall back to the untouched path (the parser
    # will raise its own error; do not mask it with a half-converted source)
    if (is.null(out)) return(list(src = fp, first_line = ""))
    out
  }
  txt <- gsub("\r\n", "\n", txt, fixed = TRUE)
  txt <- gsub("\r", "\n", txt, fixed = TRUE)
  list(src = I(txt), first_line = sub("\n.*$", "", txt))
}

pick_col_ci <- function(df, candidates) {
  # Return the first matching column name from `candidates` using
  # case-insensitive matching against names(df).
  # Returns NA_character_ if no match is found.
  cn     <- names(df)
  cn_low <- tolower(cn)
  hit    <- match(tolower(candidates), cn_low)
  hit    <- hit[!is.na(hit)][1]
  if (is.na(hit)) NA_character_ else cn[hit]
}

#### 3. Timestamp and timezone utilities #######################################


parse_ts_auto <- function(x, tz = "UTC") {
  # Robust timestamp parser. Tries multiple lubridate formats in sequence.
  # Handles POSIXt, Date, numeric (Excel Windows epoch), and character input.
  # Returns a POSIXct vector in the requested timezone.
  if (inherits(x, "POSIXt")) return(as.POSIXct(x, tz = tz))
  if (inherits(x, "Date"))   return(as.POSIXct(x, tz = tz))
  if (is.numeric(x))         return(as.POSIXct(as.Date(x, origin = "1899-12-30"), tz = tz))
  
  x <- as.character(x)
  ts <- suppressWarnings(lubridate::ymd_hms(x, tz = tz, quiet = TRUE))
  if (all(is.na(ts))) ts <- suppressWarnings(lubridate::dmy_hms(x, tz = tz, quiet = TRUE))
  if (all(is.na(ts))) ts <- suppressWarnings(lubridate::mdy_hms(x, tz = tz, quiet = TRUE))
  if (all(is.na(ts))) ts <- suppressWarnings(lubridate::ymd(x,   tz = tz, quiet = TRUE))
  if (all(is.na(ts))) ts <- suppressWarnings(lubridate::dmy(x,   tz = tz, quiet = TRUE))
  if (all(is.na(ts))) ts <- suppressWarnings(lubridate::mdy(x,   tz = tz, quiet = TRUE))
  
  as.POSIXct(ts, tz = tz)
}

#### 4. Unit conversion utilities ##############################################


infer_unit_and_convert_to_um <- function(v_num) {
  # Heuristically infer whether a numeric vector is in mm or µm,
  # then convert to µm.
  # Decision rule: median < 1000 -> assumed mm; else assumed µm.
  # Returns a named list: value_um, unit_inferred ("mm" or "um"), median_in.
  med          <- stats::median(v_num, na.rm = TRUE)
  unit_inferred <- if (is.finite(med) && med < 1000) "mm" else "um"
  v_um          <- if (unit_inferred == "mm") v_num * 1000 else v_num
  list(value_um = v_um, unit_inferred = unit_inferred, median_in = med)
}

#### 6. datacleanr / visual cleaning utilities #################################


year_windows <- function(min_year,
                         max_year,
                         span_years,
                         step_years = max(1L, span_years - 1L)) {
  # Build a list of integer year ranges (windows) covering [min_year, max_year].
  # Default step = span_years - 1 produces overlapping windows:
  #   span=1 -> 2014, 2015, ...
  #   span=2 -> 2014:2015, 2015:2016, ...
  #   span=4 -> 2014:2017, 2017:2020, ...
  stopifnot(is.finite(min_year), is.finite(max_year),
            span_years >= 1L, step_years >= 1L)
  starts <- seq.int(min_year, max_year, by = step_years)
  out <- lapply(starts, function(s) {
    e <- min(max_year, s + span_years - 1L)
    if (e < s) return(NULL)
    s:e
  })
  Filter(Negate(is.null), out)
}

## Internal: parse "DD-MM" string into list(day, mon) -------------------------
.dm_to_md <- function(dm) {
  p <- strsplit(as.character(dm), "-", fixed = TRUE)[[1]]
  list(day = as.integer(p[1]), mon = as.integer(p[2]))
}

## Internal: seconds of overlap between [a0,a1) and [b0,b1) -------------------
.overlap_seconds <- function(a0, a1, b0, b1) {
  s <- as.numeric(difftime(min(a1, b1), max(a0, b0), units = "secs"))
  max(0, s)
}

## Internal: growing-season seconds overlapping a gap interval -----------------
.gap_growing_seconds <- function(g0, g1, grow_start_dm, grow_end_dm, tz = "UTC") {
  # Compute the number of seconds in [g0, g1) that fall inside the recurring
  # growing window defined by grow_start_dm / grow_end_dm (both "DD-MM").
  stopifnot(inherits(g0, "POSIXt"), inherits(g1, "POSIXt"))
  
  gs   <- .dm_to_md(grow_start_dm)
  ge   <- .dm_to_md(grow_end_dm)
  wrap <- (gs$mon > ge$mon) || (gs$mon == ge$mon && gs$day > ge$day)
  
  yr_seq  <- seq(lubridate::year(g0) - 1L, lubridate::year(g1) + 1L)
  gap_int <- lubridate::interval(g0, g1)
  
  tot <- 0
  for (y in yr_seq) {
    start_y <- lubridate::make_datetime(y,   gs$mon, gs$day, 0, 0, 0, tz = tz)
    end_y   <- if (!wrap) {
      lubridate::make_datetime(y,     ge$mon, ge$day, 0, 0, 0, tz = tz) + lubridate::days(1)
    } else {
      lubridate::make_datetime(y + 1, ge$mon, ge$day, 0, 0, 0, tz = tz) + lubridate::days(1)
    }
    season_int <- lubridate::interval(start_y, end_y)
    ov <- lubridate::int_length(lubridate::intersect(gap_int, season_int))
    if (is.finite(ov) && ov > 0) tot <- tot + ov
  }
  as.numeric(tot)
}

#### 9. Phase stats utilities ###################################################
##
## Shared helpers for the 03_ pipeline step (L2 -> phase_stats -> SFW).
## All 03_ scripts source pipeline_helpers.R and call these functions directly.
##
## hours_to_hhmm(x)
##   Format fractional hours (numeric) as "HH:MM" character.
##
## compute_pdmd_extrema(L2_hourly, pd_start_hr, pd_end_hr, md_start_hr, md_end_hr)
##   Extract daily predawn-min and midday-max TWD from fixed UTC hour windows.
##   Returns tibble(series, date, pdtwd, mdtwd).
##
## compute_pdmd_extrema_tz(L2_hourly, pd_start_hr, pd_end_hr, md_start_hr, md_end_hr, tz)
##   Local-time-aware version: converts ts to tz before extracting hour.
##   Required for sites where the logger clock differs from UTC (e.g. TIL, LOT).
##
## default_species_lut()
##   Reference tibble of species abbreviation -> full Latin name for all
##   DenMet project species.
##
## build_sfw(L2_daily, phase_daily, site_tag, ...)
##   Standard HOL-style SFW object from daily L2 + phase_daily.
##   Returns the SFW tibble; the caller is responsible for saving.


## hours_to_hhmm ---------------------------------------------------------------
hours_to_hhmm <- function(x) {
  ## Format a numeric fractional-hours vector as "HH:MM" strings.
  ## NA input produces NA output; infinite/NaN input produces NA output.
  dplyr::if_else(
    is.na(x) | !is.finite(x),
    NA_character_,
    sprintf("%02d:%02d", as.integer(floor(x)), as.integer(round((x - floor(x)) * 60)))
  )
}

## interp_gaps_hourly ------------------------------------------------------------
## Bridge short NA runs in an hourly value vector by linear interpolation.
## Purpose: make treenetproc::phase_stats() runnable on sparse deliveries
## (GRE/DEMMIN: ~5 values/day) whose within-phase NA share trips the internal
## calcshrinkexpparam() na_prop < 0.5 filter / lm(value ~ ts) on all-NA windows.
## Linear interpolation creates NO new extrema, so every detected maximum and
## minimum remains a measured point and shrink/exp amplitudes stay
## measurement-anchored. Runs of length > max_gap steps (e.g. dormancy masking,
## multi-day outages) are NOT bridged and stay NA.
## Apply ONLY to the copy fed to phase_stats - never to the twd column used by
## compute_pdmd_extrema() or to any stored L2 product.
##
## Arguments:
##   v        numeric vector, one series, hourly-ordered.
##   max_gap  integer; longest NA run (in steps = hours) to bridge. 12 = half a
##            day: within-day sampling gaps bridge, full-day outages stay NA.
##
## Returns: v with eligible NA runs replaced by linear interpolation (rule = 1:
##          leading/trailing NAs are never filled).

interp_gaps_hourly <- function(v, max_gap = 12L) {
  if (all(is.na(v)) || !anyNA(v)) return(v)
  filled <- stats::approx(x = seq_along(v), y = v, xout = seq_along(v),
                          method = "linear", rule = 1)$y
  r      <- rle(is.na(v))
  ends   <- cumsum(r$lengths)
  starts <- ends - r$lengths + 1L
  for (i in seq_along(r$lengths)) {
    if (r$values[i] && r$lengths[i] <= max_gap) {
      idx    <- starts[i]:ends[i]
      v[idx] <- filled[idx]
    }
  }
  v
}

