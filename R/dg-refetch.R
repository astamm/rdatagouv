#' Re-fetch a single parsed table by its stable address
#'
#' Downloads again the exact table addressed by a table URI, stored as an `id`
#' attribute on the tables returned by [dg_pull_dataset()] and readable with
#' [dg_table_id()]. The URI is built from the platform's own stable identifiers
#' (dataset id + resource id, plus the file name inside a ZIP) and opens the
#' dataset page in a browser, so this reproducibly returns the same table,
#' independent of the human-readable list keys.
#'
#' @param x Either a table returned by [dg_pull_dataset()] or [dg_refetch()]
#'   (its `id` attribute is read automatically) or a table address string: the
#'   URI `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>`
#'   (or `...#<resource_id>/<file>` for a file inside a ZIP).
#' @param remove_na Whether to drop rows containing any `NA` value (passed to
#'   `format_tibble()`). Defaults to `FALSE`.
#' @param col_types Optional named vector of column types to force on specific
#'   columns instead of letting vroom infer them, e.g.
#'   `c(date_mise_en_service = "Date")`. See [dg_pull_dataset()] for the
#'   accepted shorthand values. Defaults to `NULL` (no column overrides).
#' @param use_tabular_types Whether to seed column types from data.gouv's
#'   tabular API profile, as in [dg_pull_dataset()] (column types `col_types`
#'   does not pin are taken from the profile when it is available). Defaults to
#'   `TRUE`. Applies to single-file resources only — the profile of the
#'   addressed resource is used; a missing or inapplicable profile (including
#'   any ZIP member) falls back to type inference.
#'
#' @return A [tibble::tibble()] — the single re-fetched table (the id addresses
#'   one table, not a multi-file ZIP as a whole). The table's id is attached as
#'   an `id` attribute; parsing issues are attached as an `rdatagouv_problems`
#'   attribute, readable with [dg_problems()].
#'
#' @export
#' @examplesIf interactive()
#' tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")
#' again <- dg_refetch(tbl)
dg_refetch <- function(
  x,
  remove_na = FALSE,
  col_types = NULL,
  use_tabular_types = TRUE
) {
  id <- resolve_table_id(x)
  parts <- parse_table_id(id)
  dataset <- fetch_dataset(parts$dataset_id)
  resources <- dataset$resources
  hit <- Filter(function(r) identical(r$id, parts$resource_id), resources)
  if (length(hit) == 0) {
    stop(
      "Resource '",
      parts$resource_id,
      "' was not found on dataset '",
      parts$dataset_id,
      "'.",
      call. = FALSE
    )
  }
  resource <- hit[[1]]

  # Profile-backed column typing is resolved at the leaf: read_resource() looks
  # up the tabular profile of this exact resource (single-file only) and merges
  # it with any explicit col_types; read_one_zip_file() ignores the flag because
  # ZIP members are not addressed by the tabular service.
  tbl <- if (is.null(parts$file)) {
    read_resource(
      resource,
      col_types = col_types,
      use_tabular_types = use_tabular_types
    )
  } else {
    read_one_zip_file(
      resource,
      parts$file,
      col_types = col_types,
      use_tabular_types = use_tabular_types
    )
  }
  tbl <- format_tibble(tbl, remove_na = remove_na)
  tibble::as_tibble(table_attr(
    tbl,
    parts$dataset_id,
    parts$resource_id,
    parts$file
  ))
}
