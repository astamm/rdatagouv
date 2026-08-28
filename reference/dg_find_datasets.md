# Find datasets available on data.gouv.fr

Collects the datasets published on the data.gouv.fr platform, searching
the catalog via the v2 `datasets/search` endpoint (the same one the web
interface uses). By default it returns the first `n` datasets; use `q`
to search titles and descriptions server-side instead of enumerating the
whole catalog.

## Usage

``` r
dg_find_datasets(
  q = NULL,
  n = 1000,
  format = catalog_formats(),
  schema_only = FALSE,
  organization = NULL,
  geozone = NULL,
  access_type = NULL,
  license = NULL,
  tag = NULL,
  topic = NULL,
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
  schema" server-side filter, so this filters client-side on
  `has_schema`, which itself needs the per-dataset resource fetch. When
  `schema_only` is set without `resources = TRUE`, this function forces
  `resources = TRUE` (with an informative message about the extra
  requests) so the filter actually runs.

- organization:

  Optional data producer, matched server-side. Pass either the
  producer's **24-hex `organization` id** (as shown in the
  `organization` column of the returned tibble or on the dataset page),
  or its exact `name` or `slug` — a human-readable value is resolved to
  its id automatically via
  [`dg_find_organization()`](https://astamm.github.io/rdatagouv/reference/dg_find_organization.md)
  (only an exact match is auto-resolved, so results stay reproducible;
  an ambiguous or unmatched value stops with the candidate list). Note
  that, unlike v1, the v2 search API itself only accepts the id (a raw
  slug yields zero matches), which is why the package resolves
  names/slugs for you. Defaults to `NULL`.

- geozone:

  Optional territorial filter, passed as a territory code of the form
  `"<scope>:<code>"`, e.g. `"country:fr"`, `"country-group:ue"`,
  `"country-subset:fr:metro"`, `"fr:region:..."`,
  `"fr:departement:974"`, `"fr:epci:..."`, `"fr:commune:75056"`,
  `"fr:arrondissement:..."`, `"fr:canton:..."`, `"fr:collectivite:..."`,
  `"fr:iris:..."` or `"poi:..."`, or the bare
  `"country"`/`"country-group"`/`"country-subset"` scope with an omitted
  code for pan-national groupings. Accepted territory codes are
  open-ended (any INSEE code for the relevant scope), so this argument
  is not enumerated; only the format is validated. Defaults to `NULL`.

- access_type:

  Optional access filter. One of `"open"` (freely downloadable) or
  `"restricted"` (access requires approval). Defaults to `NULL`.

- license:

  Optional license filter, one of the exhaustive license slugs `"lov2"`,
  `"notspecified"`, `"fr-lo"`, `"odc-odbl"`, `"other-at"`, `"cc-by"`,
  `"other-pd"`, `"cc-by-sa"`, `"other-open"`, `"odc-by"`, `"cc-zero"`,
  `"odc-pddl"`. Defaults to `NULL`.

- tag:

  Optional tag filter. Tags form an open vocabulary (dynamic facets), so
  any free-form tag such as `"mobilite"` is accepted and is not
  enumerated or validated. Defaults to `NULL`.

- topic:

  Optional topic filter, the **24-hex `topic` id** of a theme (found via
  [`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md)).
  Only datasets grouped under that topic are returned. Matched
  server-side as a single-valued filter, so pass exactly one id. Topic
  ids form an open vocabulary (themes are created dynamically), so this
  is not enumerated or validated. Unlike `organization`, a
  human-readable topic name/slug is not auto-resolved — use
  [`dg_find_topics()`](https://astamm.github.io/rdatagouv/reference/dg_find_topics.md)
  to discover a theme and get its id. Defaults to `NULL`.

- granularity:

  Optional spatial granularity filter, one of the exhaustive values
  `"other"`, `"fr:commune"`, `"country"`, `"fr:epci"`,
  `"fr:departement"`, `"poi"`, `"fr:region"`, `"fr:canton"`,
  `"country-group"`, `"country-subset"`, `"fr:collectivite"`,
  `"fr:iris"`, `"fr:arrondissement"`. Defaults to `NULL`.

- last_update:

  Optional update-recency filter, one of `"last_30_days"`,
  `"last_12_months"` or `"last_3_years"`. Defaults to `NULL`.

- producer_type:

  Optional producer-type filter, one of the exhaustive values
  `"public-service"`, `"local-authority"`, `"company"`,
  `"not-specified"`, `"user"` or `"association"`. Defaults to `NULL`.

- resources:

  Whether to fetch each dataset's resources subsection (one extra
  request per dataset) so the exact `n_resources`, `formats`,
  `has_table` and `has_schema` columns can be computed. Defaults to
  `FALSE`, in which case those columns are `NA`. Automatically forced to
  `TRUE` when `schema_only = TRUE` (see `schema_only`).

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per matching dataset. The `title` and `id` columns are
always non-`NA`; the `id` column holds the stable, unique dataset
identifier used to address a dataset with
[`dg_pull_dataset()`](https://astamm.github.io/rdatagouv/reference/dg_pull_dataset.md).
When `resources = TRUE`, the columns also include `n_resources` (number
of files/resources), `formats` (a list-column whose elements are the
distinct file formats found among them), `has_table` (whether at least
one resource is in a format this package can parse) and `has_schema`
(whether at least one resource carries a pointer to a declared data
schema, whose per-variable documentation is exposed by
[`dg_schema()`](https://astamm.github.io/rdatagouv/reference/dg_schema.md));
these are `NA` when `resources = FALSE` (the default) unless
`schema_only = TRUE`, which forces the fetch so `has_schema` is filled
and the filter can run.

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
datasets <- dg_find_datasets(n = 20)
head(datasets)

# Search server-side instead of downloading the whole catalog.
cycle <- dg_find_datasets(q = "vélo", n = 10)

# Only datasets that carry at least one parquet resource; the v2 API matches
# multiple formats as a server-side union.
compact <- dg_find_datasets(format = "parquet", n = 10)

# Only datasets with a declared schema (documented variables). `schema_only`
# forces the per-dataset resource fetch itself (~30s for n = 1000), so
# `resources = TRUE` is optional here.
documented <- dg_find_datasets(schema_only = TRUE, n = 10)

# Narrow by producer and territory. A producer may be given by its 24-hex
# id or by its exact slug/name (resolved for you), and by geozone.
fr <- dg_find_datasets(organization = "sncf",
                       geozone = "country:fr", n = 10)

# Only datasets grouped under one topic (find its id with dg_find_topics()).
mob <- dg_find_topics(q = "mobilité")
dg_find_datasets(topic = mob$id[1], n = 10)
}
```
