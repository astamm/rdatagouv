# Glimpse the metadata of a dataset on data.gouv.fr

Surfaces the dataset-level health and engagement metadata that the v2
API embeds inline but the v1 fetch path does not expose — the bridge
between *discover*
([`dg_find_datasets()`](https://astamm.github.io/rdatagouv/reference/dg_find_datasets.md))
and *judge*
([`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md)'s
column documentation). It reports the dataset's `quality` score and
flags, its `metrics` (views, downloads, followers, ...) and its context
(organization, license, frequency, temporal/spatial coverage, access
type), helping a user decide whether a dataset is worth pulling.

## Usage

``` r
dg_glimpse(id, table = NULL)
```

## Arguments

- id:

  A dataset identifier (24-hex), a composed table id, or a table
  returned by
  [`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md)/[`dg_refetch()`](https://astamm.github.io/rdatagouv/reference/dg_refetch.md)
  (its `id` attribute is read).

- table:

  Whether to also include the dataset's list of resources (from the v2
  resources subsection, one extra request per dataset). `NULL` or
  `FALSE` (the default) skips the per-resource fetch; `TRUE` includes
  it.

## Value

A list with the v2-inline metadata:

- `quality`: a list with `score` (0-1) and boolean flags (`license`,
  `temporal_coverage`, `spatial`, `update_frequency`,
  `dataset_description_quality`).

- `metrics`: views, resources_downloads, followers, discussions, reuses,
  dataservices.

- `context`: organization (name/slug/id), license, frequency,
  temporal_coverage, spatial/granularity, access_type, archived,
  featured.

- `resources` (only when `table = TRUE`): the list of resource objects.

## Details

`id` composes naturally with the rest of the package: it may be a
dataset id (24-hex), a composed table id or a pulled table (whose `id`
attribute is read), so a dataset discovered or pulled elsewhere can be
glimpsed directly.

## Examples

``` r
if (FALSE) { # interactive()
g <- dg_glimpse("6a6be5976a05df136d48fb7a")
g$quality
g$metrics
}
```
