#' List datasets available on data.gouv.fr
#'
#' Collects the names (titles) of datasets published on the data.gouv.fr
#' platform. By default it returns the first `n` datasets; use `q` to search
#' titles and descriptions server-side instead of enumerating the whole
#' catalog.
#'
#' Fetching *every* dataset on the platform means paging through tens of
#' thousands of records in hundreds of HTTP requests and is both slow and
#' fragile, so the default is deliberately bounded. Set `n = Inf` to return
#' all titles regardless of count.
#'
#' @param q Optional full-text search query. When given, only datasets
#'   matching `q` are returned (the API performs the search). Defaults to
#'   `NULL`, meaning no filtering.
#' @param n Maximum number of datasets to return. Defaults to `1000`.
#'   Set to `Inf` to retrieve everything (the whole catalog).
#' @param format Optional character vector of resource formats to keep. When
#'   given, only datasets that have at least one resource in one of these
#'   formats are returned; each requested format is queried server-side and the
#'   results are combined. Defaults to the full set of officially tabular
#'   formats (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`).
#' @param schema_only Whether to keep only datasets that declare a data schema
#'   (see `has_schema`). Defaults to `FALSE`.
#'
#' @return A [tibble::tibble()] with one row per matching dataset and the
#'   columns `title`, `id`, `description`, `slug`, `n_resources`, `formats`,
#'   `has_table` and `has_schema`. The `id` column holds the stable, unique
#'   dataset identifier used to address a dataset with [dg_pull_dataset()].
#'   `n_resources` is the number of files/resources in the dataset, `formats`
#'   lists the distinct file formats found among them, `has_table` indicates
#'   whether at least one resource is in a format that can be parsed into a
#'   table by this package, and `has_schema` indicates whether at least one
#'   resource carries a pointer to a declared data schema (whose per-variable
#'   documentation is exposed by [dg_schema()]).
#'
#' @export
#' @examplesIf interactive()
#' datasets <- dg_list_datasets(n = 20)
#' head(datasets)
#'
#' # Search server-side instead of downloading the whole catalog.
#' cycle <- dg_list_datasets(q = "vélo", n = 10)
#'
#' # Only datasets that carry at least one parquet resource (a more compact
#' # format than CSV, so a later download is lighter).
#' parquet <- dg_list_datasets(format = "parquet", n = 10)
#'
#' # Only datasets with a declared schema (documented variables).
#' documented <- dg_list_datasets(schema_only = TRUE, n = 10)
dg_list_datasets <- function(
  q = NULL,
  n = 1000,
  format = catalog_formats(),
  schema_only = FALSE
) {
  datasets <- fetch_all_datasets(q = q, n = n, format = format)
  rows <- lapply(datasets, function(.x) {
    resources <- .x$resources %||% list()
    fmts <- sort(unique(tolower(vapply(
      resources,
      function(r) r$format %||% "",
      character(1)
    ))))
    data.frame(
      title = .x$title %||% NA_character_,
      id = .x$id %||% NA_character_,
      description = .x$description %||% NA_character_,
      slug = .x$slug %||% NA_character_,
      n_resources = length(resources),
      formats = paste(fmts, collapse = ", "),
      has_table = any(fmts %in% supported_formats()),
      has_schema = any(vapply(resources, resource_has_schema, logical(1))),
      stringsAsFactors = FALSE
    )
  })
  out <- tibble::as_tibble(do.call(rbind, rows))
  if (isTRUE(schema_only)) {
    out <- out[out$has_schema, , drop = FALSE]
  }
  out
}

#' List all datasets available on data.gouv.fr with tabular formats
#'
#' Collects the names (titles) of datasets published on the data.gouv.fr
#' platform. By default it returns the first `n` datasets; use `q` to search
#' in all dataset contain server-side (ElasticSearch).
#'
#' Fetching *every* dataset on the platform means paging through tens of
#' thousands of records in hundreds of HTTP requests and is both slow and
#' fragile, so the default is deliberately bounded. Set `n = Inf` to return
#' all titles regardless of count.
#'
#' @param q Require full-text search query. datasets containing
#'   matching `q` are returned (the API performs the search). Length should me >= 3.
#' @param n Maximum number of datasets to return. Defaults to `1000`.
#'   Set to `Inf` to retrieve everything (the whole catalog).
#' @param format Optional character vector of resource formats to keep. When
#'   given, only datasets that have at least one resource in one of these
#'   formats are returned; each requested format is queried server-side and the
#'   results are combined. Defaults to the full set of officially tabular
#'   formats (`csv`, `csv.gz`, `xls`, `xlsx`, `parquet`).
#'
#' @return A [tibble::tibble()] with one row per matching dataset and the
#'   columns `title`, `id`, `description`, `slug`, `n_resources`, `ressources_href`,
#'   `organization` and `data_uri``. The `id` column holds the stable, unique
#'   dataset identifier used to address a dataset with [dg_pull_dataset()].
#'   `n_resources` is the number of files/resources in the dataset, `formats`
#'   lists the distinct file formats found among them.
#'
#' @export
#' @examplesIf interactive()
#' datasets <- dg_datasets_search(q = "data.gouv")
#' head(datasets)
#'
#' # Search server-side instead of downloading the whole catalog.
#' cycle <- dg_datasets_search(q = "vélo", n = 10)
#'
#' # Only datasets that carry at least one parquet resource (a more compact
#' # format than CSV, so a later download is lighter).
#' parquet <- dg_datasets_search(q="vélo", format = "parquet", n = 10)
dg_datasets_search <- function( q="",  n = 1000, format = catalog_formats()) {
  if (is.null(q) || length(q) != 1 || is.na(q) || !nzchar(trimws(q))) {
    stop("q (query) parameter not set")
  }
  if (nchar(trimws(q)) <= 3) {
    warning("`q` contain less than 3 characters : the search may take to much time or crach.")
  }
  datasets <- fetch_all_datasets(q = q, n = n, format = format, api_version = 2)
  rows <- lapply(datasets, function(.x) {
    data.frame(
      title = .x$title %||% NA_character_,
      id = .x$id %||% NA_character_,
      description_short = .x$description_short %||% NA_character_,
      description = .x$description %||% NA_character_,
      slug = .x$slug %||% NA_character_,
      organization = .x$organization$name %||% NA_character_,
      n_resources = .x$resources$total,
      ressources_href = .x$resources$href,
      dataset_uri = .x$uri,
      stringsAsFactors = FALSE
    )
  })
  out <- tibble::as_tibble(do.call(rbind, rows))
  out

}
<<<<<<< HEAD

=======
>>>>>>> 2dd28fd (Add an opt-in live integration test.)
