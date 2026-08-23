# Download a dataset from data.gouv.fr

Downloads the first tabular resource of a dataset and parses it into a
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with `format_tibble()`. The dataset is identified by its `id`, which is
the stable, unique identifier returned in the `id` column of
[`dg_list_datasets()`](https://astamm.github.io/datagouv/reference/dg_list_datasets.md).
For backwards compatibility, an exact title is also accepted and is
resolved by searching the platform.

## Usage

``` r
dg_pull_dataset(id, all_files = FALSE, remove_na = FALSE)
```

## Arguments

- id:

  The identifier of the dataset to download (or, as a fallback, its
  exact title). Identifiers are unique and stable, so they are the
  recommended way to address a dataset; titles can collide or change
  over time.

- all_files:

  Whether to return one table per parseable file as a named list instead
  of a single tibble. Defaults to `FALSE`. For a single-file resource
  the result is the same either way (a single tibble); for a multi-file
  ZIP, `TRUE` keeps every parseable file, one named element each.

- remove_na:

  Whether to drop rows containing any `NA` value (passed to
  `format_tibble()`). Defaults to `FALSE`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
(default) or, when `all_files = TRUE` and the resource is a multi-file
ZIP, a named list of tibbles (one element per parseable file, named
after it). Every table carries its stable, unique address as an `id`
attribute — a URI of the form
`https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>` (plus
`/&lt;file&gt;` for a file inside a ZIP) — re-fetchable with
[`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md)
and readable with
[`dg_table_id()`](https://astamm.github.io/datagouv/reference/dg_table_id.md).

## Details

By default a single tibble is returned: the first resource that can
actually be parsed as a table (for a multi-file ZIP, the first parseable
file). The table's stable, unique address is attached as an `id`
attribute, readable with
[`dg_table_id()`](https://astamm.github.io/datagouv/reference/dg_table_id.md)
and accepted directly by
[`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md)
and
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md).
Set `all_files = TRUE` to instead receive one table per parseable file
as a named list (useful for a ZIP holding several files).

## Examples

``` r
if (FALSE) { # interactive()
id <- "6397c0ff56d3963118a18345"
tbl <- dg_pull_dataset(id)
head(tbl)
dg_table_id(tbl)
}
```
