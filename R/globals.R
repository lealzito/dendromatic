#' @importFrom rlang .data :=
NULL

## Column names used in dplyr/tidyr non-standard evaluation.
utils::globalVariables(c(
  ".join_key", ".sp", ".was_na", "day", "series", "ts", "value", "yr"
))
