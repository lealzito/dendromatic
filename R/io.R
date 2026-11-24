#' @rdname dm_read_table
#' @export
read_any_table <- function(fp, sheet = NULL) {
  # Read a delimited text file or Excel workbook into a data.frame.
  # Dispatches on file extension: xlsx/xls, tsv, csv/txt.
  # For csv/txt, delimiter is inferred via .guess_delim_line() on the first
  # line of the NORMALIZED text (see .normalize_text_source).
  if (is.na(fp) || !nzchar(fp)) stop("read_any_table: got NA or empty filepath.")
  ext <- tolower(tools::file_ext(fp))
  if (ext %in% c("xlsx", "xls")) {
    out <- readxl::read_excel(fp, sheet = sheet)
    return(as.data.frame(out))
  }
  if (ext %in% c("tsv", "csv", "txt")) {
    ns  <- .normalize_text_source(fp)
    dlm <- if (ext == "tsv") "\t" else .guess_delim_line(ns$first_line)
    return(readr::read_delim(ns$src, delim = dlm,
                             show_col_types = FALSE, progress = FALSE))
  }
  stop("read_any_table: unsupported extension '", ext, "'.")
}

merge_L2_rds <- function(input_dir, out_path = NULL, tz_parse = "UTC") {
  # Merge all per-series L2 RDS files in input_dir into one long data.frame.
  # Automatically excludes derived / summary files (L2_daily, phase_daily, etc.).
  # If out_path is provided, saves the merged result as RDS before returning.
  stopifnot(dir.exists(input_dir))
  
  files_all  <- list.files(input_dir, pattern = "\\.rds$", full.names = TRUE)
  if (length(files_all) == 0L) stop("merge_L2_rds: no .rds files found in: ", input_dir)
  
  base_names <- basename(files_all)
  drop_pat   <- grepl("L2_(daily|hourly|long|merged)", base_names) |
    grepl("phase_daily",    base_names) |
    grepl("avg_twd_times",  base_names)
  files_all  <- files_all[!drop_pat]
  if (length(files_all) == 0L)
    stop("merge_L2_rds: only derived files found, nothing to merge in: ", input_dir)
  
  n_files  <- length(files_all)
  message("merge_L2_rds: loading ", n_files, " RDS file(s)...")
  pb_merge <- utils::txtProgressBar(min = 0, max = n_files, style = 3, width = 50)
  dfs <- vector("list", n_files)
  for (i_f in seq_along(files_all)) {
    utils::setTxtProgressBar(pb_merge, i_f)
    f  <- files_all[i_f]
    df <- readRDS(f)
    if (!"series" %in% names(df)) df$series <- tools::file_path_sans_ext(basename(f))
    if (!"ts" %in% names(df)) stop("merge_L2_rds: column `ts` missing in: ", basename(f))
    if (is.character(df$ts))        df$ts <- as.POSIXct(df$ts, tz = tz_parse)
    if (inherits(df$ts, "Date"))    df$ts <- as.POSIXct(df$ts, tz = tz_parse)
    if (!inherits(df$ts, "POSIXct"))
      stop("merge_L2_rds: unsupported `ts` class in: ", basename(f))
    dfs[[i_f]] <- df
  }
  close(pb_merge)
  message("")  # newline after txtProgressBar
  
  merged <- dplyr::bind_rows(dfs)
  if (!is.null(out_path)) saveRDS(merged, out_path)
  merged
}

#### 10. Site pipeline backbone ################################################
##
## run_L1_L2() and build_temp_L1_generic() are shared by all 01_ site scripts.
## They encapsulate the identical L0->L1->L2 processing block that was
## previously copy-pasted across every site, removing the main source of
## structural divergence between scripts.
##
## Timezone contract (enforced here and in every 01_ script):
##   - L0 input  : ts must already be true UTC POSIXct before this function
##                 is called. The caller is responsible for the tz_in -> UTC
##                 conversion using force_tz() + with_tz() (see site scripts).
##   - L1 output : POSIXct UTC, tz attribute = "UTC".
##   - L2 output : POSIXct UTC, tz attribute = "UTC".
##   - Per-series RAW RDS files written to raw_dir inherit the same UTC ts.


## build_temp_L1_generic -------------------------------------------------------
##
## Searches clim_root recursively for xlsx / csv files containing a
## recognizable temperature column and assembles a treenetproc L1 object.
## Replaces the inline build_temp_L1 / build_temp_L1_optional helpers that
## were duplicated in 01_HOL, 01_HOF, 01_GOE.
##
## Arguments:
##   clim_root          character; directory to search for meteo files.
##   site_tag           character; used to build series name "{site_tag}_temp".
##   tz                 timezone passed to proc_L1; default "UTC".
##   reso               integer; resolution in minutes for proc_L1.
##   ts_col_priority    character vector; candidate timestamp column names.
##   temp_col_priority  character vector; candidate temperature column names.
##   out_rds            optional path; if non-NULL, saves temp_L1 to this path.
##
## Returns: treenetproc L1 object, or NULL (with a message) if no usable data.

#' @rdname dm_build_temp_l1
#' @export
build_temp_L1_generic <- function(
    clim_root,
    site_tag,
    tz                = "UTC",
    reso              = 10L,
    ts_col_priority   = c("timestamp_UTC", "ts", "timestamp", "date_time",
                          "datetime", "DateTime", "TIMESTAMP"),
    temp_col_priority = c("Temp_degC_forest", "Ta_degC", "temp",
                          "temperature", "Temp_degC", "Tair", "TA"),
    out_rds           = NULL) {
  .need_treenetproc("dm_build_temp_l1()")
  
  if (!dir.exists(clim_root)) {
    message("build_temp_L1_generic: clim_root not found: ", clim_root,
            ". Returning NULL.")
    return(NULL)
  }
  
  clim_files <- fs::dir_ls(
    path    = clim_root,
    recurse = TRUE,
    type    = "file",
    regexp  = "\\.(csv|CSV|xlsx|XLSX)$"
  )
  
  if (length(clim_files) == 0L) {
    message("build_temp_L1_generic [", site_tag, "]: no meteo files in ",
            clim_root, ". Returning NULL.")
    return(NULL)
  }
  
  read_one_clim <- function(fp) {
    df <- tryCatch(
      if (grepl("\\.xlsx$", fp, ignore.case = TRUE)) {
        suppressWarnings(readxl::read_excel(fp))
      } else {
        suppressWarnings(readr::read_csv(fp, show_col_types = FALSE))
      },
      error = function(e) { message("  skip: ", basename(fp)); NULL }
    )
    if (is.null(df) || nrow(df) == 0L) return(NULL)
    
    nms     <- names(df)
    ts_col  <- ts_col_priority[ts_col_priority %in% nms][1]
    tmp_col <- temp_col_priority[temp_col_priority %in% nms][1]
    if (is.na(ts_col) || is.na(tmp_col)) return(NULL)
    
    ts_raw <- df[[ts_col]]
    ts_pct <- if (inherits(ts_raw, "POSIXt")) {
      lubridate::with_tz(ts_raw, tzone = tz)
    } else {
      parse_ts_auto(ts_raw, tz = tz)
    }
    
    tibble::tibble(
      series = paste0(site_tag, "_temp"),
      ts     = format(as.POSIXct(ts_pct, tz = tz), "%Y-%m-%d %H:%M:%S"),
      value  = .to_num(df[[tmp_col]])
    ) %>%
      dplyr::filter(!is.na(ts), !is.na(value))
  }
  
  temp_L0 <- purrr::map_dfr(clim_files, read_one_clim) %>%
    dplyr::arrange(series, ts) %>%
    dplyr::distinct(series, ts, .keep_all = TRUE)
  
  if (nrow(temp_L0) == 0L) {
    message("build_temp_L1_generic [", site_tag, "]: no parseable temperature ",
            "data found. Returning NULL.")
    return(NULL)
  }
  
  temp_L1 <- treenetproc::proc_L1(
    data_L0     = temp_L0,
    reso        = reso,
    input       = "long",
    date_format = "%Y-%m-%d %H:%M:%S",
    tz          = tz
  )
  
  message("build_temp_L1_generic [", site_tag, "]: L1 range ",
          format(min(temp_L1$ts, na.rm = TRUE)),
          " -- ",
          format(max(temp_L1$ts, na.rm = TRUE)))
  
  if (!is.null(out_rds)) {
    saveRDS(temp_L1, out_rds)
    message("  temp_L1 saved: ", out_rds)
  }
  
  temp_L1
}


#' Read a delimited text file or Excel workbook
#'
#' Extension-dispatched table reader (xlsx/xls, tsv, csv, txt) robust to
#' UTF-16/32 byte-order marks, lone-CR line endings and unknown delimiters
#' (tab, semicolon or comma, inferred from the first line).
#' `read_any_table()` is the original DendroMatic name, kept as an exported
#' alias.
#'
#' @param fp Path to the file.
#' @param sheet Excel sheet name or index (Excel input only).
#' @return A data.frame (Excel) or tibble (delimited text).
#' @export
dm_read_table <- read_any_table

#' Assemble a temperature L1 object from a climate folder
#'
#' Recursively searches `clim_root` for xlsx/csv files with a recognisable
#' timestamp and temperature column and assembles a 'treenetproc' temperature
#' L1 object. Requires the suggested package 'treenetproc'.
#' `build_temp_L1_generic()` is the original DendroMatic name, kept as an
#' exported alias.
#'
#' @param clim_root Root directory searched for climate files.
#' @param site_tag Site code used for the series name.
#' @param tz Timezone of the input timestamps.
#' @param reso Output resolution in minutes.
#' @param ts_col_priority,temp_col_priority Candidate column names tried in
#'   order for the timestamp and temperature columns.
#' @param out_rds Optional path; when given, the result is also saved there.
#' @return A temperature L1 data.frame, or `NULL` when no usable file is
#'   found.
#' @export
dm_build_temp_l1 <- build_temp_L1_generic
