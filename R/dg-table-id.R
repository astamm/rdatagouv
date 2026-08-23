#' Read a table's stable address
#'
#' Returns the stable, unique address of a table downloaded with
#' [dg_pull_dataset()] or [dg_refetch()], which is stored as an `id` attribute
#' on the table. The address is a URI of the form
#' `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>` (plus
#' `/&lt;file&gt;` for a file inside a ZIP) and uniquely identifies a table on
#' the platform, independent of the human-readable catalog titles. It can be
#' passed directly to [dg_refetch()] or [dg_schema()] to re-fetch or document
#' that exact table.
#'
#' @param x A table returned by [dg_pull_dataset()] or [dg_refetch()].
#'
#' @return The composed table id, a string, or `NULL` if `x` carries no id
#'   attribute (e.g. an ordinary data frame).
#'
#' @export
#' @examples
#' tbl <- dg_table_id(iris)
dg_table_id <- function(x) {
  if (!is.data.frame(x)) {
    return(NULL)
  }
  table_id_from_attr(x)
}
