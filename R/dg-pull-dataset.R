#' Download a dataset from data.gouv.fr
#'
#' Downloads the first tabular resource of a dataset and parses it into a
#' [tibble::tibble()] with `format_tibble()`. The dataset is identified by its
#' `id`, which is the stable, unique identifier returned in the `id` column of
#' [dg_find_datasets()]. For backwards compatibility, an exact title is also
#' accepted and is resolved by searching the platform.
#'
#' By default a single tibble is returned: the first resource that can actually
#' be parsed as a table (for a multi-file ZIP, the first parseable file). The
#' table's stable, unique address is attached as an `id` attribute, readable
#' with [dg_table_id()] and accepted directly by [dg_refetch()] and
#' [dg_schema()]. Set `all_files = TRUE` to instead receive one table per
#' parseable file as a named list (useful for a ZIP holding several files).
#'
#' @param id The identifier of the dataset to download (or, as a fallback, its
#'   exact title). Identifiers are unique and stable, so they are the
#'   recommended way to address a dataset; titles can collide or change over
#'   time.
#' @param all_files Whether to return one table per parseable file as a named
#'   list instead of a single tibble. Defaults to `FALSE`. For a single-file
#'   resource the result is the same either way (a single tibble); for a
#'   multi-file ZIP, `TRUE` keeps every parseable file, one named element each.
#' @param remove_na Whether to drop rows containing any `NA` value (passed to
#'   `format_tibble()`). Defaults to `FALSE`.
#' @param col_types Optional named vector of column types to force on specific
#'   columns instead of letting vroom infer them, e.g.
#'   `c(date_mise_en_service = "Date")`. Values are shorthand strings:
#'   `"character"`, `"double"`/`"numeric"`, `"integer"`, `"logical"`, `"Date"`,
#'   `"datetime"`, `"skip"` or `"guess"`. Unnamed columns keep type inference.
#'   This is useful when a mostly-padded ISO date column has a few non-padded
#'   stragglers that vroom would otherwise flag (forcing `"Date"` turns those
#'   into `NA`). Defaults to `NULL` (no column overrides).
#' @param use_tabular_types Whether to seed column types from data.gouv's
#'   tabular API profile (`tabular-api.data.gouv.fr/api/resources/<rid>/profile/`),
#'   a schema-independent per-column type detection computed by data.gouv's own
#'   `csv-detective` detector. Defaults to `TRUE`. The detected types are used as
#'   vroom's `col_types` for any column `col_types` does not already pin
#'   (explicit `col_types` always win on collision). The profile is looked up
#'   per resource inside the parse loop, so the resource that is actually parsed
#'   supplies the types. It is best-effort: it only exists for single-file
#'   resources indexed by the tabular service (not ZIP members, and not
#'   oversized/unindexed files), and a missing profile silently falls back to
#'   type inference.
#'
#' @return A [tibble::tibble()] (default) or, when `all_files = TRUE` and the
#'   resource is a multi-file ZIP, a named list of tibbles (one element per
#'   parseable file, named after it). Every table carries its stable, unique
#'   address as an `id` attribute — a URI of the form
#'   `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>` (plus
#'   `/&lt;file&gt;` for a file inside a ZIP) — re-fetchable with [dg_refetch()]
#'   and readable with [dg_table_id()]. Any parsing issues vroom encountered are
#'   attached as an `rdatagouv_problems` attribute (a data frame), readable with
#'   [dg_problems()].
#'
#' @export
#' @examplesIf interactive()
#' id <- "6397c0ff56d3963118a18345"
#' tbl <- dg_pull_dataset(id)
#' head(tbl)
#' dg_table_id(tbl)
dg_pull_dataset <- function(
  id,
  all_files = FALSE,
  remove_na = FALSE,
  col_types = NULL,
  use_tabular_types = TRUE
) {
  dataset <- find_dataset(id)
  # Try the dataset's tabular resources in order, keeping the first that
  # actually parses. data.gouv's declared formats are not always accurate, so a
  # candidate can fail to read as a table (e.g. a `json` resource serving a
  # metadata document); we skip those rather than erroring on the first one.
  # Profile-backed column typing (use_tabular_types) is resolved per resource
  # inside the parse loop (read_first_parseable_resource -> read_resource), so
  # the resource actually parsed gets its own csv-detective profile.
  parsed <- read_first_parseable_resource(
    dataset,
    col_types = col_types,
    use_tabular_types = use_tabular_types
  )
  data <- parsed$data
  resource <- parsed$resource
  is_zip <- is.list(data) && !is.data.frame(data)

  if (!all_files || !is_zip) {
    # Default: a single tibble. For a multi-file ZIP, return its first
    # parseable file so the result is always ergonomically "the table".
    if (is_zip) {
      file <- names(data)[[1]]
      data <- data[[1]]
    } else {
      file <- NULL
    }
    tbl <- format_tibble(data, remove_na = remove_na)
    return(
      tibble::as_tibble(
        table_attr(tbl, dataset$id, resource$id, file)
      )
    )
  }

  # all_files = TRUE with a multi-file ZIP: one tibble per parseable file,
  # each carrying its own composed id attribute.
  Map(
    function(tbl, file) {
      tbl <- format_tibble(tbl, remove_na = remove_na)
      tibble::as_tibble(table_attr(tbl, dataset$id, resource$id, file))
    },
    data,
    names(data)
  )
}
