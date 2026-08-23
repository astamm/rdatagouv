# Read a table's stable address

Returns the stable, unique address of a table downloaded with
[`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)
or
[`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md),
which is stored as an `id` attribute on the table. The address is a URI
of the form
`https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>` (plus
`/&lt;file&gt;` for a file inside a ZIP) and uniquely identifies a table
on the platform, independent of the human-readable catalog titles. It
can be passed directly to
[`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md)
or
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md)
to re-fetch or document that exact table.

## Usage

``` r
dg_table_id(x)
```

## Arguments

- x:

  A table returned by
  [`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md)
  or
  [`dg_refetch()`](https://astamm.github.io/datagouv/reference/dg_refetch.md).

## Value

The composed table id, a string, or `NULL` if `x` carries no id
attribute (e.g. an ordinary data frame).

## Examples

``` r
tbl <- dg_table_id(iris)
```
