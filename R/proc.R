#### 5. treenetproc wrappers ###################################################


safe_proc_dendro_L2 <- function(dendro_L1, tz = "UTC") {
  .need_treenetproc("safe_proc_dendro_L2()")
  # Version-safe wrapper around treenetproc::proc_dendro_L2.
  # Inspects the function's formal arguments and passes only those that exist,
  # preventing errors when treenetproc changes its interface.
  fn   <- treenetproc::proc_dendro_L2
  argn <- names(formals(fn))
  
  common <- list(tz = tz)
  if ("plot"        %in% argn) common$plot        <- FALSE
  if ("plot_export" %in% argn) common$plot_export <- FALSE
  if ("input"       %in% argn) common$input       <- "long"
  
  if ("data_L1"   %in% argn) return(do.call(fn, c(list(data_L1   = dendro_L1), common)))
  if ("dendro_L1" %in% argn) return(do.call(fn, c(list(dendro_L1 = dendro_L1), common)))
  
  do.call(fn, c(list(dendro_L1), common))
}

#' @rdname dm_proc_l1
#' @export
multi_proc_L1 <- function(df,
                          vars,
                          timevar     = "ts",
                          reso        = 60,
                          tz          = "UTC",
                          date_format = "%Y-%m-%d %H:%M:%S",
                          drop_static = FALSE,
                          parallel    = FALSE) {
  .need_treenetproc("dm_proc_l1()")
  # Run treenetproc::proc_L1 independently on each variable in `vars`,
  # then full-join the results back on (series, ts).
  # Static columns (not in vars or the timestamp column) are optionally re-joined.
  #
  # df          : long data.frame with columns series, <timevar>, and vars
  # vars        : character vector of column names to process through proc_L1
  # timevar     : name of the timestamp column in df
  # reso        : resolution in minutes (passed to proc_L1)
  # tz          : timezone (passed to proc_L1)
  # date_format : strftime format for converting ts to character for proc_L1
  # drop_static : if FALSE, non-processed columns are re-joined after proc_L1
  # parallel    : if TRUE, use future.apply::future_lapply to process vars
  #               concurrently. The caller must set a plan() beforehand, e.g.:
  #               plan(multisession, workers = min(4L, length(vars)))
  #               Falls back to lapply with a message if future.apply is absent.
  
  stopifnot(all(c("series", timevar) %in% names(df)))
  missing_vars <- setdiff(vars, names(df))
  if (length(missing_vars) > 0L)
    stop("multi_proc_L1: missing vars in df: ", paste(missing_vars, collapse = ", "))
  
  static_cols <- setdiff(names(df), c("series", timevar, vars))
  
  # Select map function: future_lapply when parallel = TRUE and available
  map_fn <- if (isTRUE(parallel) && requireNamespace("future.apply", quietly = TRUE)) {
    future.apply::future_lapply
  } else {
    if (isTRUE(parallel))
      message("multi_proc_L1: future.apply not available; falling back to sequential lapply.")
    lapply
  }
  
  processed_list <- map_fn(vars, function(v) {
    df_temp <- df %>%
      dplyr::select(series, ts = !!rlang::sym(timevar), !!rlang::sym(v))
    colnames(df_temp) <- c("series", "ts", "value")
    
    if (!inherits(df_temp$ts, "POSIXct")) df_temp$ts <- as.POSIXct(df_temp$ts, tz = tz)
    
    df_temp <- df_temp %>%
      dplyr::arrange(series, ts) %>%
      dplyr::distinct(series, ts, .keep_all = TRUE) %>%
      dplyr::mutate(
        ts    = format(ts, format = date_format, tz = tz),
        value = as.numeric(value)
      )
    
    res <- treenetproc::proc_L1(
      data_L0     = df_temp,
      reso        = reso,
      input       = "long",
      date_format = date_format,
      tz          = tz
    )
    
    res %>% dplyr::rename(!!v := value)
  })
  
  df_proc <- Reduce(
    function(x, y) dplyr::full_join(x, y, by = c("series", "ts")),
    processed_list
  )
  
  if (!drop_static && length(static_cols) > 0L) {
    df_static <- df %>%
      dplyr::select(series, ts = !!rlang::sym(timevar), dplyr::all_of(static_cols)) %>%
      dplyr::distinct()
    df_final <- dplyr::left_join(df_proc, df_static, by = c("series", "ts"))
    existing <- static_cols[static_cols %in% names(df_final)]
    return(df_final %>% dplyr::select(series, ts, dplyr::all_of(vars), dplyr::all_of(existing)))
  }
  
  df_proc %>% dplyr::select(series, ts, dplyr::all_of(vars))
}

## run_L1_L2 -------------------------------------------------------------------
##
## Shared L0 -> L1 -> L2_auto backbone for all 01_ site scripts.
## Input MUST be a tibble with columns series (chr), ts (POSIXct UTC),
## value (num, um). No tz conversion is performed here -- that is the
## responsibility of the calling 01_ script.
##
## Arguments:
##   L0_long          tibble(series chr, ts POSIXct UTC, value num um)
##   reso_min         integer; resolution in minutes for proc_L1
##   site_tag         character; 3-char site code (used in output messages)
##   out_dir_L0       directory path; L0 RDS written here
##   out_dir_L1       directory path; L1 RDS written here
##   out_dir_L2       directory path; L2 RDS written here
##   temp_L1          treenetproc L1 temperature object, or NULL
##   tz_use           character; timezone label on all output POSIXct ("UTC")
##   write_per_series logical; if TRUE, write one RDS per series into raw_dir.
##                    Required for 02_ scripts that use prep_for_dcr() per tree.
##   raw_dir          directory for per-series RDS; defaults to
##                    file.path(out_dir_L0, paste0(site_tag, "_RAW"))
##   l0_fname         filename stem for merged L0 RDS (default "{site_tag}_L0_long.rds")
##   l1_fname         filename stem for L1 RDS  (default "{site_tag}_L1.rds")
##   l2_fname         filename stem for L2 RDS  (default "{site_tag}_L2_auto.rds")
##
## Returns: named list(L0 = ..., L1 = ..., L2 = ...) invisibly.
## Side-effects: writes RDS files; prints diagnostics to console.

#' @rdname dm_run_pipeline
#' @export
run_L1_L2 <- function(
    L0_long,
    reso_min,
    site_tag,
    out_dir_L0,
    out_dir_L1,
    out_dir_L2,
    temp_L1          = NULL,
    tz_use           = "UTC",
    write_per_series = FALSE,
    raw_dir          = file.path(out_dir_L0, paste0(site_tag, "_RAW")),
    l0_fname         = paste0(site_tag, "_L0_long.rds"),
    l1_fname         = paste0(site_tag, "_L1.rds"),
    l2_fname         = paste0(site_tag, "_L2_auto.rds")) {
  .need_treenetproc("dm_run_pipeline()")
  
  ## Input guards ---------------------------------------------------------------
  stopifnot(is.data.frame(L0_long))
  if (!all(c("series", "ts", "value") %in% names(L0_long)))
    stop("run_L1_L2: L0_long must have columns 'series', 'ts', 'value'.")
  if (!inherits(L0_long$ts, "POSIXct"))
    stop("run_L1_L2: L0_long$ts must be POSIXct. Convert before calling.")
  tz_attr <- attr(L0_long$ts, "tzone")
  if (!is.null(tz_attr) && nzchar(tz_attr) && tz_attr != "UTC")
    warning("run_L1_L2 [", site_tag, "]: L0_long$ts tzone attribute is '",
            tz_attr, "', expected 'UTC'. Proceeding but verify tz conversion.")
  
  fs::dir_create(out_dir_L0)
  fs::dir_create(out_dir_L1)
  fs::dir_create(out_dir_L2)
  
  ## Save L0 -------------------------------------------------------------------
  l0_path <- file.path(out_dir_L0, l0_fname)
  saveRDS(L0_long, l0_path)
  message(site_tag, " L0 saved: ", l0_path)
  
  message(site_tag, " L0 summary:")
  print(
    L0_long %>%
      dplyr::group_by(series) %>%
      dplyr::summarise(
        n      = dplyr::n(),
        ts_min = min(ts, na.rm = TRUE),
        ts_max = max(ts, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      dplyr::arrange(series)
  )
  
  ## Optional per-series RAW RDS (consumed by 02_ scripts via prep_for_dcr) ---
  if (isTRUE(write_per_series)) {
    fs::dir_create(raw_dir)
    series_vec <- sort(unique(as.character(L0_long$series)))
    message(site_tag, " writing ", length(series_vec),
            " per-series RAW RDS to: ", raw_dir)
    pb_ser   <- utils::txtProgressBar(min = 0, max = length(series_vec), style = 3, width = 50)
    pb_i_ser <- 0L
    for (s in series_vec) {
      pb_i_ser <- pb_i_ser + 1L
      utils::setTxtProgressBar(pb_ser, pb_i_ser)
      df_s <- L0_long %>%
        dplyr::filter(series == s) %>%
        dplyr::select(series, ts, value) %>%
        dplyr::arrange(ts)
      saveRDS(df_s, file.path(raw_dir, paste0(s, ".rds")))
    }
    close(pb_ser)
    message("")  # newline after txtProgressBar
    message("  per-series RAW RDS done.")
  }
  
  ## L0 -> L1 -----------------------------------------------------------------
  L0_for_L1 <- L0_long %>%
    dplyr::select(series, ts, value) %>%
    dplyr::arrange(series, ts) %>%
    dplyr::distinct(series, ts, .keep_all = TRUE) %>%
    dplyr::mutate(ts = format(ts, "%Y-%m-%d %H:%M:%S"))
  
  stopifnot(!any(is.na(L0_for_L1$ts)))
  stopifnot(all(nchar(L0_for_L1$ts) == 19L))
  
  L1 <- treenetproc::proc_L1(
    data_L0     = L0_for_L1,
    reso        = reso_min,
    input       = "long",
    date_format = "%Y-%m-%d %H:%M:%S",
    tz          = tz_use
  )
  
  l1_path <- file.path(out_dir_L1, l1_fname)
  saveRDS(L1, l1_path)
  message(site_tag, " L1 saved: ", l1_path)
  
  ## L1 -> L2 -----------------------------------------------------------------
  L2_auto <- treenetproc::proc_dendro_L2(
    dendro_L1   = L1,
    temp_L1     = temp_L1,
    plot        = FALSE,
    plot_export = FALSE
  ) %>%
    dplyr::arrange(series, ts) %>%
    dplyr::mutate(ts = lubridate::with_tz(ts, tzone = tz_use))
  
  l2_path <- file.path(out_dir_L2, l2_fname)
  saveRDS(L2_auto, l2_path)
  message(site_tag, " L2 saved: ", l2_path)
  
  message(site_tag, " L2 summary:")
  print(
    L2_auto %>%
      dplyr::group_by(series) %>%
      dplyr::summarise(
        n      = dplyr::n(),
        ts_min = min(ts, na.rm = TRUE),
        ts_max = max(ts, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      dplyr::arrange(series)
  )
  
  invisible(list(L0 = L0_long, L1 = L1, L2 = L2_auto))
}


#' Run 'treenetproc' L1 processing per variable
#'
#' Runs `treenetproc::proc_L1()` independently on each variable in `vars` and
#' full-joins the results back on (`series`, `ts`). Static columns are
#' optionally re-joined. Requires the suggested package 'treenetproc'
#' (GitHub: `treenet/treenetproc`). `multi_proc_L1()` is the original
#' DendroMatic name, kept as an exported alias.
#'
#' @param df Long data.frame with columns `series`, `timevar` and `vars`.
#' @param vars Character vector of value columns to process.
#' @param timevar Name of the timestamp column.
#' @param reso Output resolution in minutes (passed to `proc_L1`).
#' @param tz Timezone (passed to `proc_L1`).
#' @param date_format Timestamp format (passed to `proc_L1`).
#' @param drop_static If `TRUE`, static (non-processed) columns are dropped
#'   instead of re-joined.
#' @param parallel If `TRUE` and 'future.apply' is installed, variables are
#'   processed in parallel.
#' @return A time-aligned L1 data.frame with columns `series`, `ts`, the
#'   processed `vars`, and (unless `drop_static`) the static columns.
#' @export
dm_proc_l1 <- multi_proc_L1

#' Run the L0 to L1 to L2 site pipeline backbone
#'
#' Shared backbone for site processing scripts: validates the L0 input,
#' processes L1 and L2 via 'treenetproc' (optionally with a temperature L1),
#' and writes RDS outputs to the supplied directories. Requires the suggested
#' package 'treenetproc'. `run_L1_L2()` is the original DendroMatic name,
#' kept as an exported alias.
#'
#' @param L0_long L0 long data.frame (`series`, `ts`, `value`).
#' @param reso_min Measurement resolution in minutes.
#' @param site_tag Site code used in output filenames (e.g. `"HOL"`).
#' @param out_dir_L0,out_dir_L1,out_dir_L2 Output directories for the L0, L1
#'   and L2 RDS files. All writes go only to these user-supplied paths.
#' @param temp_L1 Optional temperature L1 object for `proc_dendro_L2`.
#' @param tz_use Timezone used throughout.
#' @param write_per_series If `TRUE`, additionally writes one RDS per series.
#' @param raw_dir Directory for per-series raw dumps.
#' @param l0_fname,l1_fname,l2_fname Output filenames.
#' @return Invisibly, a list with elements `L0`, `L1` and `L2`.
#' @export
dm_run_pipeline <- run_L1_L2
