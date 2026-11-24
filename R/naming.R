#### 2. Series naming utilities ################################################


#' @rdname dm_repair_series
#' @export
repair_series_HOLstyle <- function(series_vec,
                                   site_tag,
                                   default_species_abv = NA_character_) {
  # Standardize a vector of series identifiers to HOL style: SITE_SpAb###
  # e.g. "TIL_Ps699". Returns a tibble with columns series_old and series_new.
  #
  # series_vec          : character vector of raw series names
  # site_tag            : 3-character site code, e.g. "TIL"
  # default_species_abv : fallback species code when letters cannot be parsed
  target_pat <- paste0("^", site_tag, "_[A-Za-z]{2}[0-9]+$")
  series_vec <- as.character(series_vec)
  ok <- stringr::str_detect(series_vec, target_pat)
  
  if (all(ok)) {
    return(tibble::tibble(series_old = series_vec, series_new = series_vec))
  }
  
  digits     <- stringr::str_extract(series_vec, "[0-9]+$")
  letters_raw <- stringr::str_extract(series_vec, "(?<=_)[A-Za-z]+")
  
  sp2 <- dplyr::case_when(
    !is.na(letters_raw) & nchar(letters_raw) >= 2 ~
      paste0(toupper(substr(letters_raw, 1, 1)), tolower(substr(letters_raw, 2, 2))),
    TRUE ~ default_species_abv
  )
  
  # Handle known legacy code "PISY" -> "Ps"
  sp2 <- ifelse(!is.na(letters_raw) & toupper(letters_raw) == "PISY", "Ps", sp2)
  
  series_new <- ifelse(
    !is.na(digits) & !is.na(sp2),
    paste0(site_tag, "_", sp2, digits),
    series_vec
  )
  
  tibble::tibble(series_old = series_vec, series_new = series_new)
}


#' Standardise series identifiers to SITE_SpAb### style
#'
#' Rewrites raw series names to the standard form
#' `<site>_<SpeciesAbv><number>` (e.g. `"TIL_Ps699"`), extracting species
#' letters and tree numbers where possible. `repair_series_HOLstyle()` is the
#' original DendroMatic name, kept as an exported alias.
#'
#' @param series_vec Character vector of raw series names.
#' @param site_tag Site code (e.g. `"TIL"`).
#' @param default_species_abv Fallback species code when letters cannot be
#'   parsed from a name.
#' @return A tibble with columns `series_old` and `series_new`.
#' @export
dm_repair_series <- repair_series_HOLstyle
