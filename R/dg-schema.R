#' Documented schema of a parsed table's columns
#'
#' Returns the declared data schema of a table's columns: the per-variable
#' `fields` recorded by the dataset producer. Because data.gouv attaches a schema
#' only as a *pointer* (`schema$name` / `schema$url`), this resolves that pointer
#' against [schema.data.gouv.fr](https://schema.data.gouv.fr) and returns the
#' human-readable column documentation (`name`, `title`, `description`, `type`)
#' that the schema carries — the information needed to judge whether a variable
#' really means what a statistical exploration assumes.
#'
#' This is a *supplement* to [dg_pull_dataset()]: the table itself comes from the
#' main API; the schema is read from the producer's declared data specification.
#' Only resources that carry a schema pointer have documentation; resources
#' without one return `NULL` with a message. Use `dg_list_datasets()` (column
#' `has_schema`, or the `schema_only` argument) to target schema-documented
#' tables in the first place.
#'
#' @param x Either a table returned by [dg_pull_dataset()] or [dg_refetch()]
#'   (its `id` attribute is read automatically) or a table address string: the
#'   canonical URI `https://www.data.gouv.fr/datasets/<dataset_id>#<resource_id>`
#'   (or `...#<resource_id>/<file>` for a file inside a ZIP), or a legacy
#'   composed id of the form `<dataset_id>::<resource_id>` /
#'   `<dataset_id>::<resource_id>::<file>`, as readable with [dg_table_id()].
#'
#' @return A [tibble::tibble()] with one row per column and the columns `name`,
#'   `title`, `description`, `type` and `example` (where the schema provides
#'   them; absent entries are `NA`), or `NULL` (with a message) if the resource
#'   has no declared schema. The schema's own `title` and `name` are attached as
#'   the attributes `schema_title` and `schema_name`.
#'
#' @export
#' @examplesIf interactive()
#' tbl <- dg_pull_dataset("62c5961ff0013fb71d7278e3")
#' dg_schema(tbl)
dg_schema <- function(x) {
  id <- resolve_table_id(x)
  parts <- parse_table_id(id)
  dataset <- fetch_dataset(parts$dataset_id)
  resources <- dataset$resources %||% list()
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

  pointer <- resource$schema %||% list()
  url <- pointer$url %||% resolve_schema_url(pointer$name)
  if (is.null(url)) {
    message(
      "Resource '",
      parts$resource_id,
      "' of dataset '",
      dataset$title,
      "' has no declared schema; no variable documentation available. ",
      "Search with dg_list_datasets(schema_only = TRUE) to find documented ",
      "resources."
    )
    return(NULL)
  }

  body <- httr2::resp_body_json(
    http_perform(req_data_gouv(httr2::request(url)))
  )
  fields <- body$fields %||% list()

  # Table Schema documents list fields either as an array of objects or as a
  # named object (name -> spec); normalise both to a named character matrix.
  if (length(fields) > 0 && !is.null(names(fields))) {
    nm <- names(fields)
  } else {
    nm <- vapply(fields, function(.f) .f$name %||% NA_character_, character(1))
  }
  out <- tibble::tibble(
    name = nm,
    title = field_attr(fields, "title"),
    description = field_attr(fields, "description"),
    type = field_attr(fields, "type"),
    example = field_attr(fields, "example")
  )
  attr(out, "schema_title") <- body$title %||% NA_character_
  attr(out, "schema_name") <- pointer$name %||% NA_character_
  out
}

# Extract a named attribute from every entry of a `fields` list, coercing
# each value to a single character (scalars pass through; NULL becomes NA).
# Works both for an array of field objects and for a name -> spec object.
field_attr <- function(fields, what) {
  unname(vapply(
    fields,
    function(.f) {
      val <- .f[[what]]
      # Treat an absent field as NA, and also a present-but-empty value (some
      # producers serialize an empty description as `{}`, which parses back to a
      # zero-length list rather than NULL).
      if (is.null(val) || length(val) == 0) {
        NA_character_
      } else {
        paste(as.character(val), collapse = ", ")
      }
    },
    character(1)
  ))
}

# Resolve a schema *name* (e.g. "CEREMA/schema-arrete-circulation-marchandises")
# to the URL of its latest schema document, via the schema.data.gouv.fr catalog.
# Returns NULL when the name is unknown.
resolve_schema_url <- function(name) {
  if (is.null(name) || !nzchar(name)) {
    return(NULL)
  }
  body <- httr2::resp_body_json(
    http_perform(
      req_data_gouv(httr2::request("https://schema.data.gouv.fr/schemas.json"))
    )
  )
  schemas <- body$schemas %||% list()
  hits <- Filter(function(s) identical(s$name, name), schemas)
  if (length(hits) == 0) {
    message(
      "Schema '",
      name,
      "' was not found in the schema.data.gouv.fr catalog."
    )
    return(NULL)
  }
  hits[[1]]$schema_url
}
