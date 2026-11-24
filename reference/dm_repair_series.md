# Standardise series identifiers to SITE_SpAb### style

Rewrites raw series names to the standard form
`<site>_<SpeciesAbv><number>` (e.g. `"TIL_Ps699"`), extracting species
letters and tree numbers where possible. `repair_series_HOLstyle()` is
the original DendroMatic name, kept as an exported alias.

## Usage

``` r
repair_series_HOLstyle(
  series_vec,
  site_tag,
  default_species_abv = NA_character_
)

dm_repair_series(series_vec, site_tag, default_species_abv = NA_character_)
```

## Arguments

- series_vec:

  Character vector of raw series names.

- site_tag:

  Site code (e.g. `"TIL"`).

- default_species_abv:

  Fallback species code when letters cannot be parsed from a name.

## Value

A tibble with columns `series_old` and `series_new`.
