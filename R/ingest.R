## raw_to_L0 -------------------------------------------------------------------
##
## Arguments:
##   df_raw           data.frame or tibble of raw dendrometer data
##   ts_col           column name for timestamps
##   long_or_wide     "long" (default) or "wide"; controls how value_col and
##                    tree_num_col are interpreted (see below).
##   value_col        In "long" mode: single column name for measurement values.
##                    In "wide" mode: character vector of sensor column names (one
##                    per tree/series); the function pivots these to long format
##                    using tidyr::pivot_longer before processing. Tree numbers
##                    are extracted from the column names via tree_num_regex.
##   tree_num_col     In "long" mode: required column name for tree IDs.
##                    In "wide" mode: not used; tree IDs come from value_col
##                    column names.
##   site             3-character alphanumeric site code, e.g. "HOL"
##   tz_in            timezone string for interpreting raw timestamps
##   tz_out           output timezone; default "UTC"
##   measurement_unit one of: "um", "mm", "cm", "voltage", "resistance"
##   species_col      column in df_raw with 2-letter species code (e.g. "Aa")
##   metadata         alternative: data.frame joined on tree_num_col/meta_id_col
##   meta_id_col      column in metadata matching values in tree_num_col
##   meta_species_col column in metadata with 2-letter species code
##   species_abv      alternative scalar: single code for all rows
##   tree_num_pad     zero-padding width for tree number (default 3)
##   tree_num_regex   regex to extract numeric portion of tree_num_col;
##                    default "\\d+$" (trailing digits). Override for other formats.
##   excel_epoch      "windows" (default) or "mac"; only relevant for numeric ts
##   supply_col       column with per-row supply voltage (voltage mode)
##   supply_voltage   scalar supply voltage (voltage mode)
##   scale_um         full-scale travel in µm (default 11000)
##   value_in_mv      TRUE if value column is in mV (voltage mode)
##   ohm_span         full-scale resistance in Ω (resistance mode)
##   um_span          µm corresponding to ohm_span (resistance mode)
##   ohm_zero         resistance at 0 µm; default 0 (resistance mode)
##   resist_invert    TRUE if resistance decreases with extension (resistance mode)
##
## Returns: tibble with columns series, ts (POSIXct UTC), value (µm).
##   Strict treenetproc L0 format; (series, ts) duplicates removed.

#' @rdname dm_build_l0
#' @export
raw_to_L0 <- function(df_raw,
                      ts_col,
                      value_col,
                      tree_num_col     = NULL,
                      site,
                      long_or_wide     = c("long", "wide"),
                      tz_in,
                      tz_out           = "UTC",
                      measurement_unit = c("um", "mm", "cm", "voltage", "resistance"),
                      species_col      = NULL,
                      metadata         = NULL,
                      meta_id_col      = NULL,
                      meta_species_col = NULL,
                      species_abv      = NULL,
                      tree_num_pad     = 3,
                      tree_num_regex   = "\\d+$",
                      excel_epoch      = c("windows", "mac"),
                      date_format      = NULL,
                      supply_col       = NULL,
                      supply_voltage   = NULL,
                      scale_um         = 11000,
                      value_in_mv      = FALSE,
                      ohm_span         = NULL,
                      um_span          = NULL,
                      ohm_zero         = 0,
                      resist_invert    = FALSE,
                      treatment_col    = NULL) {
  
  measurement_unit <- match.arg(measurement_unit)
  excel_epoch      <- match.arg(excel_epoch)
  long_or_wide     <- match.arg(long_or_wide)
  n_in             <- nrow(df_raw)
  
  # --- Wide-to-long pivot -----------------------------------------------------
  # In wide mode, each sensor column is pivoted to a row; the original column
  # names become tree identifiers, replacing tree_num_col. The function then
  # proceeds identically to long mode from this point onward.
  if (long_or_wide == "wide") {
    if (!is.character(value_col) || length(value_col) < 1L)
      stop("raw_to_L0 [wide]: value_col must be a character vector of sensor column names.")
    if (!is.null(species_col))
      stop("raw_to_L0 [wide]: species_col is not supported in wide mode. ",
           "Use species_abv (scalar) or metadata (with meta_id_col matching sensor column names).")
    if (!ts_col %in% names(df_raw))
      stop("raw_to_L0 [wide]: ts_col \"", ts_col, "\" not found in df_raw.")
    missing_wide <- setdiff(value_col, names(df_raw))
    if (length(missing_wide) > 0L)
      stop("raw_to_L0 [wide]: value_col column(s) not found in df_raw: ",
           paste(missing_wide, collapse = ", "))
    n_sensor_cols <- length(value_col)
    df_raw        <- tidyr::pivot_longer(
      df_raw,
      cols      = dplyr::all_of(value_col),
      names_to  = "._col_id",
      values_to = "._value"
    )
    message("raw_to_L0 [wide]: pivoted ", n_sensor_cols, " sensor column(s); ",
            n_in, " wide rows -> ", nrow(df_raw), " long rows.")
    tree_num_col <- "._col_id"
    value_col    <- "._value"
  }
  
  # --- Input validation -------------------------------------------------------
  if (long_or_wide == "long" && is.null(tree_num_col))
    stop("raw_to_L0: tree_num_col is required in long mode.")
  
  missing_cols <- setdiff(c(ts_col, value_col, tree_num_col), names(df_raw))
  if (length(missing_cols) > 0L)
    stop("raw_to_L0: column(s) not found in df_raw: ",
         paste(missing_cols, collapse = ", "))
  
  if (!is.character(site) || !grepl("^[A-Za-z0-9]{3}$", trimws(site)))
    stop("raw_to_L0: 'site' must be a 3-character alphanumeric string (e.g. \"HOL\").")
  
  n_sp_sources <- sum(!is.null(species_col), !is.null(metadata), !is.null(species_abv))
  if (n_sp_sources == 0L)
    stop("raw_to_L0: provide exactly one species source: species_col, metadata, or species_abv.")
  if (n_sp_sources > 1L)
    stop("raw_to_L0: provide only one species source: species_col, metadata, or species_abv.")
  
  if (!is.null(species_col) && !species_col %in% names(df_raw))
    stop("raw_to_L0: species_col \"", species_col, "\" not found in df_raw.")
  
  if (!is.null(metadata)) {
    if (is.null(meta_id_col) || is.null(meta_species_col))
      stop("raw_to_L0: metadata requires both meta_id_col and meta_species_col.")
    missing_meta <- setdiff(c(meta_id_col, meta_species_col), names(metadata))
    if (length(missing_meta) > 0L)
      stop("raw_to_L0: column(s) not found in metadata: ",
           paste(missing_meta, collapse = ", "))
  }
  
  if (measurement_unit == "voltage") {
    if (is.null(supply_col) && is.null(supply_voltage))
      stop("raw_to_L0: measurement_unit = \"voltage\" requires supply_col or supply_voltage.")
    if (!is.null(supply_col) && !supply_col %in% names(df_raw))
      stop("raw_to_L0: supply_col \"", supply_col, "\" not found in df_raw.")
    if (!is.null(supply_voltage) && (!is.numeric(supply_voltage) || supply_voltage <= 0))
      stop("raw_to_L0: supply_voltage must be a positive numeric scalar.")
  }
  
  if (measurement_unit == "resistance") {
    if (is.null(ohm_span) || is.null(um_span))
      stop("raw_to_L0: measurement_unit = \"resistance\" requires ohm_span and um_span.")
    if (!is.numeric(ohm_span) || ohm_span <= 0)
      stop("raw_to_L0: ohm_span must be a positive numeric scalar.")
    if (!is.numeric(um_span) || um_span <= 0)
      stop("raw_to_L0: um_span must be a positive numeric scalar.")
  }
  
  # --- Species vector ---------------------------------------------------------
  if (!is.null(species_col)) {
    sp_vec <- as.character(df_raw[[species_col]])
    
  } else if (!is.null(metadata)) {
    meta_slim <- metadata %>%
      dplyr::select(
        .join_key = dplyr::all_of(meta_id_col),
        .sp       = dplyr::all_of(meta_species_col)
      ) %>%
      dplyr::mutate(.join_key = as.character(.join_key))
    
    df_raw <- df_raw %>%
      dplyr::mutate(.join_key = as.character(.data[[tree_num_col]])) %>%
      dplyr::left_join(meta_slim, by = ".join_key") %>%
      dplyr::select(-.join_key)
    
    sp_vec <- as.character(df_raw$.sp)
    df_raw <- dplyr::select(df_raw, -.sp)
    
  } else {
    sp_vec <- rep(as.character(species_abv), nrow(df_raw))
  }
  
  n_na_sp <- sum(is.na(sp_vec))
  if (n_na_sp > 0L)
    warning("raw_to_L0: ", n_na_sp, " row(s) have NA species. They will appear as ",
            site, "_NA### and must be corrected before downstream use.")
  
  non_standard <- !is.na(sp_vec) & !grepl("^[A-Z][a-z]$", sp_vec)
  if (any(non_standard)) {
    bad_codes <- sort(unique(sp_vec[non_standard]))
    warning("raw_to_L0: non-standard species code(s) (expected [A-Z][a-z]): ",
            paste(bad_codes, collapse = ", "),
            ". These will produce non-standard series identifiers.")
  }
  
  # --- Tree number extraction -------------------------------------------------
  tree_num_raw    <- as.character(df_raw[[tree_num_col]])
  tree_num_digits <- stringr::str_extract(tree_num_raw, tree_num_regex)
  
  na_ids <- which(is.na(tree_num_digits))
  if (length(na_ids) > 0L) {
    bad_vals <- unique(tree_num_raw[na_ids])
    stop("raw_to_L0: could not extract tree number with regex \"", tree_num_regex,
         "\" from ", length(na_ids), " row(s). Offending values: ",
         paste(utils::head(bad_vals, 10), collapse = ", "),
         if (length(bad_vals) > 10L) paste0(" ... (", length(bad_vals) - 10L, " more)") else "",
         ". Adjust tree_num_regex or fix input.")
  }
  
  tree_num_padded <- formatC(as.integer(tree_num_digits), width = tree_num_pad, flag = "0")
  
  # --- Series string ----------------------------------------------------------
  # Format: {SITE}_{SpAb}{padded_num}  e.g. HOL_Aa075
  # NA species produces HOL_NA075 — two uppercase chars, distinguishable from
  # valid [A-Z][a-z] codes.
  ## Treatment suffix (when treatment_col provided, appended as _TOKEN to prevent
  ## same-species/same-tree-nr rows from collapsing in deduplication below)
  treatment_sfx_vec <- if (!is.null(treatment_col) && treatment_col %in% names(df_raw)) {
    tv <- as.character(df_raw[[treatment_col]])
    dplyr::if_else(!is.na(tv) & nzchar(tv), paste0("_", tv), "")
  } else {
    rep("", nrow(df_raw))
  }
  series_vec <- paste0(site, "_", sp_vec, tree_num_padded, treatment_sfx_vec)

  # --- Distinct-tree collision guard ------------------------------------------
  # as.integer(tree_num_digits) above collapses sub-integer tree numbers: "2.1"
  # and "2.2" both extract to 2 -> the SAME series, silently merging two distinct
  # trees. The loss then hides in the (series, ts) dedup below as a benign-looking
  # "duplicate timestamp" removal. Hard-stop when two DISTINCT raw tree-id values
  # map to one series, so a corrupted corpus can never be blessed. Same raw value
  # repeated (true duplicates) or a shared number across subsites (disambiguated
  # later) is one distinct token -> not flagged. When dec_distinct is enabled the
  # caller strips the separator before this call, so decimals become integer-
  # unique and this guard passes.
  .cg_keep <- !is.na(series_vec) & !is.na(tree_num_raw)
  if (any(.cg_keep)) {
    .cg_n <- tapply(tree_num_raw[.cg_keep], series_vec[.cg_keep],
                    function(x) length(unique(x)))
    .cg_bad <- names(.cg_n)[.cg_n > 1L]
    if (length(.cg_bad)) {
      .cg_ex  <- .cg_bad[1L]
      .cg_raw <- unique(tree_num_raw[.cg_keep][series_vec[.cg_keep] == .cg_ex])
      stop("raw_to_L0: ", length(.cg_bad), " series would merge >1 distinct tree id ",
           "(sub-integer/decimal tree numbers are lost by integer extraction). ",
           "e.g. series \"", .cg_ex, "\" <- {",
           paste(utils::head(.cg_raw, 6L), collapse = ", "),
           if (length(.cg_raw) > 6L) ", ..." else "", "}. ",
           "Enable 'each decimal = distinct tree' (dec_distinct) on the TREE_NR ",
           "segment, or make the tree ids integer-unique.")
    }
  }

  # --- Timestamp --------------------------------------------------------------
  ts_raw <- .parse_ts(df_raw[[ts_col]], tz = tz_in, excel_epoch = excel_epoch,
                      fmt = date_format)
  ts_vec <- lubridate::with_tz(ts_raw, tzone = tz_out)
  
  # --- Value conversion to µm -------------------------------------------------
  raw_val <- .to_num(df_raw[[value_col]])
  
  value_um <- switch(measurement_unit,
                     um         = raw_val,
                     mm         = raw_val * 1000,
                     cm         = raw_val * 10000,
                     voltage    = {
                       v      <- if (isTRUE(value_in_mv)) raw_val / 1000 else raw_val
                       supply <- if (!is.null(supply_col)) .to_num(df_raw[[supply_col]]) else supply_voltage
                       dplyr::if_else(is.finite(supply) & supply > 0, (v / supply) * scale_um, NA_real_)
                     },
                     resistance = {
                       frac <- (raw_val - ohm_zero) / ohm_span
                       if (isTRUE(resist_invert)) frac <- 1 - frac
                       out_range <- is.finite(raw_val) & (raw_val < ohm_zero | raw_val > ohm_zero + ohm_span)
                       if (any(out_range, na.rm = TRUE))
                         warning("raw_to_L0: ", sum(out_range, na.rm = TRUE),
                                 " resistance value(s) outside [ohm_zero, ohm_zero + ohm_span]. ",
                                 "Check resist_invert / ohm_zero / ohm_span.")
                       frac * um_span
                     }
  )
  
  # --- Assemble L0 ------------------------------------------------------------
  # The .l0_* columns carry the structured naming parts (species code, integer
  # tree number, treatment token) so post_rename_l0_series() can rebuild the
  # series identifier from fields instead of re-parsing the packed string — a
  # site code containing a digit made the string re-parse grab the wrong tree
  # number and collapse trees into one series. post_rename drops them after use;
  # they never reach the strict series/ts/value L0 format treenetproc consumes.
  L0_raw <- tibble::tibble(
    series        = series_vec,
    ts            = ts_vec,
    value         = value_um,
    .l0_sp        = as.character(sp_vec),
    .l0_tree_nr   = as.integer(tree_num_digits),
    .l0_treatment = sub("^_", "", treatment_sfx_vec)
  )
  ## Count rows the NA filter removes, by cause, before dropping them. Any deletion
  ## or NA-ing must be surfaced to the user (not just the console) — the caller reads
  ## these attributes to raise an explicit warning. NA ts usually means a timestamp
  ## that would not parse; NA value means an unparseable / sentinel measurement.
  na_ts_mask  <- is.na(L0_raw$ts)
  na_val_mask <- !is.finite(L0_raw$value)   # catches NA, NaN, Inf, -Inf
  na_ser_mask <- is.na(L0_raw$series)
  drop_mask   <- na_ts_mask | na_val_mask | na_ser_mask
  n_na_ts     <- sum(na_ts_mask)
  n_na_value  <- sum(na_val_mask)
  n_na_series <- sum(na_ser_mask)
  n_dropped_na <- sum(drop_mask)
  L0_raw <- L0_raw[!drop_mask, , drop = FALSE]
  if (n_dropped_na > 0L)
    message("raw_to_L0: ", n_dropped_na, " row(s) dropped as NA ",
            "(ts=", n_na_ts, ", value=", n_na_value, ", series=", n_na_series, ").")

  # Deduplicate on (series, ts): treenetproc::proc_L1 does not deduplicate and
  # will produce incorrect output or error on repeated timestamps.
  n_pre_dedup <- nrow(L0_raw)
  L0 <- L0_raw %>%
    dplyr::arrange(series, ts) %>%
    dplyr::distinct(series, ts, .keep_all = TRUE)
  n_dropped <- n_pre_dedup - nrow(L0)
  if (n_dropped > 0L)
    message("raw_to_L0: ", n_dropped, " duplicate (series, ts) row(s) removed.")
  ## Expose the silent dedup + NA-drop counts so callers (e.g. the QC panel) can
  ## surface them; the post-filter L0 no longer contains those rows to re-detect.
  attr(L0, "n_dupes_removed")   <- n_dropped
  attr(L0, "n_rows_dropped_na") <- n_dropped_na
  attr(L0, "n_na_ts")           <- n_na_ts
  attr(L0, "n_na_value")        <- n_na_value
  attr(L0, "n_na_series")       <- n_na_series

  ## Ambiguous day/month dates: a non-ISO (day- or month-first) timestamp where no
  ## value in the first two positions exceeds 12 could be read as either DMY or MDY,
  ## so the chosen interpretation is a guess. A single token > 12 disambiguates it.
  ## Flag the ambiguous case so the user can confirm the date order in the UI.
  ts_ambiguous <- FALSE
  if (is.character(df_raw[[ts_col]]) || is.factor(df_raw[[ts_col]])) {
    tok <- stringr::str_match(as.character(df_raw[[ts_col]]),
                              "^\\s*(\\d+)\\D+(\\d+)\\D+(\\d+)")
    p1  <- suppressWarnings(as.integer(tok[, 2L]))
    p2  <- suppressWarnings(as.integer(tok[, 3L]))
    p1n <- nchar(tok[, 2L])
    not_year_first <- !is.na(p1) & !is.na(p2) & !(p1n >= 4L | p1 > 31L)
    if (any(not_year_first) &&
        max(p1[not_year_first], na.rm = TRUE) <= 12 &&
        max(p2[not_year_first], na.rm = TRUE) <= 12)
      ts_ambiguous <- TRUE
  }
  attr(L0, "ts_ambiguous_daymonth") <- ts_ambiguous

  ## Inconsistent timezone offsets (doc §QC timestamp validation): if the raw
  ## timestamps carry more than one explicit offset suffix (e.g. +00:00 and +02:00),
  ## the series mixes reference frames and a single tz_in cannot describe it.
  ts_mixed_tz <- FALSE
  if (is.character(df_raw[[ts_col]]) || is.factor(df_raw[[ts_col]])) {
    off <- stringr::str_extract(as.character(df_raw[[ts_col]]), "(Z|[+-]\\d{2}:?\\d{2})\\s*$")
    off <- unique(off[!is.na(off)])
    if (length(off) > 1L) ts_mixed_tz <- TRUE
  }
  attr(L0, "ts_mixed_tz") <- ts_mixed_tz

  # --- Sanity output ----------------------------------------------------------
  message("raw_to_L0 summary:")
  message("  rows in -> out: ", n_in, " -> ", nrow(L0))
  message("  unique series: ", dplyr::n_distinct(L0$series))
  message("  value (um) range: [",
          round(min(L0$value, na.rm = TRUE), 1), ", ",
          round(max(L0$value, na.rm = TRUE), 1), "]")
  message("  ts range (", tz_out, "): ",
          format(min(L0$ts, na.rm = TRUE)), " to ",
          format(max(L0$ts, na.rm = TRUE)))
  print(dplyr::count(L0, series))
  
  L0
}


#' Convert a raw dendrometer table to 'treenetproc' L0 format
#'
#' Ingests a raw logger table of almost any shape -- long or wide, text or
#' Excel origin -- and returns the strict L0 long format used by
#' 'treenetproc' and the rest of the dendromatic pipeline: `series`
#' (character), `ts` (POSIXct) and `value` (micrometres). Handles timestamp
#' parsing (including Excel serial dates), unit conversion (mm, cm, voltage-
#' or resistance-based sensors to micrometres), species lookup, tree-number
#' extraction and deduplication. `raw_to_L0()` is the original DendroMatic
#' name, kept as an exported alias.
#'
#' @param df_raw Raw data.frame as read from the logger export.
#' @param ts_col Name of the timestamp column in `df_raw`.
#' @param value_col Name of the measurement column (long layout).
#' @param tree_num_col Optional column holding the tree number; `NULL` to
#'   extract it from series names via `tree_num_regex`.
#' @param site Site tag prepended to series identifiers (e.g. `"HOL"`).
#' @param long_or_wide `"long"` or `"wide"` input layout.
#' @param tz_in Timezone of the input timestamps.
#' @param tz_out Timezone of the output `ts` column.
#' @param measurement_unit Input unit: `"um"`, `"mm"` or `"cm"`; sensors
#'   reporting voltage or resistance are handled via the `supply_*`/`ohm_*`
#'   arguments.
#' @param species_col Optional column with species codes or names.
#' @param metadata Optional metadata data.frame joined by `meta_id_col`.
#' @param meta_id_col,meta_species_col Column names in `metadata` holding the
#'   tree identifier and the species.
#' @param species_abv Fallback species abbreviation when none can be derived.
#' @param tree_num_pad Zero-padding width for tree numbers in series names.
#' @param tree_num_regex Regex used to extract the tree number from raw ids.
#' @param excel_epoch `"windows"` or `"mac"` Excel date origin.
#' @param date_format Explicit timestamp format; `NULL` = auto-detect.
#' @param supply_col,supply_voltage,scale_um,value_in_mv Conversion settings
#'   for voltage-based sensors.
#' @param ohm_span,um_span,ohm_zero,resist_invert Conversion settings for
#'   resistance-based sensors.
#' @param treatment_col Optional treatment column carried through to the output.
#' @return A data.frame in L0 long format with columns `series` (character),
#'   `ts` (POSIXct in `tz_out`) and `value` (micrometres), deduplicated on
#'   (`series`, `ts`), plus any carried metadata columns.
#' @export
dm_build_l0 <- raw_to_L0
