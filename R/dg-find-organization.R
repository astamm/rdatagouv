#' Search for organizations (data producers) on data.gouv.fr
#'
#' Searches the platform's producers via the v2 `organizations/search` endpoint
#' and returns a tibble with one row per matching organization, including its
#' stable 24-hex `id`. That `id` is exactly what you pass to the `organization`
#' argument of [dg_find_datasets()] to restrict a catalog search to one
#' producer — or, more conveniently, you can pass a producer's exact `name` or
#' `slug` to `dg_find_datasets()` directly and it is resolved for you (see
#' [dg_find_datasets()]).
#'
#' Useful when you want to *discover* which producers exist, how a producer's
#' name is spelled, or how many datasets it publishes — before narrowing a
#' search.
#'
#' @param q Optional full-text query matched against organization names,
#'   descriptions, etc. (server-side). Defaults to `NULL`, meaning no filter.
#'   When `NULL` the most recently active/popular producers are returned.
#' @param n Maximum number of organizations to return. Defaults to `20`. Set to
#'   `Inf` to retrieve as many as the API allows.
#'
#' @return A [tibble::tibble()] with one row per matching organization and
#'   columns:
#'   \itemize{
#'   \item `id` — the stable, unique 24-hex producer id (passable to the
#'     `organization` argument of [dg_find_datasets()]). Always non-`NA`.
#'   \item `name` — the producer's display name.
#'   \item `slug` — the URL-friendly slug.
#'   \item `acronym` — the acronym, or `NA`.
#'   \item `description` — the producer's description.
#'   \item `datasets` — number of datasets the producer currently publishes.
#'   \item `badges` — comma-joined badge kinds (e.g.
#'     `"public-service, certified"`), or `NA`.
#'   \item `business_number_id` — the French SIREN identifier when known, else
#'     `NA`.
#'   }
#'
#' @export
#' @examplesIf interactive()
#' # Who publishes rail/mobility data? (server-side ranked search)
#' orgs <- dg_find_organization(q = "SNCF")
#' orgs[, c("id", "name", "datasets")]
#'
#' # Use the resolved id to narrow a catalog search to one producer.
#' datagouv <- dg_find_organization(q = "data.gouv")
#' open_data <- dg_find_datasets(organization = datagouv$id[1], n = 5)
dg_find_organization <- function(q = NULL, n = 20) {
  orgs <- fetch_organizations_all(q = q, n = n)

  if (length(orgs) == 0) {
    return(tibble::as_tibble(organization_empty_columns()))
  }

  chrv <- function(f) vapply(orgs, f, character(1))
  intv <- function(f) {
    vapply(
      orgs,
      function(o) as.integer(f(o)),
      integer(1)
    )
  }
  badge_str <- function(o) {
    badges <- vapply(
      o$badges %||% list(),
      function(b) b$kind %||% NA_character_,
      character(1)
    )
    if (length(badges) > 0) paste(badges, collapse = ", ") else NA_character_
  }

  tibble::tibble(
    id = chrv(function(o) o$id %||% NA_character_),
    name = chrv(function(o) o$name %||% NA_character_),
    slug = chrv(function(o) o$slug %||% NA_character_),
    acronym = chrv(function(o) o$acronym %||% NA_character_),
    description = chrv(function(o) o$description %||% NA_character_),
    datasets = intv(function(o) {
      (o$metrics %||% list())$datasets %||% NA_integer_
    }),
    badges = chrv(badge_str),
    business_number_id = chrv(function(o) {
      o$business_number_id %||% NA_character_
    })
  )
}

# Column schema of a dg_find_organization() result, so an empty result still
# carries the full column set with the correct types.
organization_empty_columns <- function() {
  list(
    id = character(),
    name = character(),
    slug = character(),
    acronym = character(),
    description = character(),
    datasets = integer(),
    badges = character(),
    business_number_id = character()
  )
}
