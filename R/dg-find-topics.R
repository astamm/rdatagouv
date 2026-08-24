#' Find topics (themes) on data.gouv.fr
#'
#' Searches the platform's themes via the v2 `topics/search` endpoint and
#' returns a tibble with one row per matching topic, including its stable
#' 24-hex `id`. That `id` is what you pass to the `topic` argument of
#' [dg_find_datasets()] to restrict a catalog search to one theme. (data.gouv
#' does not resolve topic names/slugs to ids inside `dg_find_datasets()`, so
#' this finder is the way to discover a theme and get its id.)
#'
#' Useful when you want to *discover* which curated themes exist and how many
#' elements (datasets, reuses, dataservices...) they group, before narrowing a
#' search — e.g. browse "Mobilité", "Environnement", "Énergie".
#'
#' @param q Optional full-text query matched against topic names/descriptions
#'   (server-side). Defaults to `NULL`, meaning no filter.
#' @param n Maximum number of topics to return. Defaults to `20`. Set to `Inf`
#'   to retrieve as many as the API allows.
#' @param elements Whether to fetch each topic's `elements` subsection (one
#'   extra request per topic, an N+1 crawl) to fill the `n_datasets`,
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
#'   \item `n_elements` — number of elements (datasets, reuses,
#'     dataservices, ...) grouped under the topic, from the API.
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
  lglv <- function(f) vapply(topics, function(t) isTRUE(f(t)), logical(1))
  intv <- function(f) vapply(topics, function(t) as.integer(f(t)), integer(1))
  tag_str <- function(t) {
    tags <- t$tags %||% character()
    if (length(tags) > 0) paste(tags, collapse = ", ") else NA_character_
  }
  n_elements <- function(t) (t$elements %||% list())$total %||% NA_integer_

  out <- tibble::tibble(
    id = chrv(function(t) t$id %||% NA_character_),
    name = chrv(function(t) t$name %||% NA_character_),
    slug = chrv(function(t) t$slug %||% NA_character_),
    description = chrv(function(t) t$description %||% NA_character_),
    tags = chrv(tag_str),
    featured = lglv(function(t) t$featured),
    n_elements = intv(n_elements)
  )

  if (isTRUE(elements)) {
    # fetch_topic_elements() returns the raw subsection $data items; the kind
    # classifier is the nested element$class (confirmed live).
    counts <- lapply(out$id, topic_element_counts)
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
