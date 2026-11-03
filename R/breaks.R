## Internal: filter a data.frame to a year range for dcr_app ------------------
.make_dcr_view <- function(df, year_range = NULL, tz = "UTC") {
  if (!inherits(df$ts, "POSIXct")) df$ts <- as.POSIXct(df$ts, tz = tz)
  if (is.null(year_range)) return(df)
  
  y_min    <- min(year_range)
  y_max    <- max(year_range)
  start_ts <- as.POSIXct(sprintf("%d-01-01 00:00:00", y_min),     tz = tz)
  end_ts   <- as.POSIXct(sprintf("%d-01-01 00:00:00", y_max + 1L), tz = tz)
  
  df[df$ts >= start_ts & df$ts < end_ts, , drop = FALSE]
}

## Internal: growth slope estimators (µm/day) ----------------------------------
.estimate_slope <- function(pre_win,
                            method = c("daily_lm", "10min_lm",
                                       "daily_robust", "10min_lm_flip"),
                            allow_negative_growth = FALSE) {
  # Estimate radial growth rate (µm/day) from a window of pre-break data.
  # Returns list(slope_day, used_fallback).
  method <- match.arg(method)
  if (nrow(pre_win) < 3) return(list(slope_day = 0, used_fallback = TRUE))
  
  if (method %in% c("10min_lm", "10min_lm_flip")) {
    x   <- as.numeric(pre_win$ts) / 86400
    fit <- try(stats::lm(pre_win$value ~ x), silent = TRUE)
    if (inherits(fit, "try-error")) return(list(slope_day = 0, used_fallback = TRUE))
    s <- as.numeric(stats::coef(fit)[2])
    if (method == "10min_lm_flip") s <- -s
    if (!allow_negative_growth) s <- max(0, s)
    return(list(slope_day = s, used_fallback = FALSE))
  }
  
  daydat <- pre_win %>%
    dplyr::mutate(day = as.Date(ts, tz = attr(pre_win$ts, "tzone"))) %>%
    dplyr::group_by(day) %>%
    dplyr::summarise(value = stats::median(value, na.rm = TRUE), .groups = "drop") %>%
    dplyr::arrange(day)
  
  if (nrow(daydat) < 3) return(list(slope_day = 0, used_fallback = TRUE))
  
  if (method == "daily_lm") {
    xd  <- as.numeric(daydat$day)
    fit <- try(stats::lm(daydat$value ~ xd), silent = TRUE)
    if (inherits(fit, "try-error")) return(list(slope_day = 0, used_fallback = TRUE))
    s <- as.numeric(stats::coef(fit)[2])
    if (!allow_negative_growth) s <- max(0, s)
    return(list(slope_day = s, used_fallback = FALSE))
  }
  
  if (method == "daily_robust") {
    xd <- as.numeric(daydat$day)
    dv <- diff(daydat$value)
    dx <- diff(xd)
    s  <- stats::median(dv / dx, na.rm = TRUE)
    if (!is.finite(s)) return(list(slope_day = 0, used_fallback = TRUE))
    if (!allow_negative_growth) s <- max(0, s)
    return(list(slope_day = s, used_fallback = FALSE))
  }
  
  list(slope_day = 0, used_fallback = TRUE)
}

#' @rdname dm_clean_series
#' @export
apply_breaks_and_shift <- function(
    df,
    brks,                              # list of c(start_ts, end_ts)
    grow_start_dm        = "01-05",    # DD-MM start of growing season
    grow_end_dm          = "31-10",    # DD-MM end of growing season
    growth_window_days   = 14,
    growth_method        = c("daily_lm", "10min_lm", "daily_robust", "10min_lm_flip"),
    allow_negative_growth = FALSE,
    max_slope_day        = Inf,        # µm/day cap for slope estimate
    max_growth_total     = Inf,        # µm cap for g_est per gap
    tz                   = "UTC",
    rerun_proc_L2        = TRUE,
    year_range           = NULL,
    do_dormancy_gap      = TRUE,       # erase inter-seasonal dormancy periods and
    # pre-first-season data for every series
    align_to_prev_peak   = TRUE,       # align each season's start to prior year's max
    initial_clip_ts      = NULL,       # drop rows before this timestamp (character or POSIXct)
    final_clip_ts        = NULL,       # drop rows after this timestamp  (character or POSIXct)
    first_year_override  = NULL,       # integer: force a specific first growing-season year;
    # NULL = auto-detect (first year with >= 1 non-NA obs WITHIN [grow_start_dm, grow_end_dm])
    last_year_override   = NULL        # integer: force a specific last growing-season year;
    # NULL = auto-detect (last year with >= 1 non-NA obs WITHIN [grow_start_dm, grow_end_dm])
) {
  growth_method <- match.arg(growth_method)
  if (isTRUE(rerun_proc_L2)) .need_treenetproc("dm_clean_series(rerun_proc_L2 = TRUE)")
  if (!all(c("series", "ts", "value") %in% names(df)))
    stop("apply_breaks_and_shift: df must contain: series, ts, value.")
  
  if (!inherits(df$ts, "POSIXct")) df$ts <- as.POSIXct(df$ts, tz = tz)
  attr(df$ts, "tzone") <- tz
  df   <- df %>% dplyr::arrange(series, ts)
  df   <- df %>% dplyr::mutate(.row_id = dplyr::row_number())
  ## Back-compat (pre-2026-08-17 interface): legacy site scripts (KROOF/HOF/HOL/
  ## basic 02_ pipelines) pass a FLAT unnamed list of c(start, end) pairs for a
  ## single-series df. The named per-series lookup below would then silently
  ## apply ZERO breaks to every series (the 2026-08-20 KROOF uncleaned-L2 bug).
  ## Detect the flat shape and wrap it as the expected series -> pairs list.
  is_flat_pairs <- length(brks) > 0L && is.null(names(brks)) &&
    all(vapply(brks, function(b) is.atomic(b) && length(b) == 2L, logical(1L)))
  if (is_flat_pairs) {
    ser_all <- unique(as.character(df$series))
    if (length(ser_all) != 1L)
      stop("apply_breaks_and_shift: a flat brks pair list is only valid for a ",
           "single-series df (got ", length(ser_all), " series). ",
           "Pass a named list (series -> list of c(start, end) pairs) instead.")
    brks <- stats::setNames(list(brks), ser_all)
  }
  ## brks is a named list (series → list of c(start_ts, end_ts) pairs).
  ## Convert each pair's timestamps to POSIXct; do NOT collapse the outer structure.
  brks <- lapply(brks, function(b_list) {
    lapply(b_list, function(b) as.POSIXct(b, tz = tz))
  })
  
  # 0) Optional timestamp clips (applied before any break or dormancy logic)
  if (!is.null(initial_clip_ts)) {
    clip_s <- if (inherits(initial_clip_ts, "POSIXct")) initial_clip_ts
    else as.POSIXct(as.character(initial_clip_ts), tz = tz)
    df <- df %>% dplyr::filter(ts >= clip_s)
    message("apply_breaks_and_shift: initial_clip_ts applied; ",
            nrow(df), " rows remaining.")
  }
  if (!is.null(final_clip_ts)) {
    clip_e <- if (inherits(final_clip_ts, "POSIXct")) final_clip_ts
    else as.POSIXct(as.character(final_clip_ts), tz = tz)
    df <- df %>% dplyr::filter(ts <= clip_e)
    message("apply_breaks_and_shift: final_clip_ts applied; ",
            nrow(df), " rows remaining.")
  }
  out <- df  # re-assign so step 1 picks up clipped df
  
  # 1) User-defined breaks with growth-aware base leveling.
  # All breaks are processed inside a single group_modify call, replacing the
  # previous one group_modify per break loop. This avoids O(N_breaks * N_series)
  # dplyr group-split/bind overhead; corrections still accumulate in order.
  n_total_brks <- sum(vapply(brks, length, integer(1L)))
  if (n_total_brks > 0L) {

    # Progress bar: one tick per series in group_modify
    n_ser_brk   <- dplyr::n_distinct(out$series)
    message("apply_breaks_and_shift [1/3 breaks]: ", n_total_brks,
            " break(s) across ", n_ser_brk, " series...")
    pb_brk      <- utils::txtProgressBar(min = 0, max = n_ser_brk, style = 3, width = 50)
    pb_env_brk  <- new.env(parent = emptyenv())
    pb_env_brk$i <- 0L
    
    adjust_all_breaks <- function(g, key, brks_list) {
      # Increment progress counter (shared mutable environment, one tick per series)
      pb_env_brk$i <- pb_env_brk$i + 1L
      utils::setTxtProgressBar(pb_brk, pb_env_brk$i)
      # Apply every break correction sequentially to a single-series data frame.
      # Breaks must be applied in chronological order so each shift accumulates.
      if (nrow(g) == 0L) return(g)
      ser_name <- as.character(key$series[1L])
      my_brks  <- brks_list[[ser_name]] %||% list()
      for (b in my_brks) {
        b_start <- b[[1]]
        b_end   <- b[[2]]
        if (is.na(b_start) || is.na(b_end) || b_end <= b_start) next
        
        # --- v3 bounded nearest-non-NA reference search (replaces the v1_idx/v2_idx boundary lookup) ---
        # A break endpoint frequently lands on (or inside) a gap, so the grid cell AT the boundary is
        # NA. Reading v1/v2 from that cell made adj = NA and nulled the entire post-break tail (the L2
        # truncation bug). Re-doing breaks in dcr_app can likewise place an endpoint directly on an NA
        # cell. Instead of the boundary cell, take the nearest non-NA value on each side, bounded to
        # within growth_window_days of the endpoint (same window as the slope estimate, so the level
        # reference and the growth extrapolation stay coherent; an unbounded search could grab a far
        # reference across an uncovered pre-b_start sensor gap and apply a wrong offset).
        # No in-window reference on either side -> delete the in-gap span, skip the shift, warn (series
        # + break) for the residual review queue. The v2 is.finite(adj) check downstream is the net.
        win        <- lubridate::days(as.numeric(growth_window_days))
        valid_pre  <- which(g$ts <  b_start & g$ts >= (b_start - win) & !is.na(g$value))
        valid_post <- which(g$ts >  b_end   & g$ts <= (b_end   + win) & !is.na(g$value))
        if (length(valid_pre) == 0L || length(valid_post) == 0L) {
          g$value[g$ts >= b_start & g$ts <= b_end] <- NA_real_
          warning(sprintf(
            "apply_breaks_and_shift [%s]: break [%s, %s] has no in-window reference (endpoint on a gap); in-gap deleted, level shift skipped.",
            as.character(key$series[1L]),
            format(b_start, "%Y-%m-%d %H:%M"), format(b_end, "%Y-%m-%d %H:%M")))
          next
        }
        v1 <- g$value[max(valid_pre)]   # nearest non-NA value before b_start (within window)
        v2 <- g$value[min(valid_post)]  # nearest non-NA value after  b_end   (within window)
        
        in_gap <- g$ts >= b_start & g$ts <= b_end
        g$value[in_gap] <- NA_real_
        
        adj <- v1 - v2
        
        win_start <- b_start - lubridate::days(as.numeric(growth_window_days))
        pre_win   <- g[g$ts >= win_start & g$ts < b_start & !is.na(g$value), ]
        est       <- .estimate_slope(pre_win,
                                     method = growth_method,
                                     allow_negative_growth = allow_negative_growth)
        slope_day <- min(est$slope_day, max_slope_day)
        grow_secs <- .gap_growing_seconds(b_start, b_end, grow_start_dm, grow_end_dm, tz = tz)
        g_est_raw <- slope_day * (grow_secs / 86400)
        g_est     <- min(g_est_raw, max_growth_total)
        adj       <- adj + g_est
        
        ## Guard against NA-propagation erasure (was: unconditional g$value[after] <- + adj).
        ## v1 or v2 is NA when a break endpoint lands on an NA grid cell (breaks usually sit
        ## at gap edges), so adj becomes NA and adding it nulls EVERY value after b_end --
        ## the root cause of the L2 tail truncation seen across many series. When adj is
        ## non-finite the in-gap span is still deleted above, but the level shift is skipped
        ## so post-break data is preserved (un-levelled) and a warning names the series and
        ## break so its endpoints can be moved onto valid (non-NA) data if re-levelling is needed.
        if (is.finite(adj)) {
          after <- g$ts > b_end & !is.na(g$value)
          g$value[after] <- g$value[after] + adj
        } else {
          warning(sprintf(
            "apply_breaks_and_shift [%s]: break [%s, %s] has an NA reference value (endpoint on a gap); level shift skipped, post-break data preserved un-levelled.",
            as.character(key$series[1L]),
            format(b_start, "%Y-%m-%d %H:%M"), format(b_end, "%Y-%m-%d %H:%M")))
        }
      }
      g
    }
    
    out <- out %>%
      dplyr::group_by(series) %>%
      dplyr::group_modify(~ adjust_all_breaks(.x, .y, brks_list = brks)) %>%
      dplyr::ungroup()
    
    close(pb_brk)
    message("")  # newline after txtProgressBar
  }
  
  # 3) Optional dormancy erase + peak align with carry-forward
  #
  # do_dormancy_gap = TRUE: set all data outside [grow_start_dm, grow_end_dm] to NA
  # for every year in the series, including:
  #   (a) Data before grow_start_dm of the first year (pre-season erasure).
  #   (b) Inter-annual dormancy periods (grow_end(y-1) to grow_start(y)).
  #   (c) Data after grow_end_dm of the last year with valid growing-season data.
  #
  # align_to_prev_peak = TRUE: for years > first_year only, shift each season's
  # start value up to match the previous year's maximum (preserves cumulative
  # growth across winter). No alignment is applied for the first year (no prior
  # peak exists). No value anchoring to zero is performed here; step 3.5 ensures
  # min(value) = 0 per series after all erasure and alignment are complete.
  #
  # The two flags are independent: do_dormancy_gap controls erasure only;
  # align_to_prev_peak controls inter-annual peak carry-forward only.
  if (isTRUE(do_dormancy_gap) || isTRUE(align_to_prev_peak)) {
    
    # Progress bar: one tick per series in group_modify
    n_ser_dorm   <- dplyr::n_distinct(out$series)
    message("apply_breaks_and_shift [2/3 dormancy/alignment]: ",
            n_ser_dorm, " series...")
    pb_dorm      <- utils::txtProgressBar(min = 0, max = n_ser_dorm, style = 3, width = 50)
    pb_env_dorm  <- new.env(parent = emptyenv())
    pb_env_dorm$i <- 0L
    
    out <- out %>%
      dplyr::mutate(yr = as.integer(format(ts, "%Y"))) %>%
      dplyr::group_by(series) %>%
      dplyr::group_modify(function(g, key) {
        # Increment progress counter
        pb_env_dorm$i <- pb_env_dorm$i + 1L
        utils::setTxtProgressBar(pb_dorm, pb_env_dorm$i)
        if (nrow(g) == 0L) return(g)
        years <- sort(unique(as.integer(format(g$ts, "%Y"))))
        
        mk_ts <- function(y, dm, end_of_day = FALSE) {
          d      <- as.integer(substr(dm, 1, 2))
          m      <- as.integer(substr(dm, 4, 5))
          hhmmss <- if (end_of_day) "23:59:59" else "00:00:00"
          as.POSIXct(sprintf("%04d-%02d-%02d %s", y, m, d, hhmmss), tz = tz)
        }
        
        ## Auto-detect the first growing-season year:
        ## first_gs_year is the earliest year that has at least one non-NA value
        ## WITHIN [grow_start_dm, grow_end_dm] of that year. This correctly handles
        ## series that start in the dormant period (e.g., November 2022): calendar
        ## year 2022 contains no data inside May-Oct 2022, so it is skipped and 2023
        ## becomes the true first growing-season year. Data from Nov 2022 through
        ## Apr 2023 is then erased by the year-1 treatment (g$ts < grow_start(2023)).
        ## Contrast with the previous logic (ts >= grow_start_dm only): November 2022
        ## satisfies ts >= May 2022, so 2022 was incorrectly elected as first_gs_year,
        ## leaving Nov 2022-Apr 2023 data intact.
        ## first_year_override (from the calling script) allows a manual override.
        first_gs_year <- NA_integer_
        for (y_fgs in years) {
          gs_start_y <- mk_ts(y_fgs, grow_start_dm)
          gs_end_y   <- mk_ts(y_fgs, grow_end_dm, end_of_day = TRUE)
          if (any(g$ts >= gs_start_y & g$ts <= gs_end_y & !is.na(g$value))) {
            first_gs_year <- y_fgs
            break
          }
        }
        if (!is.null(first_year_override) && is.finite(as.integer(first_year_override))) {
          yr_ov    <- as.integer(first_year_override)
          ov_start <- mk_ts(yr_ov, grow_start_dm)
          ov_end   <- mk_ts(yr_ov, grow_end_dm, end_of_day = TRUE)
          if (any(g$ts >= ov_start & g$ts <= ov_end & !is.na(g$value))) {
            ## Override year has growing-season data; honour it.
            first_gs_year <- yr_ov
          } else {
            ## Override year has no growing-season data (e.g., only a few hours
            ## on Dec 31 of the year before the true first season). Fall back to
            ## the auto-detected year; emit a message for traceability.
            message("apply_breaks_and_shift [", key$series[1L], "]: first_year_override=",
                    yr_ov, " has no growing-season data; using auto-detected year ",
                    if (is.na(first_gs_year)) "NA (series will be fully erased)"
                    else first_gs_year, " instead.")
          }
        }
        if (is.na(first_gs_year)) {
          ## Series has no growing-season data at all; erase everything and move on.
          g$value <- NA_real_
          return(g)
        }
        
        for (y in years) {
          start_prev <- mk_ts(y - 1L, grow_start_dm)
          end_prev   <- mk_ts(y - 1L, grow_end_dm,  end_of_day = TRUE)
          start_cur  <- mk_ts(y,      grow_start_dm)
          
          i_start <- suppressWarnings(min(which(g$ts >= start_cur & !is.na(g$value))))
          if (!is.finite(i_start)) next
          
          ## Year-1 treatment: erase ALL data before grow_start_dm of first_gs_year.
          ## Uses timestamp comparison (not row index) so data from any earlier calendar
          ## year (e.g., December of the year before first_gs_year) is also erased.
          if (y == first_gs_year && isTRUE(do_dormancy_gap)) {
            g$value[g$ts < start_cur] <- NA_real_
            next
          }
          
          ## Regular inter-annual dormancy gap and peak alignment (y > first_year)
          if (isTRUE(do_dormancy_gap)) {
            i_end_prev <- suppressWarnings(max(which(g$ts <= end_prev & !is.na(g$value))))
            if (is.finite(i_end_prev) && i_end_prev < i_start) {
              mid <- (seq_len(nrow(g)) > i_end_prev) & (seq_len(nrow(g)) < i_start)
              g$value[mid] <- NA_real_
            }
          }
          
          if (isTRUE(align_to_prev_peak)) {
            prev_win <- g$ts >= start_prev & g$ts <= end_prev & !is.na(g$value)
            if (any(prev_win)) {
              prev_max  <- max(g$value[prev_win], na.rm = TRUE)
              cur_first <- g$value[i_start]
              if (is.finite(prev_max) && is.finite(cur_first) && cur_first < prev_max) {
                delta <- prev_max - cur_first
                use   <- which(g$ts >= start_cur & !is.na(g$value))
                if (length(use) > 0L) g$value[use] <- g$value[use] + delta
              }
            }
          }
        }
        
        ## Final-clip: erase all data after grow_end_dm of the last year
        ## that has any non-NA values WITHIN [grow_start_dm, grow_end_dm].
        ## Activated when do_dormancy_gap = TRUE (align_to_prev_peak not required).
        ##
        ## "Last valid year" (y_last_valid): the latest year y for which at least one
        ## non-NA observation falls strictly inside the growing window
        ## [grow_start_dm(y), grow_end_dm(y)]. The search iterates years in reverse
        ## so it short-circuits at the first hit. last_year_override allows a manual
        ## override (e.g. if sensor data in late October is unreliable).
        ##
        ## Using WITHIN (not >= grow_start_dm alone) is the symmetric fix to the
        ## first_gs_year correction: a series that ends in January 2024 with no
        ## growing-season data in 2024 correctly returns y_last_valid = 2023.
        ##
        ## This correctly handles three common situations:
        ##   (1) Series ends mid-growing-season: final_clip = grow_end_dm(y_last)
        ##       is beyond the last data point -- a no-op, nothing is erased.
        ##   (2) Series extends into winter after the last growing season:
        ##       post-season rows are erased up to the series end.
        ##   (3) Series ends in the dormancy period of year y+1 with no growing-season
        ##       data that year (e.g. data only in Jan-Feb of y+1): y+1 is not valid,
        ##       y_last = y, and those Jan-Feb rows are erased.
        if (isTRUE(do_dormancy_gap)) {
          y_last_valid <- NA_integer_
          if (!is.null(last_year_override) && is.finite(as.integer(last_year_override))) {
            y_last_valid <- as.integer(last_year_override)
          } else {
            for (yc in rev(years)) {
              gs_start_yc <- mk_ts(yc, grow_start_dm)
              gs_end_yc   <- mk_ts(yc, grow_end_dm, end_of_day = TRUE)
              if (any(g$ts >= gs_start_yc & g$ts <= gs_end_yc & !is.na(g$value))) {
                y_last_valid <- yc
                break
              }
            }
          }
          if (!is.na(y_last_valid)) {
            end_last <- mk_ts(y_last_valid, grow_end_dm, end_of_day = TRUE)
            g$value[g$ts > end_last] <- NA_real_
          }
        }
        
        g
      }) %>%
      dplyr::ungroup() %>%
      dplyr::select(-yr)
    
    close(pb_dorm)
    message("")  # newline after txtProgressBar
  }
  
  
  # 3.5) Per-series min -> 0, applied after all break corrections, dormancy
  # gap erasure, and peak alignment (steps 1 and 3).
  #
  # This replaces the former global-minimum subtraction (step 2, removed).
  # Step 2 ran BEFORE the dormancy gap / year-1 anchor (step 3). Because the
  # year-1 anchor subtracts the season-start value from the entire growing
  # season, within-season dips below the season-start baseline (e.g. drought
  # TWD events) produced negative values that corrupted proc_dendro_L2 TWD.
  #
  # Positioning AFTER step 3 corrects any residual negatives before they reach
  # proc_dendro_L2. TWD is a running-maximum deficit and depends only on
  # relative differences, so a constant per-series offset does not distort it.
  # Per-series grouping (not global) ensures each series is independently
  # floored at zero regardless of cross-series amplitude differences.
  out <- out %>%
    dplyr::group_by(series) %>%
    dplyr::mutate(value = {
      s_min <- suppressWarnings(min(value, na.rm = TRUE))
      if (is.finite(s_min) && s_min != 0) ifelse(is.na(value), NA_real_, value - s_min) else value
    }) %>%
    dplyr::ungroup()
  
  # 4) Optional re-run of L2 so ZG and TWD are consistent
  if (isTRUE(rerun_proc_L2)) {
    message("apply_breaks_and_shift [3/3 rerun L2]...")
    ## Record positions erased by dormancy gap / year-1 treatment (step 3).
    ## proc_dendro_L2 may restore pre-season NAs (e.g. by carrying the first
    ## valid observation backward as a running baseline). Re-applying the mask
    ## after proc_dendro_L2 ensures all erased positions remain NA in the output.
    pre_proc_na <- tibble::tibble(
      series  = out$series,
      ts      = out$ts,
      .was_na = is.na(out$value)
    )
    
    L1_like <- out %>%
      dplyr::arrange(series, ts) %>%
      dplyr::select(dplyr::all_of(c("series", "ts", "value")))
    
    res <- treenetproc::proc_dendro_L2(dendro_L1 = L1_like, plot = FALSE)
    
    ## Guard: proc_dendro_L2 silently returns an empty or column-stripped data
    ## frame when all values for a series are NA (treenetproc message:
    ## "There is no data available for <series>. This series is skipped.").
    ## In that case the left_join below would crash on missing series/ts columns.
    ## Return `out` as-is -- the NA mask is already applied and there is nothing
    ## for proc_dendro_L2 to recompute.
    if (nrow(res) == 0L || !all(c("series", "ts") %in% names(res))) {
      message("apply_breaks_and_shift: proc_dendro_L2 returned no usable output ",
              "(all-NA series after dormancy erasure or break correction). ",
              "Returning pre-proc data unchanged.")
      attr(out, "dcr_view") <- .make_dcr_view(out, year_range = year_range, tz = tz)
      return(out)
    }
    
    ## Re-apply dormancy / pre-season NA mask: erased positions must remain NA
    ## regardless of what proc_dendro_L2 computed for them.
    res <- res %>%
      dplyr::left_join(pre_proc_na, by = c("series", "ts")) %>%
      dplyr::mutate(
        value = dplyr::if_else(!is.na(.was_na) & .was_na, NA_real_, value)
      ) %>%
      dplyr::select(-.was_na)
    
    attr(res, "dcr_view") <- .make_dcr_view(res, year_range = year_range, tz = tz)
    return(res)
  } else {
    attr(out, "dcr_view") <- .make_dcr_view(out, year_range = year_range, tz = tz)
    return(out)
  }
}


#' Clean a dendrometer series: breaks, dormancy, alignment, zero base
#'
#' The DendroMatic cleaning core. Applies user-defined break windows with
#' growth-aware level shifting (a bounded nearest-non-NA reference search on
#' each side of the break, plus a growth extrapolation from the pre-break
#' slope), optionally erases dormancy periods outside the growing season,
#' aligns each season's start to the prior year's maximum, re-bases every
#' series so its minimum is zero, and optionally re-runs
#' `treenetproc::proc_dendro_L2()` on the result ('treenetproc' required only
#' for that step). `apply_breaks_and_shift()` is the original DendroMatic
#' name, kept as an exported alias.
#'
#' @param df Data.frame with columns `series`, `ts`, `value`.
#' @param brks Named list: series name to a list of `c(start, end)` timestamp
#'   pairs. A flat unnamed list of pairs is accepted for a single-series `df`.
#' @param grow_start_dm,grow_end_dm Growing-season start and end as
#'   `"DD-MM"` strings.
#' @param growth_window_days Window (days) used for the slope estimate and
#'   the level-shift reference search around each break.
#' @param growth_method Slope estimation method: one of `"daily_lm"`,
#'   `"10min_lm"`, `"daily_robust"`, `"10min_lm_flip"`.
#' @param allow_negative_growth If `FALSE`, negative slope estimates are
#'   clamped to zero.
#' @param max_slope_day Cap on the slope estimate (micrometres per day).
#' @param max_growth_total Cap on the growth extrapolation per gap
#'   (micrometres).
#' @param tz Timezone for timestamp coercion.
#' @param rerun_proc_L2 If `TRUE`, re-runs `proc_dendro_L2` on the cleaned
#'   data (requires 'treenetproc').
#' @param year_range Optional year range for the attached display view.
#' @param do_dormancy_gap If `TRUE`, erases inter-seasonal dormancy periods
#'   and pre-first-season data.
#' @param align_to_prev_peak If `TRUE`, aligns each season's start to the
#'   prior year's maximum.
#' @param initial_clip_ts,final_clip_ts Optional timestamps; rows outside
#'   `[initial_clip_ts, final_clip_ts]` are dropped before any other step.
#' @param first_year_override,last_year_override Integers forcing the first or
#'   last growing-season year; `NULL` = auto-detect from data inside the
#'   growing-season window.
#' @return A data.frame of the same shape as `df` with breaks levelled,
#'   dormancy erased, seasons aligned and each series re-based to zero (the
#'   L2 output when `rerun_proc_L2 = TRUE`). Carries a `"dcr_view"`
#'   attribute with the display view.
#' @export
dm_clean_series <- apply_breaks_and_shift
