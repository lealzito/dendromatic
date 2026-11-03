## Every dm_* export is byte-identical to its original DendroMatic name.
test_that("dm_* aliases are identical to the original functions", {
  pairs <- list(
    c("dm_build_l0",      "raw_to_L0"),
    c("dm_proc_l1",       "multi_proc_L1"),
    c("dm_run_pipeline",  "run_L1_L2"),
    c("dm_clean_series",  "apply_breaks_and_shift"),
    c("dm_merge_series",  "merge_series"),
    c("dm_pdmd_extrema",  "compute_pdmd_extrema_tz"),
    c("dm_build_sfw",     "build_sfw"),
    c("dm_match_lwp",     "match_lwp_to_sfw"),
    c("dm_build_temp_l1", "build_temp_L1_generic"),
    c("dm_read_table",    "read_any_table"),
    c("dm_repair_series", "repair_series_HOLstyle"),
    c("dm_species_lut",   "default_species_lut")
  )
  ns <- asNamespace("dendromatic")
  for (p in pairs) {
    expect_identical(get(p[1], envir = ns), get(p[2], envir = ns),
                     label = paste(p[1], "==", p[2]))
  }
})
