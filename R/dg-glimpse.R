#' Glimpse the metadata of a dataset on data.gouv.fr
#'
#' Surfaces the dataset-level health and engagement metadata that the v2 API
#' embeds inline but the v1 fetch path does not expose — the bridge between
#' *discover* ([dg_list_datasets()]) and *judge* ([dg_schema()]'s column
#' documentation). It reports the dataset's `quality` score and flags, its
#' `metrics` (views, downloads, followers, ...) and its context
#' (organization, license, frequency, temporal/spatial coverage, access type),
#' helping a user decide whether a dataset is worth pulling.
#'
#' `id` composes naturally with the rest of the package: it may be a dataset id
#' (24-hex), a composed table id or a pulled table (whose `id` attribute is
#' read), so a dataset discovered or pulled elsewhere can be glimpsed directly.
#'
#' @param id A dataset identifier (24-hex), a composed table id, or a table
#'   returned by [dg_pull_dataset()]/[dg_refetch()] (its `id` attribute is
#'   read).
#' @param table Whether to also include the dataset's list of resources (from
#'   the v2 resources subsection, one extra request per dataset). `NULL` or
#'   `FALSE` (the default) skips the per-resource fetch; `TRUE` includes it.
#'
#' @return A list with the v2-inline metadata:
#'   * `quality`: a list with `score` (0-1) and boolean flags (`license`,
#'     `temporal_coverage`, `spatial`, `update_frequency`,
#'     `dataset_description_quality`).
#'   * `metrics`: views, resources_downloads, followers, discussions, reuses,
#'     dataservices.
#'   * `context`: organization (name/slug/id), license, frequency,
#'     temporal_coverage, spatial/granularity, access_type, archived, featured.
#'   * `resources` (only when `table = TRUE`): the list of resource objects.
#'
#' @export
#' @examplesIf interactive()
#' g <- dg_glimpse("6a6be5976a05df136d48fb7a")
#' g$quality
#' g$metrics
dg_glimpse <- function(id, table = NULL) {
  dataset_id <- resolve_dataset_id(id)
  dataset <- fetch_dataset_v2(dataset_id)

  quality <- dataset$quality %||% list()
  metrics <- dataset$metrics %||% list()
  temporal <- dataset$temporal_coverage %||% list()
  spatial <- dataset$spatial %||% list()
  org <- dataset$organization %||% list()

  out <- list(
    id = dataset$id %||% NA_character_,
    title = dataset$title %||% NA_character_,
    slug = dataset$slug %||% NA_character_,
    description = dataset$description %||% NA_character_,
    quality = list(
      score = quality$score %||% NA_real_,
      flags = quality[setdiff(names(quality), "score")]
    ),
    metrics = list(
      views = metrics$views %||% NA_integer_,
      resources_downloads = metrics$resources_downloads %||% NA_integer_,
      followers = metrics$followers %||% NA_integer_,
      discussions = metrics$discussions %||% NA_integer_,
      reuses = metrics$reuses %||% NA_integer_,
      dataservices = metrics$dataservices %||% NA_integer_
    ),
    context = list(
      organization = list(
        name = org$name %||% NA_character_,
        slug = org$slug %||% NA_character_,
        id = org$id %||% NA_character_
      ),
      license = dataset$license %||% NA_character_,
      frequency = dataset$frequency %||% NA_character_,
      temporal_coverage = list(
        start = temporal$start %||% NA_character_,
        end = temporal$end %||% NA_character_
      ),
      spatial = list(
        zones = spatial$zones %||% list(),
        granularity = spatial$granularity %||% NA_character_
      ),
      access_type = dataset$access_type %||% NA_character_,
      archived = dataset$archived %||% FALSE,
      featured = dataset$featured %||% FALSE
    )
  )

  if (isTRUE(table)) {
    subsection <- if (is.list(dataset$resources)) dataset$resources else list()
    out$resources <- fetch_resource_subsection(subsection)
  }
  out
}

# Resolve a dataset id from any of dg_glimpse()'s accepted inputs: a bare
# 24-hex id, a composed table id, or a pulled table (read from its `id`
# attribute). Returns the 24-hex dataset id.
resolve_dataset_id <- function(id) {
  if (is.data.frame(id)) {
    tid <- attr(id, "id")
    if (is.null(tid)) {
      stop(
        "This table carries no table id; pass a dataset id directly.",
        call. = FALSE
      )
    }
    return(parse_table_id(tid)$dataset_id)
  }
  if (is.character(id) && length(id) == 1) {
    if (is_dataset_id(id)) {
      return(id)
    }
    return(parse_table_id(id)$dataset_id)
  }
  stop(
    "`id` must be a dataset id (24-hex), a composed table id, or a pulled ",
    "table.",
    call. = FALSE
  )
}
