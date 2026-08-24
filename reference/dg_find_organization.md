# Search for organizations (data producers) on data.gouv.fr

Searches the platform's producers via the v2 `organizations/search`
endpoint and returns a tibble with one row per matching organization,
including its stable 24-hex `id`. That `id` is exactly what you pass to
the `organization` argument of
[`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)
to restrict a catalog search to one producer — or, more conveniently,
you can pass a producer's exact `name` or `slug` to
[`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)
directly and it is resolved for you (see
[`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)).

## Usage

``` r
dg_find_organization(q = NULL, n = 20)
```

## Arguments

- q:

  Optional full-text query matched against organization names,
  descriptions, etc. (server-side). Defaults to `NULL`, meaning no
  filter. When `NULL` the most recently active/popular producers are
  returned.

- n:

  Maximum number of organizations to return. Defaults to `20`. Set to
  `Inf` to retrieve as many as the API allows.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per matching organization and columns:

- `id` — the stable, unique 24-hex producer id (passable to the
  `organization` argument of
  [`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)).
  Always non-`NA`.

- `name` — the producer's display name.

- `slug` — the URL-friendly slug.

- `acronym` — the acronym, or `NA`.

- `description` — the producer's description.

- `datasets` — number of datasets the producer currently publishes.

- `badges` — comma-joined badge kinds (e.g.
  `"public-service, certified"`), or `NA`.

- `business_number_id` — the French SIREN identifier when known, else
  `NA`.

## Details

Useful when you want to *discover* which producers exist, how a
producer's name is spelled, or how many datasets it publishes — before
narrowing a search.

## Examples

``` r
if (FALSE) { # interactive()
# Who publishes rail/mobility data? (server-side ranked search)
orgs <- dg_find_organization(q = "SNCF")
orgs[, c("id", "name", "datasets")]

# Use the resolved id to narrow a catalog search to one producer.
datagouv <- dg_find_organization(q = "data.gouv")
open_data <- dg_find_datasets(organization = datagouv$id[1], n = 5)
}
```
