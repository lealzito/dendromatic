# Read a delimited text file or Excel workbook

Extension-dispatched table reader (xlsx/xls, tsv, csv, txt) robust to
UTF-16/32 byte-order marks, lone-CR line endings and unknown delimiters
(tab, semicolon or comma, inferred from the first line).
`read_any_table()` is the original DendroMatic name, kept as an exported
alias.

## Usage

``` r
read_any_table(fp, sheet = NULL)

dm_read_table(fp, sheet = NULL)
```

## Arguments

- fp:

  Path to the file.

- sheet:

  Excel sheet name or index (Excel input only).

## Value

A data.frame (Excel) or tibble (delimited text).
