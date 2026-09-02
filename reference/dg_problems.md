# Return the parsing problems of a downloaded table

Returns the data frame of parsing issues that
[vroom](https://vroom.tidyverse.org/) encountered while reading a table
downloaded with
[`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
or
[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md).
These are vroom's "parsing issues" (rows that could not be converted to
the inferred column type, e.g. a mostly-padded ISO date column holding a
few non-padded values like `2021-7-01`).

## Usage

``` r
dg_problems(x)
```

## Arguments

- x:

  A table returned by
  [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)
  or
  [`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md).

## Value

A data frame with columns `row`, `col`, `expected` and `actual` (one row
per parsing issue), or `NULL` if there were none.

## Details

The noisy per-cell warnings themselves are suppressed by default during
a pull; use this accessor to inspect what happened. The problems live in
the `rdatagouv_problems` attribute of the table. Returns `NULL` when the
table carries no recorded problems (or when `x` is an ordinary data
frame).

## Examples

``` r
dg_problems(iris)
#> NULL
```
