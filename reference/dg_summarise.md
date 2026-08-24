# Summarise several datasets

Applies
[`dg_summary()`](https://astamm.github.io/datagouv/reference/dg_summary.md)
to a collection of tables and combines the resulting metrics into a
single tibble. If `datasets` is `NULL`, the first `n` datasets returned
by
[`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)
are downloaded and summarised.

## Usage

``` r
dg_summarise(datasets = NULL, n = 100)
```

## Arguments

- datasets:

  Either a named list of tibbles (each element is a single table, named
  after it), a named list of such lists (as returned by
  [`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md),
  where a ZIP may contribute several tables), a tibble from
  [`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)
  (identified by its `id` column; each dataset is downloaded and
  summarised), a character vector of dataset identifiers (or exact
  titles), or `NULL` (the default) to use the first `n` datasets from
  [`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md).

- n:

  Number of datasets to summarise when `datasets` is `NULL`. Defaults to
  `100`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per table and the columns described in
[`dg_summary()`](https://astamm.github.io/datagouv/reference/dg_summary.md).

## Examples

``` r
# Summarise in-memory tables (no network needed).
dg_summarise(datasets = list(iris = iris, mtcars = mtcars))
#> # A tibble: 2 × 7
#>   dataset size_kb n_vars n_numeric n_non_numeric n_rows prop_missing
#> * <chr>     <dbl>  <int>     <int>         <int>  <int>        <dbl>
#> 1 iris       7.09      5         4             1    150            0
#> 2 mtcars     7.04     11        11             0     32            0

if (FALSE) { # interactive()
# Download and summarise the first datasets of the catalog.
dg_summarise()
}
```
