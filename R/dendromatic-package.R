#' @keywords internal
"_PACKAGE"

#' @importFrom dplyr %>%
NULL

## treenetproc is Suggests (GitHub-only, not on CRAN): every call site is
## guarded by .need_treenetproc(). Install via
## remotes::install_github("treenet/treenetproc").
.need_treenetproc <- function(fun = "this function") {
  if (!requireNamespace("treenetproc", quietly = TRUE)) {
    stop(fun, " requires the 'treenetproc' package (GitHub-only). ",
         "Install it with remotes::install_github(\"treenet/treenetproc\").",
         call. = FALSE)
  }
}
