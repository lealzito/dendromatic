#### 7. LWP-to-SFW matching utilities #########################################
##
## match_lwp_to_sfw() -- two-tier LWP-to-SFW matching
##
## Purpose: standardize the way every site's 05_ script attaches LWP values to
## the SFW_prov dendrometer table. Two tiers are supported:
##
##   Tier A (timestamp-based): when ts_pd / ts_md are available in LWP_daily AND
##          L2_hourly is supplied. The TWD value is looked up in L2_hourly at the
##          nearest hourly timestamp within ±TIER_A_TOL_MIN of the measurement
##          time. TWDnorm at measurement time is computed as
##          pdTWDnorm_tierA = twd_at_ts / MDS_max.
##
##   Tier B (date-based): join on (series, day) only; uses the pre-computed
##          pdtwd / mdtwd in SFW_prov from fixed windows (03_ output).
##
## For each (series, day) Tier A is preferred. Tier B fills remaining rows.
## Sites without timestamps (HOL, TIL, GOE, GRE) always fall through to Tier B.
##
## KRF treatment-split handling:
##   After the KRF series renaming (KRFCTR / KRFTEE1 / KRFTEE2), LWP data may
##   carry the old series name. Pass old_series_col = "old_series" to try a
##   secondary join using the pre-rename name before giving up.
##
## Arguments:
##   SFW            SFW_prov tibble. Required cols: series, day, MDS_max,
##                  pdtwd, mdtwd, pdtwd_mds, mdtwd_mds.
##   LWP_daily      Daily LWP tibble. Required: series, day, pdlwp, mdlwp.
##                  Optional (enable Tier A): ts_pd, ts_md (POSIXct UTC).
##   L2_hourly      Hourly L2 tibble (series, ts, twd). NULL -> Tier B only.
##   TIER_A_TOL_MIN Integer minutes; default 30.
##   old_series_col Column name in SFW holding the pre-rename series string.
##                  NULL (default) = no fallback. Set to "old_series" for KRF.
##   site_tag       Character label for diagnostic messages.
##
## Returns: SFW with added columns:
##   pdlwp, mdlwp           LWP (MPa) matched from LWP_daily.
##   ts_pd_lwp, ts_md_lwp   Exact measurement POSIXct when Tier A; else NA.
##   pdTWDnorm_tierA,
##   mdTWDnorm_tierA        TWD/MDS_max at measurement time (Tier A only; NA = B).
##   lwp_tier_pd,
##   lwp_tier_md            "A" or "B" (NA if no LWP matched at all).
##
## NOTE: MDS_max in SFW must be populated before calling this function.
##       If L2_hourly is supplied it must cover the same date range as LWP_daily.

#' @rdname dm_match_lwp
#' @export
match_lwp_to_sfw <- function(
    SFW,
    LWP_daily,
    L2_hourly      = NULL,
    TIER_A_TOL_MIN = 30L,
    old_series_col = NULL,
    site_tag       = "?"
) {
  
  # --- 0) Input guards --------------------------------------------------------
  stopifnot(is.data.frame(SFW), is.data.frame(LWP_daily))
  stopifnot(all(c("series","day","MDS_max","pdtwd","mdtwd") %in% names(SFW)))
  stopifnot(all(c("series","day","pdlwp","mdlwp") %in% names(LWP_daily)))
  
  SFW       <- SFW       %>% dplyr::mutate(day = as.Date(.data$day))
  LWP_daily <- LWP_daily %>% dplyr::mutate(day = as.Date(.data$day))
  
  # Determine whether Tier A is viable
  has_ts_cols <- all(c("ts_pd","ts_md") %in% names(LWP_daily))
  tier_a_ok   <- has_ts_cols && !is.null(L2_hourly) &&
    all(c("series","ts","twd") %in% names(L2_hourly))
  
  if (!tier_a_ok && !is.null(L2_hourly)) {
    message(site_tag, ": L2_hourly supplied but ts_pd / ts_md missing from LWP_daily.",
            " Proceeding with Tier B only.")
  }
  
  # --- 1) Tier B baseline join ------------------------------------------------
  # Primary join on current series name.
  LWP_B <- LWP_daily %>%
    dplyr::select(.data$series, .data$day, .data$pdlwp, .data$mdlwp)
  
  SFW_B <- SFW %>%
    dplyr::left_join(LWP_B, by = c("series", "day"))
  
  # KRF old_series fallback: for rows that got no LWP, try the pre-rename name.
  if (!is.null(old_series_col) && old_series_col %in% names(SFW_B)) {
    
    unmatched <- is.na(SFW_B$pdlwp) & is.na(SFW_B$mdlwp) &
      !is.na(SFW_B[[old_series_col]])
    
    if (any(unmatched)) {
      LWP_B_for_fallback <- LWP_B %>%
        dplyr::rename(
          pdlwp_fb = .data$pdlwp,
          mdlwp_fb = .data$mdlwp
        )
      
      fallback_keys <- tibble::tibble(
        join_series = as.character(SFW_B[[old_series_col]][unmatched]),
        day         = SFW_B$day[unmatched]
      )
      
      fallback_vals <- fallback_keys %>%
        dplyr::left_join(
          LWP_B_for_fallback %>% dplyr::rename(join_series = .data$series),
          by = c("join_series", "day")
        )
      
      SFW_B$pdlwp[unmatched] <- fallback_vals$pdlwp_fb
      SFW_B$mdlwp[unmatched] <- fallback_vals$mdlwp_fb
      
      n_filled <- sum(!is.na(fallback_vals$pdlwp_fb) | !is.na(fallback_vals$mdlwp_fb),
                      na.rm = TRUE)
      message(site_tag, ": old_series fallback filled ", n_filled, " additional rows.")
    }
  }
  
  # Add Tier B diagnostic and placeholder columns
  SFW_B <- SFW_B %>%
    dplyr::mutate(
      lwp_tier_pd     = dplyr::if_else(!is.na(.data$pdlwp), "B", NA_character_),
      lwp_tier_md     = dplyr::if_else(!is.na(.data$mdlwp), "B", NA_character_),
      ts_pd_lwp       = as.POSIXct(NA_real_, tz = "UTC"),
      ts_md_lwp       = as.POSIXct(NA_real_, tz = "UTC"),
      pdTWDnorm_tierA = NA_real_,
      mdTWDnorm_tierA = NA_real_
    )
  
  if (!tier_a_ok) {
    message(site_tag, ": Tier B final -> ",
            sum(!is.na(SFW_B$pdlwp)), " PD / ",
            sum(!is.na(SFW_B$mdlwp)), " MD rows matched.")
    return(SFW_B)
  }
  
  # --- 2) Tier A: timestamp-based matching ------------------------------------
  tol_secs <- as.numeric(TIER_A_TOL_MIN) * 60L
  
  # MDS_max is constant per series; take the first non-NA value.
  mds_tbl <- SFW %>%
    dplyr::filter(!is.na(.data$MDS_max), .data$MDS_max > 0) %>%
    dplyr::group_by(.data$series) %>%
    dplyr::slice(1L) %>%
    dplyr::ungroup() %>%
    dplyr::select(.data$series, .data$MDS_max)
  
  # Prepare L2_hourly (only valid TWD rows; sort for fast binary search later)
  L2h <- L2_hourly %>%
    dplyr::select(.data$series, .data$ts, .data$twd) %>%
    dplyr::filter(!is.na(.data$twd)) %>%
    dplyr::arrange(.data$series, .data$ts)
  
  # Vectorised nearest-timestamp lookup within tolerance.
  lookup_twd_at_ts <- function(series_vec, ts_vec) {
    n   <- length(series_vec)
    out <- rep(NA_real_, n)
    
    series_unique <- unique(stats::na.omit(series_vec))
    
    # Progress bar: one tick per unique series
    message("match_lwp_to_sfw [Tier A TWD lookup]: ",
            length(series_unique), " series...")
    pb_ta   <- utils::txtProgressBar(min = 0, max = max(length(series_unique), 1L),
                                     style = 3, width = 50)
    pb_i_ta <- 0L
    
    for (s in series_unique) {
      pb_i_ta <- pb_i_ta + 1L
      utils::setTxtProgressBar(pb_ta, pb_i_ta)
      idx_s <- which(series_vec == s & !is.na(ts_vec))
      if (length(idx_s) == 0L) next
      
      sub <- L2h[L2h$series == s, ]
      if (nrow(sub) == 0L) next
      
      sub_ts <- sub$ts
      sub_td <- sub$twd
      
      # For each LWP timestamp, find argmin |L2h_ts - ts_lwp|
      ts_query <- ts_vec[idx_s]
      for (k in seq_along(idx_s)) {
        dt   <- abs(as.numeric(sub_ts - ts_query[k], units = "secs"))
        best <- which.min(dt)
        if (dt[best] <= tol_secs) out[idx_s[k]] <- sub_td[best]
      }
    }
    close(pb_ta)
    message("")  # newline after txtProgressBar
    out
  }
  
  # Prepare LWP rows that have at least one timestamp
  LWP_ts <- LWP_daily %>%
    dplyr::filter(!is.na(.data$ts_pd) | !is.na(.data$ts_md)) %>%
    dplyr::left_join(mds_tbl, by = "series")
  
  if (nrow(LWP_ts) == 0L) {
    message(site_tag, ": No rows with valid ts_pd / ts_md. Falling back to Tier B only.")
    return(SFW_B)
  }
  
  twd_at_pd <- lookup_twd_at_ts(LWP_ts$series, LWP_ts$ts_pd)
  twd_at_md <- lookup_twd_at_ts(LWP_ts$series, LWP_ts$ts_md)
  
  # Build Tier A daily table
  tier_a_rows <- LWP_ts %>%
    dplyr::mutate(
      .twd_pd       = twd_at_pd,
      .twd_md       = twd_at_md,
      .pdTWDnorm_A  = dplyr::if_else(
        !is.na(.data$.twd_pd) & !is.na(.data$MDS_max) & .data$MDS_max > 0,
        .data$.twd_pd / .data$MDS_max, NA_real_
      ),
      .mdTWDnorm_A  = dplyr::if_else(
        !is.na(.data$.twd_md) & !is.na(.data$MDS_max) & .data$MDS_max > 0,
        .data$.twd_md / .data$MDS_max, NA_real_
      ),
      .tier_pd      = dplyr::if_else(!is.na(.data$.twd_pd) & !is.na(.data$ts_pd),
                                     "A", NA_character_),
      .tier_md      = dplyr::if_else(!is.na(.data$.twd_md) & !is.na(.data$ts_md),
                                     "A", NA_character_)
    )
  
  # Aggregate to daily: mean LWP and TWDnorm; keep first timestamp per day
  tier_a_daily <- tier_a_rows %>%
    dplyr::group_by(.data$series, .data$day) %>%
    dplyr::summarise(
      .pdlwp_A       = if (all(is.na(.data$pdlwp))) NA_real_
      else mean(.data$pdlwp, na.rm = TRUE),
      .mdlwp_A       = if (all(is.na(.data$mdlwp))) NA_real_
      else mean(.data$mdlwp, na.rm = TRUE),
      .ts_pd_lwp     = dplyr::first(stats::na.omit(.data$ts_pd)),
      .ts_md_lwp     = dplyr::first(stats::na.omit(.data$ts_md)),
      .pdTWDnorm_A   = if (all(is.na(.data$.pdTWDnorm_A))) NA_real_
      else mean(.data$.pdTWDnorm_A, na.rm = TRUE),
      .mdTWDnorm_A   = if (all(is.na(.data$.mdTWDnorm_A))) NA_real_
      else mean(.data$.mdTWDnorm_A, na.rm = TRUE),
      .tier_pd       = dplyr::first(stats::na.omit(.data$.tier_pd)),
      .tier_md       = dplyr::first(stats::na.omit(.data$.tier_md)),
      .groups        = "drop"
    )
  
  # --- 3) Merge Tier A into Tier B result ------------------------------------
  # Tier A values override Tier B where both exist for the same (series, day).
  SFW_out <- SFW_B %>%
    dplyr::left_join(tier_a_daily, by = c("series", "day")) %>%
    dplyr::mutate(
      pdlwp           = dplyr::coalesce(.data$.pdlwp_A, .data$pdlwp),
      mdlwp           = dplyr::coalesce(.data$.mdlwp_A, .data$mdlwp),
      ts_pd_lwp       = dplyr::coalesce(.data$.ts_pd_lwp, .data$ts_pd_lwp),
      ts_md_lwp       = dplyr::coalesce(.data$.ts_md_lwp, .data$ts_md_lwp),
      pdTWDnorm_tierA = .data$.pdTWDnorm_A,
      mdTWDnorm_tierA = .data$.mdTWDnorm_A,
      lwp_tier_pd     = dplyr::coalesce(.data$.tier_pd, .data$lwp_tier_pd),
      lwp_tier_md     = dplyr::coalesce(.data$.tier_md, .data$lwp_tier_md)
    ) %>%
    dplyr::select(-dplyr::starts_with("."))
  
  # Diagnostic summary
  n_A_pd <- sum(SFW_out$lwp_tier_pd == "A", na.rm = TRUE)
  n_A_md <- sum(SFW_out$lwp_tier_md == "A", na.rm = TRUE)
  n_B_pd <- sum(SFW_out$lwp_tier_pd == "B", na.rm = TRUE)
  n_B_md <- sum(SFW_out$lwp_tier_md == "B", na.rm = TRUE)
  message(site_tag, ": Tier A -> ", n_A_pd, " PD / ", n_A_md, " MD | ",
          "Tier B -> ", n_B_pd, " PD / ", n_B_md, " MD")
  
  SFW_out
}

## default_species_lut ---------------------------------------------------------
## Returns the full DenMet project species lookup table.
## Extend here when a new species is added to any site.

#' @rdname dm_species_lut
#' @export
default_species_lut <- function() {
  tibble::tribble(
    ~species_abv, ~species,
    "Pa",  "Picea abies",
    "Fs",  "Fagus sylvatica",
    "Aa",  "Abies alba",
    "Ps",  "Pinus sylvestris",
    "Cb",  "Carpinus betulus",
    "Ld",  "Larix decidua",
    "Qr",  "Quercus robur",
    "Qp",  "Quercus pubescens",
    "Qs",  "Quercus sp",
    "Pm",  "Pseudotsuga menziesii",
    "St",  "Sorbus torminalis",
    "Fe",  "Fraxinus excelsior",
    "Ap",  "Acer pseudoplatanus"
  )
}

## build_sfw -------------------------------------------------------------------
##
## Construct a standard HOL-style SFW tibble from daily L2 + phase_daily.
## Returns the SFW object; the caller writes saveRDS().
##
## Arguments:
##   L2_daily           tibble(series, day, value, max, twd, gro_yr, pdtwd, mdtwd)
##   phase_daily        treenetproc::phase_stats() output, deduplicated per
##                      (series, day), with columns:
##                      series, day, phase_class, shrink_dur, shrink_amp
##   site_tag           character scalar; site code e.g. "HOL"
##   treatment          scalar character; assigned to all rows (default "Control")
##   species_lut        tibble(species_abv, species); pass NULL to skip lookup.
##                      Default: default_species_lut().
##   site_col           "tag"    -> site column = site_tag constant (default)
##                      "series" -> site column = series prefix up to first "_"
##                      Use "series" for LOT-style subsite-as-site.
##   include_phase_cols logical; if TRUE, retain shrink/exp phase columns in output

#' @rdname dm_build_sfw
#' @export
build_sfw <- function(L2_daily,
                      phase_daily,
                      site_tag,
                      treatment          = "Control",
                      species_lut        = default_species_lut(),
                      site_col           = c("tag", "series"),
                      include_phase_cols = FALSE) {
  site_col <- match.arg(site_col)
  
  stopifnot(
    is.data.frame(L2_daily),
    is.data.frame(phase_daily),
    is.character(site_tag) && length(site_tag) == 1L && nzchar(site_tag)
  )
  
  need_l2 <- c("series", "day", "value", "max", "twd", "gro_yr", "pdtwd", "mdtwd")
  miss_l2 <- setdiff(need_l2, names(L2_daily))
  if (length(miss_l2) > 0L)
    stop("build_sfw: L2_daily missing columns: ", paste(miss_l2, collapse = ", "))
  
  need_ph <- c("series", "day", "phase_class", "shrink_dur", "shrink_amp")
  miss_ph <- setdiff(need_ph, names(phase_daily))
  if (length(miss_ph) > 0L)
    stop("build_sfw: phase_daily missing columns: ", paste(miss_ph, collapse = ", "))
  
  # -- 1) Join daily L2 with phase stats (full join: keep all days) ------------
  sfw <- dplyr::full_join(L2_daily, phase_daily, by = c("series", "day"))
  
  # -- 2) Core derived columns ------------------------------------------------
  sfw <- sfw %>%
    dplyr::mutate(
      phase_keep = (!is.na(.data$phase_class) & .data$phase_class == 1L &
                      !is.na(.data$shrink_dur) & .data$shrink_dur <= 1440),
      MDS        = dplyr::if_else(.data$phase_keep, abs(.data$shrink_amp), NA_real_),
      site       = if (site_col == "tag") {
        site_tag
      } else {
        stringr::str_extract(as.character(.data$series), "^[^_]+")
      },
      year       = lubridate::year(as.Date(.data$day)),
      treatment  = treatment,
      tree_id    = stringr::str_replace(
        as.character(.data$series),
        paste0("^[^_]+_"),
        ""
      )
    )
  
  # -- 3) MDS_max per series, MDS_max_year per series x year ------------------
  sfw <- sfw %>%
    dplyr::group_by(.data$series) %>%
    dplyr::mutate(
      MDS_max = if (all(is.na(.data$MDS))) NA_real_
      else as.numeric(stats::quantile(.data$MDS, probs = 0.99, na.rm = TRUE))
    ) %>%
    dplyr::group_by(.data$series, .data$year) %>%
    dplyr::mutate(
      MDS_max_year = if (all(is.na(.data$MDS))) NA_real_
      else as.numeric(stats::quantile(.data$MDS, probs = 0.99, na.rm = TRUE))
    ) %>%
    dplyr::ungroup()
  
  # -- 4) Normalised metrics --------------------------------------------------
  sfw <- sfw %>%
    dplyr::mutate(
      pdtwd_mds = .data$pdtwd / .data$MDS_max,
      mdtwd_mds = .data$mdtwd / .data$MDS_max,
      MDSnorm   = .data$MDS   / .data$MDS_max
    )
  
  # -- 5) Species lookup -------------------------------------------------------
  sfw <- sfw %>%
    dplyr::mutate(species_abv = substr(.data$tree_id, 1L, 2L))
  
  if (!is.null(species_lut)) {
    if (!all(c("species_abv", "species") %in% names(species_lut)))
      stop("build_sfw: species_lut must have columns 'species_abv' and 'species'.")
    sfw <- dplyr::left_join(sfw, species_lut, by = "species_abv")
  }
  
  # -- 6) Column selection ----------------------------------------------------
  core_cols <- c(
    "series", "site", "tree_id", "species_abv",
    if (!is.null(species_lut)) "species" else NULL,
    "day", "year", "treatment",
    "pdtwd", "mdtwd", "pdtwd_mds", "mdtwd_mds",
    "MDS", "MDS_max", "MDS_max_year", "MDSnorm",
    "value", "max", "twd", "gro_yr"
  )
  
  phase_cols <- c(
    "phase_class", "phase_keep",
    "shrink_start", "shrink_end", "shrink_dur", "shrink_amp", "shrink_slope",
    "exp_start", "exp_end", "exp_dur", "exp_amp", "exp_slope"
  )
  
  keep_cols <- if (include_phase_cols) {
    c(core_cols, intersect(phase_cols, names(sfw)))
  } else {
    core_cols
  }
  
  # Gracefully drop any column that does not exist in sfw
  keep_cols <- intersect(keep_cols, names(sfw))
  
  sfw <- sfw %>%
    dplyr::select(dplyr::all_of(keep_cols)) %>%
    dplyr::arrange(.data$series, .data$day)
  
  # -- 7) Diagnostic summary --------------------------------------------------
  message("build_sfw [", site_tag, "]: ",
          nrow(sfw), " rows | ",
          dplyr::n_distinct(sfw$series), " series | ",
          sum(!is.na(sfw$MDS)), " MDS non-NA | ",
          sum(!is.na(sfw$pdtwd)), " pdtwd non-NA")
  
  sfw
}


#' Assemble the standard SFW table from daily L2 and phase statistics
#'
#' Builds the HOL-style SFW (stem features and water deficit) tibble from
#' daily L2 output and `treenetproc::phase_stats()` output: species lookup,
#' MDS and predawn/midday TWD normalisation, one row per series and day.
#' `build_sfw()` is the original DendroMatic name, kept as an exported alias.
#'
#' @param L2_daily Daily L2 data.frame; must contain `series`, `day`, `value`,
#'   `max`, `twd`, `gro_yr`, `pdtwd`, `mdtwd`.
#' @param phase_daily `treenetproc::phase_stats()` output, deduplicated per
#'   series and day.
#' @param site_tag Site code written into the `tag` column.
#' @param treatment Treatment label written into the `treatment` column.
#' @param species_lut Lookup tibble with columns `species_abv` and `species`;
#'   defaults to [dm_species_lut()].
#' @param site_col Where to read the site from: `"tag"` or `"series"`.
#' @param include_phase_cols If `TRUE`, phase columns are kept in the output.
#' @return The SFW tibble, one row per series and day.
#' @export
dm_build_sfw <- build_sfw

#' Match leaf water potential campaigns to the SFW table
#'
#' Two-tier matching of leaf water potential (LWP) observations to SFW rows:
#' Tier A matches on timestamp against hourly L2 data within
#' `TIER_A_TOL_MIN` minutes; Tier B falls back to a date join on
#' (`series`, `day`). `match_lwp_to_sfw()` is the original DendroMatic name,
#' kept as an exported alias.
#'
#' @param SFW SFW data.frame; must contain `series`, `day`, `MDS_max`,
#'   `pdtwd`, `mdtwd`.
#' @param LWP_daily LWP data.frame; must contain `series`, `day`, `pdlwp`,
#'   `mdlwp`.
#' @param L2_hourly Optional hourly L2 data.frame enabling Tier A timestamp
#'   matching.
#' @param TIER_A_TOL_MIN Tier A matching tolerance in minutes.
#' @param old_series_col Optional column in `LWP_daily` holding legacy series
#'   names to translate.
#' @param site_tag Site label used in diagnostic messages.
#' @return The SFW data.frame with matched LWP columns and per-row tier flags
#'   (`lwp_tier_pd`, `lwp_tier_md`).
#' @export
dm_match_lwp <- match_lwp_to_sfw

#' Default species abbreviation lookup table
#'
#' Reference tibble mapping two-letter species abbreviations to Latin names.
#' `default_species_lut()` is the original DendroMatic name, kept as an
#' exported alias.
#'
#' @return A tibble with columns `species_abv` and `species`.
#' @export
dm_species_lut <- default_species_lut
