#### 8. Series merging utilities ###############################################
##
## merge_series() -- merge consecutive series from the same physical tree
##
## Purpose: when a sensor is replaced and logged under a different name, the
## two (or more) segments can be unified into a single named series before
## entering the pipeline. Overlap between segments is resolved per
## overlap_method. Value discontinuity at junctions is NOT corrected here;
## use apply_breaks_and_shift() afterward with a break at the junction time.
##
## Arguments:
##   input          Either:
##                    (a) A long data.frame with columns series, ts, value.
##                        Filter is done internally using series_names.
##                    (b) A named list of data.frames, each containing ts and
##                        value (series column optional; name of list element
##                        is used as the series identifier).
##   series_names   Character vector of series names to merge, in the intended
##                  chronological order (first element = earliest segment).
##                  For list input: must match names(input).
##                  For data.frame input: must match values in the series column.
##   output_series  Character. Series name assigned to every row of the output.
##   overlap_method One of:
##                    "first"  -- keep values from the earlier series at
##                                overlapping timestamps (default).
##                    "second" -- keep values from the later series.
##                    "mean"   -- average the two values; if one is NA, use
##                                the non-NA value.
##   tz             Timezone string used when coercing ts to POSIXct (default
##                  "UTC"). Only applied when ts is not already POSIXct.
##
## Returns: tibble with columns series (= output_series), ts (POSIXct), value,
##          sorted by ts, with duplicated timestamps resolved.
##
## Typical workflow:
##   merged <- merge_series(L2_by_series,
##                          series_names  = c("HOL_Aa001", "HOL_Aa001b"),
##                          output_series = "HOL_Aa001")
##   # Then pass merged to apply_breaks_and_shift() with a break at the
##   # junction between the two original segments.

#' @rdname dm_merge_series
#' @export
merge_series <- function(
    input,
    series_names,
    output_series,
    overlap_method = c("first", "second", "mean"),
    tz             = "UTC"
) {
  overlap_method <- match.arg(overlap_method)
  
  if (!is.character(series_names) || length(series_names) < 2L)
    stop("merge_series: series_names must be a character vector of length >= 2.")
  if (!is.character(output_series) || length(output_series) != 1L || !nzchar(output_series))
    stop("merge_series: output_series must be a single non-empty character string.")
  
  # -- 1) Parse input into a named list of (ts, value) tibbles ----------------
  if (is.data.frame(input)) {
    if (!all(c("series", "ts", "value") %in% names(input)))
      stop("merge_series: data.frame input must contain columns: series, ts, value.")
    missing_s <- setdiff(series_names, unique(as.character(input$series)))
    if (length(missing_s) > 0L)
      stop("merge_series: series not found in input: ", paste(missing_s, collapse = ", "))
    df_list <- lapply(series_names, function(s) {
      sub <- input[as.character(input$series) == s, , drop = FALSE]
      tibble::tibble(series = s, ts = sub$ts, value = sub$value)
    })
    
  } else if (is.list(input) && !is.data.frame(input)) {
    missing_s <- setdiff(series_names, names(input))
    if (length(missing_s) > 0L)
      stop("merge_series: series not found in input list: ",
           paste(missing_s, collapse = ", "))
    df_list <- lapply(series_names, function(s) {
      df <- input[[s]]
      if (!is.data.frame(df))
        stop("merge_series: input[[\"", s, "\"]] is not a data.frame.")
      if (!all(c("ts", "value") %in% names(df)))
        stop("merge_series: input[[\"", s, "\"]] must contain 'ts' and 'value'.")
      tibble::tibble(series = s, ts = df$ts, value = df$value)
    })
    
  } else {
    stop("merge_series: 'input' must be a data.frame or a named list of data.frames.")
  }
  names(df_list) <- series_names
  
  # -- 2) Coerce timestamps and sort each segment ------------------------------
  df_list <- lapply(df_list, function(df) {
    if (!inherits(df$ts, "POSIXct")) df$ts <- as.POSIXct(df$ts, tz = tz)
    dplyr::arrange(df, ts)
  })
  
  # -- 3) Tag rows with source order, bind, resolve overlaps ------------------
  # .src_order: 1 = first/earliest series, 2 = second, etc.
  # This integer tag drives overlap resolution without relying on series names.
  tagged <- lapply(seq_along(series_names), function(i) {
    df_list[[series_names[i]]] %>%
      dplyr::mutate(.src_order = i)
  })
  
  combined <- dplyr::bind_rows(tagged)
  
  # Identify timestamps that appear more than once across segments
  ts_num   <- as.numeric(combined$ts)
  dup_ts   <- unique(ts_num[duplicated(ts_num)])
  n_overlap <- length(dup_ts)
  
  if (n_overlap > 0L) {
    message("merge_series: ", n_overlap, " overlapping timestamp(s) across input segments.")
    message("  Resolving with overlap_method = '", overlap_method, "'.")
    
    if (overlap_method == "first") {
      # Keep earliest-segment value; discard later-segment rows at same ts
      combined <- combined %>%
        dplyr::arrange(ts, .data$.src_order) %>%
        dplyr::distinct(ts, .keep_all = TRUE)
      
    } else if (overlap_method == "second") {
      # Keep latest-segment value; discard earlier-segment rows at same ts
      combined <- combined %>%
        dplyr::arrange(ts, dplyr::desc(.data$.src_order)) %>%
        dplyr::distinct(ts, .keep_all = TRUE)
      
    } else {
      # mean: average finite values; fall back to the non-NA value if only one
      combined <- combined %>%
        dplyr::group_by(ts) %>%
        dplyr::summarise(
          series     = series_names[min(.data$.src_order)],
          value      = {
            v <- value[is.finite(value)]
            if (length(v) == 0L) NA_real_ else mean(v)
          },
          .src_order = min(.data$.src_order),
          .groups    = "drop"
        )
    }
  }
  
  # -- 4) Assign output series name and finalise -------------------------------
  out <- combined %>%
    dplyr::mutate(series = output_series) %>%
    dplyr::select(series, ts, value) %>%
    dplyr::arrange(ts)
  
  # Diagnostic summary
  message("merge_series: merged ", length(series_names), " segment(s) -> '",
          output_series, "'")
  message("  Segments (in order): ", paste(series_names, collapse = " -> "))
  message("  Output rows: ", nrow(out),
          " | ts range: ", format(min(out$ts, na.rm = TRUE)),
          " to ", format(max(out$ts, na.rm = TRUE)))
  message("  value range: [",
          round(suppressWarnings(min(out$value, na.rm = TRUE)), 1), ", ",
          round(suppressWarnings(max(out$value, na.rm = TRUE)), 1), "]")
  print(summary(out$value))
  
  out
}


#' Merge consecutive dendrometer series from the same tree
#'
#' Concatenates two or more series (e.g. after a sensor swap) into one output
#' series, resolving overlap periods by the chosen method. No value
#' discontinuity correction is applied -- run [dm_clean_series()] with a break
#' window afterwards. `merge_series()` is the original DendroMatic name, kept
#' as an exported alias.
#'
#' @param input A long data.frame (`series`, `ts`, `value`) or a named list of
#'   per-series data.frames.
#' @param series_names Character vector (length >= 2) of series to merge, in
#'   chronological order.
#' @param output_series Name of the merged output series.
#' @param overlap_method How to resolve overlapping timestamps: `"first"`,
#'   `"second"` or `"mean"`.
#' @param tz Timezone for timestamp coercion.
#' @return A data.frame (`series`, `ts`, `value`) holding the merged series
#'   under `output_series`.
#' @export
dm_merge_series <- merge_series
