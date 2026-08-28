#' Return the parsing problems of a downloaded table
#'
#' Returns the data frame of parsing issues that [vroom](https://vroom.r-lib.org/)
#' encountered while reading a table downloaded with [dg_pull_dataset()] or
#' [dg_refetch()]. These are vroom's "parsing issues" (rows that could not be
#' converted to the inferred column type, e.g. a mostly-padded ISO date column
#' holding a few non-padded values like `2021-7-01`).
#'
#' The noisy per-cell warnings themselves are suppressed by default during a
#' pull; use this accessor to inspect what happened. The problems live in the
#' `rdatagouv_problems` attribute of the table. Returns `NULL` when the table
#' carries no recorded problems (or when `x` is an ordinary data frame).
#'
#' @param x A table returned by [dg_pull_dataset()] or [dg_refetch()].
#'
#' @return A data frame with columns `row`, `col`, `expected` and `actual`
#'   (one row per parsing issue), or `NULL` if there were none.
#'
#' @export
#' @examples
#' dg_problems(iris)
dg_problems <- function(x) {
  attr(x, "rdatagouv_problems")
}
