#' Compute summary metrics for a dataset
#'
#' Computes key metrics describing a parsed dataset: its in-memory weight in
#' kilobytes, the number of variables, the number of numeric and non-numeric
#' variables, the number of rows and the proportion of missing values.
#'
#' @param x A data frame or tibble (a single table, e.g. one element of the
#'   list returned by [dg_pull_dataset()]).
#' @param name An optional label attached to the result (e.g. the dataset
#'   title). When `NULL` (the default), the label is taken from the expression
#'   passed to `x` when possible.
#'
#' @return A [tibble::tibble()] with a single row and the following columns:
#'   `dataset`, `size_kb`, `n_vars`, `n_numeric`, `n_non_numeric`, `n_rows`
#'   and `prop_missing`.
#'
#' @export
#' @examples
#' dg_summary(iris, name = "iris")
dg_summary <- function(x, name = NULL) {
  if (!is.data.frame(x)) {
    cli::cli_abort(
      "{.arg x} must be a data frame or {.cls tibble}.",
      class = "datagouv_invalid_data_frame"
    )
  }
  if (is.null(name)) {
    name <- deparse(substitute(x))
  }
  numeric_vars <- vapply(x, is.numeric, logical(1))
  n_total <- nrow(x) * ncol(x)

  tibble::tibble(
    dataset = name,
    size_kb = as.numeric(utils::object.size(x)) / 1024,
    n_vars = ncol(x),
    n_numeric = sum(numeric_vars),
    n_non_numeric = ncol(x) - sum(numeric_vars),
    n_rows = nrow(x),
    prop_missing = if (n_total == 0) 0 else sum(is.na(x)) / n_total
  )
}
