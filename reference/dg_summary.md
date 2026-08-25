# Compute summary metrics for a dataset

Computes key metrics describing a parsed dataset: its in-memory weight
in kilobytes, the number of variables, the number of numeric and
non-numeric variables, the number of rows and the proportion of missing
values.

## Usage

``` r
dg_summary(x, name = NULL)
```

## Arguments

- x:

  A data frame or tibble (a single table, e.g. one element of the list
  returned by
  [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)).

- name:

  An optional label attached to the result (e.g. the dataset title).
  When `NULL` (the default), the label is taken from the expression
  passed to `x` when possible.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with a single row and the following columns: `dataset`, `size_kb`,
`n_vars`, `n_numeric`, `n_non_numeric`, `n_rows` and `prop_missing`.

## Examples

``` r
dg_summary(iris, name = "iris")
#> # A tibble: 1 × 7
#>   dataset size_kb n_vars n_numeric n_non_numeric n_rows prop_missing
#>   <chr>     <dbl>  <int>     <int>         <int>  <int>        <dbl>
#> 1 iris       7.09      5         4             1    150            0
```
