# Topic support — implementation sketch

Implements the two additions recommended in the v2-search assessment:

1. a `topic =` filter argument on `dg_find_datasets()` (server-side, like `organization`), and
2. a new exported finder `dg_find_topics()` (analogous to `dg_find_organization()`) so users can discover themes and obtain a stable 24-hex topic id to pass to that filter.

Grounded against the live API on 2026-08-24: `datasets/search?topic=<id>` is a valid
server-side filter (verified: returns `total` hits), and `topics/search` uses the exact same
pointer-pagination envelope (`{data, page, page_size, total, next_page, previous_page, facets}`)
as `organizations/search`, so it reuses the package's existing crawler without new machinery.

---

## 1. `topic =` filter on `dg_find_datasets()`

The v2 `datasets/search` endpoint already accepts `topic` (a topic's 24-hex id) as a
single-valued server-side filter — the same shape as `organization`, `geozone`, etc. This threads
straight through the existing filter mechanism.

### 1a. `R/utils.R` — thread `topic` through the search functions

Add `topic = NULL` to both `fetch_search_page()` and `fetch_search_all()`, and include it in the
`single` list of single-valued params inside `fetch_search_page()`:

```r
fetch_search_page <- function(
  url = datagouv_search_url(),
  page_size = 100,
  q = NULL,
  format = catalog_formats(),
  organization = NULL,
  geozone = NULL,
  access_type = NULL,
  license = NULL,
  tag = NULL,
  granularity = NULL,
  last_update = NULL,
  producer_type = NULL,
  topic = NULL,          # <-- new
  schema = NULL
) {
  ...
  single <- c(
    args,
    list(
      organization = organization,
      geozone = geozone,
      access_type = access_type,
      license = license,
      tag = tag,
      granularity = granularity,
      last_update = last_update,
      producer_type = producer_type,
      topic = topic,      # <-- new
      schema = schema
    )
  )
  ...
}
```

`fetch_search_all()` gains the same `topic = NULL` argument and forwards it in its
`do.call(fetch_search_page, ...)` call (check the exact forwarding call at the bottom of
`fetch_organization`-style code — the datasets crawler forwards the filter args to
`fetch_search_page()`; `topic` must be added there too). No pagination changes; `topic` rides
each page's query string like the other single-valued filters.

### 1b. `R/dg-find-datasets.R`

- Add `topic = NULL` to the signature (alphabetical position: after `tag`, before `granularity`,
  matching the argument-ordering style of the existing param list).
- Add it to `filter_args` in the body:

```r
  filter_args <- list(
    organization = resolve_organization_id(organization),
    geozone = geozone,
    access_type = access_type,
    license = license,
    tag = tag,
    topic = topic,            # <-- new
    granularity = granularity,
    last_update = last_update,
    producer_type = producer_type
  )
```

- **No validation in `validate_filter_args()`.** `topic` is a 24-hex id from an *open* set
  (dynamically created topics, like `tag`/`geozone`), so it is deliberately **not** added to
  `dg_filter_vocabularies`. Only `NULL` (no filter) or a single topic id is accepted by the
  server; a malformed id simply yields zero hits server-side. Optionally add a light guard:
  if `topic` is non-`NULL` but not a 24-hex id and not a topic `slug`/`name`, stop early — but
  unlike `organization`, there is no cheap id resolution endpoint to auto-resolve names, so keep
  `topic` strictly id-in / id-out and let `dg_find_topics()` be the name-discovery path. (See the
  design note below.)

- Roxygen `@param topic` documenting it as the single-valued topic id filter, cross-referring
  [dg_find_topics()]:

```r
#' @param topic Optional topic filter, the **24-hex `topic` id** of a theme
#'   (found via [dg_find_topics()]). Only datasets grouped under that topic are
#'   returned. Matched server-side as a single-valued filter, so pass exactly one
#'   id. Topic ids form an open vocabulary (they are created dynamically), so
#'   this is not enumerated or validated. Defaults to `NULL`.
```

- Add an `@examplesIf interactive()` line:

```r
#' # Only datasets grouped under one topic (find its id with dg_find_topics()).
#' mob <- dg_find_topics(q = "mobilité")
#' dg_find_datasets(topic = mob$id[1], n = 10)
```

### 1c. Tests — `tests/testthat/`

Add to an existing find-datasets test file (e.g. mocks in `helper-data.R` already capture the
search envelope):

- A unit test that `topic = "<id>"` is rendered into the request URL as a `topic=<id>` query
  param (reuse the mock-`http_perform` capture pattern used for the other filter args, recording
  the outgoing URL from the request).
- A test that `dg_find_datasets(topic = <id>)` forwards the filter into
  `fetch_search_all()` (spy on the internal call, as the organization filter test does).
- No `validate_filter_args()` test entry needed (topic is deliberately excluded).

---

## 2. `dg_find_topics()` — new exported finder

Mirrors `dg_find_organization()` end to end: a `topics/search` crawler in `R/utils.R` (a
near-clone of the organizations crawler, same pointer-pagination envelope) plus the exported
wrapper in a new `R/dg-find-topics.R`.

### 2a. `R/utils.R` — topics URL + two internal helpers

```r
# URL of the v2 topics/search endpoint (themes grouping datasets/services/etc).
datagouv_topics_url <- function() {
  paste0(datagouv_v2_base_url(), "topics/search/")
}

# Mirrors fetch_organization_page(): one page of v2 topics/search with the same
# pointer-pagination envelope.
fetch_topic_page <- function(
  url = datagouv_topics_url(),
  page_size = 100,
  q = NULL
) {
  args <- list(page_size = page_size)
  if (!is.null(q)) {
    args$q <- q
  }
  frags <- paste0(
    names(args),
    "=",
    vapply(args, function(v) utils::URLencode(as.character(v), reserved = TRUE), character(1))
  )
  url <- append_url_params(url, frags)
  httr2::resp_body_json(http_perform(req_data_gouv(httr2::request(url))))
}

# Mirrors fetch_organizations_all(): follow pointer pagination until `n` topics
# are collected or the last page is reached. Reuses adaptive_page_size().
fetch_topics_all <- function(
  url = datagouv_topics_url(),
  page_size = 100,
  q = NULL,
  n = 20
) {
  all <- list()
  repeat {
    eff_page <- adaptive_page_size(page_size = page_size, n = n, remaining = n - length(all))
    body <- fetch_topic_page(url = url, page_size = eff_page, q = q)
    items <- body$data %||% list()
    if (length(items) == 0) break
    take <- items
    if (!is.infinite(n) && length(all) + length(take) > n) take <- take[seq_len(n - length(all))]
    all <- c(all, take)
    if (!is.infinite(n) && length(all) >= n) break
    np <- body$next_page
    if (is.character(np)) {
      url <- np
    } else if (is.list(np) && !is.null(np$page)) {
      url <- replace_url_page(url, np$page)
    } else {
      break
    }
  }
  all
}

# Fetch a topic's whole `elements` subsection, following pointer pagination the
# same way fetch_topics_all() does (the elements endpoint pages via next_page,
# so a single call can truncate; confirmed live on a topic with 87 elements).
# Returns the raw `data` list of element items. The kind classifier is each
# item's nested `element$class` (Dataset/Reuse/Dataservice/... or NULL for
# external-link entries) -- see the confirmed shape note in section 2b.
fetch_topic_elements <- function(
  topic_id,
  page_size = 100
) {
  url <- paste0(
    datagouv_v2_base_url(), "topics/", topic_id, "/elements/",
    "?page_size=", page_size
  )
  all <- list()
  repeat {
    body <- httr2::resp_body_json(http_perform(req_data_gouv(httr2::request(url))))
    items <- body$data %||% list()
    if (length(items) == 0) break
    all <- c(all, items)
    np <- body$next_page
    if (is.character(np)) {
      url <- np
    } else {
      break
    }
  }
  all
}

# Per-kind element counts for one topic, driving the `elements = TRUE` branch of
# dg_find_topics(). Only Dataset/Reuse/Dataservice classes count; NULL-class
# external-link entries are excluded.
topic_element_counts <- function(topic_id) {
  items <- fetch_topic_elements(topic_id)
  cls <- vapply(
    items,
    function(item) (item$element %||% list())$class %||% NA_character_,
    character(1)
  )
  list(
    n_datasets = sum(cls == "Dataset", na.rm = TRUE),
    n_dataservices = sum(cls == "Dataservice", na.rm = TRUE),
    n_reuses = sum(cls == "Reuse", na.rm = TRUE)
  )
}
```

### 2b. `R/dg-find-topics.R` — the exported wrapper

New file (hyphenated name, per convention). The topic object (from the live probe) carries:
`id, name, slug, description, tags, color, featured, organization`, and an `elements` subsection
pointer (a `rel=subsection` GET whose `total` gives the element count but is NOT inlined).

`topic_element_counts()` (below, imported from `R/utils.R`) wraps the paginated
`fetch_topic_elements()` and returns the per-kind counts; see the confirmed element-class logic
in the note at the end of this section.

```r
#' Find topics (themes) on data.gouv.fr
#'
#' Searches the platform's themes via the v2 `topics/search` endpoint and returns
#' a tibble with one row per matching topic, including its stable 24-hex `id`.
#' That `id` is what you pass to the `topic` argument of [dg_find_datasets()] to
#' restrict a catalog search to one theme. (data.gouv does not resolve topic
#' names/slugs to ids inside `dg_find_datasets()`, so this finder is the way to
#' discover a theme and get its id.)
#'
#' Useful when you want to *discover* which curated themes exist and how many
#' elements (datasets, reuses, dataservices...) they group, before narrowing a
#' search — e.g. browse "Mobilité", "Environnement", "Énergie".
#'
#' @param q Optional full-text query matched against topic names/descriptions
#'   (server-side). Defaults to `NULL`, meaning no filter.
#' @param n Maximum number of topics to return. Defaults to `20`. Set to `Inf`
#'   to retrieve as many as the API allows.
#' @param elements Whether to fetch each topic's `elements` subsection (one extra
#'   request per topic, an N+1 crawl) to fill the `n_datasets`,
#'   `n_dataservices` and `n_reuses` counts exactly. Defaults to `FALSE`, in
#'   which case `n_elements` is the topic's declared total and the breakdown
#'   counts are `NA`.
#'
#' @return A [tibble::tibble()] with one row per matching topic and columns:
#'   \itemize{
#'   \item `id` — the stable, unique 24-hex topic id (passable to the `topic`
#'     argument of [dg_find_datasets()]). Always non-`NA`.
#'   \item `name` — the topic's display name.
#'   \item `slug` — the URL-friendly slug.
#'   \item `description` — the topic's description.
#'   \item `tags` — comma-joined tags, or `NA`.
#'   \item `featured` — whether the platform features this topic.
#'   \item `n_elements` — number of elements (datasets, reuses, dataservices, ...)
#'     grouped under the topic, from the API.
#'   \item `n_datasets`, `n_dataservices`, `n_reuses` — per-kind counts, only
#'     when `elements = TRUE` (else `NA`).
#'   }
#'
#' @export
#' @examplesIf interactive()
#' # Browse the curated themes.
#' dg_find_topics(n = 5)[, c("id", "name", "n_elements")]
#'
#' # Narrow a catalog search to one theme once you have its id.
#' mob <- dg_find_topics(q = "mobilité")
#' dg_find_datasets(topic = mob$id[1], n = 10)
dg_find_topics <- function(q = NULL, n = 20, elements = FALSE) {
  topics <- fetch_topics_all(q = q, n = n)

  if (length(topics) == 0) {
    return(tibble::as_tibble(topic_empty_columns()))
  }

  chrv <- function(f) vapply(topics, f, character(1))
  lglv <- function(f) vapply(topics, f, logical(1))
  intv <- function(f) vapply(topics, function(t) as.integer(f(t)), integer(1))
  tag_str <- function(t) {
    tags <- t$tags %||% character()
    if (length(tags) > 0) paste(tags, collapse = ", ") else NA_character_
  }
  n_elements <- function(t) {
    (t$elements %||% list())$total %||% NA_integer_
  }

  out <- tibble::tibble(
    id = chrv(function(t) t$id %||% NA_character_),
    name = chrv(function(t) t$name %||% NA_character_),
    slug = chrv(function(t) t$slug %||% NA_character_),
    description = chrv(function(t) t$description %||% NA_character_),
    tags = chrv(tag_str),
    featured = lglv(function(t) isTRUE(t$featured)),
    n_elements = intv(n_elements)
  )

  if (isTRUE(elements)) {
    # fetch_topic_elements() returns the raw subsection $data items; the kind
    # classifier is the nested element$class (confirmed live). See the note
    # below for the exact counting logic.
    counts <- lapply(out$id, topic_element_counts)  # helper in R/utils.R
    out$n_datasets <- vapply(counts, `[[`, integer(1), "n_datasets")
    out$n_dataservices <- vapply(counts, `[[`, integer(1), "n_dataservices")
    out$n_reuses <- vapply(counts, `[[`, integer(1), "n_reuses")
  } else {
    out$n_datasets <- NA_integer_
    out$n_dataservices <- NA_integer_
    out$n_reuses <- NA_integer_
  }
  out
}

# Column schema of a dg_find_topics() result, so an empty result still carries
# the full column set with the correct types.
topic_empty_columns <- function() {
  list(
    id = character(),
    name = character(),
    slug = character(),
    description = character(),
    tags = character(),
    featured = logical(),
    n_elements = integer(),
    n_datasets = integer(),
    n_dataservices = integer(),
    n_reuses = integer()
  )
}
```

`fetch_topic_elements()` (new internal in `R/utils.R`) fetches
`/api/2/topics/<id>/elements/` and returns the parsed subsection. **Confirmed shape (live probe
2026-08-24):** the elements endpoint returns a search-envelope object
(`{data, page, page_size, total, next_page, previous_page}`) whose `data` items are
`{id, title, description, tags, extras, element}`. The kind classifier lives in the nested
`element` object:
- `element$class == "Dataset"` → `element$id` is a dataset id (count toward `n_datasets`).
- `element$class == "Reuse"` → count toward `n_reuses`.
- `element$class == "Dataservice"` → count toward `n_dataservices` (the v2 model includes it;
  it was not present in the probe samples but belongs in the classifier).
- `element == NULL`/`{}` → **link/external entries** (topic-specific annotations pointing at
  external URLs, not reusable tables). Do not count these toward any pull-able bucket.

The element-level `title`/`description`/`extras` are the *topic-curator's* annotations (e.g. a
hackathon marking "availability"), not the underlying element's own metadata — do not surface
them as element titles. So the suggested `elements = TRUE` breakdown counts the nested
`element$class`, not the top-level item fields:

```r
  if (isTRUE(elements)) {
    # fetch_topic_elements(id) returns the raw subsection $data list
    class_of <- function(item) (item$element %||% list())$class %||% NA_character_
    counts <- lapply(
      out$id,
      function(topic_id) {
        items <- fetch_topic_elements(topic_id)
        cls <- vapply(items, class_of, character(1))
        list(
          n_datasets = sum(cls == "Dataset", na.rm = TRUE),
          n_dataservices = sum(cls %in% "Dataservice"),
          n_reuses = sum(cls == "Reuse", na.rm = TRUE)
        )
      }
    )
    out$n_datasets <- vapply(counts, `[[`, integer(1), "n_datasets")
    out$n_dataservices <- vapply(counts, `[[`, integer(1), "n_dataservices")
    out$n_reuses <- vapply(counts, `[[`, integer(1), "n_reuses")
  }
```

Use `fetch_topics_all()`-style pointer pagination inside `fetch_topic_elements()` too: the
elements endpoint supports `next_page` (a topic with 87 elements spans multiple pages at the
default page size), so a single `/elements/?page_size=100` call would silently truncate.

### 2c. `elements` N+1 trade-off

Like `resources = TRUE` on `dg_find_datasets()`, per-topic element counts are **not** inlined,
so the breakdown requires one extra request per topic. Keep `n_elements` (the API's cheap
declared `total`) always populated, and gate only the *breakdown* (`n_datasets`/
`n_dataservices`/`n_reuses`) behind `elements = TRUE`. This keeps the default call a single
request while still offering per-kind counts to users who want them.

---

## Design note: no name/slug resolution for `topic`

`dg_find_datasets(organization =)` auto-resolves an org name/slug to its id via
`organizations/search` because a producer name is human-recognizable. Topics have an analogous
`topics/search` endpoint, so auto-resolution *is* technically possible the same way (exact
name/slug match). I recommend **not** adding it initially:

- It would complicate `resolve_organization_id()`-style logic with a second, parallel resolver.
- Topic ids are discoverable through `dg_find_topics()`, and passing the id directly is the
  idiomatic, reproducible path (matching how `organization` ids are the canonical input).

If desired later, a `resolve_topic_id()` mirroring `resolve_organization_id()` can be layered on
without changing the public signature. Flag this as an explicit scope decision.

---

## Files touched (summary)

| File | Change |
|------|--------|
| `R/utils.R` | `datagouv_topics_url()`, `fetch_topic_page()`, `fetch_topics_all()`, `fetch_topic_elements()`; add `topic = NULL` to `fetch_search_page()`/`fetch_search_all()` |
| `R/dg-find-datasets.R` | add `topic = NULL` param + `@param` + example; add to `filter_args` |
| `R/dg-find-topics.R` | **new** — `dg_find_topics()` + `topic_empty_columns()` |
| `tests/testthat/` | URL-param unit test for `topic`; `topic` forwarding test; live-test entry in `test-live-api.R` |
| docs | roxygen/`devtools::document()`; `NIPATES.md` reference + list the 9th export; `NEWS.md`; `README.qmd`/`README.md`; `vignettes/rdatagouv.qmd`; `DESIGN-discovery.md` change map; `_pkgdown.yml` reference section |
| format | `air format .` at package root before committing |

---

## Suggested next steps

1. Confirm the `elements/` subsection response shape (one live call to
   `/api/2/topics/<id>/elements/`) so the `elements = TRUE` branch is exact.
2. Implement parts 1a–1b (the `topic =` filter) — small, low-risk, directly improves
   `dg_find_datasets()`.
3. Implement `dg_find_topics()` with `elements = FALSE` first, then add the breakdown.
4. Decide on the `resolve_topic_id()` scope question before finalizing docs.
