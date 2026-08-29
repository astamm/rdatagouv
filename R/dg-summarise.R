#' Summarise several datasets
#'
#' Applies [dg_summary()] to a collection of tables and combines the resulting
#' metrics into a single tibble. If `datasets` is `NULL`, the first `n` datasets
#' returned by [dg_find_datasets()] are downloaded and summarised.
#'
#' @param datasets Either a named list of tibbles (each element is a single
#'   table, named after it), a named list of such lists (as returned by
#'   [dg_pull_dataset()], where a ZIP may contribute several tables), a tibble
#'   from [dg_find_datasets()] (identified by its `id` column; each dataset is
#'   downloaded and summarised), a character vector of dataset identifiers (or
#'   exact titles), or `NULL` (the default) to use the first `n` datasets from
#'   [dg_find_datasets()].
#' @param n Number of datasets to summarise when `datasets` is `NULL`.
#'   Defaults to `100`.
#'
#' @return A [tibble::tibble()] with one row per table and the columns
#'   described in [dg_summary()].
#'
#' @export
#' @examples
#' # Summarise in-memory tables (no network needed).
#' dg_summarise(datasets = list(iris = iris, mtcars = mtcars))
#'
#' @examplesIf interactive()
#' # Download and summarise the first datasets of the catalog.
#' dg_summarise()
dg_summarise <- function(datasets = NULL, n = 100) {
  if (is.null(datasets)) {
    catalog <- dg_find_datasets(n = n)
    # Label each downloaded dataset with its title (disambiguating any title
    # shared by several datasets by appending its id), but address the download
    # by the stable, unique identifier.
    datasets <- uniquify_names(stats::setNames(catalog$id, catalog$title))
    datasets <- lapply(datasets, dg_pull_dataset)
  } else if (is.data.frame(datasets) && "id" %in% names(datasets)) {
    # A tibble from dg_find_datasets(): download each id, labelled by title.
    catalog <- datasets
    datasets <- uniquify_names(stats::setNames(catalog$id, catalog$title))
    datasets <- lapply(datasets, dg_pull_dataset)
  } else if (is.character(datasets)) {
    # Elements may be identifiers or, as a fallback, exact titles.
    datasets <- stats::setNames(datasets, datasets)
    datasets <- lapply(datasets, dg_pull_dataset)
  } else if (!is.list(datasets)) {
    cli::cli_abort(
      "{.arg datasets} must be a list of {.cls tibble}s, a character vector or
       NULL.",
      class = "datagouv_invalid_datasets"
    )
  }

  datasets <- flatten_tables(datasets)

  if (length(datasets) == 0) {
    return(tibble::tibble(
      dataset = character(),
      size_kb = numeric(),
      n_vars = integer(),
      n_numeric = integer(),
      n_non_numeric = integer(),
      n_rows = integer(),
      prop_missing = numeric()
    ))
  }

  res <- mapply(
    function(df, nm) dg_summary(df, name = nm),
    datasets,
    names(datasets),
    SIMPLIFY = FALSE
  )
  do.call(rbind, res)
}

# Flatten a named list whose elements are either single tibbles or named lists
# of tibbles (as returned by dg_pull_dataset() for a multi-file ZIP) into a
# flat named list of tibbles, one summary row per table. When a dataset
# contributes a single table it keeps its label; when it contributes several,
# each table's name is appended to the dataset label.
flatten_tables <- function(x) {
  out <- list()
  for (nm in names(x)) {
    el <- x[[nm]]
    if (is.data.frame(el)) {
      out[[nm]] <- el
    } else {
      inner <- names(el)
      if (length(el) == 1) {
        out[[nm]] <- el[[1]]
      } else {
        for (i in seq_along(el)) {
          out[[paste0(nm, " / ", inner[i])]] <- el[[i]]
        }
      }
    }
  }
  out
}
