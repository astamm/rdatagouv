test_that("dg_schema() returns the documented fields of a schema-attached resource", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"

  # The dataset declares a schema by *name*; the pointer itself has no URL.
  resource <- mock_resource(format = "csv", id = rid)
  resource$schema <- list(
    name = "CEREMA/schema-arrete-circulation-marchandises",
    url = NULL,
    version = NULL
  )
  dataset <- mock_dataset(title = "Arrêtés", id = did)
  dataset$resources <- list(resource)

  # The schema document (as fetched from its URL) carries the fields.
  doc <- list(
    title = "Arrêtés de circulation",
    fields = list(
      list(
        name = "ID",
        title = "Identifiant",
        description = "Identifiant unique de la ligne.",
        type = "string",
        example = "ARR-001"
      ),
      list(
        name = "ARR_DATE",
        title = "Date",
        description = "Date de l'arrêté.",
        type = "date",
        example = "2022-01-01"
      )
    )
  )
  schema_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(doc, auto_unbox = TRUE))
  )

  local_mocked_bindings(
    fetch_dataset = function(id) dataset,
    resolve_schema_url = function(name) {
      "https://schema.data.gouv.fr/schemas/x.json"
    },
    http_perform = function(req) schema_resp
  )

  out <- dg_schema(paste(did, rid, sep = "::"))

  expect_s3_class(out, "tbl_df")
  expect_named(out, c("name", "title", "description", "type", "example"))
  expect_equal(out$name, c("ID", "ARR_DATE"))
  expect_equal(out$title, c("Identifiant", "Date"))
  expect_equal(out$type, c("string", "date"))
  expect_equal(attr(out, "schema_title"), "Arrêtés de circulation")
})

test_that("dg_schema() accepts the canonical URI", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"
  uri <- paste0("https://www.data.gouv.fr/datasets/", did, "#", rid)

  resource <- mock_resource(format = "csv", id = rid)
  resource$schema <- list(
    name = NULL,
    url = "https://example.org/schema.json",
    version = NULL
  )
  dataset <- mock_dataset(title = "Dataset", id = did)
  dataset$resources <- list(resource)

  doc <- list(
    title = "S",
    fields = list(
      list(name = "a", type = "integer", description = "Column a")
    )
  )
  schema_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(doc, auto_unbox = TRUE))
  )

  local_mocked_bindings(
    fetch_dataset = function(id) dataset,
    resolve_schema_url = function(name) {
      "https://schema.data.gouv.fr/schemas/x.json"
    },
    http_perform = function(req) schema_resp
  )

  out <- dg_schema(uri)

  expect_equal(out$name, "a")
})

test_that("dg_schema() accepts a table and reads its id attribute", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"

  resource <- mock_resource(format = "csv", id = rid)
  resource$schema <- list(
    name = NULL,
    url = "https://example.org/schema.json",
    version = NULL
  )
  dataset <- mock_dataset(title = "Dataset", id = did)
  dataset$resources <- list(resource)

  doc <- list(
    title = "S",
    fields = list(
      list(name = "a", type = "integer", description = "Column a")
    )
  )
  schema_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(doc, auto_unbox = TRUE))
  )

  local_mocked_bindings(
    fetch_dataset = function(id) dataset,
    resolve_schema_url = function(name) {
      "https://schema.data.gouv.fr/schemas/x.json"
    },
    http_perform = function(req) schema_resp
  )

  tbl <- structure(data.frame(a = 1), id = paste(did, rid, sep = "::"))
  out <- dg_schema(tbl)

  expect_equal(out$name, "a")
})

test_that("dg_schema() uses the schema URL directly when the pointer has one", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"

  resource <- mock_resource(format = "csv", id = rid)
  resource$schema <- list(
    name = NULL,
    url = "https://example.org/schema.json",
    version = NULL
  )
  dataset <- mock_dataset(title = "Dataset", id = did)
  dataset$resources <- list(resource)

  doc <- list(
    title = "S",
    fields = list(
      list(name = "a", type = "integer", description = "Column a")
    )
  )
  schema_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(doc, auto_unbox = TRUE))
  )

  seen_url <- NULL
  local_mocked_bindings(
    fetch_dataset = function(id) dataset,
    http_perform = function(req) {
      seen_url <<- req$url
      schema_resp
    }
  )

  out <- dg_schema(paste(did, rid, sep = "::"))

  expect_equal(seen_url, "https://example.org/schema.json")
  expect_equal(out$name, "a")
})

test_that("dg_schema() tolerates fields given as a name -> spec object", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"

  resource <- mock_resource(format = "csv", id = rid)
  resource$schema <- list(
    name = "etalab/schema-bal",
    url = NULL,
    version = NULL
  )
  dataset <- mock_dataset(title = "Dataset", id = did)
  dataset$resources <- list(resource)

  # Named-object shape: keys are the field names.
  doc <- list(
    title = "BAL",
    fields = list(
      a = list(title = "A", type = "string", description = "col a"),
      b = list(title = "B", type = "integer", description = NULL)
    )
  )
  schema_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(doc, auto_unbox = TRUE))
  )

  local_mocked_bindings(
    fetch_dataset = function(id) dataset,
    resolve_schema_url = function(name) {
      "https://schema.data.gouv.fr/schemas/x.json"
    },
    http_perform = function(req) schema_resp
  )

  out <- dg_schema(paste(did, rid, sep = "::"))

  expect_equal(out$name, c("a", "b"))
  expect_equal(out$type, c("string", "integer"))
  expect_true(is.na(out$description[[2]]))
})

test_that("dg_schema() conservatively handles a missing example value", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"

  resource <- mock_resource(format = "csv", id = rid)
  resource$schema <- list(name = "x/y", url = NULL, version = NULL)
  dataset <- mock_dataset(title = "Dataset", id = did)
  dataset$resources <- list(resource)

  doc <- list(
    title = "S",
    fields = list(
      list(name = "a", type = "string", description = "col a")
    )
  )
  schema_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(doc, auto_unbox = TRUE))
  )

  local_mocked_bindings(
    fetch_dataset = function(id) dataset,
    resolve_schema_url = function(name) {
      "https://schema.data.gouv.fr/schemas/x.json"
    },
    http_perform = function(req) schema_resp
  )

  out <- dg_schema(paste(did, rid, sep = "::"))

  expect_true(is.na(out$example[[1]]))
  expect_true(is.na(out$title[[1]]))
})

test_that("dg_schema() returns NULL (message) when the resource has no schema", {
  did <- "aaaaaaaaaaaaaaaaaaaaaaaa"
  rid <- "99999999-9999-4999-8999-999999999999"

  resource <- mock_resource(format = "csv", id = rid) # no $schema pointer
  dataset <- mock_dataset(title = "Plain", id = did)
  dataset$resources <- list(resource)

  local_mocked_bindings(
    fetch_dataset = function(id) dataset
  )

  expect_message(
    out <- dg_schema(paste(did, rid, sep = "::")),
    "has no declared schema"
  )
  expect_null(out)
})

test_that("dg_schema() errors when the resource is not on the dataset", {
  local_mocked_bindings(
    fetch_dataset = function(id) mock_dataset(title = "D", id = id)
  )

  expect_error(
    dg_schema("aaaaaaaaaaaaaaaaaaaaaaaa::99999999-9999-4999-8999-999999999999"),
    "was not found on dataset"
  )
})

test_that("resolve_schema_url() looks a name up in the schema.data.gouv.fr catalog", {
  cat_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(
      auto_unbox = TRUE,
      list(
        schemas = list(
          list(
            name = "etalab/schema-bal",
            schema_url = "https://schema.data.gouv.fr/schemas/etalab/schema-bal/latest/schema.json"
          ),
          list(
            name = "CEREMA/schema-arrete-circulation-marchandises",
            schema_url = "https://schema.data.gouv.fr/schemas/CEREMA/schema-arrete-circulation-marchandises/latest/schema.json"
          )
        )
      )
    ))
  )

  local_mocked_bindings(
    http_perform = function(req) cat_resp
  )

  expect_equal(
    resolve_schema_url("CEREMA/schema-arrete-circulation-marchandises"),
    "https://schema.data.gouv.fr/schemas/CEREMA/schema-arrete-circulation-marchandises/latest/schema.json"
  )
})

test_that("resolve_schema_url() returns NULL when the name is not in the catalog", {
  cat_resp <- httr2::response(
    status_code = 200,
    headers = "Content-Type: application/json",
    body = charToRaw(jsonlite::toJSON(
      auto_unbox = TRUE,
      list(schemas = list(list(name = "other/x", schema_url = "https://x")))
    ))
  )

  local_mocked_bindings(
    http_perform = function(req) cat_resp
  )

  expect_message(
    res <- resolve_schema_url("unknown/name"),
    "not found in the schema.data.gouv.fr catalog"
  )
  expect_null(res)
})

test_that("resolve_schema_url() returns NULL for an empty name", {
  expect_null(resolve_schema_url(NULL))
  expect_null(resolve_schema_url(""))
})
