#' Find datasets available on data.gouv.fr
#'
#' Collects the datasets published on the data.gouv.fr platform, searching the
#' catalog via the v2 `datasets/search` endpoint (the same one the web
#' interface uses). By default it returns the first `n` datasets; use `q` to
#' search titles and descriptions server-side instead of enumerating the whole
#' catalog.
#'
#' Fetching *every* dataset on the platform means paging through many thousands
#' of records in many HTTP requests and is both slow and fragile, so the
#' default is deliberately bounded. Set `n = Inf` to return as many matches as
#' the API allows. Note that data.gouv caps a search at 10,000 matches, so an
#' un-narrowed `n = Inf` crawl stops at that cap even though the platform holds
#' more. For large or infinite `n` the crawl scales its page size up (to ~250)
#' so a full 10,000-row crawl takes ~40 requests, not hundreds.
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
#'   schema" server-side filter, so this filters client-side on `has_schema`,
#'   which itself needs the per-dataset resource fetch. When `schema_only` is
#'   set without `resources = TRUE`, this function forces `resources = TRUE`
#'   (with an informative message about the extra requests) so the filter
#'   actually runs.
#' @param organization Optional data producer, matched server-side. Pass either
#'   the producer's **24-hex `organization` id** (as shown in the
#'   `organization` column of the returned tibble or on the dataset page), or
#'   its exact `name` or `slug` — a human-readable value is resolved to its id
#'   automatically via [dg_find_organization()] (only an exact match is
#'   auto-resolved, so results stay reproducible; an ambiguous or unmatched
#'   value stops with the candidate list). Note that, unlike v1, the v2 search
#'   API itself only accepts the id (a raw slug yields zero matches), which is
#'   why the package resolves names/slugs for you. Defaults to `NULL`.
#' @param geozone Optional territorial filter, passed as a territory code of
#'   the form `"<scope>:<code>"`, e.g. `"country:fr"`, `"country-group:ue"`,
#'   `"country-subset:fr:metro"`, `"fr:region:..."`, `"fr:departement:974"`,
#'   `"fr:epci:..."`, `"fr:commune:75056"`, `"fr:arrondissement:..."`,
#'   `"fr:canton:..."`, `"fr:collectivite:..."`, `"fr:iris:..."` or `"poi:..."`,
#'   or the bare `"country"`/`"country-group"`/`"country-subset"` scope with an
#'   omitted code for pan-national groupings. Accepted territory codes are
#'   open-ended (any INSEE code for the relevant scope), so this argument is not
#'   enumerated; only the format is validated. Defaults to `NULL`.
#' @param access_type Optional access filter. One of `"open"` (freely
#'   downloadable) or `"restricted"` (access requires approval). Defaults to
#'   `NULL`.
#' @param license Optional license filter, one of the exhaustive license slugs
#'   `"lov2"`, `"notspecified"`, `"fr-lo"`, `"odc-odbl"`, `"other-at"`,
#'   `"cc-by"`, `"other-pd"`, `"cc-by-sa"`, `"other-open"`, `"odc-by"`,
#'   `"cc-zero"`, `"odc-pddl"`. Defaults to `NULL`.
#' @param tag Optional tag filter. Tags form an open vocabulary (dynamic
#'   facets), so any free-form tag such as `"mobilite"` is accepted and is not
#'   enumerated or validated. Defaults to `NULL`.
#' @param topic Optional topic filter, the **24-hex `topic` id** of a theme
#'   (found via [dg_find_topics()]). Only datasets grouped under that topic are
#'   returned. Matched server-side as a single-valued filter, so pass exactly
#'   one id. Topic ids form an open vocabulary (themes are created
#'   dynamically), so this is not enumerated or validated. Unlike `organization`,
#'   a human-readable topic name/slug is not auto-resolved — use
#'   [dg_find_topics()] to discover a theme and get its id. Defaults to `NULL`.
#' @param granularity Optional spatial granularity filter, one of the
#'   exhaustive values `"other"`, `"fr:commune"`, `"country"`, `"fr:epci"`,
#'   `"fr:departement"`, `"poi"`, `"fr:region"`, `"fr:canton"`,
#'   `"country-group"`, `"country-subset"`, `"fr:collectivite"`, `"fr:iris"`,
#'   `"fr:arrondissement"`. Defaults to `NULL`.
#' @param last_update Optional update-recency filter, one of `"last_30_days"`,
#'   `"last_12_months"` or `"last_3_years"`. Defaults to `NULL`.
#' @param producer_type Optional producer-type filter, one of the exhaustive
#'   values `"public-service"`, `"local-authority"`, `"company"`,
#'   `"not-specified"`, `"user"` or `"association"`. Defaults to `NULL`.
#' @param resources Whether to fetch each dataset's resources subsection
#'   (one extra request per dataset) so the exact `n_resources`, `formats`,
#'   `has_table` and `has_schema` columns can be computed. Defaults to
#'   `FALSE`, in which case those columns are `NA`. Automatically forced to
#'   `TRUE` when `schema_only = TRUE` (see `schema_only`).
#'
#' @return A [tibble::tibble()] with one row per matching dataset. The
#'   `title` and `id` columns are always non-`NA`; the `id` column holds the
#'   stable, unique dataset identifier used to address a dataset with
#'   [dg_pull_dataset()]. When `resources = TRUE`, the columns also include
#'   `n_resources` (number of files/resources), `formats` (distinct file
#'   formats found among them), `has_table` (whether at least one resource is
#'   in a format this package can parse) and `has_schema` (whether at least one
#'   resource carries a pointer to a declared data schema, whose per-variable
#'   documentation is exposed by [dg_schema()]); these are `NA` when
#'   `resources = FALSE` (the default) unless `schema_only = TRUE`, which forces
#'   the fetch so `has_schema` is filled and the filter can run.
#'
#' @export
#' @examplesIf interactive()
#' datasets <- dg_find_datasets(n = 20)
#' head(datasets)
#'
#' # Search server-side instead of downloading the whole catalog.
#' cycle <- dg_find_datasets(q = "vélo", n = 10)
#'
#' # Only datasets that carry at least one parquet resource; the v2 API matches
#' # multiple formats as a server-side union.
#' compact <- dg_find_datasets(format = "parquet", n = 10)
#'
#' # Only datasets with a declared schema (documented variables). `schema_only`
#' # forces the per-dataset resource fetch itself (~30s for n = 1000), so
#' # `resources = TRUE` is optional here.
#' documented <- dg_find_datasets(schema_only = TRUE, n = 10)
#'
#' # Narrow by producer and territory. A producer may be given by its 24-hex
#' # id or by its exact slug/name (resolved for you), and by geozone.
#' fr <- dg_find_datasets(organization = "sncf",
#'                        geozone = "country:fr", n = 10)
#'
#' # Only datasets grouped under one topic (find its id with dg_find_topics()).
#' mob <- dg_find_topics(q = "mobilité")
#' dg_find_datasets(topic = mob$id[1], n = 10)
dg_find_datasets <- function(
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
) {
  validate_filter_args(
    access_type = access_type,
    license = license,
    granularity = granularity,
    last_update = last_update,
    producer_type = producer_type
  )

  # `schema_only` filters client-side on `has_schema`, which v2 only makes
  # available through the per-dataset resource fetch. Forcing `resources = TRUE`
  # (with a note about the N+1 crawl) lets the user's declared intent work
  # instead of silently returning an unfiltered catalog with has_schema = NA.
  if (isTRUE(schema_only) && !isTRUE(resources)) {
    cli::cli_inform(
      "Forcing `resources = TRUE` because `schema_only = TRUE` selects on \\
       `has_schema`, which needs the per-dataset resource fetch.",
      class = "datagouv_forced_resources"
    )
    resources <- TRUE
  }

  filter_args <- list(
    organization = resolve_organization_id(organization),
    geozone = geozone,
    access_type = access_type,
    license = license,
    tag = tag,
    topic = topic,
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

# Column schema of a dg_find_datasets() result, so an empty result still
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

# Exhaustive option values for the closed-vocabulary server-side filters of
# dg_find_datasets(), as exposed by the v2 datasets/search `facets` field and
# verified live against the API. Keep these in sync with the roxygen @param
# docs above.
#
# access_type: how much of a dataset is publicly reachable.
dg_access_type_values <- c("open", "restricted")

# producer_type: the kind of organization publishing the dataset.
dg_producer_type_values <- c(
  "public-service",
  "local-authority",
  "company",
  "not-specified",
  "user",
  "association"
)

# last_update: how recently the dataset was updated (relative to now).
dg_last_update_values <- c("last_30_days", "last_12_months", "last_3_years")

# license: the license slug attached to the dataset.
dg_license_values <- c(
  "lov2",
  "notspecified",
  "fr-lo",
  "odc-odbl",
  "other-at",
  "cc-by",
  "other-pd",
  "cc-by-sa",
  "other-open",
  "odc-by",
  "cc-zero",
  "odc-pddl"
)

# granularity: the finest spatial granularity of the dataset's geography.
dg_granularity_values <- c(
  "other",
  "fr:commune",
  "country",
  "fr:epci",
  "fr:departement",
  "poi",
  "fr:region",
  "fr:canton",
  "country-group",
  "country-subset",
  "fr:collectivite",
  "fr:iris",
  "fr:arrondissement"
)

# The closed-vocabulary filters of dg_find_datasets() and their exhaustive
# valid values. Each is a single-valued server-side filter: NULL (no filter)
# is the only other acceptable value; NA or a vector of length > 1 is invalid.
# tag and geozone are deliberately absent: tag is an open vocabulary (dynamic
# facets) and geozone is a free territory code (see validate_filter_args()).
dg_filter_vocabularies <- list(
  access_type = dg_access_type_values,
  license = dg_license_values,
  granularity = dg_granularity_values,
  last_update = dg_last_update_values,
  producer_type = dg_producer_type_values
)

# Validate the closed-vocabulary filter arguments of dg_find_datasets() before
# they reach the server, replacing three footguns the v2 search endpoint
# otherwise produces on a bad value:
#   * producer_type with an invalid value -> cryptic server validation error;
#   * license/granularity/access_type with an invalid value -> silently 0 hits;
#   * last_update with an invalid value -> silently ignored (full catalog).
# Each argument must be NULL (no filter) or a single valid value. On a problem
# it stops with the exhaustive list of valid options so users can self-correct.
# geozone (a free territory code, e.g. "country:fr", "fr:departement:974",
# "fr:commune:75056", "country-group:ue") and tag (an open vocabulary) are not
# validated here.
validate_filter_args <- function(
  access_type,
  license,
  granularity,
  last_update,
  producer_type
) {
  args <- list(
    access_type = access_type,
    license = license,
    granularity = granularity,
    last_update = last_update,
    producer_type = producer_type
  )
  for (nm in names(args)) {
    value <- args[[nm]]
    if (is.null(value)) {
      next
    }
    valid <- dg_filter_vocabularies[[nm]]
    if (is.character(value) && length(value) == 1 && value %in% valid) {
      next
    }
    if (length(value) > 1) {
      cli::cli_abort(
        "`{nm}` must be a single value, not a vector.",
        class = "datagouv_invalid_filter"
      )
    }
    cli::cli_abort(
      "Unknown `{nm}` value \"{value}\". Valid options are: {valid}.",
      class = "datagouv_invalid_filter"
    )
  }
  invisible(NULL)
}
