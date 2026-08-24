# Find topics (themes) on data.gouv.fr

Searches the platform's themes via the v2 `topics/search` endpoint and
returns a tibble with one row per matching topic, including its stable
24-hex `id`. That `id` is what you pass to the `topic` argument of
[`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)
to restrict a catalog search to one theme. (data.gouv does not resolve
topic names/slugs to ids inside
[`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md),
so this finder is the way to discover a theme and get its id.)

## Usage

``` r
dg_find_topics(q = NULL, n = 20, elements = FALSE)
```

## Arguments

- q:

  Optional full-text query matched against topic names/descriptions
  (server-side). Defaults to `NULL`, meaning no filter.

- n:

  Maximum number of topics to return. Defaults to `20`. Set to `Inf` to
  retrieve as many as the API allows.

- elements:

  Whether to fetch each topic's `elements` subsection (one extra request
  per topic, an N+1 crawl) to fill the `n_datasets`, `n_dataservices`
  and `n_reuses` counts exactly. Defaults to `FALSE`, in which case
  `n_elements` is the topic's declared total and the breakdown counts
  are `NA`.

## Value

A
[`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html)
with one row per matching topic and columns:

- `id` — the stable, unique 24-hex topic id (passable to the `topic`
  argument of
  [`dg_find_datasets()`](https://astamm.github.io/datagouv/reference/dg_find_datasets.md)).
  Always non-`NA`.

- `name` — the topic's display name.

- `slug` — the URL-friendly slug.

- `description` — the topic's description.

- `tags` — comma-joined tags, or `NA`.

- `featured` — whether the platform features this topic.

- `n_elements` — number of elements (datasets, reuses, dataservices,
  ...) grouped under the topic, from the API.

- `n_datasets`, `n_dataservices`, `n_reuses` — per-kind counts, only
  when `elements = TRUE` (else `NA`).

## Details

Useful when you want to *discover* which curated themes exist and how
many elements (datasets, reuses, dataservices...) they group, before
narrowing a search — e.g. browse "Mobilité", "Environnement", "Énergie".

## Examples

``` r
if (FALSE) { # interactive()
# Browse the curated themes.
dg_find_topics(n = 5)[, c("id", "name", "n_elements")]

# Narrow a catalog search to one theme once you have its id.
mob <- dg_find_topics(q = "mobilité")
dg_find_datasets(topic = mob$id[1], n = 10)
}
```
