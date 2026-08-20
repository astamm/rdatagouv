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
#'   canonical URI `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>`
#'   (or `...#<resource_id>/<file>` for a file inside a ZIP), or a legacy
#'   composed id of the form `<dataset_id>::<resource_id>` /
#'   `<dataset_id>::<resource_id>::<file>`.
#' @param remove_na Whether to drop rows containing any `NA` value (passed to
#'   `format_tibble()`). Defaults to `FALSE`.
#'
#' @return A [tibble::tibble()] — the single re-fetched table (the id addresses
#'   one table, not a multi-file ZIP as a whole). The table's id is attached as
#'   an `id` attribute.
#'
#' @export
#' @examplesIf interactive()
#' tbl <- dg_pull_dataset("6397c0ff56d3963118a18345")
#' again <- dg_refetch(tbl)
dg_refetch <- function(x, remove_na = FALSE) {
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

  tbl <- if (is.null(parts$file)) {
    read_resource(resource)
  } else {
    read_one_zip_file(resource, parts$file)
  }
  tbl <- format_tibble(tbl, remove_na = remove_na)
  tibble::as_tibble(table_attr(
    tbl,
    parts$dataset_id,
    parts$resource_id,
    parts$file
  ))
}
