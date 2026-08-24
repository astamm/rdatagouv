#' List datasets available on data.gouv.fr
#'
#' Collects the datasets published on the data.gouv.fr platform, searching the
#' catalog via the v2 `datasets/search` endpoint (the same one the web
#' interface uses). By default it returns the first `n` datasets; use `q` to
#' search titles and descriptions server-side instead of enumerating the whole
#' catalog.
#'
#' Fetching *every* dataset on the platform means paging through tens of
#' thousands of records in hundreds of HTTP requests and is both slow and
#' fragile, so the default is deliberately bounded. Set `n = Inf` to return as
#' many matches as the API allows. Note that data.gouv caps a search at 10,000
#' matches, so an un-narrowed `n = Inf` crawl stops at that cap even though the
#' platform holds more.
#'
#' Because v2 search embeds rich per-dataset metadata inline, the returned
#' tibble includes columns such as `license`, `quality_score`, `views`,
#' `access_type`, `frequency`, `temporal_start`/`temporal_end`, `archived` and
#' `featured` that help judge whether a dataset is worth pulling.
#'
#' v2 search does NOT inline each dataset's resources (they are subsection
#' pointers), so the exact resource-based columns `n_resources`, `formats`,
#' `has_table` and `has_schema` can no longer be computed without one extra
#' request per dataset (an N+1 crawl). By default these are `NA`; set
#' `resources = TRUE` to opt into the per-dataset resource fetch and fill them
#' exactly.
#'
#' @param q Optional full-text search query. When given, only datasets
#'   matching `q` are returned (the API performs the search). Defaults to
#'   `NULL`, meaning no filtering.
#' @param n Maximum number of datasets to return. Defaults to `1000`.
#'   Set to `Inf` to retrieve as many as the API allows (capped at 10,000).
#' @param format Optional character vector of resource formats to keep. Only
#'   datasets that have at least one resource in one of these formats are
#'   returned. The v2 API matches multiple values when passed as repeated
#'   parameters (a server-side union). Defaults to the full set of officially
#'   tabular formats (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`).
#' @param schema_only Whether to keep only datasets that declare a data schema
#'   (see `has_schema`). Defaults to `FALSE`. v2 has no boolean "declares any
#'   schema" server-side filter, so this filters client-side and only works
#'   reliably when `resources = TRUE` fills `has_schema`.
#' @param organization Optional data producer, matched server-side by its
#'   **24-hex `organization` id** (as shown in the `organization` column or on
#'   the dataset page). Unlike v1, the v2 search API does *not* accept the
#'   organization slug or name here (a slug yields zero matches). Defaults to
#'   `NULL`.
#' @param geozone Optional territorial filter, e.g. `"country:fr"` or
#'   `"fr:commune:75056"`. Defaults to `NULL`.
#' @param access_type Optional access filter, `"open"` or `"restricted"`.
#'   Defaults to `NULL`.
#' @param license Optional license filter (a license slug, e.g. `"lov2"` or
#'   `"odc-odbl"`). Defaults to `NULL`.
#' @param tag Optional tag filter, e.g. `"mobilite"`. Defaults to `NULL`.
#' @param granularity Optional spatial granularity filter, e.g. `"fr:commune"`.
#'   Defaults to `NULL`.
#' @param last_update Optional update-recency filter:
#'   `"last_30_days"`, `"last_12_months"` or `"last_3_years"`. Defaults to
#'   `NULL`.
#' @param producer_type Optional producer-type filter (a facet value, e.g.
#'   `"public-service"` or `"local-authority"`). Defaults to `NULL`.
#' @param resources Whether to fetch each dataset's resources subsection
#'   (one extra request per dataset) so the exact `n_resources`, `formats`,
#'   `has_table` and `has_schema` columns can be computed. Defaults to
#'   `FALSE`, in which case those columns are `NA`.
#'
#' @return A [tibble::tibble()] with one row per matching dataset. The
#'   `title` and `id` columns are always non-`NA`; the `id` column holds the
#'   stable, unique dataset identifier used to address a dataset with
#'   [dg_pull_dataset()]. When `resources = TRUE`, the columns also include
#'   `n_resources` (number of files/resources), `formats` (distinct file
#'   formats found among them), `has_table` (whether at least one resource is
#'   in a format this package can parse) and `has_schema` (whether at least one
#'   resource carries a pointer to a declared data schema, whose per-variable
#'   documentation is exposed by [dg_schema()]); these are `NA` otherwise.
#'
#' @export
#' @examplesIf interactive()
#' datasets <- dg_list_datasets(n = 20)
#' head(datasets)
#'
#' # Search server-side instead of downloading the whole catalog.
#' cycle <- dg_list_datasets(q = "vélo", n = 10)
#'
#' # Only datasets that carry at least one parquet resource; the v2 API matches
#' # multiple formats as a server-side union.
#' compact <- dg_list_datasets(format = "parquet", n = 10)
#'
#' # Only datasets with a declared schema (documented variables). Resolving
#' # `has_schema` exactly needs the per-dataset resource fetch.
#' documented <- dg_list_datasets(schema_only = TRUE, resources = TRUE, n = 10)
#'
#' # Narrow by producer (server-side id filter) and territory.
#' fr <- dg_list_datasets(organization = "534fff91a3a7292c64a77f53",
#'                        geozone = "country:fr", n = 10)
dg_list_datasets <- function(
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
) {
  filter_args <- list(
    organization = organization,
    geozone = geozone,
    access_type = access_type,
    license = license,
    tag = tag,
    granularity = granularity,
    last_update = last_update,
    producer_type = producer_type
  )
  datasets <- do.call(
    fetch_search_all,
    c(list(q = q, n = n, format = format), filter_args)
  )
  if (length(datasets) == 0) {
    return(tibble::as_tibble(datagouv_empty_columns()))
  }

  chrv <- function(f) vapply(datasets, f, character(1))
  numv <- function(f) vapply(datasets, function(d) as.numeric(f(d)), numeric(1))
  intv <- function(f) vapply(datasets, function(d) as.integer(f(d)), integer(1))
  lglv <- function(f) vapply(datasets, function(d) isTRUE(f(d)), logical(1))

  org_slug <- function(d) {
    org <- d$organization %||% list()
    org$slug %||% org$name %||% org$id %||% NA_character_
  }
  flag_str <- function(d) {
    quality <- d$quality %||% list()
    flags <- names(Filter(isTRUE, quality[setdiff(names(quality), "score")]))
    if (length(flags) > 0) paste(flags, collapse = ", ") else NA_character_
  }

  out <- tibble::tibble(
    title = chrv(function(d) d$title %||% NA_character_),
    id = chrv(function(d) d$id %||% NA_character_),
    description = chrv(function(d) d$description %||% NA_character_),
    slug = chrv(function(d) d$slug %||% NA_character_),
    organization = chrv(org_slug),
    license = chrv(function(d) d$license %||% NA_character_),
    quality_score = numv(function(d) {
      (d$quality %||% list())$score %||% NA_real_
    }),
    quality_flags = chrv(flag_str),
    views = intv(function(d) (d$metrics %||% list())$views %||% NA_integer_),
    resources_downloads = intv(function(d) {
      (d$metrics %||% list())$resources_downloads %||% NA_integer_
    }),
    access_type = chrv(function(d) d$access_type %||% NA_character_),
    frequency = chrv(function(d) d$frequency %||% NA_character_),
    spatial_granularity = chrv(function(d) {
      (d$spatial %||% list())$granularity %||% NA_character_
    }),
    temporal_start = chrv(function(d) {
      (d$temporal_coverage %||% list())$start %||% NA_character_
    }),
    temporal_end = chrv(function(d) {
      (d$temporal_coverage %||% list())$end %||% NA_character_
    }),
    archived = lglv(function(d) d$archived),
    featured = lglv(function(d) d$featured)
  )

  if (isTRUE(resources)) {
    res_list <- lapply(datasets, function(.x) {
      subsection <- if (is.list(.x$resources)) .x$resources else list()
      fetch_resource_subsection(subsection)
    })
    out$n_resources <- vapply(res_list, length, integer(1))
    out$formats <- vapply(
      res_list,
      function(res) {
        fmts <- sort(unique(tolower(vapply(
          res,
          function(r) r$format %||% "",
          character(1)
        ))))
        paste(fmts, collapse = ", ")
      },
      character(1)
    )
    out$has_table <- vapply(
      res_list,
      function(res) {
        fmts <- sort(unique(tolower(vapply(
          res,
          function(r) r$format %||% "",
          character(1)
        ))))
        any(fmts %in% supported_formats())
      },
      logical(1)
    )
    out$has_schema <- vapply(
      res_list,
      function(res) any(vapply(res, resource_has_schema, logical(1))),
      logical(1)
    )
    out$formats[out$formats == ""] <- NA_character_
  } else {
    out$n_resources <- NA_integer_
    out$formats <- NA_character_
    out$has_table <- NA
    out$has_schema <- NA
  }

  if (isTRUE(schema_only)) {
    out <- out[out$has_schema, , drop = FALSE]
  }
  out
}

# Column schema of a dg_list_datasets() result, so an empty result still
# carries the full column set with the correct types.
datagouv_empty_columns <- function() {
  list(
    title = character(),
    id = character(),
    description = character(),
    slug = character(),
    organization = character(),
    license = character(),
    quality_score = numeric(),
    quality_flags = character(),
    views = integer(),
    resources_downloads = integer(),
    access_type = character(),
    frequency = character(),
    spatial_granularity = character(),
    temporal_start = character(),
    temporal_end = character(),
    archived = logical(),
    featured = logical(),
    n_resources = integer(),
    formats = character(),
    has_table = logical(),
    has_schema = logical()
  )
}
