# List datasets available on data.gouv.fr

Collects the datasets published on the data.gouv.fr platform, searching
the catalog via the v2 `datasets/search` endpoint (the same one the web
interface uses). By default it returns the first `n` datasets; use `q`
to search titles and descriptions server-side instead of enumerating the
whole catalog.

## Usage

``` r
dg_list_datasets(
  q = NULL,
  n = 1000,
  format = catalog_formats(),
  schema_only = FALSE,
  organization = NULL,
  geozone = NULL,
  access_type = NULL,
  license = NULL,
  tag = NULL,
  granularity = NULL,
  last_update = NULL,
  producer_type = NULL,
  resources = FALSE
)
```

## Arguments

- q:

  Optional full-text search query. When given, only datasets matching
  `q` are returned (the API performs the search). Defaults to `NULL`,
  meaning no filtering.

- n:

  Maximum number of datasets to return. Defaults to `1000`. Set to `Inf`
  to retrieve as many as the API allows (capped at 10,000).

- format:

  Optional character vector of resource formats to keep. Only datasets
  that have at least one resource in one of these formats are returned.
  The v2 API matches multiple values when passed as repeated parameters
  (a server-side union). Defaults to the full set of officially tabular
  formats (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`).

- schema_only:

  Whether to keep only datasets that declare a data schema (see
  `has_schema`). Defaults to `FALSE`. v2 has no boolean "declares any
  schema" server-side filter, so this filters client-side and only works
  reliably when `resources = TRUE` fills `has_schema`.

- organization:

  Optional data producer, matched server-side by its **24-hex
  `organization` id** (as shown in the `organization` column or on the
  dataset page). Unlike v1, the v2 search API does *not* accept the
  organization slug or name here (a slug yields zero matches). Defaults
  to `NULL`.

- geozone:

  Optional territorial filter, e.g. `"country:fr"` or
  `"fr:commune:75056"`. Defaults to `NULL`.

- access_type:

  Optional access filter, `"open"` or `"restricted"`. Defaults to
  `NULL`.

- license:

  Optional license filter (a license slug, e.g. `"lov2"` or
  `"odc-odbl"`). Defaults to `NULL`.

- tag:

  Optional tag filter, e.g. `"mobilite"`. Defaults to `NULL`.

- granularity:

  Optional spatial granularity filter, e.g. `"fr:commune"`. Defaults to
  `NULL`.

- last_update:

  Optional update-recency filter: `"last_30_days"`, `"last_12_months"`
  or `"last_3_years"`. Defaults to `NULL`.

- producer_type:

  Optional producer-type filter (a facet value, e.g. `"public-service"`
  or `"local-authority"`). Defaults to `NULL`.

- resources:

  Whether to fetch each dataset's resources subsection (one extra
  request per dataset) so the exact `n_resources`, `formats`,
  `has_table` and `has_schema` columns can be computed. Defaults to
  `FALSE`, in which case those columns are `NA`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per matching dataset. The `title` and `id` columns are
always non-`NA`; the `id` column holds the stable, unique dataset
identifier used to address a dataset with
[`dg_pull_dataset()`](https://astamm.github.io/datagouv/reference/dg_pull_dataset.md).
When `resources = TRUE`, the columns also include `n_resources` (number
of files/resources), `formats` (distinct file formats found among them),
`has_table` (whether at least one resource is in a format this package
can parse) and `has_schema` (whether at least one resource carries a
pointer to a declared data schema, whose per-variable documentation is
exposed by
[`dg_schema()`](https://astamm.github.io/datagouv/reference/dg_schema.md));
these are `NA` otherwise.

## Details

Fetching *every* dataset on the platform means paging through many
thousands of records in many HTTP requests and is both slow and fragile,
so the default is deliberately bounded. Set `n = Inf` to return as many
matches as the API allows. Note that data.gouv caps a search at 10,000
matches, so an un-narrowed `n = Inf` crawl stops at that cap even though
the platform holds more. For large or infinite `n` the crawl scales its
page size up (to ~250) so a full 10,000-row crawl takes ~40 requests,
not hundreds.

Because v2 search embeds rich per-dataset metadata inline, the returned
tibble includes columns such as `license`, `quality_score`, `views`,
`access_type`, `frequency`, `temporal_start`/`temporal_end`, `archived`
and `featured` that help judge whether a dataset is worth pulling.

v2 search does NOT inline each dataset's resources (they are subsection
pointers), so the exact resource-based columns `n_resources`, `formats`,
`has_table` and `has_schema` can no longer be computed without one extra
request per dataset (an N+1 crawl). By default these are `NA`; set
`resources = TRUE` to opt into the per-dataset resource fetch and fill
them exactly.

## Examples

``` r
if (FALSE) { # interactive()
datasets <- dg_list_datasets(n = 20)
head(datasets)

# Search server-side instead of downloading the whole catalog.
cycle <- dg_list_datasets(q = "vélo", n = 10)

# Only datasets that carry at least one parquet resource; the v2 API matches
# multiple formats as a server-side union.
compact <- dg_list_datasets(format = "parquet", n = 10)

# Only datasets with a declared schema (documented variables). Resolving
# `has_schema` exactly needs the per-dataset resource fetch.
documented <- dg_list_datasets(schema_only = TRUE, resources = TRUE, n = 10)

# Narrow by producer (server-side id filter) and territory.
fr <- dg_list_datasets(organization = "534fff91a3a7292c64a77f53",
                       geozone = "country:fr", n = 10)
}
```
